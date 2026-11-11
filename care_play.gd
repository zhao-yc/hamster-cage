extends Control

signal completed(kind: int)
signal cancelled

var kind := 0
var phase := 0
var progress := 0.0
var dragging := false
var pointer := Vector2.ZERO
var last_pointer := Vector2.ZERO
var tool := Vector2(220, 390)
var start := Vector2(220, 390)
var target := Vector2(670, 370)
var loaded := false
var cells: Dictionary = {}
var done_delay := -1.0
var font: Font
var particles: Array[Dictionary] = []
var touch_id := -1
var elapsed := 0.0
var drain_left := 0.0

func begin(value: int, face: Font) -> void:
	kind = value
	font = face
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

func _local_point(position: Vector2) -> Vector2:
	return (position - (size - Vector2(1024, 640) * _scale()) * 0.5) / _scale()

func _scale() -> float:
	return minf(size.x / 1024.0, size.y / 640.0)

func _gui_input(event: InputEvent) -> void:
	if done_delay >= 0:
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed and touch_id < 0:
			touch_id = event.index
			_press(_local_point(event.position))
		elif not event.pressed and event.index == touch_id:
			_release()
			touch_id = -1
	elif event is InputEventScreenDrag and event.index == touch_id:
		_drag(_local_point(event.position))
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(_local_point(event.position))
		else:
			_release()
	elif event is InputEventMouseMotion and dragging and touch_id < 0:
		_drag(_local_point(event.position))
	accept_event()

func _press(at: Vector2) -> void:
	if at.distance_to(Vector2(939, 70)) < 34:
		cancelled.emit()
		return
	if at.distance_to(tool) < 100 or kind == 2:
		dragging = true
		last_pointer = at
		pointer = at
		if kind == 0:
			loaded = true
		_drag(at)

func _drag(at: Vector2) -> void:
	if not dragging:
		return
	var movement := at.distance_to(last_pointer)
	last_pointer = at
	pointer = at
	tool = at.clamp(Vector2(90, 140), Vector2(930, 510))
	if kind == 0 and loaded and at.distance_to(target) < 95:
		loaded = false
		progress += 1.0 / 3.0
		_burst(at, Color("#bc8b45"), 20)
		if progress >= 0.99:
			_finish()
	elif kind == 0 and at.distance_to(start) < 80:
		loaded = true
	elif kind == 1 and phase == 0 and at.y < 185 and movement > 2:
		phase = 1
		drain_left = 0.8
		start = Vector2(220, 390)
		tool = start
		dragging = false
	elif kind == 2 and movement > 2 and Rect2(350, 210, 480, 250).has_point(at):
		var cell := Vector2i(clampi(int((at.x - 350) / 120), 0, 3), clampi(int((at.y - 210) / 125), 0, 1))
		cells[cell] = true
		progress = cells.size() / 8.0
		_burst(at, Color("#b49a75") if phase == 0 else Color("#e3c79b"), 3)
		if cells.size() == 8:
			if phase == 0:
				phase = 1
				cells.clear()
				progress = 0
				dragging = false
				tool = start
			else:
				_finish()
	queue_redraw()

func _release() -> void:
	dragging = false
	tool = Vector2(670, 235) if kind == 1 and phase == 0 else start
	queue_redraw()

func _finish() -> void:
	dragging = false
	done_delay = 0.65
	progress = 1.0
	_burst(Vector2(600, 280), Color("#e7b85d"), 36)

func _burst(at: Vector2, color: Color, count: int) -> void:
	for i in range(count):
		particles.append({"p": at, "v": Vector2(randf_range(-100, 100), randf_range(-150, 30)), "life": 0.7, "color": color})

func _process(delta: float) -> void:
	elapsed += delta
	if drain_left > 0:
		drain_left = maxf(0, drain_left - delta)
		_burst(Vector2(730, 420), Color("#93aaa5"), 2)
	if kind == 1 and phase == 0 and not dragging:
		tool = Vector2(670, 235)
	if kind == 1 and phase == 1 and drain_left <= 0 and dragging and tool.distance_to(Vector2(610, 260)) < 90:
		progress = minf(1, progress + delta / 2.0)
		_burst(Vector2(658, 277), Color("#8ac0cd"), 2)
		if progress >= 1:
			_finish()
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].v.y += 350 * delta
		particles[i].p += particles[i].v * delta
		if particles[i].life <= 0:
			particles.remove_at(i)
	if done_delay >= 0:
		done_delay -= delta
		if done_delay <= 0:
			set_process(false)
			completed.emit(kind)
	queue_redraw()

