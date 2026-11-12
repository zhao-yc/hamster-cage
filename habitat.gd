extends Node3D
const Meshes = preload("res://habitat_meshes.gd")
const Hamster = preload("res://hamster_geometry.gd")

const WHEEL_RUN := Vector2(3.12, -1.62)
const WHEEL_ENTRY := Vector2(3.12, -0.48)
const BOWL := Vector2(-2.90, 0.75)
const DRINK := Vector2(0.62, -2.44)
const CUBBIES := [Vector2(-3.70, -1.51), Vector2(-1.39, -1.70)]
const NEST_DEPTH := 1.17
const ADULT_SIZE := [1.73, 1.52]
const BODY_CENTER := Vector3(0, 0.315, -0.115)
const BODY_RADII := Vector3(0.31, 0.305, 0.41)
const WATER_BOTTOM := 1.01
const WATER_HEIGHT := 0.74
const DROP_TARGETS := [
	{"area": AABB(Vector3(-3.93, 0, -0.23), Vector3(2.37, 0.68, 2.22)),
		"task": "吃", "label": "吃粮", "landing": BOWL + Vector2(1.32, 0.90)},
	{"area": AABB(Vector3(0.03, 0, -3.62), Vector3(1.17, 2.85, 2.35)),
		"task": "喝", "label": "喝水", "landing": DRINK + Vector2(0, 1.55)},
	{"area": AABB(Vector3(-4.83, 0, -3.02), Vector3(2.22, 2.50, 2.32)),
		"task": "睡", "label": "进小窝", "nest": 0, "landing": CUBBIES[0] + Vector2(0, 0.68)},
	{"area": AABB(Vector3(-2.48, 0, -3.18), Vector3(2.19, 2.50, 2.37)),
		"task": "睡", "label": "进小窝", "nest": 1, "landing": CUBBIES[1] + Vector2(0, 0.68)},
	{"area": AABB(Vector3(1.58, 0, -2.64), Vector3(3.10, 3.23, 3.04)),
		"task": "跑", "label": "跑滚轮", "landing": WHEEL_ENTRY + Vector2(0, 1.1)},
]

var camera: Camera3D
var sun: DirectionalLight3D
var night_mix := -1.0
var wheel: Node3D
var pets: Array[Node3D] = []
var heads: Array[Node3D] = []
var feet: Array[Array] = []
var eyelids: Array[Array] = []
var noses: Array[Node3D] = []
var ears: Array[Array] = []
var whiskers: Array[Array] = []
var limbs: Array[Array] = []
var poses: Array[Dictionary] = []
var grip: Node3D
var grip_pivot: Node3D
var grip_fingers: Array[Node3D] = []
var grip_owner := -1
var grip_progress := 0.0
var grounds: Array[ShaderMaterial] = []
var water: Node3D
var water_column: MeshInstance3D
var seeds: Node3D
var seed_parts: Array[Node3D] = []
var dirt := -1.0
var wood_texture: Texture2D
var soft_shadow: Texture2D
var bedding_layers: Array[MultiMesh] = []
var bedding_cells: Dictionary = {}
var displaced: Dictionary = {}
var flying_chips: Array[Dictionary] = []
var chip_cloud: MultiMeshInstance3D
var waste_model: MultiMeshInstance3D
var waste_signature := ""

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#aa7651")
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#aeb9c6")
	sky_material.sky_horizon_color = Color("#e5caa7")
	sky_material.ground_horizon_color = Color("#af906b")
	sky_material.ground_bottom_color = Color("#a18d72")
	sky_material.sky_energy_multiplier = 0.72
	sky_material.ground_energy_multiplier = 0.65
	sky_material.sun_angle_max = 5.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -29, 0)
	sun.light_color = Color("#fff0d6")
	sun.light_energy = 0.67
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.62
	sun.directional_shadow_max_distance = 18.0
	sun.shadow_blur = 2.3
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(0, 3.65, 8.65)
	add_child(camera)
	camera.look_at(Vector3(0, -0.25, -0.65))
	camera.fov = 44
	camera.current = true
	wood_texture = load("res://assets/birch-knots.png")
	soft_shadow = _shadow_texture()
	_room()
	_house(Vector3(-3.70, 0, -2.76), Color("#caa781"))
	_house(Vector3(-1.39, 0, -2.95), Color("#b6bc9c"))
	_wheel()
	_supplies()
	for index in range(2):
		_pet(index)
	_make_grip()
	chip_cloud = MultiMeshInstance3D.new()
	chip_cloud.multimesh = MultiMesh.new()
	chip_cloud.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	chip_cloud.multimesh.mesh = _shaving()
	chip_cloud.multimesh.instance_count = 128
	chip_cloud.multimesh.visible_instance_count = 0
	chip_cloud.material_override = _material(Color("#dec39b"))
	chip_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chip_cloud)
	waste_model = MultiMeshInstance3D.new()
	waste_model.multimesh = MultiMesh.new()
	waste_model.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var pellet := SphereMesh.new()
	pellet.radial_segments = 12
	pellet.rings = 6
	waste_model.multimesh.mesh = pellet
	waste_model.material_override = _material(Color("#69523e"), 0.98)
	add_child(waste_model)

