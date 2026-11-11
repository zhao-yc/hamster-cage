extends Control

const Care = preload("res://care.gd")
const Art = preload("res://cage_art.gd")
const Habitat = preload("res://habitat.gd")
const Motion = preload("res://cage_motion.gd")
const CarePlay = preload("res://care_play.gd")
const DESIGN := Vector2(1024, 640)
const ACTIONS := ["添粮", "加水", "换垫料"]
const CARE_BUTTON_SIZE := Vector2(128, 52)
const CARE_BUTTON_GAP := 14.0
const CAPTION_HEIGHT := 35.0
const CHASE_DURATION := 5.0
const FIGHT_DURATION := 4.0
const FIGHT_NOTICE := "它们打起来了，轻轻抱开一只吧。"
const HINTS := ["点「添粮」，给仓鼠装满食盆。", "点「加水」，给仓鼠装满水壶。", "点「换垫料」，给仓鼠铺好干净的床。"]
const CREAM := Color("#fff0d7")

enum SocialKind { CHASE, FIGHT }

var care := Care.new()
var actors: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var stage: Control
var habitat: Node3D
var controls: Array[Button] = []
var gear: Button
var caption_y := 0.0
var ui_font: Font
var audio: AudioStreamPlayer
var modal: ColorRect
var modal_content: VBoxContainer
var memorial := -1
var farewells: Array[int] = []
var notice := ""
var notice_left := 0.0
var tutorial := 0
var wheel_owner := -1
var wheel_angle := 0.0
var wheel_speed := 0.0
var clock_left := 0.0
var clock_origin := 0
var clock_ticks := 0
var save_left := 0.0
var save_failed := false
var parent_hold := -1.0
var ar: Object
var ar_pending := false
var care_play: Control
var touches: Dictionary = {}
var touch_consumed := false
var held := -1
var social_left := 0.0
var social_cooldown := 35.0
var social_kind := SocialKind.CHASE
var social_center := Vector2.ZERO
var social_angle := 0.0
var last_steps := [-1, -1]

