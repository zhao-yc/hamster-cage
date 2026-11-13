extends SceneTree

const Habitat = preload("res://habitat.gd")
const WIDTH := 256
const ROWS := 32
const MATERIALS := ["Coat", "Details", "Eyes"]
const ROUGHNESS := [0.94, 0.82, 0.18]

var atlas: Image
var palette: Dictionary
var output: FileAccess
var triangles: int
var invalid_faces: int

func _initialize() -> void:
	call_deferred("_export")

func _export() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("用法：Godot --headless --script res://ios/export-hamsters.gd -- <输出目录>")
		quit(1)
		return
	var folder: String = args[0]
	var habitat := Habitat.new()
	# 直接取笼中角色的部件和绑定姿势，跳过垫料、家具与地面阴影。
	for index in range(2):
		habitat._pet(index, true)
		for foot in range(4):
			habitat._position_limb(index, foot)
		var name := "HamsterGray" if index == 0 else "HamsterWhite"
		var ok := _write_pet(habitat, index, folder.path_join(name))
		if not ok:
			habitat.free()
			quit(1)
			return
	habitat.free()
	quit()

func _write_pet(habitat: Node3D, index: int, path: String) -> bool:
	atlas = Image.create_empty(WIDTH, ROWS * 4, false, Image.FORMAT_RGB8)
	palette = {}
	triangles = 0
	invalid_faces = 0
	output = FileAccess.open(path + ".usda", FileAccess.WRITE)
	if output == null:
		printerr("无法写入模型：", path)
		return false
	output.store_string('#usda 1.0\n(\n defaultPrim = "Hamster"\n metersPerUnit = 1\n upAxis = "Y"\n)\ndef Xform "Hamster" {\n')
	var pet: Node3D = habitat.pets[index]
	var head: Node3D = habitat.heads[index]
	var feet: Array = habitat.feet[index]
	var limbs: Array = habitat.limbs[index]
	var scale_in_meters: float = 0.079 * Habitat.ADULT_SIZE[index]
	# 站姿最低点约为 0.038 个笼内单位，整体落到 AR 桌面。
	output.store_line(" double3 xformOp:translate = (0, %s, 0)" % (-0.038 * scale_in_meters))
	output.store_line(" double3 xformOp:scale = (%s, %s, %s)" % [scale_in_meters, scale_in_meters, scale_in_meters])
	output.store_line(' uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]')
	_write_materials(path.get_file() + ".png")
	var body: Array[Node3D] = []
	for child in pet.get_children():
		if child != head and child not in feet and child not in limbs:
			body.append(child)
	_write_group("Body", body, Vector3.ZERO)
	_write_group("Head", [head], head.position)
	for foot in range(4):
		_write_group("Foot%d" % foot, [feet[foot], limbs[foot]], feet[foot].position)
	output.store_line("}")
	output.close()
	if invalid_faces > 0 or triangles == 0 or triangles > 100000 or palette.size() > ROWS:
		printerr("无效模型：三角面 %d，异常面 %d，材质 %d" % [triangles, invalid_faces, palette.size()])
		return false
	print("%s：%d 个三角面，%d 行颜色" % [path.get_file(), triangles, palette.size()])
	return atlas.save_png(path + ".png") == OK

func _write_materials(texture: String) -> void:
	output.store_line(' def Scope "Looks" {')
	for index in range(MATERIALS.size()):
		var name: String = MATERIALS[index]
		var prim := "/Hamster/Looks/" + name
		output.store_string(('''
  def Material "%s" {
   token outputs:surface.connect = <%s/Surface.outputs:surface>
   def Shader "Surface" {
    uniform token info:id = "UsdPreviewSurface"
    color3f inputs:diffuseColor.connect = <%s/Color.outputs:rgb>
    float inputs:roughness = %s
    float inputs:metallic = 0
    float inputs:ior = %s
    token outputs:surface
   }
   def Shader "UV" {
    uniform token info:id = "UsdPrimvarReader_float2"
    string inputs:varname = "st"
    float2 outputs:result
   }
   def Shader "Color" {
    uniform token info:id = "UsdUVTexture"
    asset inputs:file = @%s@
    token inputs:sourceColorSpace = "sRGB"
    float2 inputs:st.connect = <%s/UV.outputs:result>
    token inputs:wrapS = "clamp"
    token inputs:wrapT = "clamp"
    float3 outputs:rgb
   }
  }
''') % [name, prim, prim, ROUGHNESS[index], 1.15 if index == 0 else 1.45, texture, prim])
	output.store_line(" }")

