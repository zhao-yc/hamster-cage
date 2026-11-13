extends SceneTree

const Cage = preload("res://cage.tscn")
const Habitat = preload("res://habitat.gd")
const Care = preload("res://care.gd")
const CarePlay = preload("res://care_play.gd")
const PetVoice = preload("res://pet_voice.gd")
var game: Control
var failures := 0

class TestAR extends RefCounted:
	func is_supported() -> bool:
		return true

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
	for index in range(2):
		game.care.pets[index].food_at = game.care.now - roundi(Care.FOOD[index] * 0.5)
	game.care.water_until = game.care.now + 12 * Care.HOUR
	game.care.bedding_at = game.care.now - 36 * Care.HOUR
	game.care.add_dropping(Vector2(1.5, 2.0), 2)
	for index in range(3):
		var button := game.stage.get_child(index) as Button
		await _mouse(button.get_global_rect().get_center(), true)
		await _mouse(button.get_global_rect().get_center(), false)
		_check(is_instance_valid(game.care_play), "打开照料小游戏")
		await _play_care(index)
		_check(game.tutorial == index + 1, "照料引导步骤 %d" % (index + 1))
		_check_voice(["huihui-food", "baibai-water", "huihui-bedding"][index])
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
	_check_voice("huihui-greet")
	_check(game.audio.playing and _is_greet_notice(0) and game.notice.contains("日龄"), "点击后随机叫川川并显示台词和日龄")
	await create_timer(0.25).timeout
	var before_repeat: float = game.audio.get_playback_position()
	await _mouse(point, true)
	await _mouse(point, false)
	_check(before_repeat > 0.1 and game.audio.get_playback_position() >= before_repeat, "连点时不重播当前句")
	var white_point: Vector2 = game.habitat.camera.unproject_position(game.habitat.pets[1].position + Vector3(0, 0.28, 0))
	await _mouse(white_point, true)
	await _mouse(white_point, false)
	_check_voice("baibai-wheel")
	await _mouse(point, true, MOUSE_BUTTON_RIGHT)
	_check(game.held == 0, "右键抱起肥嘟嘟")
	_check_voice("huihui-lift")
	await _mouse(point, false, MOUSE_BUTTON_RIGHT)
	_check(game.held == -1, "松开右键放下肥嘟嘟")
	_check_voice("huihui-drop")
	game.actors[0].state = "跑"
	game.actors[0].pos = Habitat.WHEEL_RUN
	game.wheel_owner = 0
	await create_timer(0.18).timeout
	_check(game.wheel_angle > 0, "滚轮旋转")

	game.care.pets[1].born_at -= 365 * Care.DAY
	game.ar = TestAR.new()
	var settings := game.gear as Button
	await _mouse(settings.get_global_rect().get_center(), true)
	await _mouse(settings.get_global_rect().get_center(), false)
	# 设置弹窗里的按钮由 VBoxContainer 延迟布局，下一帧再取中心坐标。
	await process_frame
	var age_label := game.modal_content.get_child(1) as Label
	_check(age_label.text == "肥嘟嘟 21 天大　·　好可爱 1 岁 21 天", "设置页分别显示幼崽和成年仓鼠的年龄")
	game.care.pets[0].born_at -= Care.DAY
	game._refresh()
	_check(age_label.text.begins_with("肥嘟嘟 22 天大"), "设置页打开时也会更新日龄")
	var footer := game.modal_content.get_child(-1) as Label
	_check(footer.position.y + footer.size.y <= game.modal_content.get_parent().size.y - game.modal_content.position.y - 14.0,
		"显示年龄和 AR 按钮后，设置内容仍在面板内")
	if DisplayServer.get_name() != "headless":
		await _snapshot(Vector2i(1024, 640), "settings-age-16x10")
		await _snapshot(Vector2i(1024, 768), "settings-age-4x3")
		root.size = Vector2i(1024, 640)
		await process_frame
		await process_frame
	var sound := game.modal_content.get_child(2) as Button
	var sound_point := sound.get_global_rect().get_center()
	await _mouse(sound_point, true)
	await _mouse(sound_point, false)
	_check(not game.care.sound and not game.audio.playing, "关闭声音立即停止配音")
	await process_frame
	var family := game.modal_content.get_child(4) as Button
	var family_point := family.get_global_rect().get_center()
	await _mouse(family_point, true)
	await _mouse(family_point, false)
	await process_frame
	_check(not family.has_focus(), "短按松开后不保留按钮的焦点边框")
	await _mouse(family_point, true)
	await create_timer(1.3).timeout
	await _mouse(family_point, false)
	_check(game.modal.visible and game.modal_content.get_child(0).text == "家长", "家长入口须长按")
	game._close_dialog()
	_check(game.size.x > 0 and game.stage.scale.x > 0, "布局可见")
	game.care.water_until = game.care.now + 5 * Care.HOUR
	_check(game._needs() == "水壶里的水快喝完了。", "水少时只显示一条共用水壶提示")
	game.care.water_until = game.care.now
	_check(game._needs() == "水壶没水了，先加水吧。", "水壶为空时只显示一条加水提示")
	for index in range(2):
		_check(game._activity_problem(index, "喝", index) == game._needs(), "两只都不能从空水壶喝水")
	game.care.refill("water")
	_check(game.care.water_fill() == 1.0 and not game._needs().contains("水壶"), "加水同时恢复水位并消除提示")
	await _check_water_levels()
	game.actors[1].pos = Vector2(1.3, 1.5)
	game.actors[1].state = "嗅"
	game.actors[1].left = 10.0
	await process_frame
	white_point = game.habitat.camera.unproject_position(game.habitat.pets[1].position + Vector3(0, 0.28, 0))
	await _mouse(white_point, true)
	await _mouse(white_point, false)
	_check(_is_greet_notice(1) and not game.audio.playing, "静音时点好可爱仍显示随机台词")

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

