extends SceneTree

const Cage = preload("res://cage.tscn")
const Habitat = preload("res://habitat.gd")
const Care = preload("res://care.gd")
const Motion = preload("res://cage_motion.gd")
var game: Control
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = Cage.instantiate()
	game.care.path = "user://drop-activity-test-%d.json" % OS.get_process_id()
	root.add_child(game)
	game.set_process(false)
	game.care.sound = false
	await process_frame
	var fixtures := [
		[Vector3(Habitat.BOWL.x, 0.44, Habitat.BOWL.y), "吃", -1],
		[Vector3(Habitat.DRINK.x, 1.48, -3.32), "喝", -1],
		[Vector3(Habitat.CUBBIES[0].x, 0.57, -1.78), "睡", 0],
		[Vector3(Habitat.CUBBIES[1].x, 0.57, -1.97), "睡", 1],
		[Vector3(Habitat.WHEEL_ENTRY.x, 1.63, -1.65), "跑", -1],
	]
	for fixture in fixtures:
		_reset_actors()
		var task: String = fixture[1]
		var use_touch := task == "吃"
		var target := _drag_to(fixture[0], use_touch)
		_check(game.held == 0 and game.held_target.get("task", "") == task, "识别目标 " + task)
		if use_touch and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png("res://dist/hamster-drop-activity.png") == OK, "保存拖放提示画面")
		_release(target, use_touch)
		_check(game.held < 0 and game.actors[0].state == "走", "松手后安排路线 " + task)
		var landed: Vector2 = game.actors[0].pos
		if task == "吃":
			_check(landed.distance_to(Habitat.BOWL) >= Motion.bowl_clearance(0, game.care.growth_scale(0)) - 0.001, "捏到碗上也落在碗外")
		game._process(0.05)
		_check(game.actors[0].pos.is_equal_approx(landed), "先落地再走 " + task)
		for frame in range(300):
			game._process(0.05)
			if game.actors[0].state == task:
				break
		_check(game.actors[0].state == task, "抵达后执行 %s，实际状态 %s，位置 %s，目标 %s" % [task, game.actors[0].state, game.actors[0].pos, game.actors[0].goal])
		if task == "睡":
			var door: Vector2 = Habitat.CUBBIES[fixture[2]]
			_check(game.actors[0].nest == fixture[2] and game.actors[0].pos.y < door.y - 1.0, "进入选中的小窝")
			game._travel(game.actors[0], Vector2(0, 3), "嗅")
			_check(game.actors[0].goal == door + Vector2(0, 0.42), "离窝时先走门洞")
		elif task == "跑":
			game._process(0.05)
			_check(game.wheel_owner == 0 and game.wheel_speed > 0.0, "上轮后滚轮随脚步转动")
	_reset_actors()
	game.care.pets[0].food_at = game.care.now - Care.FOOD[0] - 1
	_release(_drag_to(fixtures[0][0]), false)
	_check(game.actors[0].state == "回应" and "先添粮" in game.notice, "空食盆提示添粮")
	game.care.refill("food")
	_reset_actors()
	game.actors[1].state = "喝"
	game.actors[1].pos = Habitat.DRINK
	_release(_drag_to(fixtures[1][0]), false)
	_check(game.actors[0].state == "回应" and "有人用" in game.notice, "水壶被占用时不抢占")
	_reset_actors()
	_drag_to(fixtures[4][0])
	game._cancel_gestures()
	_check(game.held < 0 and game.wheel_owner < 0 and game.actors[0].state == "回应", "打断手势不会安排动作")
	await _check_bowl_paths()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(game.care.path + suffix):
			DirAccess.remove_absolute(game.care.path + suffix)
	game.queue_free()
	await process_frame
	print("拖放行为测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _check_bowl_paths() -> void:
	for fixture in [[0, Care.WEAN_AGE], [0, Care.ADULT_AGE], [1, Care.ADULT_AGE]]:
		_reset_actors()
		var index: int = fixture[0]
		game.care.pets[index].born_at = game.care.now - fixture[1]
		var actor: Dictionary = game.actors[index]
		var other: Dictionary = game.actors[1 - index]
		actor.pos = Habitat.CUBBIES[0] + Vector2(0, 0.42)
		other.pos = Vector2(2.7, 3.8)
		game._process(0.05)
		var clearance := Motion.bowl_clearance(index, game.care.growth_scale(index))
		# 左窝出口到前方过道的直线穿过碗，验证整条绕行路线和实际位置。
		game._travel(actor, Vector2(-3.7, 3.2), "嗅")
		var walk_gap := _advance_to(actor, "嗅")
		_check(actor.state == "嗅" and walk_gap >= clearance - 0.001, "从左窝旁走到前方全程避开食盆")
		game._start_activity(index, "吃", -1)
		var eating_gap := _advance_to(actor, "吃")
		_check(actor.state == "吃" and eating_gap >= clearance - 0.001, "到碗沿吃粮时身体一直在碗外")
		for frame in range(45):
			game._process(0.05)
		var nose: Vector3 = game.habitat.noses[index].global_position
		var nose_distance := Vector2(nose.x, nose.z).distance_to(Habitat.BOWL)
		_check(absf(nose_distance - Habitat.BOWL_RADIUS) < 0.18 and nose.y > Habitat.BOWL_RIM_HEIGHT, "进食时只把嘴伸到碗沿上方")
		if index == 1 and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			_check(root.get_texture().get_image().save_png("res://dist/hamster-bowl-clearance.png") == OK, "保存碗沿吃粮的效果")

func _advance_to(actor: Dictionary, state: String) -> float:
	var smallest := INF
	for frame in range(550):
		game._process(0.05)
		var position: Vector2 = actor.pos
		smallest = minf(smallest, position.distance_to(Habitat.BOWL))
		if actor.state == state:
			break
	return smallest

func _reset_actors() -> void:
	game.wheel_owner = -1
	game.actors[0] = game._actor(-0.9, 60)
	game.actors[1] = game._actor(2.65, 60)
	game.actors[0].pos.y = 2.8
	game.actors[1].pos.y = 3.8
	game.social_cooldown = 1000
	game._process(0.05)

func _drag_to(world: Vector3, use_touch: bool = false) -> Vector2:
	var camera: Camera3D = game.habitat.camera
	var start := camera.unproject_position(game.habitat.pets[0].position + Vector3(0, 0.47, 0))
	var target := camera.unproject_position(world)
	if use_touch:
		_touch(0, start - Vector2(12, 0), true)
		_touch(1, start + Vector2(12, 0), true)
	else:
		_mouse(start, true)
	for frame in range(9):
		game._process(0.05)
	if use_touch:
		for i in range(2):
			var event := InputEventScreenDrag.new()
			event.index = i
			event.position = target + Vector2(-12 if i == 0 else 12, 0)
			game._input(event)
	else:
		var event := InputEventMouseMotion.new()
		event.position = target
		game._input(event)
	game._process(0.05)
	return target

func _release(target: Vector2, use_touch: bool) -> void:
	if use_touch:
		_touch(0, target - Vector2(12, 0), false)
		_touch(1, target + Vector2(12, 0), false)
	else:
		_mouse(target, false)

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	game._input(event)

func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = position
	event.pressed = pressed
	game._input(event)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("未通过：", message)
