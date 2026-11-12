extends SceneTree

const Cage = preload("res://cage.tscn")
const Care = preload("res://care.gd")
const Habitat = preload("res://habitat.gd")
const Motion = preload("res://cage_motion.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = Cage.instantiate()
	var path := "user://growth-test-%d.json" % OS.get_process_id()
	game.care.path = path
	root.add_child(game)
	game.set_process(false)
	game.care.sound = false
	game.social_cooldown = 1000
	for i in range(2):
		game.actors[i].pos = Vector2(-1.25 if i == 0 else 1.25, 3.0)
		game.actors[i].dir = 0.55 if i == 0 else -0.55
		game.actors[i].facing = game.actors[i].dir
		game.actors[i].left = 1000.0
	var home_at: int = game.care.now
	game._process(0.05)
	_check(game.care.age_days(0) == 21 and game.care.growth_scale(0) < 0.60, "新仓鼠以断奶幼崽开始")
	_check(game.care.save(), "保存幼崽成长起点")
	var reopened := Care.new(path)
	var after_two_days := home_at + 2 * Care.DAY
	_check(reopened.load_or_start(after_two_days), "重开读到原来的幼崽")
	reopened.settle(after_two_days)
	var offline_size := reopened.growth_scale(0)
	_check(reopened.alive(0) and reopened.age_days(0) == 23 and offline_size > Care.BABY_SCALE, "离线两天计入成长")
	reopened.settle(home_at)
	_check(is_equal_approx(reopened.growth_scale(0), offline_size), "时间回拨不会变小")
	var collage := Image.create_empty(1536, 320, false, Image.FORMAT_RGBA8)
	var screenshot_index := 0
	var previous_size := 0.0
	for day in range(64):
		game.care.settle(home_at + day * Care.DAY)
		game.care.refill("food")
		game.care.refill("water")
		game.care.replace_bedding()
		game._process(0.05)
		var ratio: float = game.care.growth_scale(0)
		_check(ratio > previous_size and game.care.alive(0), "第 %d 天比前一天长大" % (day + 1))
		previous_size = ratio
		for i in range(2):
			_check(is_equal_approx(game.habitat.pets[i].scale.x, Habitat.ADULT_SIZE[i] * ratio), "笼子里显示对应体型")
		if day in [0, 21, 63] and DisplayServer.get_name() != "headless":
			game.notice = ["3 周龄 · 幼崽", "6 周龄 · 成长中", "12 周龄 · 成年"][screenshot_index]
			game.notice_left = 4.0
			game.stage.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.convert(Image.FORMAT_RGBA8)
			frame.resize(512, 320, Image.INTERPOLATE_LANCZOS)
			collage.blit_rect(frame, Rect2i(0, 0, 512, 320), Vector2i(screenshot_index * 512, 0))
			screenshot_index += 1
	_check(is_equal_approx(game.care.growth_scale(0), 1.0) and game.care.age_days(0) == 84, "约十二周龄达到成年体型")
	game.care.pets[0].death_at = game.care.now
	_check(game.care.adopt(0), "领养新仓鼠")
	game._process(0.05)
	_check(is_equal_approx(game.care.growth_scale(0), Care.BABY_SCALE) and game.care.growth_scale(1) == 1.0, "领养只重置新仓鼠的成长")
	var mixed_spacing := Motion.spacing(game.actors)
	_check(mixed_spacing < Motion.ADULT_SPACING and mixed_spacing > 1.2, "幼崽与成年仓鼠按各自体型避让")
	_check(game.care.save(), "保存重新领养后的不同日龄")
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	legacy.version = 1
	for pet in legacy.pets:
		pet.water_at = game.care.now
	legacy.pets[0].born_at = game.care.now - 3 * Care.DAY
	legacy.pets[1].erase("born_at")
	var old_save := FileAccess.open(path, FileAccess.WRITE)
	old_save.store_string(JSON.stringify(legacy))
	old_save.close()
	_check(reopened.load_or_start(game.care.now), "迁移旧版成长存档")
	var old_scale := lerpf(Care.BABY_SCALE, 1.0, 3.0 / 7.0)
	_check(reopened.growth_scale(1) == 1.0 and absf(reopened.growth_scale(0) - old_scale) < 0.001, "迁移保留旧成年与成长中仓鼠体型")
	if screenshot_index == 3:
		_check(collage.save_png("res://dist/hamster-growth.png") == OK, "保存成长实机渲染对照")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	game.queue_free()
	await process_frame
	print("成长测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("未通过：", message)
