extends Control

signal completed(kind: int)
signal cancelled

enum { FOOD, WATER, BEDDING }
enum WaterStep { OPEN, POUR, CLOSE }
enum BeddingStep { CLEAR, SPREAD }

const DESIGN_SIZE := Vector2(1024, 640)
const FOOD_BAG := Vector2(243, 291)
const FOOD_BOWL := Vector2(683, 368)
const TOOL_REST := Vector2(220, 390)
const SCOOP_TIME := 0.30
const SCOOPS := 3
const GRAIN_POUR_TIME := 0.46
const CAP_HOME := Vector2(670, 235)
const CAP_REST := Vector2(838, 342)
const POUR_POSITION := Vector2(557, 237)
const DRAIN_TIME := 0.8
const POUR_TIME := 2.0
const TRAY := Rect2(350, 218, 520, 244)
const BEDDING_COLUMNS := 8
const BEDDING_ROWS := 4
const COVERED_ENOUGH := 28

var kind := FOOD
var phase := 0
var dragging := false
var tool := TOOL_REST
var offset := Vector2.ZERO
var tool_angle := 0.0
var done_delay := -1.0
var font: Font
var particles: Array[Dictionary] = []
var touch_id := -1
var elapsed := 0.0

var initial_food_fill := 0.0
var scoop_fill := 0.0
var food_served := 0
var grain_pour_left := 0.0

var initial_water_fill := 0.0
var drain_left := 0.0
var poured := 0.0
var stream_strength := 0.0

var covered: Dictionary = {}
var pellets: PackedVector2Array = []
var bedding_chips: PackedVector2Array = []
var bedding_dirt := 0.0

func begin(value: int, face: Font, supplies: Dictionary) -> void:
	kind = value
	font = face
	match kind:
		FOOD:
			initial_food_fill = supplies.food
		WATER:
			initial_water_fill = supplies.water
			tool = CAP_HOME
		BEDDING:
			bedding_dirt = supplies.dirt
			_prepare_bedding(supplies.droppings)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_CLICK
	grab_focus()
	queue_redraw()

func _prepare_bedding(droppings: Array) -> void:
	var pattern := RandomNumberGenerator.new()
	pattern.seed = 154
	for index in range(960):
		var chip := TRAY.position + Vector2(9, 9) + Vector2(pattern.randf(), pattern.randf()) * (TRAY.size - Vector2(18, 18))
		bedding_chips.append(chip)
		bedding_chips.append(chip + Vector2.from_angle(pattern.randf_range(0.0, TAU)) * pattern.randf_range(3.0, 8.0))
	for item in droppings:
		var uv := Vector2(clampf((float(item.x) + 4.2) / 8.4, 0.04, 0.96),
			clampf((float(item.z) + 2.1) / 6.2, 0.04, 0.96))
		for pellet in range(int(item.get("count", 3))):
			pellets.append(TRAY.position + uv * TRAY.size + Vector2(pellet * 2.4, pellet % 2 * 2.0))

func _local_point(position: Vector2) -> Vector2:
	var ratio := _scale()
	return (position - (size - DESIGN_SIZE * ratio) * 0.5) / ratio

func _scale() -> float:
	return maxf(0.001, minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y))

func _gui_input(event: InputEvent) -> void:
	if done_delay >= 0:
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed and touch_id < 0:
			touch_id = event.index
			_press(_local_point(event.position))
		elif not event.pressed and event.index == touch_id:
			if event.canceled:
				_cancel_drag()
			else:
				_release()
			touch_id = -1
	elif event is InputEventScreenDrag and event.index == touch_id:
		_drag(_local_point(event.position))
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and touch_id < 0:
		if event.pressed:
			_press(_local_point(event.position))
		else:
			_release()
	elif event is InputEventMouseMotion and dragging and touch_id < 0:
		_drag(_local_point(event.position))
	accept_event()

func _press(at: Vector2) -> void:
	if at.distance_to(Vector2(935, 69)) < 34:
		cancelled.emit()
		return
	if grain_pour_left > 0.0 or drain_left > 0.0 or at.distance_to(tool) > 85:
		return
	dragging = true
	offset = tool - at

func _drag(at: Vector2) -> void:
	if not dragging:
		return
	var before := tool
	tool = (at + offset).clamp(Vector2(86, 144), Vector2(925, 506))
	if kind == WATER and phase == WaterStep.OPEN and tool.distance_to(CAP_REST) <= 48.0:
		phase = WaterStep.POUR
		drain_left = DRAIN_TIME if initial_water_fill > 0.0 else 0.0
		_cancel_drag()
	elif kind == BEDDING:
		_sweep(before, tool)