func _material(color: Color, roughness: float = 0.88) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func _speckled(color: Color, kind: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/ceramic_grain.gdshader")
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("seed_kind", kind)
	return mat

func _painted_wood(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/painted_wood.gdshader")
	material.set_shader_parameter("grain", wood_texture)
	material.set_shader_parameter("tint", color)
	return material

func _bedding_material(color: Color, packed: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/bedding.gdshader")
	material.set_shader_parameter("grain", load("res://assets/aspen.png") if packed else wood_texture)
	material.set_shader_parameter("tint", color)
	material.set_shader_parameter("packed", packed)
	return material

func _shadow_texture() -> ImageTexture:
	var pixels := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var radius := Vector2((x - 63.5) / 63.5, (y - 63.5) / 63.5).length()
			pixels.set_pixel(x, y, Color(0.22, 0.13, 0.06, pow(maxf(0, 1.0 - radius), 1.8) * 0.63))
	return ImageTexture.create_from_image(pixels)

func _contact(at: Vector3, dimensions: Vector2, host: Node3D) -> void:
	var material := _material(Color.WHITE)
	material.albedo_texture = soft_shadow
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var plane := PlaneMesh.new()
	plane.size = dimensions
	_mesh(plane, at, material, host).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _node(at: Vector3, host: Node3D) -> Node3D:
	var part := Node3D.new()
	part.position = at
	host.add_child(part)
	return part

func _mesh(shape: Mesh, at: Vector3, mat: Material, host: Node3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = shape
	part.position = at
	part.material_override = mat
	host.add_child(part)
	return part

func _box(at: Vector3, dimensions: Vector3, mat: Material, host: Node3D = null) -> MeshInstance3D:
	var radius := minf(0.055, minf(dimensions.x, minf(dimensions.y, dimensions.z)) * 0.35)
	var shape := Meshes.rounded_box(dimensions, radius)
	return _mesh(shape, at, mat, host if host != null else self)

func _ellipsoid(at: Vector3, radii: Vector3, mat: Material, host: Node3D) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radial_segments = 40
	shape.rings = 24
	var part := _mesh(shape, at, mat, host)
	part.scale = radii * 2.0
	return part

func _cylinder(at: Vector3, radius: float, height: float, mat: Material, host: Node3D = null, bottom: float = -1) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.radial_segments = 48
	shape.top_radius = radius
	shape.bottom_radius = radius if bottom < 0 else bottom
	shape.height = height
	return _mesh(shape, at, mat, host if host != null else self)

func _ring(at: Vector3, inner: float, outer: float, mat: Material, host: Node3D, vertical: bool = true) -> void:
	var shape := TorusMesh.new()
	shape.inner_radius = inner
	shape.outer_radius = outer
	shape.rings = 48
	shape.ring_segments = 12
	_mesh(shape, at, mat, host).rotation.x = PI / 2 if vertical else 0.0

func _room() -> void:
	var base := _bedding_material(Color("#dac4a1"), true)
	grounds.append(base)
	_mesh(Meshes.bedding(), Vector3.ZERO, base, self)
	var wood := ShaderMaterial.new()
	wood.shader = load("res://assets/warm_wood.gdshader")
	wood.set_shader_parameter("grain", wood_texture)
	wood.set_shader_parameter("tint", Color("#bfb6aa"))
	_box(Vector3(0, 3.0, -3.98), Vector3(24, 6.0, 0.3), wood)
	var rng := RandomNumberGenerator.new()
	rng.seed = 279
	# 木屑按材质分批实例化，避免为每片垫料创建节点。
	for tone in ["#ead9bb", "#e9dfc9", "#dbc9aa", "#d4c3a9"]:
		var mat := _bedding_material(Color(tone))
		grounds.append(mat)
		var geometry := _shaving()
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = geometry
		batch.instance_count = 6200
		var layer_id := bedding_layers.size()
		bedding_layers.append(batch)
		for i in range(batch.instance_count):
			var point := Vector3(rng.randf_range(-8, 8), rng.randf_range(0.012, 0.065), rng.randf_range(-3.75, 5.7))
			# 小路的木屑更细、更低，保留薄薄一层踩实的垫料。
			var path_x := sin(point.z * 0.72) * 0.74 + 0.22
			var packed := smoothstep(0.39, 0.90, absf(point.x - path_x)) if point.z > -1.7 else 1.0
			point.y = point.y * lerpf(0.10, 0.65, packed) + Meshes.bedding_height(point.x, point.z)
			if point.z < -1.9 and point.x < 0.05:
				point.y = minf(point.y, 0.025)
			var axis := Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0, TAU), rng.randf_range(-0.4, 0.4)))
			var scale_factor := rng.randf_range(0.55, 1.25) * lerpf(0.18, 1.0, packed)
			batch.set_instance_transform(i, Transform3D(axis.scaled(Vector3.ONE * scale_factor), point))
			var cell := Vector2i(floori(point.x * 2), floori(point.z * 2))
			if not bedding_cells.has(cell):
				bedding_cells[cell] = []
			bedding_cells[cell].append(Vector2i(layer_id, i))
		var layer := MultiMeshInstance3D.new()
		layer.multimesh = batch
		layer.material_override = mat
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(layer)

func _shaving() -> ArrayMesh:
	var shape := SurfaceTool.new()
	shape.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strip := [
		Vector3(-0.085, 0.026, -0.022), Vector3(-0.077, 0.023, 0.020),
		Vector3(-0.030, 0, -0.030), Vector3(-0.026, 0.002, 0.029),
		Vector3(0.035, 0.009, -0.024), Vector3(0.044, 0.012, 0.025),
		Vector3(0.098, 0.060, -0.016), Vector3(0.090, 0.054, 0.015)]
	for i in range(0, 6, 2):
		for vertex in [i, i + 2, i + 1, i + 2, i + 3, i + 1]:
			shape.set_normal(Vector3(-strip[vertex].x * 2.5, 1, 0.04).normalized())
			shape.set_uv(Vector2((strip[vertex].x + 0.1) * 5.0, (strip[vertex].z + 0.04) * 10.0))
			shape.set_color(Color.WHITE * (0.86 + strip[vertex].y * 2.0))
			shape.add_vertex(strip[vertex])
	return shape.commit()

func _house(at: Vector3, color: Color) -> void:
	var house := _node(at, self)
	house.scale = Vector3(1.48, 1.68, 1.48)
	_contact(Vector3(0, 0.072, 0.25), Vector2(2.3, 2.2), house)
	var walls := _material(color)
	var roof := _painted_wood(Color("#b68165") if color.r > color.g + 0.1 else Color("#82957b"))
	walls.albedo_texture = wood_texture
	for side in [-1.0, 1.0]:
		_box(Vector3(side * 0.67, 0.48, 0), Vector3(0.14, 0.96, 1.32), walls, house)
	_mesh(Meshes.roof(), Vector3.ZERO, roof, house)
	var facade := CSGPolygon3D.new()
	var outline := PackedVector2Array([Vector2(-0.72, 0), Vector2(-0.72, 0.98), Vector2(0.72, 0.98),
		Vector2(0.72, 0), Vector2(0.29, 0), Vector2(0.29, 0.42)])
	for step in range(1, 33):
		var theta := PI * step / 32.0
		outline.append(Vector2(cos(theta) * 0.29, 0.42 + sin(theta) * 0.29))
	outline.append(Vector2(-0.29, 0))
	facade.polygon = outline
	facade.depth = 0.13
	facade.material = walls
	facade.position.z = 0.66
	house.add_child(facade)
	_box(Vector3(0, 0.055, -0.04), Vector3(1.31, 0.03, 1.26), _material(Color("#795636")), house)
	_box(Vector3(0, 0.52, -0.61), Vector3(1.35, 1.04, 0.13), walls, house)
	var badge := _cylinder(Vector3(0, 1.17, 0.808), 0.092, 0.022, _material(Color("#f6e1be")), house)
	badge.rotation.x = PI / 2

func _wheel() -> void:
	var sage := _painted_wood(Color("#97a588"))
	var trim := _painted_wood(Color("#bdc6a6"))
	var tread := _material(Color("#8e9c7d"))
	_box(Vector3(WHEEL_RUN.x, 0.085, -2.18), Vector3(1.93, 0.17, 1.4), sage)
	_box(Vector3(WHEEL_RUN.x, 0.94, -2.75), Vector3(0.30, 1.8, 0.24), sage)
	wheel = _node(Vector3(WHEEL_RUN.x, 1.63, -2.14), self)
	wheel.scale = Vector3.ONE * 1.41
	var shell: Array[Vector2] = [Vector2(0.0, -0.42), Vector2(0.92, -0.42), Vector2(1.055, -0.39),
		Vector2(1.08, -0.29), Vector2(1.08, 0.30), Vector2(1.07, 0.36), Vector2(1.025, 0.36),
		Vector2(1.015, 0.29), Vector2(1.015, -0.25), Vector2(0.94, -0.32), Vector2(0.0, -0.32)]
	_mesh(Meshes.lathe(shell), Vector3.ZERO, sage, wheel).rotation.x = PI / 2
	_cylinder(Vector3(0, 0, -0.29), 0.19, 0.10, trim, wheel).rotation.x = PI / 2
	_cylinder(Vector3(0, 0, -0.21), 0.12, 0.08, trim, wheel).rotation.x = PI / 2
	for index in range(12):
		var angle := TAU * index / 12.0
		var seam := _box(Vector3(sin(angle) * 0.56, cos(angle) * 0.56, -0.315), Vector3(0.008, 0.70, 0.006), tread, wheel)
		seam.rotation.z = -angle
	for index in range(32):
		var angle := TAU * index / 32
		var slat := _box(Vector3(sin(angle), cos(angle), 0) * 1.018, Vector3(0.018, 0.014, 0.60), tread, wheel)
		slat.rotation.z = -angle
	_ring(Vector3(0, 0, 0.36), 1.015, 1.10, trim, wheel)
	_contact(Vector3(WHEEL_RUN.x, 0.076, -1.9), Vector2(3.5, 2.6), self)

func _supplies() -> void:
	var ceramic := _material(Color("#c39463"))
	var lip := _speckled(Color("#e0cdb1"))
	var bowl := _node(Vector3(BOWL.x, 0.07, BOWL.y), self)
	bowl.scale = Vector3.ONE * 1.55
	_contact(Vector3(0, 0.01, 0), Vector2(1.5, 1.5), bowl)
	var bowl_profile: Array[Vector2] = [Vector2(0, 0), Vector2(0.37, 0), Vector2(0.43, 0.04),
		Vector2(0.48, 0.27), Vector2(0.47, 0.31), Vector2(0.43, 0.32), Vector2(0.40, 0.28),
		Vector2(0.35, 0.10), Vector2(0, 0.09)]
	_mesh(Meshes.lathe(bowl_profile), Vector3.ZERO, lip, bowl)
	var leaf_color := _material(Color("#72805c"))
	for angle in [-0.65, 0.0, 0.65]:
		var decoration := _node(Vector3(sin(angle) * 0.465, 0.19, cos(angle) * 0.465), bowl)
		decoration.rotation.y = angle
		_box(Vector3(0, -0.02, 0), Vector3(0.006, 0.14, 0.005), leaf_color, decoration)
		for side in [-1.0, 1.0]:
			var leaf := _ellipsoid(Vector3(side * 0.026, side * 0.032, 0), Vector3(0.019, 0.038, 0.003), leaf_color, decoration)
			leaf.rotation.z = side * 0.62
	seeds = _node(Vector3.ZERO, bowl)
	var grain := _speckled(Color("#b48d50"), 1.0)
	var sunflower := _speckled(Color("#514638"), 2.0)
	var oat := _speckled(Color("#c9b78d"), 1.0)
	for index in range(90):
		var angle := index * 2.39996
		var r := 0.37 * sqrt(float(index) / 90.0)
		var material := sunflower if index % 4 == 0 else (grain if index % 3 == 0 else oat)
		var seed := _ellipsoid(Vector3(cos(angle) * r, 0.27 - r * 0.16 + sin(angle * 3.0) * 0.012, sin(angle) * r),
			Vector3(0.029, 0.020, 0.066) if index % 4 == 0 else Vector3(0.024, 0.023, 0.048), material, seeds)
		seed.rotation.y = angle
		seed.rotation.x = sin(angle) * 0.2
		seed_parts.append(seed)
	var bottle := _node(Vector3(DRINK.x, 0, -3.52), self)
	bottle.scale = Vector3.ONE * 1.40
	var mounting := _material(Color("#c8a47d"))
	mounting.albedo_texture = wood_texture
	_box(Vector3(0, 1.29, -0.205), Vector3(0.72, 1.05, 0.10), mounting, bottle)
	var cap := _material(Color("#a9b79b"), 0.34)
	var glass := _material(Color("#e9e8dc28"), 0.10)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.render_priority = 1
	var metal := _material(Color("#b5b6ae"), 0.18)
	metal.metallic = 0.80
	for side in [-1.0, 1.0]:
		for height in [0.95, 1.63]:
			_cylinder(Vector3(side * 0.29, height, -0.135), 0.043, 0.018, metal, bottle).rotation.x = PI / 2
			_box(Vector3(side * 0.29, height, -0.122), Vector3(0.035, 0.007, 0.004), ceramic, bottle)
	var bottle_shape: Array[Vector2] = [Vector2(0.15, 0.87), Vector2(0.22, 0.94), Vector2(0.235, 1.04), Vector2(0.235, 1.72), Vector2(0.22, 1.80), Vector2(0.15, 1.83)]
	_mesh(Meshes.lathe(bottle_shape), Vector3.ZERO, glass, bottle).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var water_material := _material(Color("#79b5c4a8"), 0.16)
	water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_material.render_priority = -1
	water = _node(Vector3(0, WATER_BOTTOM + WATER_HEIGHT, 0), bottle)
	water_column = _cylinder(Vector3(0, -WATER_HEIGHT * 0.5, 0), 0.20, WATER_HEIGHT, water_material, water)
	water_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface := _material(Color("#a5d6dcdb"), 0.19)
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring(Vector3.ZERO, 0.183, 0.205, surface, water, false)
	for index in range(9):
		_ellipsoid(Vector3(sin(index * 2.4) * 0.12, -0.27 + index * 0.063, 0.15), Vector3.ONE * (0.008 + (index % 3) * 0.004), glass, water_column).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var highlight := _material(Color("#fff9e96c"))
	highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box(Vector3(-0.14, 1.40, 0.171), Vector3(0.018, 0.66, 0.005), highlight, bottle).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for y in [1.12, 1.32, 1.52, 1.72]:
		_box(Vector3(0.14, y, 0.184), Vector3(0.06, 0.008, 0.004), metal, bottle)
	var cap_shape: Array[Vector2] = [Vector2(0, 1.77), Vector2(0.22, 1.77), Vector2(0.25, 1.80), Vector2(0.25, 1.91), Vector2(0.22, 1.96), Vector2(0, 1.96)]
	_mesh(Meshes.lathe(cap_shape), Vector3.ZERO, cap, bottle)
	_cylinder(Vector3(0, 1.99, 0), 0.085, 0.05, cap, bottle)
	var funnel: Array[Vector2] = [Vector2(0.055, 0.77), Vector2(0.06, 0.81), Vector2(0.20, 0.86), Vector2(0.25, 0.92), Vector2(0.25, 1.0), Vector2(0.22, 1.01), Vector2(0.20, 0.94)]
	_mesh(Meshes.lathe(funnel), Vector3.ZERO, cap, bottle)
	var nozzle := _node(Vector3(0, 0.78, 0.02), bottle)
	nozzle.rotation.x = -0.70
	_cylinder(Vector3(0, -0.23, 0), 0.043, 0.46, metal, nozzle)
	_cylinder(Vector3(0, -0.463, 0), 0.029, 0.004, _material(Color("#373732")), nozzle)
	_ellipsoid(Vector3(0, -0.47, 0), Vector3.ONE * 0.018, metal, nozzle)

func _pet(index: int) -> void:
	var root := _node(Vector3.ZERO, self)
	pets.append(root)
	poses.append({"ready": false, "ground": 0.0, "stride": 0.0, "sleep": 0.0, "fight": 0.0, "held": 0.0,
		"head_y": 0.325, "head_pitch": 0.0, "crouch": 0.0})
	_contact(Vector3(0, 0.065, -0.06), Vector2(1.5, 1.7), root)
	var ear_fur := _material(Color("#a49682") if index == 0 else Color("#d7cabc"))
	var pink := _material(Color("#bd9687"), 0.57)
	var eyes := _material(Color("#100d0b"), 0.055)
	var shine := _material(Color("#fff6df"), 0.12)
	_furred_part(BODY_CENTER, BODY_RADII, 6500, index, false, root)
	var head := _node(Vector3(0, 0.325, 0.235), root)
	heads.append(head)
	var head_radii := Vector3(0.245, 0.225, 0.245)
	_furred_part(Vector3.ZERO, head_radii, 5200, index, true, head)
	var paws: Array[Node3D] = []
	var legs: Array[Node3D] = []
	var pair: Array[Node3D] = []
	var ear_pair: Array[Node3D] = []
	var whisker_pair: Array[Node3D] = []
	var ear_material := _material(Color.WHITE, 0.84)
	ear_material.vertex_color_use_as_albedo = true
	ear_material.vertex_color_is_srgb = true
	ear_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mouth := _material(Color("#956d60"), 0.75)
	var whisker_color := _material(Color("#b9ad99"), 0.78)
	var ear_edge := _material(Color("#bca58d") if index == 0 else Color("#d5c5ae"))
	ear_edge.metallic_specular = 0.06
	var nail := _material(Color("#d1b9a7"), 0.55)
	for side in [-1.0, 1.0]:
		var ear := _node(Vector3(side * 0.158, 0.182, -0.048), head)
		ear.rotation = Vector3(0.05, side * 0.43, -side * 0.23)
		_mesh(Hamster.ear(index), Vector3.ZERO, ear_material, ear)
		_mesh(Hamster.ear_rim(), Vector3.ZERO, ear_edge, ear)
		_mesh(Hamster.curve(Vector3(-0.042, -0.043, -0.012), Vector3(-0.040, 0.010, -0.010), Vector3(0.028, -0.01, -0.005), Vector3(0.025, -0.066, -0.003), 0.0035, 0.002), Vector3.ZERO, ear_fur, ear)
		ear_pair.append(ear)
		var eye_unit := Vector3(side * 0.72, 0.30, 0.625).normalized()
		var eye_normal := Hamster.normal(eye_unit, head_radii, true)
		var eye := _node(Hamster.point(eye_unit, head_radii, true) - eye_normal * 0.012, head)
		eye.quaternion = Quaternion(Vector3.BACK, eye_normal)
		_ellipsoid(Vector3.ZERO, Vector3(0.040, 0.045, 0.029), eyes, eye)
		_ellipsoid(Vector3(-0.007, 0.011, 0.025), Vector3(0.005, 0.007, 0.0015), shine, eye)
		_ellipsoid(Vector3(0.008, -0.011, 0.025), Vector3(0.0018, 0.0025, 0.001), shine, eye)
		pair.append(eye)
		var fan := _node(Vector3.ZERO, head)
		whisker_pair.append(fan)
		for offset in range(7):
			var rise := (offset - 3) * 0.026
			var start := Vector3(side * (0.047 + offset * 0.007), -0.057 - offset * 0.004, 0.232 - offset * 0.004)
			_mesh(Hamster.curve(start, start + Vector3(side * 0.10, rise * 0.3, 0.02), Vector3(side * 0.27, -0.07 + rise, 0.30), Vector3(side * (0.35 + offset * 0.008), -0.08 + rise * 0.9, 0.26 - offset * 0.014), 0.0010), Vector3.ZERO, whisker_color, fan)
			_ellipsoid(start - Vector3(0, 0, 0.002), Vector3.ONE * 0.0023, mouth, head)
		for z in [-0.28, 0.27]:
			var paw := _node(Vector3(side * 0.175, 0.049, z), root)
			_ellipsoid(Vector3(0, 0.007, -0.010), Vector3(0.026, 0.018, 0.050), pink, paw)
			for toe in range(4):
				var toe_position := Vector3((toe - 1.5) * 0.012, -0.004, 0.039 + (1.5 - absf(toe - 1.5)) * 0.006)
				_ellipsoid(toe_position, Vector3(0.0065, 0.007, 0.025), pink, paw)
				_ellipsoid(toe_position + Vector3(0, 0.002, 0.023), Vector3(0.0035, 0.0035, 0.006), nail, paw)
			paws.append(paw)
			var leg := _node(Vector3.ZERO, root)
			_furred_part(Vector3.ZERO, Vector3(0.024, 0.10, 0.026), 650, index + 2, false, leg)
			legs.append(leg)
		_mesh(Hamster.curve(Vector3(0, -0.066, 0.257), Vector3(side * 0.010, -0.075, 0.253), Vector3(side * 0.021, -0.075, 0.248), Vector3(side * 0.028, -0.068, 0.242), 0.0018, 0.0008), Vector3.ZERO, mouth, head)
	feet.append(paws)
	limbs.append(legs)
	eyelids.append(pair)
	ears.append(ear_pair)
	whiskers.append(whisker_pair)
	noses.append(_ellipsoid(Vector3(0, -0.035, 0.259), Vector3(0.024, 0.016, 0.014), pink, head))
	_mesh(Hamster.curve(Vector3(0, -0.047, 0.265), Vector3(0, -0.052, 0.262), Vector3(0, -0.061, 0.259), Vector3(0, -0.067, 0.257), 0.0015, 0.0014), Vector3.ZERO, mouth, head)
	for side in [-1.0, 1.0]:
		_ellipsoid(Vector3(side * 0.012, -0.035, 0.271), Vector3(0.003, 0.002, 0.0015), mouth, head)

func _make_grip() -> void:
	grip = _node(Vector3.ZERO, self)
	grip.visible = false
	grip_pivot = _node(Vector3.ZERO, grip)
	var skin := ShaderMaterial.new()
	skin.shader = preload("res://assets/finger_skin.gdshader")
	skin.set_shader_parameter("skin_tint", Color("#d5a38c"))
	skin.set_shader_parameter("nail_tint", Color("#e2b6a9"))
	for side in [-1.0, 1.0]:
		var thumb: bool = side < 0.0
		# 指尖落在肩侧的毛发里，控制点往外弯，给圆弧形指腹留出空间。
		var direction := Vector3(side, 0.16, 0.30).normalized()
		var tip := BODY_CENTER + Hamster.point(direction, BODY_RADII, false) + Vector3(side * 0.016, 0, 0)
		var base := Vector3(side * (0.46 if thumb else 0.435), 0.72 if thumb else 0.79, -0.08 if thumb else -0.12)
		var finger := _node(base, grip_pivot)
		var curve := Meshes.finger(tip - base, tip - base + Vector3(side * 0.096, 0.035, 0.02),
			Vector3(side * 0.025, -0.14, 0.06), 0.087 if thumb else 0.072)
		_mesh(curve, Vector3.ZERO, skin, finger).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		grip_fingers.append(finger)

func show_grip(index: int, delta: float) -> void:
	if index >= 0 and pets[index].visible:
		if grip_owner != index:
			grip_owner = index
			grip_progress = 0.0
		# 和身体共用姿态与体型，挣扎和成长时指尖仍贴住肩侧。
		grip.transform = pets[index].transform
		grip_progress = move_toward(grip_progress, 1.0, delta * 7.0)
	elif grip_owner >= 0:
		# 松手后从最后的抓握位置张开上移，和正在落下的仓鼠分开。
		grip_progress = move_toward(grip_progress, 0.0, delta * 8.0)
		if grip_progress <= 0.0:
			grip_owner = -1
	else:
		return
	grip.visible = grip_progress > 0.0
	var closed := smoothstep(0.0, 1.0, grip_progress)
	grip_pivot.position.y = 0.47 * (1.0 - closed)
	grip_fingers[0].rotation.z = -0.37 * (1.0 - closed)
	grip_fingers[1].rotation.z = 0.31 * (1.0 - closed)

func _furred_part(center: Vector3, radii: Vector3, count: int, index: int, is_head: bool, host: Node3D) -> void:
	var base := ShaderMaterial.new()
	base.shader = load("res://assets/hamster_undercoat.gdshader")
	_mesh(Hamster.skin(radii, index, is_head), center, base, host)
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/hamster_tufts.gdshader")
	var patch := _mesh(Hamster.tufts(radii, count, index, is_head), center, material, host)
	# 用实体底毛投影，毛束仅负责柔和边缘，避免移动端重复绘制全部细毛阴影。
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if index < 2:
		var guard_material := _material(Color.WHITE, 0.88)
		guard_material.vertex_color_use_as_albedo = true
		guard_material.vertex_color_is_srgb = true
		guard_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		guard_material.metallic_specular = 0.10
		_mesh(Hamster.tufts(radii, 1800 if is_head else 2400, index, is_head, true), center, guard_material, host).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func show_pet(index: int, actor: Dictionary, alive: bool, delta: float = 1.0 / 60.0) -> void:
	var pet := pets[index]
	pet.visible = alive
	if not alive:
		return
	var point: Vector2 = actor.pos
	var moving: bool = actor.state in ["走", "跑", "嬉戏"]
	var phase: float = actor.phase
	var gait: float = actor.get("gait", 0.0)
	var pose := poses[index]
	var blend := 1.0 - exp(-delta * 10.0)
	var stride_target := 1.0 if actor.state == "跑" else (clampf(float(actor.get("speed", 0.0)) / 1.0, 0, 1) if moving else 0.0)
	pose.stride = lerpf(pose.stride, stride_target, blend)
	pose.sleep = lerpf(pose.sleep, 1.0 if actor.state == "睡" else 0.0, blend)
	var fighting: bool = actor.state == "打架"
	pose.fight = lerpf(pose.fight, 1.0 if fighting else 0.0, blend)
	pose.held = lerpf(pose.held, 1.0 if actor.state == "抱起" else 0.0, blend)
	var wriggle: float = (0.76 + 0.24 * sin(phase * 5.0)) * pose.held
	var fight_swing: float = actor.fight_swing if fighting else 0.0
	var strike := maxf(fight_swing, 0.0)
	var recoil := maxf(-fight_swing, 0.0)
	var near_wheel := 1.0 - smoothstep(0.24, 0.70, absf(point.x - WHEEL_RUN.x))
	var on_wheel := clampf((WHEEL_ENTRY.y - point.y) / (WHEEL_ENTRY.y - WHEEL_RUN.y), 0, 1) * near_wheel
	var ground_height := Meshes.bedding_height(point.x, point.y) + 0.025 + on_wheel * 0.12
	pose.ground = lerpf(pose.ground, ground_height, blend) if pose.ready else ground_height
	pose.ready = true
	pose.crouch = lerpf(pose.crouch, -0.025 if actor.state == "便便" else 0.0, blend)
	# 身体轻微起伏与落脚共享同一相位，去掉与步态无关的高频弹跳。
	var bob: float = (1.0 - cos(gait * 2.0)) * 0.006 * pose.stride
	pet.position = Vector3(point.x, pose.ground + bob + pose.crouch + float(actor.get("lift", 0.0)), point.y)
	if actor.state == "嬉戏":
		pet.position.y += pow(maxf(0, sin(phase * 6)), 2) * 0.06
	pet.rotation.y = actor.dir
	# 打架时后脚撑地，身体抬起，挥爪方前倾，另一只后仰。
	pet.rotation.x = (-0.48 + 0.17 * strike - 0.13 * recoil) * pose.fight
	pet.position.y += 0.15 * pose.fight
	# 身体轻轻摆动，四脚用错开的节奏蹬动。
	pet.rotation.x += sin(phase * 15.0) * 0.10 * wriggle
	pet.rotation.z = sin(phase * 12.0 + 0.4) * 0.13 * wriggle
	var size_ratio: float = actor.get("size_ratio", 1.0)
	var pet_scale: float = ADULT_SIZE[index] * size_ratio
	pet.scale = Vector3(pet_scale, pet_scale * lerpf(1.0, 0.74, pose.sleep), pet_scale)
	pet.scale.y *= 1.0 + sin(phase * 2.7) * 0.008 * (1.0 - pose.stride)
	heads[index].scale = Vector3.ONE * (1.0 + (1.0 - size_ratio) * 0.24)
	if actor.get("lift", 0.0) <= 0.01 and actor.state != "抱起":
		# 穿过较窄的窝门时稍微缩肩，越过门洞后恢复体型。
		for door in CUBBIES:
			var close_to_door := (1.0 - smoothstep(0.18, 0.50, absf(point.x - door.x))) * \
				(1.0 - smoothstep(0.24, 0.76, absf(point.y - door.y + 0.24)))
			pet.scale.x *= lerpf(1.0, 0.73, close_to_door)
			pet.scale.y *= lerpf(1.0, 0.91, close_to_door)
	var head_pitch: float = -0.3 if actor.state == "回应" else sin(phase * 2.4) * 0.015 + sin(gait) * 0.018 * pose.stride
	var head_height := 0.375 if actor.state == "回应" else 0.325
	if actor.state == "吃":
		head_pitch = 0.22 + 0.09 * sin(phase * 17.0)
		head_height = 0.30 + 0.012 * sin(phase * 17.0)
	elif actor.state == "喝":
		head_pitch = -0.25 - (1.0 - size_ratio) * 0.28 + 0.055 * sin(phase * 18.0)
		head_height = 0.36 + (1.0 - size_ratio) * 0.25
	head_pitch = lerpf(head_pitch, 0.28 + 0.12 * strike, pose.fight)
	head_pitch += (0.12 * sin(phase * 16.0 + 0.7) - 0.10) * wriggle
	pose.head_pitch = lerpf(pose.head_pitch, head_pitch, blend)
	pose.head_y = lerpf(pose.head_y, head_height, blend)
	heads[index].rotation.x = pose.head_pitch
	heads[index].position.y = pose.head_y
	# 眨眼与轻微鼻尖抽动按各自相位播放，不修改任何照料计时。
	var blink := absf(fmod(phase + index * 1.7, 5.4) - 5.15)
	for eye in eyelids[index]:
		eye.scale.y = 0.12 if actor.state == "睡" else lerpf(0.14, 1.0, smoothstep(0, 0.10, blink))
	noses[index].scale.x = 0.048 * (1.0 + sin(phase * 13.0) * 0.045)
	for side in range(2):
		var sign_value := -1.0 if side == 0 else 1.0
		ears[index][side].rotation.z = -sign_value * (0.23 + sin(phase * 4.2 + side) * 0.018)
		whiskers[index][side].rotation.y = sin(phase * 6.0 + side) * 0.012
	for offset in range(feet[index].size()):
		var paw: Node3D = feet[index][offset]
		var front := offset % 2 == 1
		var side := -1.0 if offset < 2 else 1.0
		var cycle := fposmod(gait / TAU + (0.5 if offset in [1, 2] else 0.0), 1.0)
		var swing := clampf((cycle - 0.62) / 0.38, 0, 1)
		var reach := lerpf(0.13, -0.13, cycle / 0.62) if cycle < 0.62 else lerpf(-0.13, 0.13, smoothstep(0, 1, swing))
		var lift: float = pow(sin(swing * PI), 2) * 0.055 * pose.stride
		var target := Vector3(side * 0.175, 0.049 + lift, (0.27 if front else -0.28) + reach * pose.stride)
		var toe_angle: float = sin(swing * TAU) * 0.16 * pose.stride
		if actor.state != "睡":
			var world_paw := pet.to_global(target)
			var ground := Meshes.bedding_height(world_paw.x, world_paw.z) + 0.033
			var local_ground := pet.to_local(Vector3(world_paw.x, ground, world_paw.z))
			var planted := (1.0 - on_wheel) * (1.0 - smoothstep(0.0, 0.25, float(actor.get("lift", 0.0))))
			target.y = lerpf(target.y, local_ground.y + lift, planted)
		if front and pose.fight > 0.001:
			var reach_forward := strike if offset == 3 else 0.0
			var raised_paw := Vector3(side * 0.14, 0.19 - reach_forward * 0.05, 0.33 + reach_forward * 0.25)
			target = target.lerp(raised_paw, pose.fight)
			toe_angle = lerpf(toe_angle, -0.55 + reach_forward * 0.75, pose.fight)
		if pose.held > 0.001:
			var kick_phase := phase * (19.0 if front else 21.0) + side * PI * 0.5 + (0.8 if front else 0.0)
			var kick := sin(kick_phase)
			var dangling := Vector3(side * (0.18 + 0.035 * cos(kick_phase)),
				-0.025 + kick * 0.060, (0.27 if front else -0.27) + cos(kick_phase) * 0.11)
			target = target.lerp(dangling, pose.held)
			toe_angle = lerpf(toe_angle, kick * 0.46, pose.held)
		paw.position = paw.position.lerp(target, 1.0 - exp(-delta * 24.0))
		if actor.state != "睡" and on_wheel < 0.01 and float(actor.get("lift", 0.0)) < 0.01:
			# 身体高度有缓动，脚掌仍须落在表面以上，不能因追赶目标高度而陷入垫料。
			var planted_position := paw.global_position
			planted_position.y = maxf(planted_position.y, Meshes.bedding_height(planted_position.x, planted_position.z) + 0.033)
			paw.global_position = planted_position
		paw.rotation.x = lerpf(paw.rotation.x, toe_angle, blend)
		var attachment := Vector3(side * (0.145 if front else 0.205), 0.17 if front else 0.165, 0.18 if front else -0.27)
		var wrist := paw.position + Vector3(0, 0.027, -0.016)
		var limb: Node3D = limbs[index][offset]
		limb.position = (attachment + wrist) * 0.5
		limb.quaternion = Quaternion(Vector3.UP, (attachment - wrist).normalized())
		limb.scale.y = (attachment - wrist).length() / 0.20 + 0.14

func update_supplies(angle: float, food: float, fill: float, dirty: float) -> void:
	wheel.rotation.z = angle
	for index in range(seed_parts.size()):
		seed_parts[index].visible = index < ceili(food * seed_parts.size())
	water.visible = fill > 0.0
	if water.visible:
		# 液柱从瓶底往上缩放，液面环保持厚度，少量水也能看清。
		var depth := WATER_HEIGHT * fill
		water.position.y = WATER_BOTTOM + depth
		water_column.position.y = -depth * 0.5
		water_column.scale.y = fill
	if is_equal_approx(dirt, dirty):
		return
	dirt = dirty
	var colors := ["#dac4a1", "#ead9bb", "#e9dfc9", "#dbc9aa", "#d4c3a9"]
	for index in range(grounds.size()):
		grounds[index].set_shader_parameter("tint", Color(colors[index]).lerp(Color("#a7896b"), dirt * 0.57))

func update_light(night: bool, delta: float) -> void:
	var target := 1.0 if night else 0.0
	night_mix = move_toward(night_mix, target, delta * 0.55) if night_mix >= 0.0 else target
	sun.light_color = Color("#fff0d6").lerp(Color("#d8e3ff"), night_mix)
	sun.light_energy = lerpf(0.67, 0.31, night_mix)

func hit(index: int, point: Vector2) -> bool:
	var bounds := Rect2()
	var first := true
	# 投影完整身体包围盒，让毛发边缘和后背也能接收轻点。
	for x in [-0.43, 0.43]:
		for y in [-0.02, 0.70]:
			for z in [-0.61, 0.59]:
				var corner: Vector3 = pets[index].global_transform * Vector3(x, y, z)
				if camera.is_position_behind(corner):
					continue
				var projected := camera.unproject_position(corner)
				bounds = Rect2(projected, Vector2.ZERO) if first else bounds.expand(projected)
				first = false
	return not first and bounds.grow(8).has_point(point)

func floor_point(screen: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var result: Variant = Plane(Vector3.UP, 0.12).intersects_ray(origin, direction)
	return Vector2(result.x, result.z) if result != null else Vector2(0, 3)

func drop_target_at(screen: Vector2) -> Dictionary:
	# 设施有高度，按可见范围选目标；落地仍走安全地面的规则。
	var closest := INF
	var selected: Dictionary = {}
	for target in DROP_TARGETS:
		var area: AABB = target.area
		var bounds := Rect2(camera.unproject_position(area.position), Vector2.ZERO)
		for corner in range(1, 8):
			bounds = bounds.expand(camera.unproject_position(area.get_endpoint(corner)))
		bounds = bounds.grow(8.0)
		if bounds.has_point(screen):
			var distance := ((screen - bounds.get_center()) / bounds.size).length_squared()
			if distance < closest:
				closest = distance
				selected = target
	return selected

func nudge_bedding(at: Vector3, direction: Vector2) -> void:
	var cell := Vector2i(floori(at.x * 2), floori(at.z * 2))
	var moved := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for reference in bedding_cells.get(cell + Vector2i(dx, dz), []):
				var batch := bedding_layers[reference.x]
				var transform := batch.get_instance_transform(reference.y)
				var offset := Vector2(transform.origin.x - at.x, transform.origin.z - at.z)
				if offset.length() > 0.20 or moved >= 12:
					continue
				if not displaced.has(reference):
					displaced[reference] = transform
				var push := (offset.normalized() + direction * 0.3) * 0.055
				transform.origin += Vector3(push.x, -0.015, push.y)
				# 反复经过也只压实表层，不让同一片木屑持续下沉到地面以下。
				var original: Transform3D = displaced[reference]
				transform.origin = original.origin + (transform.origin - original.origin).limit_length(0.16)
				transform.origin.y = maxf(transform.origin.y, Meshes.bedding_height(transform.origin.x, transform.origin.z) + 0.003)
				batch.set_instance_transform(reference.y, transform)
				moved += 1
	for i in range(4):
		if flying_chips.size() >= 128:
			break
		flying_chips.append({"p": Vector3(at.x, Meshes.bedding_height(at.x, at.z) + 0.04, at.z),
			"v": Vector3(direction.x * 0.20 + randf_range(-0.35, 0.35), randf_range(0.3, 0.7), direction.y * 0.20 + randf_range(-0.35, 0.35)),
			"age": 0.0, "angle": randf_range(0, TAU)})

func tick_bedding(delta: float) -> void:
	for i in range(flying_chips.size() - 1, -1, -1):
		var chip := flying_chips[i]
		chip.age += delta
		if chip.age > 0.85:
			flying_chips.remove_at(i)
			continue
		chip.v.y -= delta * 3.5
		chip.p += chip.v * delta
		var floor_y := Meshes.bedding_height(chip.p.x, chip.p.z) + 0.015
		if chip.p.y < floor_y:
			chip.p.y = floor_y
			chip.v *= Vector3(0.8, -0.20, 0.8)
	chip_cloud.multimesh.visible_instance_count = flying_chips.size()
	for i in range(flying_chips.size()):
		var chip := flying_chips[i]
		var scale_value := 0.65 * (1.0 - smoothstep(0.60, 0.85, chip.age))
		chip_cloud.multimesh.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(chip.age * 3, chip.angle, 0)).scaled(Vector3.ONE * scale_value), chip.p))

func clean_bedding() -> void:
	for reference in displaced:
		bedding_layers[reference.x].set_instance_transform(reference.y, displaced[reference])
	displaced.clear()
	flying_chips.clear()
	chip_cloud.multimesh.visible_instance_count = 0

func sync_droppings(items: Array) -> void:
	var signature := JSON.stringify(items)
	if signature == waste_signature:
		return
	waste_signature = signature
	var total := 0
	for item in items:
		total += int(item.get("count", 3))
	waste_model.multimesh.instance_count = total
	var instance := 0
	for i in range(items.size()):
		var item: Dictionary = items[i]
		var count: int = int(item.get("count", 3))
		for j in range(count):
			var x: float = item.x + (j - (count - 1) * 0.5) * 0.072
			var z: float = item.z + sin(i * 2.1 + j) * 0.055
			var pose := Basis.from_euler(Vector3(0, i * 2.39 + j, 0)).scaled(Vector3(0.070, 0.045, 0.125))
			waste_model.multimesh.set_instance_transform(instance, Transform3D(pose, Vector3(x, Meshes.bedding_height(x, z) + 0.024, z)))
			instance += 1