func _ready() -> void:
	rng.randomize()
	var font := FontVariation.new()
	font.base_font = load("res://assets/NotoSansSC.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 530}
	ui_font = font
	care.load_or_start(_wall())
	clock_origin = maxi(clock_origin, care.now)
	tutorial = ACTIONS.size() if care.tutorial_seen else 0
	actors = [_actor(-0.7, 1.0), _actor(1.55, 1.4)]
	habitat = Habitat.new()
	add_child(habitat)
	var lens := ColorRect.new()
	lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lens_material := ShaderMaterial.new()
	lens_material.shader = load("res://assets/lens.gdshader")
	lens.material = lens_material
	add_child(lens)
	stage = Control.new()
	stage.size = DESIGN
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	stage.draw.connect(_draw_stage)
	resized.connect(_layout)
	for index in range(3):
		var button := _button("      " + ACTIONS[index], Rect2(Vector2.ZERO, CARE_BUTTON_SIZE), CREAM, 20)
		button.pressed.connect(_care_action.bind(index))
		_add_icon(button, index)
		controls.append(button)
	gear = _button("", Rect2(0, 0, 54, 54), CREAM)
	gear.tooltip_text = "设置"
	gear.draw.connect(func() -> void:
		var center := gear.size * 0.5
		gear.draw_arc(center, 9.5, 0, TAU, 28, Art.INK, 5.5, true)
		for i in range(8):
			var ray := Vector2.from_angle(TAU * i / 8.0)
			gear.draw_line(center + ray * 10, center + ray * 15, Art.INK, 4.5, true)
	)
	gear.pressed.connect(_show_settings)
	if OS.get_name() == "iOS" and Engine.has_singleton("HamsterAR"):
		ar = Engine.get_singleton("HamsterAR")

	audio = AudioStreamPlayer.new()
	add_child(audio)
	_make_modal()
	_layout()
	_refresh()
	habitat.sync_droppings(care.droppings)
	_save()

func _actor(x: float, delay: float) -> Dictionary:
	return {"pos": Vector2(x, 1.3), "goal": Vector2(x, 1.3), "route": [],
		"next": "嗅", "state": "嗅", "left": delay, "dir": 0.2, "phase": delay, "visits": 0,
		"lift": 0.0, "poop_left": randf_range(45, 90), "velocity": Vector2.ZERO,
		"facing": 0.2, "turn_speed": 0.0, "gait": 0.0, "speed": 0.0}

func _layout() -> void:
	var area := Rect2(Vector2.ZERO, size)
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var window_size := get_window().size
		if safe.has_area() and window_size.x > 0 and window_size.y > 0:
			var units := size / Vector2(window_size)
			var visible := Rect2(Vector2(safe.position) * units, Vector2(safe.size) * units)
			if area.intersects(visible):
				area = area.intersection(visible)
	var scale_factor := minf(area.size.x / DESIGN.x, area.size.y / DESIGN.y)
	stage.scale = Vector2.ONE * scale_factor
	stage.position = area.get_center() - DESIGN * scale_factor * 0.5
	var local := Rect2((area.position - stage.position) / stage.scale, area.size / stage.scale)
	# 从安全区左下角排列，提示条和按钮之间留出固定的垂直间距。
	var buttons_start := Vector2(local.position.x + 24, local.end.y - CARE_BUTTON_SIZE.y - 22)
	for index in range(controls.size()):
		controls[index].position = buttons_start + Vector2(index * (CARE_BUTTON_SIZE.x + CARE_BUTTON_GAP), 0)
	gear.position = local.end * Vector2(1, 0) + Vector2(-76, local.position.y + 22)
	caption_y = buttons_start.y - CAPTION_HEIGHT - 20
	modal.position = local.position
	modal.size = local.size
	modal.get_child(0).position = DESIGN * 0.5 - local.position - Vector2(306, 228)
	stage.queue_redraw()

func _button(title: String, rect: Rect2, color: Color, font_size: int = 23, host: Control = null) -> Button:
	var button := Button.new()
	button.text = title
	button.position = rect.position
	button.custom_minimum_size = rect.size
	button.size = rect.size
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ui_font)
	button.add_theme_font_size_override("font_size", font_size)
	# 焦点文字有独立的主题颜色，浅色按钮获得焦点后也要保持深色字。
	button.add_theme_color_override("font_focus_color", Art.INK)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = color.lightened(0.15) if state == "hover" else color
		style.set_corner_radius_all(28)
		style.set_border_width_all(1)
		style.border_color = Color("#fff9e9")
		style.shadow_color = Color("#82604b32")
		style.shadow_size = 2 if state == "pressed" else 5
		style.shadow_offset = Vector2(0, 3)
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", Art.INK)
	(host if host != null else stage).add_child(button)
	return button

func _make_modal() -> void:
	modal = ColorRect.new()
	modal.size = DESIGN
	modal.color = Color("#49302479")
	stage.add_child(modal)
	var panel := Panel.new()
	panel.position = Vector2(206, 92)
	panel.size = Vector2(612, 456)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff3da")
	style.set_corner_radius_all(27)
	panel.add_theme_stylebox_override("panel", style)
	modal.add_child(panel)
	modal_content = VBoxContainer.new()
	modal_content.position = Vector2(38, 29)
	modal_content.size = Vector2(536, 398)
	modal_content.add_theme_constant_override("separation", 13)
	panel.add_child(modal_content)
	modal.hide()

func _dialog(title: String, body: String) -> void:
	_cancel_gestures()
	parent_hold = -1
	modal.show()
	for child in modal_content.get_children():
		modal_content.remove_child(child)
		child.queue_free()
	_dialog_label(title, 30)
	if not body.is_empty():
		_dialog_label(body, 20)

func _dialog_label(value: String, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Art.INK)
	modal_content.add_child(label)

func _dialog_button(value: String, action: Callable) -> void:
	var button := _button(value, Rect2(0, 0, 0, 47), Color("#e5d5ad"), 19, modal_content)
	button.pressed.connect(action)
	button.grab_focus()

