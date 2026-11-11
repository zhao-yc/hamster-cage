extends RefCounted

# 身体与毛束使用同一曲面；脸颊、眼窝的改形会同步传到毛根，避免穿模。
static func point(unit: Vector3, radii: Vector3, head: bool) -> Vector3:
	var p := unit * radii
	if radii.y > radii.x * 2.0:
		return p
	if head:
		var front := smoothstep(-0.10, 0.95, unit.z)
		p.x *= 1.0 - front * 0.06
		p.y -= front * 0.025
		var cheek := exp(-pow((absf(unit.x) - 0.62) / 0.32, 2) - pow((unit.y + 0.37) / 0.43, 2)) * smoothstep(0.0, 0.60, unit.z)
		p.x += signf(unit.x) * cheek * 0.045
		p.z += cheek * 0.024 + pow(maxf(unit.z, 0.0), 9.0) * 0.015
		var socket := exp(-pow((absf(unit.x) - 0.76) / 0.15, 2) - pow((unit.y - 0.27) / 0.17, 2) - pow((unit.z - 0.56) / 0.24, 2))
		p -= unit * socket * 0.018
	else:
		var shoulder := smoothstep(-0.25, 0.90, unit.z)
		p.x *= 1.0 - shoulder * 0.22
		p.y += (1.0 - shoulder) * 0.025
	return p

static func normal(unit: Vector3, radii: Vector3, head: bool) -> Vector3:
	var u := unit.cross(Vector3.UP)
	if u.length_squared() < 0.001:
		u = unit.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := unit.cross(u).normalized()
	var dx := point((unit + u * 0.002).normalized(), radii, head) - point((unit - u * 0.002).normalized(), radii, head)
	var dy := point((unit + v * 0.002).normalized(), radii, head) - point((unit - v * 0.002).normalized(), radii, head)
	return dx.cross(dy).normalized()

static func coat(unit: Vector3, index: int, head: bool) -> Color:
	if index >= 2:
		var limb_fur := Color("#d6c5ae") if index == 2 else Color("#e0d3c1")
		return Color("#c5a490").lerp(limb_fur, smoothstep(-0.92, -0.42, unit.y))
	var cream := Color("#e6d4b9") if index == 0 else Color("#e5d7c7")
	var back := Color("#67615a") if index == 0 else Color("#c8bdae")
	var border := -0.19
	if head:
		border = -0.10 + smoothstep(0.65, 0.99, unit.z) * 0.12
	var mix_value := smoothstep(border - 0.21, border + 0.22, unit.y)
	var mottling := sin(unit.x * 13.0 + sin(unit.z * 7.0)) * sin(unit.y * 11.0) * 0.012
	return cream.lerp(back, mix_value).lightened(mottling)