func _release() -> void:
	if not dragging:
		return
	if kind == FOOD and scoop_fill >= 1.0 and tool.distance_to(FOOD_BOWL) <= 92:
		dragging = false
		tool = FOOD_BOWL + Vector2(-49, -47)
		grain_pour_left = GRAIN_POUR_TIME
		return
	if kind == WATER and phase == WaterStep.CLOSE and tool.distance_to(CAP_HOME) <= 66:
		tool = CAP_HOME
		_finish()
		return
	_cancel_drag()

func _cancel_drag() -> void:
	dragging = false
	stream_strength = 0.0
	if kind == WATER and phase != WaterStep.POUR:
		tool = CAP_HOME if phase == WaterStep.OPEN else CAP_REST
	else:
		tool = TOOL_REST
	if kind == FOOD and scoop_fill < 1.0:
		scoop_fill = 0.0

func _sweep(from: Vector2, to: Vector2) -> void:
	# 快速划动会补扫路径中间，避免平板触摸事件稀疏时留下细缝。
	var steps := maxi(1, ceili(from.distance_to(to) / 24.0))
	var last_count := covered.size()
	var cell_size := TRAY.size / Vector2(BEDDING_COLUMNS, BEDDING_ROWS)
	for step in range(steps + 1):
		var sample := from.lerp(to, float(step) / steps)
		for row in range(BEDDING_ROWS):
			for column in range(BEDDING_COLUMNS):
				var cell := Vector2i(column, row)
				var center := TRAY.position + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
				if center.distance_squared_to(sample) <= 54.0 * 54.0:
					covered[cell] = true
	if covered.size() > last_count:
		_burst(to, Color("#b59771") if phase == BeddingStep.CLEAR else Color("#e2bb84"), 8)
	if covered.size() >= COVERED_ENOUGH:
		if phase == BeddingStep.CLEAR:
			phase = BeddingStep.SPREAD
			covered.clear()
			_cancel_drag()
		else:
			_finish()

func _finish() -> void:
	dragging = false
	done_delay = 0.65
	_burst(Vector2(687, 335), Color("#e7b85d"), 24)

func _burst(at: Vector2, color: Color, count: int) -> void:
	for index in range(mini(count, 140 - particles.size())):
		particles.append({"p": at, "v": Vector2(randf_range(-105, 105), randf_range(-125, -25)),
			"life": randf_range(0.30, 0.65), "color": color})

func water_level() -> float:
	# 换水只预演水位，关掉小游戏时实际水量仍由笼子的存档决定。
	if phase == WaterStep.OPEN:
		return initial_water_fill
	return maxf(poured, initial_water_fill * drain_left / DRAIN_TIME)

func _process(delta: float) -> void:
	elapsed += delta
	var angle := 0.0
	if kind == FOOD:
		if grain_pour_left > 0.0:
			angle = 0.95
			grain_pour_left = maxf(0.0, grain_pour_left - delta)
			if grain_pour_left == 0.0:
				food_served += 1
				scoop_fill = 0.0
				tool = TOOL_REST
				if food_served == SCOOPS:
					_finish()
		elif dragging and tool.distance_to(FOOD_BAG) <= 58:
			angle = -0.26
			scoop_fill = move_toward(scoop_fill, 1.0, delta / SCOOP_TIME)
		elif scoop_fill < 1.0:
			scoop_fill = move_toward(scoop_fill, 0.0, delta / SCOOP_TIME)
	elif kind == WATER:
		drain_left = maxf(0.0, drain_left - delta)
		var pouring := phase == WaterStep.POUR and drain_left <= 0.0 and dragging and tool.distance_to(POUR_POSITION) <= 65
		stream_strength = move_toward(stream_strength, 1.0 if pouring else 0.0, delta * 7.0)
		angle = 0.54 * stream_strength
		if pouring:
			poured = move_toward(poured, 1.0, delta / POUR_TIME)
			if poured >= 1.0:
				phase = WaterStep.CLOSE
				stream_strength = 0.0
				tool_angle = 0.0
				angle = 0.0
				_cancel_drag()
	elif dragging:
		angle = -0.18 if phase == BeddingStep.CLEAR else 0.44
	tool_angle = lerpf(tool_angle, angle, 1.0 - exp(-delta * 16.0))
	for index in range(particles.size() - 1, -1, -1):
		var particle := particles[index]
		particle.life -= delta
		particle.v.y += 360.0 * delta
		particle.p += particle.v * delta
		if particle.life <= 0:
			particles.remove_at(index)
	if done_delay >= 0:
		done_delay -= delta
		if done_delay <= 0:
			set_process(false)
			completed.emit(kind)
	queue_redraw()