func _show_farewell() -> void:
	memorial = farewells.pop_front()
	_dialog("和%s说再见" % Care.NAMES[memorial], "%s已经离世了。我们把它的照片留在相册里。" % Care.NAMES[memorial])
	_portrait(memorial)
	_dialog_button("回到笼子", _close_dialog)

func _portrait(index: int) -> void:
	var picture := Control.new()
	picture.custom_minimum_size.y = 130
	picture.draw.connect(func() -> void:
		Art.pill(picture, Rect2(192, 4, 152, 119), Color("#e2e6bf"), 16)
		Art.hamster(picture, Vector2(267, 103), index, 1, "嗅", 0.5, 1.22)
	)
	modal_content.add_child(picture)

func _show_album(offset: int = 0) -> void:
	_refresh()
	if memorial != -1:
		return
	if care.album.is_empty():
		_dialog("仓鼠相册", "纪念照片会留在这里。")
	else:
		var entry: Dictionary = care.album[care.album.size() - 1 - offset]
		var date := Time.get_date_string_from_unix_time(int(entry.at))
		_dialog("仓鼠相册  %d / %d" % [offset + 1, care.album.size()], "%s  ·  %s" % [Care.NAMES[int(entry.pet)], date])
		_portrait(int(entry.pet))
		if offset + 1 < care.album.size():
			_dialog_button("更早的照片", _show_album.bind(offset + 1))
		if offset > 0:
			_dialog_button("较新的照片", _show_album.bind(offset - 1))
	_dialog_button("回到笼子", _close_dialog)

func _show_parent() -> void:
	_refresh()
	if memorial != -1:
		parent_hold = -1.0
		return
	_dialog("家长", "可以为已经离世的仓鼠领养一位同色的新成员。")
	for index in range(2):
		if not care.alive(index):
			_dialog_button("领养新的%s" % Care.NAMES[index], _confirm_adopt.bind(index))
	_dialog_button("返回", _close_dialog)

func _show_settings() -> void:
	_dialog("设置", "")
	_dialog_button("声音开" if care.sound else "声音关", func() -> void:
		care.sound = not care.sound
		_save()
		_chime(1)
		_show_settings()
	)
	_dialog_button("仓鼠相册", _show_album)
	_dialog_button("长按 · 家长", func() -> void: pass)
	var family := modal_content.get_child(modal_content.get_child_count() - 1) as Button
	family.button_down.connect(func() -> void: parent_hold = 0.0)
	family.button_up.connect(func() -> void: parent_hold = -1.0)
	family.mouse_exited.connect(func() -> void: parent_hold = -1.0)
	if ar != null and ar.is_supported():
		_dialog_button("到桌上玩", func() -> void:
			_close_dialog()
			_open_ar()
		)
	_dialog_button("回到笼子", _close_dialog)
	_dialog_label("双指捏住可抱起；电脑用鼠标右键拖动", 16)

func _confirm_adopt(index: int) -> void:
	_dialog("确认领养", "新的%s会来到笼子，旧照片会留在相册里。" % Care.NAMES[index])
	_dialog_button("确认领养", _adopt.bind(index))
	_dialog_button("取消", _show_parent)

func _adopt(index: int) -> void:
	_refresh()
	if memorial != -1:
		return
	if care.adopt(index):
		actors[index] = _actor(-0.7 if index == 0 else 1.55, 0.5)
		_save()
		_feedback("新的%s到家啦。" % Care.NAMES[index], 2)
	_close_dialog()

func _close_dialog() -> void:
	memorial = -1
	modal.hide()
	if not farewells.is_empty():
		_show_farewell()

func _care_action(index: int) -> void:
	_refresh()
	if modal.visible or is_instance_valid(care_play):
		return
	if index < 2 and not care.alive(0) and not care.alive(1):
		_feedback("笼子现在空着。", 0)
		return
	_cancel_gestures()
	_end_social()
	care_play = CarePlay.new()
	add_child(care_play)
	care_play.begin(index, ui_font)
	care_play.completed.connect(_finish_care)
	care_play.cancelled.connect(_cancel_care)

func _cancel_care() -> void:
	if is_instance_valid(care_play):
		care_play.queue_free()
	care_play = null