func _is_greet_notice(index: int) -> bool:
	for line in PetVoice.GREET_LINES[index]:
		if game.notice.begins_with("%s · %s" % [Care.NAMES[index], line[0]]):
			return true
	return false

func _check_water_levels() -> void:
	for remaining in [0, 2 * Care.HOUR, 12 * Care.HOUR, Care.WATER_DURATION]:
		game.care.water_until = game.care.now + remaining
		await process_frame
		var fill: float = game.care.water_fill()
		_check(game.habitat.water.visible == (fill > 0.0), "笼子里只在有水时显示液面")
		if fill > 0.0:
			_check(is_equal_approx(game.habitat.water.position.y, Habitat.WATER_BOTTOM + Habitat.WATER_HEIGHT * fill), "笼子液面按实际剩余水量升降")
		if remaining == 2 * Care.HOUR and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://dist/water-bottle-low.png")
		game._care_action(1)
		var play = game.care_play
		var opened: float = game.care.water_fill()
		var water_until: int = game.care.water_until
		_check(is_equal_approx(play.water_level(), opened), "加水小游戏初始液面和水壶余量一致")
		if remaining == 2 * Care.HOUR and DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://dist/water-minigame-low.png")
		play._press(CarePlay.CAP_HOME)
		play._drag(CarePlay.CAP_REST)
		_check(is_equal_approx(play.water_level(), opened), "开始倒旧水时液面不跳高")
		play._process(play.DRAIN_TIME * 0.5)
		_check(is_equal_approx(play.water_level(), opened * 0.5), "旧水从实际水位排空")
		game._cancel_care()
		_check(game.care.water_until == water_until, "取消加水不改变原水壶的存档余量")
		await process_frame

func _check_voice(clip: String) -> void:
	var stream: AudioStream = game.audio.stream
	var matches := stream is AudioStreamWAV and stream.resource_path.ends_with("/" + clip + ".wav")
	if clip.ends_with("-greet") and stream is AudioStreamWAV:
		var basename := stream.resource_path.get_file().trim_suffix(".wav")
		matches = basename == clip or basename.begins_with(clip + "-")
	_check(matches, "播放 " + clip)

