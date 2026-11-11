extends RefCounted

const INK := Color("#523c35")

static func pill(canvas: CanvasItem, rect: Rect2, color: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	canvas.draw_style_box(style, rect)

static func oval(canvas: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		points.append(center + Vector2.from_angle(TAU * i / 40.0) * radii)
	canvas.draw_colored_polygon(points, color)

static func hamster(canvas: CanvasItem, point: Vector2, index: int, direction: float,
		action: String, phase: float, factor: float = 1.0) -> void:
	var bounce := absf(sin(phase * 13)) if action in ["跑", "走"] else sin(phase * 4) * 0.3
	var lift := 5.0 if action == "回应" else 0.0
	var outline := Color("#766768") if index == 0 else Color("#c9a999")
	var fur := Color("#a3969b") if index == 0 else Color("#fff4e8")
	var tummy := Color("#ded1cc") if index == 0 else Color("#fffdf4")
	var feet := Color("#d29591")
	if action != "跑" and factor == 1.0:
		oval(canvas, point + Vector2(0, 2), Vector2(40, 7), Color("#644b3939"))
	canvas.draw_set_transform(point + Vector2(0, -bounce * 4 - lift) * factor, 0, Vector2(direction, 1) * factor)
	var head_y := -34.0 if action != "睡" else -24.0
	oval(canvas, Vector2(-24, -15), Vector2(14, 12), outline)
	oval(canvas, Vector2(-8, -24), Vector2(35, 26 if action != "睡" else 19), outline)
	oval(canvas, Vector2(-8, -25), Vector2(33, 24 if action != "睡" else 17), fur)
	oval(canvas, Vector2(-8, -14), Vector2(28, 14), tummy)
	for i in [-1, 1]:
		var paw := Vector2(i * 19 + sin(phase * 13) * i * bounce * 5, -3)
		oval(canvas, paw, Vector2(9, 4), feet)
	for ear in [Vector2(5, head_y - 21), Vector2(29, head_y - 16)]:
		oval(canvas, ear, Vector2(11, 12), outline)
		oval(canvas, ear, Vector2(8, 8), Color("#edb7ad"))
	oval(canvas, Vector2(17, head_y), Vector2(28, 23), outline)
	oval(canvas, Vector2(17, head_y - 1), Vector2(26, 21), fur)
	oval(canvas, Vector2(27, head_y + 9), Vector2(17, 11), tummy)
	oval(canvas, Vector2(20, head_y + 6), Vector2(7, 4), Color("#e9aca0"))
	var eye := Vector2(28, head_y - 5)
	if action == "睡" or fmod(phase, 5.0) > 4.85:
		canvas.draw_arc(eye + Vector2(0, -2), 5, 0, PI, 8, INK, 2, true)
	else:
		canvas.draw_circle(eye, 4.5, INK, true, -1, true)
		canvas.draw_circle(eye + Vector2(-1, -1), 1.35, Color.WHITE, true, -1, true)
	oval(canvas, Vector2(42, head_y + 4), Vector2(5, 3.2), Color("#a66067"))
	for i in [-1, 1]:
		canvas.draw_line(Vector2(38, head_y + 8), Vector2(52, head_y + 8 + i * 3), outline, 1, true)
	canvas.draw_set_transform(Vector2.ZERO)