func _finish_care(index: int) -> void:
	_cancel_care()
	_refresh()
	if modal.visible:
		return
	if index < 2:
		care.refill("food" if index == 0 else "water")
	else:
		care.replace_bedding()
		habitat.clean_bedding()
		habitat.sync_droppings(care.droppings)
	if tutorial == index:
		tutorial += 1
		care.tutorial_seen = tutorial == ACTIONS.size()
	_save()
	_feedback(["食盆装满了！", "水壶装满了！", "垫料变干净啦！"][index], index)

func _wall() -> int:
	var wall := int(Time.get_unix_time_from_system())
	var ticks := Time.get_ticks_msec()
	@warning_ignore("integer_division")
	var elapsed := (ticks - clock_ticks) / 1000
	if wall > clock_origin + elapsed:
		clock_origin = wall
		clock_ticks = ticks
		return wall
	return clock_origin + elapsed

func _refresh() -> void:
	var departed := care.settle(_wall())
	if departed.is_empty():
		return
	farewells.append_array(departed)
	if ar_pending:
		ar.close()
	if wheel_owner in departed:
		wheel_owner = -1
	_save()
	if memorial == -1:
		_show_farewell()

func _save() -> void:
	save_failed = not care.save()
	save_left = 15.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and is_instance_valid(modal):
		_cancel_gestures()
		_cancel_care()
		parent_hold = -1
		_refresh()
		_save()
	elif what == NOTIFICATION_APPLICATION_RESUMED and is_instance_valid(modal):
		_refresh()
		_layout()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(modal):
		_cancel_gestures()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST and is_instance_valid(modal):
		_refresh()
		_save()

func _open_ar() -> void:
	_refresh()
	if modal.visible or ar_pending:
		return
	if not care.alive(0) and not care.alive(1):
		_feedback("有仓鼠住进来后，就能到桌上玩。", 0)
		return
	_save()
	ar_pending = ar.open(care.alive(0), care.alive(1))
	if not ar_pending:
		_feedback("现在打不开相机，可以继续在笼子里玩。", 0)

func _process(delta: float) -> void:
	if ar_pending:
		var event: int = ar.take_event()
		if event != 0:
			ar_pending = false
			_refresh()
			if event == 2:
				_feedback("相机未开启，可以继续在笼子里玩。", 0)
	clock_left -= delta
	if clock_left <= 0.0:
		clock_left = 1.0
		_refresh()
	save_left -= delta
	if save_left <= 0.0:
		_save()
	if parent_hold >= 0.0:
		parent_hold += delta
		if parent_hold >= 1.2:
			_show_parent()
	notice_left -= delta
	var frame_delta := minf(delta, 0.05)
	var previous := [actors[0].pos, actors[1].pos]
	_social(frame_delta)
	for index in range(actors.size()):
		if care.alive(index):
			if index != held and social_left <= 0:
				_move_actor(index, frame_delta)
			else:
				actors[index].phase += frame_delta
				if index == held:
					Motion.face(actors[index], actors[index].facing, frame_delta)
			actors[index].lift = move_toward(actors[index].lift, 1.25 if index == held else 0.0, frame_delta * 4.0)
			_poop(index, frame_delta)
	var airborne := held if held >= 0 and actors[held].lift >= 1.1 else -1
	Motion.separate(actors, [care.alive(0), care.alive(1)], airborne)
	for index in range(actors.size()):
		var distance: float = actors[index].pos.distance_to(previous[index]) if index != held else 0.0
		actors[index].speed = distance / maxf(frame_delta, 0.001)
		# 行走步态随真正走过的距离推进；停下或被挡住时不再原地高速踏步。
		actors[index].gait += frame_delta * 14.0 if actors[index].state == "跑" else distance * TAU / ((1.73 if index == 0 else 1.52) * 0.42)
		habitat.show_pet(index, actors[index], care.alive(index), frame_delta)
		if care.alive(index) and actors[index].state in ["走", "嬉戏", "打架"] and index != held and actors[index].speed > 0.12:
			var step := floori(actors[index].gait / PI)
			if step != last_steps[index]:
				last_steps[index] = step
				var paw: Node3D = habitat.feet[index][step % 4]
				var closest := INF
				for foot in habitat.feet[index]:
					var p: Vector3 = foot.global_position
					var gap: float = p.y - Habitat.Meshes.bedding_height(p.x, p.z)
					if gap < closest:
						closest = gap
						paw = foot
				if closest < 0.12:
					habitat.nudge_bedding(paw.global_position, Vector2(sin(actors[index].dir), cos(actors[index].dir)))
	habitat.tick_bedding(frame_delta)
	wheel_speed = move_toward(wheel_speed, 5.6 if wheel_owner >= 0 and actors[wheel_owner].state == "跑" else 0.0, delta * 5.0)
	wheel_angle = fposmod(wheel_angle + wheel_speed * delta, TAU)
	var dirt := clampf(float(care.now - care.bedding_at) / Care.BEDDING_TIME, 0, 1)
	habitat.update_supplies(wheel_angle, _supply("food", Care.FOOD), _supply("water", Care.WATER), dirt)
	stage.queue_redraw()

