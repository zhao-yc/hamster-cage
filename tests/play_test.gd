extends SceneTree

const Cage = preload("res://cage.tscn")
const CageScript = preload("res://cage.gd")
const Motion = preload("res://cage_motion.gd")
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
	game.care.path = "user://play-test-%d.json" % OS.get_process_id()
	root.add_child(game)
	game.set_process(false)
	# 加速模拟会在极短时间内触发大量提示，关闭测试存档的音效。
	game.care.sound = false
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	game.tutorial = 3
	game.care.tutorial_seen = true
	# 不依赖截图姿态：模拟十分钟自主活动、迎面相遇和强制同点重叠。
	game.actors[0].pos = Vector2(-1, 2.4)
	game.actors[1].pos = Vector2(1, 2.4)
	game._travel(game.actors[0], Vector2(3, 2.4), "嗅")
	game._travel(game.actors[1], Vector2(-3, 2.4), "嗅")
	var minimum := INF
	for frame in range(12000):
		game._process(0.05)
		minimum = minf(minimum, game.actors[0].pos.distance_to(game.actors[1].pos))
	check(minimum >= 1.665, "十分钟走动与嬉戏不相互穿模")
	game.actors[0].pos = Vector2(0, 2.4)
	game.actors[1].pos = Vector2(0, 2.4)
	Motion.separate(game.actors, [true, true], -1)
	check(game.actors[0].pos.distance_to(game.actors[1].pos) >= 1.67, "同点重叠可恢复")
	check(not game.habitat.displaced.is_empty(), "脚步实际移动地面木屑")
	check(game.habitat.flying_chips.size() <= 128, "脚步木屑池有上限")
	check(not game.care.droppings.is_empty() and game.care.droppings.size() <= 80, "排便与数量上限")
	game.care.save()
	var restored := Care.new(game.care.path)
	check(restored.load_or_start(game.care.now) and restored.droppings.size() == game.care.droppings.size(), "便便保存后重开保留数量")
	for i in range(mini(restored.droppings.size(), game.care.droppings.size())):
		var old: Dictionary = game.care.droppings[i]
		var loaded: Dictionary = restored.droppings[i]
		check(Vector2(old.x, old.z).distance_to(Vector2(loaded.x, loaded.z)) < 0.0001, "便便位置 JSON 往返精度")
	await _check_fight()
	_start_encounter()
	check(game.social_left > 0 and game.social_kind == CageScript.SocialKind.CHASE, "打架后下一轮仍可触发追逐")
	game._process(0.05)
	check(game.actors[0].state == "嬉戏" and game.actors[1].state == "嬉戏", "追逐仍有独立动作")
	game._end_social()
	_start_encounter()
	for frame in range(35):
		game._process(0.04)
	check(game.actors[0].state == "打架" and game.actors[1].state == "打架", "抱开前两只正在打架")
	var center: Vector2 = game.habitat.camera.unproject_position(game.habitat.pets[0].position + Vector3(0, 0.5, 0))
	_touch(0, center - Vector2(14, 0), true)
	check(game.held == -1, "单指不抱起")
	_touch(1, center + Vector2(14, 0), true)
	check(game.held == 0 and game.social_left == 0 and game.actors[1].state == "嗅", "双指抱起会打断打架")
	for frame in range(12):
		game._process(0.05)
	check(game.actors[0].lift > 1.1, "抱起离开地面")
	var target: Vector2 = game.habitat.camera.unproject_position(Vector3(2.5, 0.12, 3.2))
	for i in range(2):
		var motion := InputEventScreenDrag.new()
		motion.index = i
		motion.position = target + Vector2(-14 if i == 0 else 14, 0)
		game._input(motion)
	_touch(0, target, false)
	_touch(1, target, false)
	check(game.held == -1 and game.touches.is_empty(), "任一手指松开后安全放下并清理手势")
	check(game.actors[0].pos.distance_to(game.actors[1].pos) >= 1.75, "落点避开同伴")
	check(game.social_cooldown >= 90, "抱开后不立刻重新追逐")
	var old_food: int = game.care.pets[0].food_at
	game._care_action(0)
	game.care_play._press(Vector2(220, 390))
	game.care_play._drag(Vector2(670, 370))
	game._cancel_care()
	await process_frame
	check(game.care.pets[0].food_at == old_food, "半途取消不补满食物")
	var count: int = game.care.droppings.size()
	game._care_action(2)
	game._cancel_care()
	await process_frame
	check(game.care.droppings.size() == count, "取消清扫保留便便")
	game._care_action(0)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://dist/care-play-1.5.1.png")
	game._cancel_care()
	game._finish_care(2)
	check(game.care.droppings.is_empty() and game.habitat.displaced.is_empty(), "换垫料完成后清掉便便并恢复木屑")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(game.care.path + suffix):
			DirAccess.remove_absolute(game.care.path + suffix)
	# 等待关闭小游戏与场景的延迟释放，避免测试直接退出时遗留队列中的节点。
	game.queue_free()
	await process_frame
	await process_frame
	print("互动与碰撞测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _start_encounter() -> void:
	# 让两只在开阔处相遇，通过正常社交触发路径进入动作。
	for i in range(2):
		var actor: Dictionary = game.actors[i]
		actor.pos = Vector2(-0.9 if i == 0 else 0.9, 2.6)
		actor.dir = PI / 2 if i == 0 else -PI / 2
		actor.velocity = Vector2.ZERO
		actor.state = "嗅"
		actor.left = 10.0
		actor.poop_left = 60.0
	game.social_cooldown = 0
	game._process(0.02)

func _check_fight() -> void:
	game.social_kind = CageScript.SocialKind.CHASE
	_start_encounter()
	check(game.actors[0].state == "打架" and game.actors[1].state == "打架", "开阔处相遇能触发打架")
	var swatted := [false, false]
	var min_distance := INF
	for frame in range(103):
		game._process(0.04)
		min_distance = minf(min_distance, game.actors[0].pos.distance_to(game.actors[1].pos))
		if game.social_left <= 0:
			break
		for i in range(2):
			if game.actors[i].fight_swing > 0.8 and game.actors[1 - i].fight_swing < -0.8:
				swatted[i] = true
		if frame == 35:
			var front: Node3D = game.habitat.feet[0][3]
			var rear: Node3D = game.habitat.feet[0][2]
			check(front.global_position.y > rear.global_position.y + 0.3, "打架时抬起前爪、后脚撑地")
			if DisplayServer.get_name() != "headless":
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://dist/hamster-fight.png")
	check(swatted[0] and swatted[1], "两只交替挥爪和后仰")
	check(min_distance >= 1.665, "打架时仍保持身体间距")
	check(game.social_left == 0 and game.actors[0].state == "嗅" and game.actors[1].state == "嗅", "四秒后自行分开并恢复活动")
	check(game.social_cooldown > 0, "打架结束后进入冷却")

func _touch(index: int, at: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	game._input(event)