func _hint() -> String:
	if done_delay >= 0:
		return ["食盆装满了！", "水壶盖好了！", "新垫料铺好啦！"][kind]
	match kind:
		FOOD:
			if grain_pour_left > 0.0:
				return "粮食掉进碗里啦。"
			return "把勺子拖到碗上，松手倒进去。" if scoop_fill >= 1.0 else "把勺子拖进粮袋，停一下舀满。"
		WATER:
			match phase:
				WaterStep.OPEN:
					return "把瓶盖拖到右边的圈里，倒掉旧水。" if initial_water_fill > 0.0 else "把瓶盖拖到右边的圈里。"
				WaterStep.POUR:
					return "拖水壶到瓶口，按住倒水。" if drain_left <= 0.0 else "等旧水流完，再倒入干净的水。"
				WaterStep.CLOSE:
					return "把瓶盖拖回瓶口，松手盖好。"
	return "拖小铲扫过旧木屑，把便便一起清走。" if phase == BeddingStep.CLEAR else "拖木屑袋在托盘上来回移动，铺上干净木屑。"

func _progress() -> float:
	match kind:
		FOOD:
			return float(food_served) / SCOOPS
		WATER:
			if phase == WaterStep.OPEN:
				return 0.0
			return 1.0 if done_delay >= 0.0 else 0.14 * (1.0 - drain_left / DRAIN_TIME) + 0.76 * poured
	var coverage := minf(1.0, float(covered.size()) / COVERED_ENOUGH)
	return (float(phase) + coverage) * 0.5

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#3b2b2073"))
	_at()
	_pill(Rect2(50, 32, 924, 566), Color("#71573b66"), 36)
	_pill(Rect2(50, 24, 924, 566), Color("#fff0d6"), 36)
	_pill(Rect2(76, 153, 872, 365), Color("#f8e7c9"), 28)
	_text(["给它们盛饭", "换一瓶干净的水", "一起换垫料"][kind], Vector2(88, 81), 34)
	_text(_hint(), Vector2(88, 125), 24)
	_pill(Rect2(911, 45, 48, 48), Color("#efdec1"), 24)
	draw_line(Vector2(928, 62), Vector2(942, 76), Color("#6a5142"), 3.0, true)
	draw_line(Vector2(942, 62), Vector2(928, 76), Color("#6a5142"), 3.0, true)
	_pill(Rect2(88, 550, 848, 12), Color("#e3d2b2"), 6)
	var meter := clampf(_progress(), 0.0, 1.0)
	if meter > 0.0:
		_pill(Rect2(88, 550, 848 * meter, 12), Color("#8d9f71"), 6)
	match kind:
		FOOD:
			_draw_food()
		WATER:
			_draw_water()
		BEDDING:
			_draw_bedding()
	for particle in particles:
		draw_circle(particle.p, 3.0, Color(particle.color, minf(particle.life * 3.0, 1.0)), true)
	draw_set_transform(Vector2.ZERO)