func _move_actor(index: int, delta: float) -> void:
	var actor := actors[index]
	actor.phase += delta
	actor.left -= delta
	if actor.state == "走":
		var other_airborne: bool = held == 1 - index and actors[1 - index].lift >= 1.1
		Motion.advance(actor, actors[1 - index].pos, care.alive(1 - index) and not other_airborne, index, delta)
		if actor.pos.distance_to(actor.goal) > 0.008:
			return
		actor.pos = actor.goal
		actor.velocity = Vector2.ZERO
		if not actor.route.is_empty():
			_set_goal(actor, actor.route.pop_front())
			return
		actor.state = actor.next
		if actor.state == "上轮":
			_travel(actor, Habitat.WHEEL_RUN, "跑")
			return
		actor.left = rng.randf_range(3.0, 6.0) if actor.state in ["睡", "跑"] else rng.randf_range(0.8, 1.8)
		if actor.state == "跑":
			actor.facing = -PI / 2
		elif actor.state == "吃":
			actor.facing = -PI / 2
		elif actor.state in ["喝", "睡"]:
			actor.facing = PI
		return
	actor.velocity = Vector2.ZERO
	Motion.face(actor, actor.facing, delta)
	if actor.left > 0:
		return
	if wheel_owner == index:
		wheel_owner = -1
		_travel(actor, Habitat.WHEEL_ENTRY, "嗅")
		return
	actor.visits += 1
	var options := ["走走", "嗅", "睡", "吃", "喝", "跑"]
	var task: String = "跑" if actor.visits % 4 == 0 else options[rng.randi_range(0, options.size() - 1)]
	if task == "跑" and wheel_owner == -1:
		wheel_owner = index
		_travel(actor, Habitat.WHEEL_ENTRY, "上轮")
	elif task == "睡":
		_travel(actor, Habitat.CUBBIES[index], "睡")
	elif task == "吃" and care.remaining(index, "food") > 0 and not _reserved(1 - index, "吃"):
		_travel(actor, Habitat.BOWL + Vector2(1.22, 0), "吃")
	elif task == "喝" and care.remaining(index, "water") > 0 and not _reserved(1 - index, "喝"):
		_travel(actor, Habitat.DRINK, "喝")
	else:
		_travel(actor, Vector2(rng.randf_range(-3.35, 3.35), rng.randf_range(2.05, 3.65)), "嗅")

func _travel(actor: Dictionary, goal: Vector2, next: String) -> void:
	actor.next = next
	actor.state = "走"
	actor.route.clear()
	if next != "跑" and absf(actor.pos.x - goal.x) > 0.65:
		# 横向穿过开阔过道，避免穿过小窝、食盆和滚轮。
		var aisle := 2.12
		actor.route.assign([Vector2(actor.pos.x, aisle), Vector2(goal.x, aisle)])
	actor.route.append(goal)
	_set_goal(actor, actor.route.pop_front())

func _set_goal(actor: Dictionary, goal: Vector2) -> void:
	actor.goal = goal
	var offset: Vector2 = goal - actor.pos
	if offset.length_squared() > 0.001:
		actor.facing = atan2(offset.x, offset.y)