func _mouse(point: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	var click := InputEventMouseButton.new()
	click.button_index = button
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
	var play = game.care_play
	await _care_snapshot(kind, "start")
	if kind == 0:
		_check(absf(play.initial_food_fill - 0.5) < 0.01, "食盆沿用实际余粮")
		await _mouse(CarePlay.TOOL_REST, true)
		await _drag(CarePlay.FOOD_BOWL)
		await _mouse(CarePlay.FOOD_BOWL, false)
		_check(play.food_served == 0 and play.grain_pour_left == 0.0, "空勺拖到食盆不会添粮")
		for scoop in range(CarePlay.SCOOPS):
			var touch := scoop > 0
			await _care_drag_input(CarePlay.TOOL_REST, touch, true)
			await _care_drag_input(CarePlay.FOOD_BAG, touch)
			await create_timer(CarePlay.SCOOP_TIME + 0.12).timeout
			_check(play.scoop_fill == 1.0, "停在粮袋中把勺子舀满")
			await _care_drag_input(CarePlay.FOOD_BOWL, touch)
			await create_timer(0.18).timeout
			_check(play.food_served == scoop and play.grain_pour_left == 0.0 and play.dragging, "满勺到食盆后等松手才倒粮")
			await _care_drag_input(CarePlay.FOOD_BOWL, touch, false)
			_check(play.grain_pour_left > 0.0, "松手后开始倒粮")
			if scoop == 0:
				await create_timer(0.18).timeout
				await _care_snapshot(kind, "pour")
			await create_timer(CarePlay.GRAIN_POUR_TIME + 0.08).timeout
			_check(play.food_served == scoop + 1, "倒完一勺后，碗里的粮食增加")
	elif kind == 1:
		var original_until: int = game.care.water_until
		await _care_drag_input(CarePlay.CAP_HOME, true, true)
		await _care_drag_input(CarePlay.CAP_HOME - Vector2(0, 75), true)
		_check(play.phase == CarePlay.WaterStep.OPEN, "瓶盖没到右边的圈时继续拖动")
		await _care_drag_input(CarePlay.CAP_REST, true)
		_check(play.phase == CarePlay.WaterStep.POUR, "瓶盖拖到右边的圈即打开")
		await _care_drag_input(CarePlay.CAP_REST, true, false)
		await create_timer(CarePlay.DRAIN_TIME + 0.12).timeout
		_check(play.water_level() == 0.0, "倒掉旧水后从空瓶开始")
		await _mouse(CarePlay.TOOL_REST, true)
		await _drag(CarePlay.POUR_POSITION)
		await create_timer(0.64).timeout
		await _care_snapshot(kind, "pour")
		await _drag(CarePlay.TOOL_REST)
		var paused: float = play.water_level()
		await create_timer(0.15).timeout
		_check(paused > 0.0 and paused < 1.0 and play.water_level() == paused, "壶嘴离开瓶口，水位暂停上涨")
		await _drag(CarePlay.POUR_POSITION)
		await create_timer(CarePlay.POUR_TIME + 0.15).timeout
		await _mouse(CarePlay.POUR_POSITION, false)
		_check(play.phase == CarePlay.WaterStep.CLOSE and game.care.water_until == original_until, "倒满后等盖好才保存")
		await _mouse(CarePlay.CAP_REST, true)
		await _drag(CarePlay.CAP_HOME)
		await _mouse(CarePlay.CAP_HOME, false)
	else:
		_check(play.pellets.size() >= 2, "托盘显示当前笼子的便便")
		for phase in range(2):
			# 铺垫料用触摸事件验证，清扫则走电脑鼠标路径。
			var touch := phase == CarePlay.BeddingStep.SPREAD
			if touch and DisplayServer.get_name() != "headless":
				root.size = Vector2i(1024, 768)
				await process_frame
				await process_frame
			await _care_drag_input(CarePlay.TOOL_REST, touch, true)
			for row in range(CarePlay.BEDDING_ROWS):
				var y := 248.5 + row * 61.0
				var from := Vector2(382 if row % 2 == 0 else 837, y)
				var to := Vector2(837 if row % 2 == 0 else 382, y)
				await _care_drag_input(from, touch)
				await _care_drag_input(to, touch)
				if row == 1:
					_check(play.covered.size() >= 14, "两次长划扫过路径上的木屑")
					await _care_snapshot(kind, "sweep-%d" % phase)
			await _care_drag_input(Vector2(382, 431.5), touch, false)
		_check(play.done_delay >= 0.0, "扫净后铺上新木屑才完成")
		root.size = Vector2i(1024, 640)
	await create_timer(0.8).timeout
	_check(not is_instance_valid(game.care_play), "完成照料小游戏 %d" % kind)

func _care_drag_input(at: Vector2, touch: bool, pressed: Variant = null) -> void:
	if not touch:
		if pressed == null:
			await _drag(at)
		else:
			await _mouse(at, pressed)
		return
	var play = game.care_play
	var ratio: float = play._scale()
	var screen: Vector2 = at * ratio + (play.size - CarePlay.DESIGN_SIZE * ratio) * 0.5
	if pressed == null:
		var motion := InputEventScreenDrag.new()
		motion.position = screen
		Input.parse_input_event(motion)
	else:
		var tap := InputEventScreenTouch.new()
		tap.position = screen
		tap.pressed = pressed
		Input.parse_input_event(tap)
	await process_frame

func _care_snapshot(kind: int, step: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://dist/care-detail-%d-%s.png" % [kind, step])

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("未通过：", label)