static func skin(radii: Vector3, index: int, head: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(48):
		for col in range(80):
			for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var uv := Vector2(float(col + offset.x) / 80.0, float(row + offset.y) / 48.0)
				var unit := Vector3(sin(uv.y * PI) * cos(uv.x * TAU), cos(uv.y * PI), sin(uv.y * PI) * sin(uv.x * TAU))
				surface.set_uv(uv)
				surface.set_color(coat(unit, index, head).darkened(0.025))
				surface.set_normal(normal(unit, radii, head))
				surface.add_vertex(point(unit, radii, head))
	return surface.commit()

# 一片曲面承载一束细毛，弯曲方向随身体部位变化；毛尖通过覆盖率抗锯齿渐隐。
static func tufts(radii: Vector3, count: int, index: int, head: bool, guard: bool = false) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1279 + index * 97 + int(head) + int(guard) * 313
	for i in range(count):
		var y := rng.randf_range(-0.98, 1.0)
		var a := rng.randf_range(0, TAU)
		var unit := Vector3(cos(a) * sqrt(1.0 - y * y), y, sin(a) * sqrt(1.0 - y * y))
		var n := normal(unit, radii, head)
		var base := point(unit, radii, head)
		var flow := Vector3(unit.x * 0.12, -0.30, -1.0)
		if radii.y > radii.x * 2.0:
			flow = Vector3(unit.x * 0.10, -1.0, 0)
		if head:
			flow = Vector3(unit.x * 0.85, -0.42, -0.62)
		var tangent := (flow - n * flow.dot(n)).normalized()
		var across := n.cross(tangent).normalized()
		var length := rng.randf_range(0.038, 0.078)
		if head:
			length *= lerpf(0.93, 0.37, smoothstep(0.15, 0.90, unit.z))
			var socket := exp(-pow((absf(unit.x) - 0.78) / 0.19, 2) - pow((unit.y - 0.28) / 0.21, 2) - pow((unit.z - 0.56) / 0.25, 2))
			length *= 1.0 - socket * 0.85
		elif radii.y > radii.x * 2.0:
			length *= 0.24
		var width := rng.randf_range(0.003, 0.007)
		if guard:
			width = rng.randf_range(0.00035, 0.00065)
			length *= 0.86
		var bend := rng.randf_range(-0.20, 0.20)
		var color := coat(unit, index, head) * rng.randf_range(0.97, 1.04)
		if guard:
			color *= rng.randf_range(0.88, 1.10)
		color.a = 1.0
		for segment in range(4):
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t: float = (segment + corner.y) / 4.0
				var center := base + tangent * length * t + n * length * (0.035 + sin(t * PI * 0.76) * (0.17 if guard else 0.33)) + across * length * bend * t * t
				var position: Vector3 = center + across * (corner.x * 2.0 - 1.0) * width * (1.0 - t * (0.99 if guard else 0.45))
				surface.set_normal((n + tangent * t * 0.15).normalized())
				surface.set_color(color.lightened(t * 0.14) if guard else color)
				surface.set_uv(Vector2(corner.x, t))
				surface.add_vertex(position)
	return surface.commit()

static func ear(index: int) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(12):
		for col in range(64):
			for offset in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var r: float = (row + offset.y) / 12.0
				var angle: float = (col + offset.x) * TAU / 64.0
				var x := cos(angle) * 0.077 * r
				var y := sin(angle) * 0.100 * r
				var z := -0.029 * (1.0 - r * r) + x * 0.16
				var rim := smoothstep(0.76, 1.0, r)
				var outside := Color("#a59580") if index == 0 else Color("#d4c8b7")
				surface.set_color(Color("#b98b80").lerp(Color("#d3aa9a"), r * 0.6).lerp(outside, rim))
				surface.set_normal(Vector3(-x * 8.5 - 0.16, -y * 6.0, 1).normalized())
				surface.set_uv(Vector2(x / 0.16 + 0.5, y / 0.20 + 0.5))
				surface.add_vertex(Vector3(x, y, z))
	return surface.commit()

static func ear_rim() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(96):
		for col in range(6):
			for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var angle: float = (row + offset.y) * TAU / 96.0
				var ring: float = (col + offset.x) * TAU / 6.0
				var center := Vector3(cos(angle) * 0.077, sin(angle) * 0.100, cos(angle) * 0.077 * 0.16)
				var n := Vector3(cos(angle) * cos(ring), sin(angle) * cos(ring), sin(ring))
				surface.set_normal(n)
				surface.add_vertex(center + n * 0.0034)
	return surface.commit()

static func curve(a: Vector3, b: Vector3, c: Vector3, d: Vector3, radius: float, end_radius: float = 0.00025) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(12):
		for side in range(6):
			for offset in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var t: float = (segment + offset.y) / 12.0
				var center := a.bezier_interpolate(b, c, d, t)
				var tangent := a.bezier_derivative(b, c, d, t).normalized()
				var across := tangent.cross(Vector3.FORWARD).normalized()
				if across.length_squared() < 0.01:
					across = Vector3.RIGHT
				var second := tangent.cross(across).normalized()
				var angle: float = (side + offset.x) * TAU / 6.0
				var n := across * cos(angle) + second * sin(angle)
				surface.set_normal(n)
				surface.add_vertex(center + n * lerpf(radius, end_radius, t))
	return surface.commit()