func _gui_input(event: InputEvent) -> void:
	if modal.visible or is_instance_valid(care_play) or held >= 0 or not event is InputEventMouseButton or event.device == InputEvent.DEVICE_ID_EMULATION or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	_respond_at(event.position)

func _respond_at(point: Vector2) -> void:
	var order := [0, 1] if actors[0].pos.y > actors[1].pos.y else [1, 0]
	for index in order:
		var actor := actors[index]
		if care.alive(index) and habitat.hit(index, point):
			if actor.state == "打架":
				return
			if actor.state == "跑":
				_feedback("%s正在跑滚轮！" % Care.NAMES[index], index)
			else:
				if wheel_owner == index:
					wheel_owner = -1
				actor.state = "回应"
				actor.facing = 0.0
				actor.velocity = Vector2.ZERO
				actor.left = 1.5
				_feedback("%s看到你啦！" % Care.NAMES[index], index)
			return

func _reserved(index: int, task: String) -> bool:
	return care.alive(index) and (actors[index].state == task or (actors[index].state == "走" and actors[index].next == task))

func _poop(index: int, delta: float) -> void:
	var actor := actors[index]
	if index == held or actor.state in ["睡", "跑", "嬉戏", "打架"] or actor.pos.y < 0.7:
		return
	actor.poop_left -= delta
	if actor.poop_left > 0:
		return
	actor.poop_left = rng.randf_range(60, 110)
	actor.state = "便便"
	actor.left = 1.4
	var behind: Vector2 = actor.pos - Vector2(sin(actor.dir), cos(actor.dir)) * 0.65
	care.add_dropping(behind)
	habitat.sync_droppings(care.droppings)
	_save()

func _end_social() -> void:
	if social_left > 0:
		for actor in actors:
			actor.state = "嗅"
			actor.left = 2.0
			actor.velocity = Vector2.ZERO
		if social_kind == SocialKind.FIGHT and notice == FIGHT_NOTICE:
			notice_left = 0.0
	social_left = 0
	social_cooldown = rng.randf_range(80, 130)

func _social(delta: float) -> void:
	if held >= 0 or modal.visible or is_instance_valid(care_play) or ar_pending or not care.alive(0) or not care.alive(1):
		_end_social()
		return
	if social_left > 0:
		if social_left <= delta:
			_end_social()
			if social_kind == SocialKind.FIGHT:
				notice = "它们分开啦。"
				notice_left = 1.8
			else:
				for i in range(2):
					_travel(actors[i], Vector2(-2.8 if i == 0 else 2.8, 3.3), "嗅")
			return
		social_left -= delta
		if social_kind == SocialKind.FIGHT:
			_fight(delta)
			return
		for i in range(2):
			var angle := social_angle + (CHASE_DURATION - social_left) * 1.1 + i * PI
			var destination := social_center + Vector2(cos(angle), sin(angle)) * 0.94
			var before: Vector2 = actors[i].pos
			actors[i].pos = before.move_toward(destination, delta * 1.5)
			var direction: Vector2 = actors[i].pos - before
			if direction.length_squared() > 0.000001:
				actors[i].facing = atan2(direction.x, direction.y)
			Motion.face(actors[i], actors[i].facing, delta)
			actors[i].velocity = direction / maxf(delta, 0.001)
			actors[i].state = "嬉戏"
		return
	social_cooldown -= delta
	if social_cooldown > 0:
		return
	for i in range(2):
		if actors[i].state not in ["走", "嗅", "回应"] or actors[i].pos.y < 1.2 or care.remaining(i, "food") <= 0 or care.remaining(i, "water") <= 0:
			return
	if actors[0].pos.distance_to(actors[1].pos) >= 2.4:
		return
	# 只在开阔地面打架，与追逐共用冷却时间，避免连续打架或挤进后排设施。
	var fight_area := Rect2(-3.9, 2.0, 7.8, 1.8)
	var can_fight := fight_area.has_point(actors[0].pos) and fight_area.has_point(actors[1].pos)
	social_kind = SocialKind.FIGHT if can_fight and social_kind == SocialKind.CHASE else SocialKind.CHASE
	social_center = (actors[0].pos + actors[1].pos) * 0.5
	# 两只都已离开原路线，释放尚未使用的滚轮。
	wheel_owner = -1
	if social_kind == SocialKind.FIGHT:
		social_left = FIGHT_DURATION
		social_angle = (actors[0].pos - social_center).angle()
		_fight(delta)
		_feedback(FIGHT_NOTICE, 2)
		notice_left = FIGHT_DURATION
	else:
		social_center = social_center.clamp(Vector2(-1.1, 2.1), Vector2(2.4, 3.1))
		social_left = CHASE_DURATION
		social_angle = (actors[0].pos - social_center).angle()
		_feedback("它们在玩追逐游戏，可以轻轻抱开哦。", 1)