func _write_group(name: String, nodes: Array[Node3D], pivot: Vector3) -> void:
	var batches: Dictionary = {}
	for node in nodes:
		var transform := node.transform
		transform.origin -= pivot
		_collect(node, transform, batches)
	output.store_line(' def Xform "%s" {' % name)
	output.store_line("  double3 xformOp:translate = %s" % _vec3(pivot))
	output.store_line('  uniform token[] xformOpOrder = ["xformOp:translate"]')
	for material in batches:
		var batch: Dictionary = batches[material]
		@warning_ignore("integer_division")
		var count: int = batch.indices.size() / 3
		triangles += count
		output.store_string(('''
  def Mesh "%s" (prepend apiSchemas = ["MaterialBindingAPI"]) {
   uniform token subdivisionScheme = "none"
   uniform token orientation = "rightHanded"
   bool doubleSided = %s
   int[] faceVertexCounts = [%s]
   int[] faceVertexIndices = [%s]
   point3f[] points = [%s]
   normal3f[] normals = [%s] (interpolation = "vertex")
   texCoord2f[] primvars:st = [%s] (interpolation = "vertex")
   rel material:binding = </Hamster/Looks/%s>
  }
''') % [material, "true" if material == "Coat" else "false", "3,".repeat(count).trim_suffix(","),
			",".join(batch.indices), ",".join(batch.positions), ",".join(batch.normals), ",".join(batch.uvs), material])
	output.store_line(" }")

func _collect(node: Node3D, transform: Transform3D, batches: Dictionary) -> void:
	if node is MeshInstance3D:
		_add_mesh(node, transform, batches)
	for child in node.get_children():
		_collect(child, transform * child.transform, batches)

func _add_mesh(node: MeshInstance3D, transform: Transform3D, batches: Dictionary) -> void:
	var mesh := node.mesh
	if mesh is SphereMesh:
		mesh = mesh.duplicate()
		mesh.radial_segments = 16
		mesh.rings = 8
	var material := node.material_override
	var kind := "Details"
	var colored := false
	var base_color := Color.WHITE
	var card := false
	if material is ShaderMaterial:
		kind = "Coat"
		colored = true
		card = material.shader.resource_path.ends_with("hamster_tufts.gdshader")
	elif material is StandardMaterial3D:
		colored = material.vertex_color_use_as_albedo
		base_color = material.albedo_color
		if colored:
			kind = "Coat"
		elif material.roughness < 0.2:
			kind = "Eyes"
	for surface in range(mesh.get_surface_count()):
		var data := mesh.surface_get_arrays(surface)
		var colors: PackedColorArray = data[Mesh.ARRAY_COLOR] if colored else PackedColorArray([base_color])
		var ramp := _color_ramp(colors)
		if not batches.has(kind):
			batches[kind] = {"positions": PackedStringArray(), "normals": PackedStringArray(),
				"uvs": PackedStringArray(), "indices": PackedStringArray(), "lookup": {}}
		var batch: Dictionary = batches[kind]
		if card:
			_add_tufts(data, batch, transform, ramp)
		else:
			_add_surface(data, batch, transform, ramp, colored, base_color)

