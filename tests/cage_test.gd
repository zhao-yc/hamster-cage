extends SceneTree

const Cage = preload("res://cage.tscn")
const Habitat = preload("res://habitat.gd")
var game: Control
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = Cage.instantiate()
	game.care.path = "user://cage-test-%d.json" % OS.get_process_id()
	root.add_child(game)
	await process_frame
	# 首帧可能仍在编译材质和同步窗口尺寸，等实际绘制完成后再取按钮坐标。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await process_frame
	_check(game.tutorial == 0 and game.care.alive(0) and game.care.alive(1), "初次启动")
	for index in range(3):
		var button := game.stage.get_child(index) as Button
		await _mouse(button.get_global_rect().get_center(), true)
		await _mouse(button.get_global_rect().get_center(), false)
		_check(is_instance_valid(game.care_play), "打开照料小游戏")
		await _play_care(index)
		_check(game.tutorial == index + 1, "照料引导步骤 %d" % (index + 1))
	_check(game.tutorial == 3 and game.care.tutorial_seen, "照料按钮完成新手提示")
	# 点击回应测试固定为地面休息状态，不能保留自主选中的滚轮状态再强行移到地面。
	game.actors[0].pos = Vector2(-1.3, 1.5)
	game.actors[0].state = "嗅"
	game.actors[0].left = 10.0
	game.actors[1].pos = Habitat.WHEEL_RUN
	game.actors[1].state = "跑"
	game.actors[1].left = 10.0
	game.wheel_owner = 1
	await process_frame
	await process_frame
	var point: Vector2 = game.habitat.camera.unproject_position(game.habitat.pets[0].position + Vector3(0, 0.28, 0))
	await _mouse(point, true)
	await _mouse(point, false)
	_check(game.actors[0].state == "回应", "点击仓鼠")
	game.actors[0].state = "跑"
	game.actors[0].pos = Habitat.WHEEL_RUN
	game.wheel_owner = 0
	await create_timer(0.18).timeout
	_check(game.wheel_angle > 0, "滚轮旋转")

	var settings := game.gear as Button
	await _mouse(settings.get_global_rect().get_center(), true)
	await _mouse(settings.get_global_rect().get_center(), false)
	var family := game.modal_content.get_child(3) as Button
	var family_point := family.get_global_rect().get_center()
	await _mouse(family_point, true)
	await create_timer(1.3).timeout
	await _mouse(family_point, false)
	_check(game.modal.visible and game.modal_content.get_child(0).text == "家长", "家长入口须长按")
	game._close_dialog()
	_check(game.size.x > 0 and game.stage.scale.x > 0, "布局可见")

	if DisplayServer.get_name() != "headless":
		game.notice_left = 0.0
		game.actors[0].pos = Vector2(0.25, 2.55)
		game.actors[0].state = "嗅"
		game.actors[0].dir = 0.48
		game.actors[0].facing = 0.48
		game.actors[0].left = 20.0
		game.actors[1].pos = Habitat.WHEEL_RUN
		game.actors[1].state = "跑"
		game.actors[1].dir = -PI / 2
		game.actors[1].facing = -PI / 2
		game.actors[1].left = 20.0
		game.wheel_owner = 1
		await process_frame
		await _snapshot(Vector2i(1024, 640), "16x10")
		await _snapshot(Vector2i(1024, 768), "4x3")
	game.set_process(false)
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(game.care.path + suffix):
			DirAccess.remove_absolute(game.care.path + suffix)
	print("笼子交互测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _mouse(point: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = point
	click.global_position = point
	Input.parse_input_event(click)
	await process_frame

func _snapshot(dimensions: Vector2i, label: String) -> void:
	root.size = dimensions
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://dist/cage-1.5.1-" + label + ".png") == OK, "截图 " + label)

func _drag(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	await process_frame

func _play_care(kind: int) -> void:
	if not is_instance_valid(game.care_play):
		return
	if kind == 0:
		for repeat in range(3):
			await _mouse(Vector2(220, 390), true)
			await _drag(Vector2(670, 370))
			await _mouse(Vector2(670, 370), false)
	elif kind == 1:
		await _mouse(Vector2(670, 235), true)
		await _drag(Vector2(670, 160))
		await _mouse(Vector2(670, 160), false)
		await create_timer(0.85).timeout
		await _mouse(Vector2(220, 390), true)
		await _drag(Vector2(610, 260))
		await create_timer(2.15).timeout
		await _mouse(Vector2(610, 260), false)
	else:
		for phase in range(2):
			await _mouse(Vector2(220, 390), true)
			for row in range(2):
				for col in range(4):
					await _drag(Vector2(410 + col * 120, 270 + row * 125))
			await _mouse(Vector2(770, 395), false)
	await create_timer(0.8).timeout
	_check(not is_instance_valid(game.care_play), "完成照料小游戏 %d" % kind)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("未通过：", label)