func _fight(delta: float) -> void:
	# 先转向对峙，再交替挥爪、后仰，最后各退一步。始终保留身体间距。
	var elapsed := FIGHT_DURATION - social_left
	var swing_time := maxf(elapsed - 1.15, 0.0)
	var beat := floori(swing_time / 0.56)
	var strength := pow(sin(fposmod(swing_time, 0.56) / 0.56 * PI), 2) if beat < 4 else 0.0
	var retreat := smoothstep(3.4, FIGHT_DURATION, elapsed) * 0.18
	for i in range(2):
		var actor := actors[i]
		var swing := strength if i == beat % 2 else -strength
		var outward := Vector2.from_angle(social_angle + i * PI)
		var radius := 0.92 + retreat - swing * (0.22 if swing > 0 else 0.07)
		var destination := social_center + outward * radius
		var before: Vector2 = actor.pos
		actor.pos = before.move_toward(destination, delta * 1.3)
		actor.velocity = (actor.pos - before) / maxf(delta, 0.001)
		actor.facing = atan2(-outward.x, -outward.y)
		Motion.face(actor, actor.facing, delta)
		actor.state = "打架"
		actor.fight_swing = swing

func _lift_at(point: Vector2) -> void:
	if held >= 0:
		return
	for index in [0, 1]:
		if care.alive(index) and habitat.hit(index, point):
			_end_social()
			held = index
			if wheel_owner == index:
				wheel_owner = -1
			actors[index].state = "抱起"
			actors[index].velocity = Vector2.ZERO
			actors[index].route.clear()
			_feedback("轻轻抱着%s，移动后松开放下。" % Care.NAMES[index], index)
			return

func _drag_held(point: Vector2) -> void:
	if held >= 0 and actors[held].lift >= 1.1:
		actors[held].pos = Motion.safe_floor(habitat.floor_point(point))

func _drop_held() -> void:
	if held < 0:
		return
	var index := held
	held = -1
	actors[index].pos = Motion.drop(actors[index].pos, actors[1-index].pos, care.alive(1-index))
	actors[index].state = "回应"
	actors[index].facing = 0.0
	actors[index].velocity = Vector2.ZERO
	actors[index].left = 2.0
	social_cooldown = 100.0

func _cancel_gestures() -> void:
	_drop_held()
	touches.clear()
	touch_consumed = false

func _input(event: InputEvent) -> void:
	if not is_instance_valid(modal) or modal.visible or is_instance_valid(care_play):
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 2:
				var points := touches.values()
				var midpoint: Vector2 = (points[0] + points[1]) * 0.5
				for i in range(2):
					if care.alive(i) and habitat.hit(i, points[0]) and habitat.hit(i, points[1]):
						_lift_at(midpoint)
						touch_consumed = held >= 0
		else:
			if held >= 0:
				_drop_held()
			elif touches.size() == 1 and not touch_consumed:
				_respond_at(event.position)
			touches.erase(event.index)
			if touches.is_empty():
				touch_consumed = false
		# 单指事件继续交给按钮，已识别的双指才拦截，避免影响照料入口。
		if touch_consumed or held >= 0:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and touches.has(event.index):
		touches[event.index] = event.position
		if held >= 0 and touches.size() == 2:
			var points := touches.values()
			_drag_held((points[0] + points[1]) * 0.5)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_lift_at(event.position)
		else:
			_drop_held()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and held >= 0 and touches.is_empty():
		_drag_held(event.position)
		get_viewport().set_input_as_handled()