func _draw_food() -> void:
	_shadow(Vector2(244, 387), Vector2(108, 15))
	_pill(Rect2(149, 282, 190, 104), Color("#b89662"), 18)
	_pill(Rect2(157, 284, 174, 91), Color("#d8b980"), 16)
	_ellipse(FOOD_BAG, Vector2(96, 28), Color("#a67d4c"))
	_ellipse(FOOD_BAG + Vector2(0, 1), Vector2(82, 19), Color("#684c35"))
	_grains(FOOD_BAG + Vector2(0, 5), Vector2(74, 11), 35 - food_served * 5 - int(scoop_fill * 5))
	_text("仓鼠粮", Vector2(199, 346), 24)
	_shadow(FOOD_BOWL + Vector2(0, 63), Vector2(147, 19))
	_ellipse(FOOD_BOWL + Vector2(0, 25), Vector2(134, 51), Color("#b59973"))
	_ellipse(FOOD_BOWL + Vector2(0, 14), Vector2(137, 53), Color("#d8c096"))
	_ellipse(FOOD_BOWL, Vector2(137, 51), Color("#fff2d4"))
	_ellipse(FOOD_BOWL + Vector2(0, 1), Vector2(118, 38), Color("#ad916e"))
	_ellipse(FOOD_BOWL + Vector2(0, 7), Vector2(111, 31), Color("#ceb18b"))
	var in_flight := 1.0 - grain_pour_left / GRAIN_POUR_TIME if grain_pour_left > 0.0 else 0.0
	var fill := lerpf(initial_food_fill, 1.0, (food_served + in_flight) / SCOOPS)
	_grains(FOOD_BOWL + Vector2(0, 5), Vector2(102, 24), roundi(fill * 76))
	for x in [635, 675, 715]:
		draw_line(Vector2(x, 429), Vector2(x + 9, 417), Color("#799068"), 2, true)
		_ellipse(Vector2(x + 6, 422), Vector2(6, 3), Color("#799068"))
	for index in range(SCOOPS):
		var spot := Vector2(650 + index * 33, 475)
		draw_circle(spot, 7.0, Color("#819768") if food_served > index else Color("#dfc8a5"), true)
	if done_delay >= 0:
		return
	var aim := FOOD_BOWL if scoop_fill >= 1.0 else FOOD_BAG
	if grain_pour_left <= 0.0:
		_guide(tool, aim, not dragging)
	_at(tool, tool_angle)
	_scoop()
	_grains(Vector2(0, -2), Vector2(26, 11), int(scoop_fill * 16 * (1.0 - in_flight)))
	_at()
	if grain_pour_left > 0.0:
		for index in range(14):
			var t := clampf(in_flight * 1.6 - index * 0.035, 0.0, 1.0)
			if t > 0.0 and t < 1.0:
				var landing := FOOD_BOWL + Vector2(index * 6 - 37, cos(index * 1.8) * 14)
				var p := (tool + Vector2(20, 12)).lerp(landing, t) - Vector2(0, sin(t * PI) * 13)
				_ellipse(p, Vector2(4.5, 3.0), Color("#a4784b") if index % 3 else Color("#5e4838"))

func _draw_water() -> void:
	var bottle := Vector2(670, 375)
	_shadow(Vector2(670, 490), Vector2(87, 14))
	var tilt := -0.27 * sin(PI * drain_left / DRAIN_TIME)
	_at(bottle, tilt)
	_pill(Rect2(-65, -100, 130, 215), Color("#a7c2bd"), 24)
	_pill(Rect2(-56, -91, 112, 196), Color("#e5eee3"), 17)
	var depth := water_level() * 186.0
	if depth > 0.0:
		var surface := 103.0 - depth
		var color := Color("#9eaf9b") if phase == WaterStep.OPEN or drain_left > 0.0 else Color("#7bb5c1")
		_pill(Rect2(-52, surface, 104, depth), color, mini(12, floori(depth * 0.5)))
		var line := PackedVector2Array()
		for x in range(-47, 48, 6):
			line.append(Vector2(x, surface + sin(elapsed * 11.0 + x * 0.11) * minf(depth * 0.16, 4.0) * stream_strength))
		draw_polyline(line, color.lightened(0.34), 2.4, true)
		if stream_strength > 0.0:
			for index in range(5):
				var y := fposmod(elapsed * (26 + index * 6) + index * 17, depth)
				draw_circle(Vector2(-25 + index * 13, 102 - y), 2 + index % 2, Color("#e5f4e8ae"), true)
	draw_line(Vector2(-44, -72), Vector2(-44, 77), Color("#ffffecab"), 5.0, true)
	for y in [-65, -34, -3, 28, 59]:
		draw_line(Vector2(27, y), Vector2(46, y), Color("#799e9b"), 2.5, true)
	_pill(Rect2(-42, -107, 84, 17), Color("#8fac9d"), 8)
	_at()
	if drain_left > 0.0:
		_ellipse(Vector2(513, 480), Vector2(61, 16), Color("#c8b691"))
		_ellipse(Vector2(513, 476), Vector2(54, 13), Color("#ebd8b3"))
		if drain_left < DRAIN_TIME:
			_ellipse(Vector2(513, 476), Vector2(46 * (1.0 - drain_left / DRAIN_TIME), 9), Color("#a4b3a1"))
		var outlet := bottle + Vector2(-41, -98).rotated(tilt)
		_stream(outlet, Vector2(513, 476), drain_left / DRAIN_TIME, Color("#a0b4a2"))
	if phase == WaterStep.POUR:
		_draw_cap(CAP_REST)
		if drain_left <= 0.0 and stream_strength <= 0.0:
			_guide(tool, POUR_POSITION, not dragging)
		if stream_strength > 0.0 and tool.distance_to(POUR_POSITION) < 85.0:
			_stream(tool + Vector2(76, -28).rotated(tool_angle), Vector2(671, 275), stream_strength, Color("#80bdca"))
		_at(tool, tool_angle)
		_pitcher()
		_at()
	else:
		if done_delay < 0.0:
			_guide(tool, CAP_REST if phase == WaterStep.OPEN else CAP_HOME, not dragging)
		_draw_cap(tool)