func _color_ramp(colors: PackedColorArray) -> Array:
	# USDZ 用纹理保留原模型顶点颜色。按亮度排序，并把相邻颜色放在同一行，避免毛色突变。
	var darkest := colors[0]
	var lightest := colors[0]
	for color in colors:
		if color.get_luminance() < darkest.get_luminance():
			darkest = color
		if color.get_luminance() > lightest.get_luminance():
			lightest = color
	var key := [darkest, lightest]
	if not palette.has(key):
		var row := palette.size()
		palette[key] = row
		if row < ROWS:
			for x in range(WIDTH):
				var color := darkest.lerp(lightest, float(x) / (WIDTH - 1))
				for y in range(row * 4, row * 4 + 4):
					atlas.set_pixel(x, y, color)
	return [darkest.get_luminance(), lightest.get_luminance(), palette[key]]

func _add_surface(data: Array, batch: Dictionary, transform: Transform3D, ramp: Array, colored: bool, base_color: Color) -> void:
	var positions: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = data[Mesh.ARRAY_COLOR] if colored else PackedColorArray()
	var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var normal_matrix := transform.basis.inverse().transposed()
	var count := indices.size() if not indices.is_empty() else positions.size()
	for start in range(0, count, 3):
		# 以原模型法线校验 USD 的面朝向。球体和手工曲面都可能含退化三角形。
		var a := indices[start] if not indices.is_empty() else start
		var b := indices[start + 1] if not indices.is_empty() else start + 1
		var c := indices[start + 2] if not indices.is_empty() else start + 2
		var face := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		if face.length_squared() < 1e-20:
			continue
		var outward := face.dot(normals[a] + normals[b] + normals[c]) >= 0.0
		for i in ([a, b, c] if outward else [a, c, b]):
			_vertex(batch, transform * positions[i], (normal_matrix * normals[i]).normalized(),
				colors[i] if colored else base_color, ramp)

func _add_tufts(data: Array, batch: Dictionary, transform: Transform3D, ramp: Array) -> void:
	var positions: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = data[Mesh.ARRAY_COLOR]
	var normal_matrix := transform.basis.inverse().transposed()
	# 取原毛束的根部、中点和末端，做成两片窄的锥形网格。用真实轮廓代替 Godot 专用透明着色器。
	for start in range(0, positions.size(), 24):
		var base := (positions[start] + positions[start + 1]) * 0.5
		var mid := (positions[start + 12] + positions[start + 13]) * 0.5
		var tip := (positions[start + 20] + positions[start + 22]) * 0.5
		var width := (positions[start + 1] - positions[start]) * 0.20
		var n := (normal_matrix * normals[start]).normalized()
		var points := [base - width, base + width, mid - width * 0.55, mid + width * 0.55, tip]
		for i in [0, 1, 2, 1, 3, 2, 2, 3, 4]:
			_vertex(batch, transform * points[i], n, colors[start], ramp)

func _vertex(batch: Dictionary, p: Vector3, n: Vector3, color: Color, ramp: Array) -> void:
	if not p.is_finite() or not n.is_finite() or n.is_zero_approx():
		invalid_faces += 1
	var span: float = ramp[1] - ramp[0]
	var value := clampf((color.get_luminance() - ramp[0]) / span, 0.0, 1.0) if span > 0.00001 else 0.5
	var uv := Vector2((value * (WIDTH - 1) + 0.5) / WIDTH, 1.0 - (ramp[2] + 0.5) / ROWS)
	var key := [_vec3(p), _vec3(n), "(%.6f, %.6f)" % [uv.x, uv.y]]
	var index: int = batch.lookup.get(key, -1)
	if index == -1:
		index = batch.positions.size()
		batch.lookup[key] = index
		batch.positions.append(key[0])
		batch.normals.append(key[1])
		batch.uvs.append(key[2])
	batch.indices.append(str(index))

func _vec3(value: Vector3) -> String:
	return "(%.7f, %.7f, %.7f)" % [value.x, value.y, value.z]