func _feedback(value: String, index: int) -> void:
	notice = value
	notice_left = 2.2
	_chime(index)

func _chime(index: int) -> void:
	if not care.sound or not is_instance_valid(audio):
		return
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(6600)
	for sample in range(3300):
		var time := float(sample) / wav.mix_rate
		var volume := sin(PI * sample / 3300.0) * 0.14
		var pitch := 440.0 + index * 85.0
		samples.encode_s16(sample * 2, int(sin(TAU * (pitch * time + 270 * time * time)) * volume * 32767))
	wav.data = samples
	audio.stream = wav
	audio.play()

func _needs() -> String:
	var alerts: Array[String] = []
	for index in range(2):
		if not care.alive(index):
			continue
		var water := care.remaining(index, "water")
		var food := care.remaining(index, "food")
		if water <= 0 or food <= 0:
			var need := "需要吃饭和喝水" if water <= 0 and food <= 0 else ("需要喝水" if water <= 0 else "饿了")
			alerts.append(Care.NAMES[index] + need)
		elif water <= Care.WATER[index] * 0.25 or food <= Care.FOOD[index] * 0.25:
			alerts.append(Care.NAMES[index] + ("的水快喝完了" if water <= Care.WATER[index] * 0.25 else "的粮快吃完了"))
	if not alerts.is_empty():
		return "　·　".join(alerts)
	if care.now - care.bedding_at >= Care.BEDDING_TIME:
		return "该换干净垫料啦。"
	if tutorial < HINTS.size():
		return HINTS[tutorial]
	return "" if care.alive(0) or care.alive(1) else "可以在相册里看看它们。"

func _supply(kind: String, capacities: Array) -> float:
	var amount := 0.0
	var count := 0
	for index in range(2):
		if care.alive(index):
			count += 1
			amount += clampf(float(care.remaining(index, kind)) / capacities[index], 0, 1)
	return amount / maxf(1, count)

func _draw_stage() -> void:
	var caption := "存档暂时无法保存，请检查设备空间。" if save_failed else (notice if notice_left > 0 else _needs())
	if caption.is_empty():
		return
	var width := ui_font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
	var start := (DESIGN.x - width) / 2
	Art.pill(stage, Rect2(start - 16, caption_y, width + 32, CAPTION_HEIGHT), CREAM, 17)
	stage.draw_string(ui_font, Vector2(start, caption_y + 24), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Art.INK)

func _add_icon(button: Button, index: int) -> void:
	# 图标画在按钮的子画布上，触控与键盘焦点仍由标准按钮管理。
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(25, CARE_BUTTON_SIZE.y * 0.5)
	icon.scale = Vector2(0.8, 0.8)
	icon.draw.connect(func() -> void:
		match index:
			0:
				for seed in [Vector2(-9, 4), Vector2(2, -8), Vector2(10, 7)]:
					Art.oval(icon, seed, Vector2(6, 9), Color("#9d6638"))
					icon.draw_line(seed + Vector2(-1, -5), seed + Vector2(1, 5), Color("#d9ae70"), 1.5, true)
			1:
				icon.draw_colored_polygon(PackedVector2Array([Vector2(0, -14), Vector2(-10, 1), Vector2(10, 1)]), Color("#477e89"))
				icon.draw_circle(Vector2(0, 2), 10, Color("#477e89"), true, -1, true)
				icon.draw_arc(Vector2(0, 1), 7, 1.9, 3.1, 12, Color("#88b7be"), 2.5, true)
			2:
				for y in [7, -4]:
					icon.draw_colored_polygon(PackedVector2Array([Vector2(-16, y), Vector2(0, y - 9), Vector2(16, y), Vector2(0, y + 9)]), Color("#7b8957"))
					icon.draw_polyline(PackedVector2Array([Vector2(-15, y + 1), Vector2(0, y + 9), Vector2(15, y + 1)]), Color("#b5c38c"), 2, true)
	)
	button.add_child(icon)