func _draw_bedding() -> void:
	_shadow(TRAY.get_center() + Vector2(0, 113), Vector2(258, 32))
	_pill(TRAY.grow(14), Color("#ad8965"), 29)
	_pill(TRAY.grow(9), Color("#e1c7a0"), 25)
	_pill(TRAY, Color("#c7a77e"), 17)
	for index in range(15):
		var y := TRAY.position.y + 13 + index * 15.0
		draw_line(Vector2(TRAY.position.x + 10, y), Vector2(TRAY.end.x - 10, y + sin(index) * 5.0), Color("#b6946e61"), 1.4, true)
	var chip_lines := PackedVector2Array()
	var chip_colors := PackedColorArray()
	for index in range(0, bedding_chips.size(), 2):
		var chip := bedding_chips[index]
		var changed := covered.has(_cell_at(chip))
		if done_delay >= 0 or changed == (phase == BeddingStep.SPREAD):
			var clean := Color("#ebc997").lerp(Color("#fbdfaf"), float(index % 7) / 6.0)
			var old := clean.lerp(Color("#95795f"), 0.18 + bedding_dirt * 0.27)
			chip_lines.append(chip)
			chip_lines.append(bedding_chips[index + 1])
			chip_colors.append(old if phase == BeddingStep.CLEAR else clean)
	if not chip_lines.is_empty():
		draw_multiline_colors(chip_lines, chip_colors, 2.7, true)
	if phase == BeddingStep.CLEAR:
		for pellet in pellets:
			if not covered.has(_cell_at(pellet)):
				_ellipse(pellet, Vector2(3.7, 2.6), Color("#694e38"))
		_shadow(Vector2(220, 310), Vector2(69, 11))
		_pill(Rect2(168, 230, 105, 76), Color("#a78e6f"), 15)
		_ellipse(Vector2(220, 234), Vector2(56, 20), Color("#76634e"))
		var waste := float(covered.size()) / COVERED_ENOUGH
		if waste > 0.0:
			_grains(Vector2(220, 235), Vector2(42, 12), roundi(waste * 38))
	if done_delay >= 0.0:
		return
	if not dragging:
		_guide(tool, Vector2(TRAY.position.x + 38, TRAY.get_center().y))
	_at(tool, tool_angle)
	if phase == BeddingStep.CLEAR:
		_draw_shovel()
	else:
		_pill(Rect2(-55, -62, 108, 121), Color("#bfa075"), 19)
		_pill(Rect2(-47, -52, 94, 103), Color("#ddc199"), 14)
		draw_line(Vector2(-40, -48), Vector2(41, -48), Color("#f5dbb3"), 4.0, true)
		_text("木屑", Vector2(-26, 11), 24)
	_at()

func _cell_at(point: Vector2) -> Vector2i:
	var uv := (point - TRAY.position) / TRAY.size
	return Vector2i(int(uv.x * BEDDING_COLUMNS), int(uv.y * BEDDING_ROWS))

func _draw_cap(at: Vector2) -> void:
	_at(at)
	_shadow(Vector2(0, 14), Vector2(49, 9))
	_pill(Rect2(-48, -15, 96, 32), Color("#7e9676"), 12)
	_pill(Rect2(-43, -16, 86, 12), Color("#a4b58c"), 6)
	for x in range(-30, 34, 10):
		draw_line(Vector2(x, -1), Vector2(x, 8), Color("#718867"), 2, true)
	_at()