func _pill(rect: Rect2, color: Color, radius: int = 24) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _text(value: String, at: Vector2, size_value: int = 26, color: Color = Color("#5a4538")) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, color)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#3b2b2066"))
	var scale_value := _scale()
	draw_set_transform((size - Vector2(1024, 640) * scale_value) * 0.5, 0, Vector2.ONE * scale_value)
	_pill(Rect2(50, 28, 924, 565), Color("#fff0d6"), 36)
	var title: String = ["给它们盛饭", "换一瓶干净的水", "一起换垫料"][kind]
	var help := "拖小勺到食盆，再回粮袋舀一勺（3 勺）"
	if kind == 1:
		help = "往上拖开瓶盖，倒掉旧水" if phase == 0 else "拖水壶到瓶口，停一会儿把水倒满"
	elif kind == 2:
		help = "拖小铲扫过整块旧垫料和便便" if phase == 0 else "拖木屑袋，把每块地面铺上新垫料"
	_text(title, Vector2(90, 83), 32)
	_text("×", Vector2(925, 82), 34)
	_text("完成啦！" if done_delay >= 0 else help, Vector2(90, 137), 23)
	_pill(Rect2(90, 540, 844, 14), Color("#d6c7ab"), 7)
	_pill(Rect2(90, 540, maxf(10, progress * 844), 14), Color("#8fa578"), 7)
	if kind == 0:
		draw_ellipse_shape(Vector2(230, 477), Vector2(100, 15), Color("#81654824"))
		_pill(Rect2(130, 275, 180, 200), Color("#c6aa78"))
		_pill(Rect2(141, 286, 158, 177), Color("#ddc398"), 20)
		draw_colored_polygon(PackedVector2Array([Vector2(130,280),Vector2(153,250),Vector2(290,250),Vector2(310,280)]),Color("#ae8d60"))
		draw_line(Vector2(151, 263),Vector2(290,263),Color("#efe0bb"),3,true)
		_text("仓鼠粮", Vector2(168, 340), 28)
		for i in range(14):
			draw_ellipse_shape(Vector2(157 + i % 6 * 25, 428 + i / 6 * 10), Vector2(6, 4), Color("#b09060"))
		draw_ellipse_shape(Vector2(675, 444), Vector2(140, 25), Color("#81654830"))
		draw_ellipse_shape(Vector2(670, 390), Vector2(130, 67), Color("#bba080"))
		draw_ellipse_shape(Vector2(670, 384), Vector2(128, 63), Color("#e6cfa6"))
		draw_ellipse_shape(Vector2(670, 370), Vector2(130, 55), Color("#e5d1ad"))
		draw_ellipse_shape(Vector2(670, 367), Vector2(111, 40), Color("#af9676"))
		draw_ellipse_shape(Vector2(670, 373), Vector2(105, 30), Color("#d2b78f"))
		for x in [600, 640, 680, 720]:
			draw_line(Vector2(x,438),Vector2(x+8,416),Color("#829267"),2,true)
			draw_ellipse_shape(Vector2(x+2,426),Vector2(6,3),Color("#829267"))
		for i in range(3):
			draw_circle(Vector2(625 + i * 44, 495), 10, Color("#95a87c") if progress * 3 > i + 0.5 else Color("#dccbad"))
		for i in range(int(progress * 90)):
			var a := i * 2.39996
			var r := sqrt(float(i) / 90.0)
			draw_ellipse_shape(Vector2(670, 370) + Vector2(cos(a) * 100, sin(a) * 33) * r, Vector2(6, 4), Color("#a67c40") if i % 3 else Color("#514333"))
	elif kind == 1:
		draw_ellipse_shape(Vector2(670, 482), Vector2(80, 14), Color("#81654824"))
		_pill(Rect2(610, 270, 120, 210), Color("#b3c9c5"), 25)
		_pill(Rect2(618, 280, 104, 191), Color("#e4ede0"), 20)
		var fill := 0.6 if phase == 0 else maxf(progress, drain_left * 0.75)
		_pill(Rect2(621, 462 - fill * 175, 98, 10 + fill * 175), Color("#86bdc5") if phase == 1 and drain_left <= 0 else Color("#a6b7a3"), 12)
		draw_line(Vector2(630,295),Vector2(630,444),Color("#ffffe9a0"),5,true)
		for y in [315,345,375,405,435]:
			draw_line(Vector2(694,y),Vector2(711,y),Color("#82a4a2"),2,true)
		draw_arc(Vector2(670, 277), 37, 0, PI, 24, Color("#7e9a86"), 7, true)
		if phase == 0:
			_pill(Rect2(tool - Vector2(64, 18), Vector2(128, 36)), Color("#8a9c75"), 10)
	elif kind == 2:
		_pill(Rect2(335, 195, 510, 280), Color("#c19b70"), 25)
		for row in range(2):
			for col in range(4):
				var cell := Vector2i(col, row)
				var origin := Vector2(350 + col * 120, 210 + row * 125)
				var filled := not cells.has(cell) if phase == 0 else cells.has(cell)
				draw_rect(Rect2(origin, Vector2(116, 121)), Color("#baa17e") if phase == 0 and filled else Color("#e4c99e") if filled else Color("#d2af80"))
				if filled:
					for i in range(32):
						var p := origin + Vector2(fmod(i * 37.1, 108), fmod(i * 23.7, 113))
						draw_line(p, p + Vector2(8, 4), Color("#f0d7ac"), 3, true)
					if phase == 0:
						draw_ellipse_shape(origin + Vector2(45, 65), Vector2(9, 5), Color("#69503b"))
	if kind != 1 or phase == 1:
		var p := tool
		if kind == 0 or (kind == 2 and phase == 0):
			draw_line(p + Vector2(-60, 39), p+Vector2(0,4), Color("#81654830"), 17, true)
			draw_line(p + Vector2(-60, 35), p, Color("#9b714b"), 15, true)
			draw_ellipse_shape(p, Vector2(42, 23), Color("#b8b9aa"))
			draw_ellipse_shape(p-Vector2(0,3), Vector2(36, 17), Color("#e6e4d0"))
			if loaded and kind == 0:
				for i in range(10):
					draw_circle(p + Vector2((i % 4 - 1.5) * 13, (i / 4 - 1) * 10), 5, Color("#b48c54"))
		else:
			_pill(Rect2(p - Vector2(52, 65), Vector2(104, 120)), Color("#8ab3b7") if kind == 1 else Color("#c6ac7d"), 17)
			_text("水" if kind == 1 else "木屑", p + Vector2(-28, 5), 27)
			if kind == 1:
				draw_colored_polygon(PackedVector2Array([p + Vector2(40,-35),p+Vector2(80,-55),p+Vector2(54,-5)]),Color("#8ab3b7"))
				draw_arc(p+Vector2(-50,-9), 33, PI*0.45, PI*1.55, 28, Color("#709ca3"), 13, true)
				draw_line(p+Vector2(-29,-46),p+Vector2(-29,29),Color("#d3e4de"),4,true)
	if not dragging and done_delay < 0:
		draw_arc(tool, 70 + sin(elapsed * 3) * 4, 0, TAU, 48, Color("#9aaa7770"), 3, true)
		var destination := Vector2(670, 160) if kind == 1 and phase == 0 else Vector2(610, 260) if kind == 1 else target
		var from := tool + Vector2(70, -45)
		for i in range(12):
			var at := from.lerp(destination - Vector2(40, 60), float(i) / 12.0)
			draw_circle(at, 2.5, Color("#c7b697"))
	for particle in particles:
		draw_circle(particle.p, 3, particle.color)
	draw_set_transform(Vector2.ZERO)

func draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		points.append(center + Vector2(cos(i * TAU / 40), sin(i * TAU / 40)) * radius)
	draw_colored_polygon(points, color)
