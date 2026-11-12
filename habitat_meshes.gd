extends RefCounted

# 固定分段的圆角和旋转曲面，供木窝、陶碗、滚轮共用。
static func rounded_box(dimensions: Vector3, radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := dimensions * 0.5
	var inner := half - Vector3.ONE * radius
	for axis in range(3):
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1
			var v := normal.cross(u)
			var extent_u := half[(axis + 1) % 3]
			var extent_v := absf(v.dot(half))
			var us := [-extent_u, -extent_u + radius * 0.3, -extent_u + radius, 0.0, extent_u - radius, extent_u - radius * 0.3, extent_u]
			var vs := [-extent_v, -extent_v + radius * 0.3, -extent_v + radius, 0.0, extent_v - radius, extent_v - radius * 0.3, extent_v]
			for y in range(6):
				for x in range(6):
					for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
						var point: Vector3 = normal * half[axis] + u * us[x + offset.x] + v * vs[y + offset.y]
						var clamped := point.clamp(-inner, inner)
						var n := (point - clamped).normalized()
						surface.set_normal(n)
						surface.set_uv(Vector2(us[x + offset.x] / dimensions[(axis + 1) % 3] + 0.5, vs[y + offset.y] / (extent_v * 2.0) + 0.5))
						surface.add_vertex(clamped + n * radius)
	return surface.commit()

static func lathe(profile: Array[Vector2], segments: int = 80) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		for row in range(profile.size() - 1):
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var angle := TAU * float(i + corner.x) / segments
				var ring := profile[row + corner.y]
				surface.set_uv(Vector2(float(i + corner.x) / segments, float(row + corner.y) / (profile.size() - 1)))
				surface.add_vertex(Vector3(cos(angle) * ring.x, ring.y, sin(angle) * ring.x))
	surface.generate_normals()
	return surface.commit()

static func finger(tip: Vector3, first_control: Vector3, second_control: Vector3, radius: float) -> ArrayMesh:
	# 以指根为旋转轴，截面沿三维曲线弯向指尖。
	var profile := PackedVector2Array([
		Vector2(0, 0), Vector2(0.38, 0.009), Vector2(0.62, 0.024), Vector2(0.80, 0.045),
		Vector2(0.92, 0.073), Vector2(0.99, 0.11), Vector2(1, 0.17), Vector2(0.98, 0.24),
		Vector2(0.95, 0.30), Vector2(0.94, 0.36), Vector2(0.98, 0.42), Vector2(1.03, 0.48),
		Vector2(1.01, 0.54), Vector2(0.97, 0.61), Vector2(0.95, 0.68), Vector2(0.96, 0.76),
		Vector2(0.98, 0.84), Vector2(0.95, 0.91), Vector2(0.84, 0.955), Vector2(0.57, 0.989),
		Vector2(0, 1)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 32
	for i in range(sides):
		for row in range(profile.size() - 1):
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var angle := TAU * float((i + corner.x) % sides) / sides
				var ring := profile[row + corner.y]
				var center := tip.bezier_interpolate(first_control, second_control, Vector3.ZERO, ring.y)
				var axis := tip.bezier_derivative(first_control, second_control, Vector3.ZERO, ring.y).normalized()
				var across := axis.cross(Vector3.BACK).normalized()
				var depth := across.cross(axis)
				surface.set_uv(Vector2(float(i + corner.x) / sides, ring.y))
				surface.add_vertex(center + (across * cos(angle) + depth * sin(angle) * 0.84) * ring.x * radius)
	surface.generate_normals()
	return surface.commit()

# 凸轮廓挤出并倒圆前后边缘，避免木屋屋顶像两块拼接的薄板。
static func roof() -> ArrayMesh:
	var corners := PackedVector2Array([Vector2(-0.78, 0.94), Vector2(0.78, 0.94), Vector2(0, 1.46)])
	var contour := PackedVector2Array()
	for i in range(corners.size()):
		var current := corners[i]
		var incoming := current + (corners[posmod(i - 1, 3)] - current).normalized() * 0.13
		var outgoing := current + (corners[(i + 1) % 3] - current).normalized() * 0.13
		for step in range(12):
			var t := float(step) / 11.0
			contour.append(incoming.lerp(current, t).lerp(current.lerp(outgoing, t), t))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector2(0, 1.13)
	for sign_value in [-1.0, 1.0]:
		for i in range(contour.size()):
			var next := (i + 1) % contour.size()
			var cap := PackedVector2Array([center, contour[next], contour[i]]) if sign_value > 0 else PackedVector2Array([center, contour[i], contour[next]])
			for point in cap:
				surface.set_normal(Vector3(0, 0, sign_value))
				surface.set_uv(Vector2(point.x + 0.8, point.y - 0.3))
				surface.add_vertex(Vector3(point.x, point.y, sign_value * 0.80))
			for band in range(4):
				for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
					var k: int = (i + offset.x) % contour.size()
					var tangent := (contour[(k + 1) % contour.size()] - contour[posmod(k - 1, contour.size())]).normalized()
					var outward := Vector2(tangent.y, -tangent.x)
					var angle: float = (band + offset.y) * PI / 8.0
					var point := contour[k] + outward * sin(angle) * 0.055
					surface.set_normal(Vector3(outward.x * sin(angle), outward.y * sin(angle), sign_value * cos(angle)))
					surface.set_uv(Vector2(point.x + 0.8, point.y - 0.3))
					surface.add_vertex(Vector3(point.x, point.y, sign_value * (0.745 + cos(angle) * 0.055)))
	for i in range(contour.size()):
		for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			var k: int = (i + offset.x) % contour.size()
			var tangent := (contour[(k + 1) % contour.size()] - contour[posmod(k - 1, contour.size())]).normalized()
			var outward := Vector2(tangent.y, -tangent.x)
			var point := contour[k] + outward * 0.055
			surface.set_normal(Vector3(outward.x, outward.y, 0))
			surface.set_uv(Vector2(point.x + 0.8, float(offset.y)))
			surface.add_vertex(Vector3(point.x, point.y, -0.745 + offset.y * 1.49))
	return surface.commit()

static func bedding_height(x: float, z: float) -> float:
	var path := sin(z * 0.72) * 0.74 + 0.22
	var packed := smoothstep(0.39, 1.0, absf(x - path))
	var height := 0.025 + packed * (0.19 + 0.13 * sin(x * 1.6) * sin(z * 1.2) + 0.035 * sin(x * 4.4 + z))
	height += packed * smoothstep(3.5, 6.5, absf(x)) * 0.23
	# 后排和食盆周边逐渐变薄；硬截断会让身体和脚掌跨边界时突然上下跳。
	var back_blend := smoothstep(-1.95, -1.30, z)
	var bowl_blend := smoothstep(0.82, 1.12, Vector2(x + 2.90, z - 0.75).length())
	return lerpf(0.025, height, back_blend * bowl_blend)

static func bedding() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(60):
		for x in range(80):
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var px: float = -8.0 + (x + offset.x) * 0.2
				var pz: float = -4.0 + (z + offset.y) * 0.2
				surface.set_uv(Vector2(px, pz) * 0.22)
				surface.add_vertex(Vector3(px, bedding_height(px, pz), pz))
	surface.generate_normals()
	return surface.commit()