func _pitcher() -> void:
	draw_arc(Vector2(-43, -8), 32, PI * 0.47, PI * 1.53, 30, Color("#6896a0"), 12, true)
	draw_colored_polygon(PackedVector2Array([Vector2(31, -47), Vector2(78, -29), Vector2(40, 0)]), Color("#84b1ba"))
	_pill(Rect2(-48, -61, 96, 117), Color("#84b1ba"), 18)
	_pill(Rect2(-38, -47, 75, 88), Color("#afd0ca"), 12)
	draw_line(Vector2(-25, -37), Vector2(-25, 25), Color("#f0f3df"), 4, true)
	draw_line(Vector2(20, 14), Vector2(34, 14), Color("#6896a0"), 2, true)
	draw_line(Vector2(20, 27), Vector2(34, 27), Color("#6896a0"), 2, true)
	_ellipse(Vector2(0, -58), Vector2(38, 8), Color("#557f89"))

func _scoop() -> void:
	draw_line(Vector2(-83, 32), Vector2(-19, 4), Color("#7c543a"), 17, true)
	draw_line(Vector2(-82, 29), Vector2(-18, 0), Color("#b5875a"), 10, true)
	_ellipse(Vector2(0, 4), Vector2(37, 21), Color("#9b9885"))
	_ellipse(Vector2(0, 0), Vector2(35, 19), Color("#e7e1cd"))
	_ellipse(Vector2(0, -1), Vector2(29, 13), Color("#c3c1aa"))

func _draw_shovel() -> void:
	draw_line(Vector2(-72, 29), Vector2(-18, 5), Color("#7c543a"), 18, true)
	draw_line(Vector2(-71, 25), Vector2(-18, 2), Color("#bd9161"), 9, true)
	_pill(Rect2(-27, -20, 66, 46), Color("#8a9c76"), 10)
	_pill(Rect2(-20, -15, 59, 32), Color("#b5be90"), 8)
	draw_line(Vector2(35, -15), Vector2(35, 17), Color("#d4d5aa"), 4, true)

func _stream(from: Vector2, to: Vector2, strength: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(15):
		var t := float(index) / 14.0
		var bend := sin(PI * t) * 18.0
		points.append(from.lerp(to, t) + Vector2(bend, -bend * 0.46))
	draw_polyline(points, Color(color, strength * 0.80), maxf(1.0, strength * 8.0), true)
	for index in range(4):
		var t := fposmod(elapsed * 2.9 + index * 0.25, 1.0)
		var p := points[mini(14, int(t * 15.0))]
		draw_circle(p, 2.6, Color("#eaf8efba"), true)

func _guide(from: Vector2, target: Vector2, trace: bool = true) -> void:
	var pulse := 0.67 + sin(elapsed * 3.5) * 0.17
	var start := from + (target - from).normalized() * 52.0
	var finish := target - (target - from).normalized() * 38.0
	if trace and from.distance_to(target) > 98.0:
		var count := maxi(2, int(start.distance_to(finish) / 18.0))
		for index in range(count):
			draw_circle(start.lerp(finish, float(index) / count), 2.3, Color("#ab9f74") * Color(1, 1, 1, pulse), true)
	draw_arc(target, 41.0 + pulse * 4.0, 0, TAU, 40, Color("#8c9b6b74"), 2, true)

func _grains(center: Vector2, radius: Vector2, count: int) -> void:
	for index in range(count):
		var angle := index * 2.39996
		var radius_factor := sqrt(fposmod(sin(index * 9.784 + 5.22) * 9987.123, 1.0))
		var p := center + Vector2(cos(angle), sin(angle)) * radius * radius_factor
		var color := Color("#674c38") if index % 5 == 0 else Color("#b98f52") if index % 3 == 0 else Color("#e2bd79")
		_ellipse(p, Vector2(5.1, 3.0), color)
		draw_line(p - Vector2(2.0, 1.0), p + Vector2(1.5, -1.0), color.lightened(0.27), 1.2, true)

func _at(position: Vector2 = Vector2.ZERO, angle: float = 0.0) -> void:
	var ratio := _scale()
	draw_set_transform((size - DESIGN_SIZE * ratio) * 0.5 + position * ratio, angle, Vector2.ONE * ratio)

func _pill(rect: Rect2, color: Color, radius: int = 24) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _text(value: String, at: Vector2, size_value: int) -> void:
	draw_string(font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_value, Color("#5a4538"))

func _shadow(center: Vector2, radius: Vector2) -> void:
	_ellipse(center, radius, Color("#8165482c"))

func _ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		points.append(center + Vector2.from_angle(index * TAU / 24.0) * radius)
	draw_colored_polygon(points, color)
