extends SceneTree

const Cage = preload("res://cage.tscn")
const Meshes = preload("res://habitat_meshes.gd")
const Care = preload("res://care.gd")
var game: Control
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("未通过：", message)

func _run() -> void:
	game = Cage.instantiate()
	game.care.path = "user://walk-test-%d.json" % OS.get_process_id()
	root.add_child(game)
	game.set_process(false)
	# 现有步行基线以成年仓鼠的尺寸和间距为准。
	for pet in game.care.pets:
		pet.born_at = game.care.now - Care.ADULT_AGE
	await process_frame
	game.tutorial = 3
	game.care.tutorial_seen = true
	# 分别覆盖稳定帧率和交替帧时；路线包含起步、过道转弯、入窝的垫料边界。
	for frame_times in [[1.0 / 30], [1.0 / 60], [1.0 / 120], [1.0 / 30, 1.0 / 60, 0.04]]:
		game.social_left = 0
		game.social_cooldown = 1000
		game.wheel_owner = -1
		game.actors[0] = game._actor(-0.7, 10)
		var actor: Dictionary = game.actors[0]
		actor.pos = Vector2(1.0, 3.2)
		actor.dir = PI * 0.5
		game.actors[1].pos = Vector2(3.12, -1.62)
		game.actors[1].state = "睡"
		game.actors[1].left = 1000
		var prior_angle: float = actor.dir
		game._travel(actor, Vector2(-1.39, -1.70), "睡")
		check(absf(angle_difference(prior_angle, actor.dir)) < 0.001, "设置路线不能瞬间扭头")
		var max_turn := 0.0
		var max_step := 0.0
		var max_rise := 0.0
		var paw_clearance := INF
		var last_y := 0.0
		var elapsed := 0.0
		var frame := 0
		while elapsed < 30 and actor.state != "睡":
			var delta: float = frame_times[frame % frame_times.size()]
			var prior_pos: Vector2 = actor.pos
			prior_angle = actor.dir
			game._process(delta)
			max_turn = maxf(max_turn, absf(angle_difference(prior_angle, actor.dir)) / delta)
			max_step = maxf(max_step, actor.pos.distance_to(prior_pos) / delta)
			var current_y: float = game.habitat.pets[0].position.y
			if frame > 20:
				max_rise = maxf(max_rise, absf(current_y - last_y) / delta)
				if actor.state == "走":
					for paw in game.habitat.feet[0]:
						var p: Vector3 = paw.global_position
						paw_clearance = minf(paw_clearance, p.y - Meshes.bedding_height(p.x, p.z))
			last_y = current_y
			elapsed += delta
			frame += 1
		check(actor.state == "睡", "路线能完整走到小窝，不因缓动停滞")
		check(max_turn <= 3.21, "连续转弯每秒不超过平滑转向上限")
		check(max_step <= 1.46, "到达路点不瞬移补齐距离")
		check(max_rise < 0.9, "过垫料边界身体高度连续")
		check(paw_clearance > 0.01, "脚掌跟随地形而不陷入地面")
		print("步行采样：", frame_times, "，最大转速=", snappedf(max_turn, 0.001), "，最大移动速度=", snappedf(max_step, 0.001), "，最大升降速度=", snappedf(max_rise, 0.001))
		print("最小脚掌离地间隙：", snappedf(paw_clearance, 0.001))
	var largest_edge := 0.0
	for x in [-3.0, -1.4, 1.0, 3.12]:
		for i in range(100):
			var z: float = -2.1 + i * 0.01
			largest_edge = maxf(largest_edge, absf(Meshes.bedding_height(x, z + 0.01) - Meshes.bedding_height(x, z)))
	check(largest_edge < 0.025, "地形进入后排时没有台阶")
	_encounter(1.0 / 30)
	_encounter(1.0 / 60)
	if DisplayServer.get_name() != "headless":
		await _capture_walk()
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(game.care.path + suffix):
			DirAccess.remove_absolute(game.care.path + suffix)
	game.queue_free()
	await process_frame
	await process_frame
	print("步行平稳性测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _capture_walk() -> void:
	root.size = Vector2i(1024, 640)
	game.social_cooldown = 1000
	game.actors[0] = game._actor(0, 10)
	game.actors[0].pos = Vector2(-1.4, 2.8)
	game.actors[0].dir = PI / 2
	game._travel(game.actors[0], Vector2(2.8, 2.8), "嗅")
	# 只取真实渲染帧，保留完整笼子；六帧用于核对转弯和脚掌位置。
	game.actors[1].pos = Vector2(3.12, -1.62)
	game.actors[1].state = "跑"
	game.actors[1].dir = -PI / 2
	game.actors[1].facing = -PI / 2
	game.actors[1].left = 1000
	game.wheel_owner = 1
	var sheet := Image.create_empty(1536, 640, false, Image.FORMAT_RGBA8)
	var index := 0
	for frame in range(240):
		game._process(1.0 / 60)
		if frame % 40 == 39:
			await process_frame
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			shot.resize(512, 320, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(shot, Rect2i(0, 0, 512, 320), Vector2i((index % 3) * 512, (index / 3) * 320))
			index += 1
	check(sheet.save_png("res://dist/walk-1.5.1-frames.png") == OK, "保存步行连续渲染帧")

func _encounter(delta: float) -> void:
	game.social_cooldown = 1000
	game.social_left = 0
	var goals := [Vector2(2.5, 2.5), Vector2(-2.5, 2.5)]
	var arrived := [false, false]
	for i in range(2):
		game.actors[i] = game._actor(0, 10)
		game.actors[i].pos = goals[1-i]
		game.actors[i].dir = PI / 2 if i == 0 else -PI / 2
		game._travel(game.actors[i], goals[i], "嗅")
	var minimum := INF
	var max_step := 0.0
	for frame in range(ceili(35.0 / delta)):
		var before := [game.actors[0].pos, game.actors[1].pos]
		game._process(delta)
		minimum = minf(minimum, game.actors[0].pos.distance_to(game.actors[1].pos))
		for i in range(2):
			max_step = maxf(max_step, game.actors[i].pos.distance_to(before[i]) / delta)
			if game.actors[i].state == "嗅":
				arrived[i] = true
				game.actors[i].left = 1000
		if arrived[0] and arrived[1]:
			break
	check(arrived[0] and arrived[1], "迎面避让后两只都能到达目的地")
	check(minimum >= 1.665, "平滑避让仍保持身体间距")
	check(max_step < 1.65, "碰撞修正不会造成明显弹开")
	print("相遇采样：", delta, "，最小间距=", snappedf(minimum, 0.001), "，最大移动速度=", snappedf(max_step, 0.001))
