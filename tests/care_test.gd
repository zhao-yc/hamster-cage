extends SceneTree

const Care = preload("res://care.gd")
const H := Care.HOUR
const START := 1700000000
var failures := 0

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("未通过：", label)

func _initialize() -> void:
	var folder := "user://test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	check(DirAccess.make_dir_recursive_absolute(folder) == OK, "创建隔离存档目录")
	var file := folder + "/care.json"
	var care := Care.new(file)
	check(not care.load_or_start(START), "新游戏")
	check(care.water_fill() == 1.0 and care.remaining(0, "water") == care.remaining(1, "water"), "两只共用满水壶")
	check(care.save(), "首次存档")
	care.settle(START + 18 * H)
	check(care.water_fill() == 0.25, "共用水壶离线消耗到四分之一")
	care.settle(START + 24 * H)
	check(care.water_remaining() == 0 and care.alive(0) and care.alive(1), "两只同时遇到空水壶，并进入宽限期")
	care.settle(START + 90 * H)
	care.refill("water")
	care.refill("food")
	care.replace_bedding()
	check(care.save(), "宽限期内补给并存档")
	var restored := Care.new(file)
	check(restored.load_or_start(START + 96 * H), "重新打开")
	check(restored.settle(START + 96 * H).is_empty() and restored.bedding_at == START + 90 * H and restored.water_fill() == 0.75, "补水后重开，统一结算离线水位")
	restored.settle(START)
	check(restored.now == START + 96 * H, "时钟回拨")
	check(restored.settle(START + 186 * H) == [0, 1], "共用水壶空满宽限期时，两只同时离世")
	check(restored.settle(START + 186 * H).is_empty(), "重复结算不重复离世")
	check(restored.adopt(0) and not restored.adopt(0), "只能补领空位")
	check(restored.alive(0) and not restored.alive(1) and restored.album.size() == 2, "保留同伴与照片")
	check(restored.settle(restored.now + 1).is_empty() and restored.water_fill() == 0.0, "新来的仓鼠有完整宽限期，共用水壶仍为空")
	check(restored.save(), "领养存档")
	check(restored.save(), "更新备份")
	var corrupt := FileAccess.open(file, FileAccess.WRITE)
	corrupt.store_string("{")
	corrupt.close()
	var recovered := Care.new(file)
	check(recovered.load_or_start(START), "损坏后恢复备份")
	check(recovered.alive(0) and not recovered.alive(1) and recovered.album.size() == 2, "备份保留领养和纪念记录")
	check(recovered.save(), "恢复后可保存")
	check(DirAccess.copy_absolute(file, file + ".tmp") == OK, "模拟主档替换前退出")
	DirAccess.remove_absolute(file)
	check(Care.new(file).load_or_start(START), "恢复完整临时档")
	var food_case := Care.new(file + ".food")
	food_case.load_or_start(START)
	for hours in [24, 48, 72, 96]:
		food_case.settle(START + hours * H)
		food_case.refill("water")
	check(food_case.settle(START + 108 * H) == [0], "单独缺粮也会触发离世")
	check(food_case.settle(START + 114 * H) == [1], "共用水壶不改变独立的缺粮结算")
	_check_water_migration(file)
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(file + suffix):
			DirAccess.remove_absolute(file + suffix)
	DirAccess.remove_absolute(folder)
	print("照料测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _check_water_migration(file: String) -> void:
	var legacy := {
		"version": 2, "now": START + 24 * H, "bedding_at": START,
		"pets": [
			{"water_at": START, "food_at": START, "death_at": 0, "born_at": START - Care.WEAN_AGE,
				"natural_at": START + 750 * Care.DAY, "ate_at": 0, "drank_at": START, "ran_at": 0, "waste_at": START},
			{"water_at": START, "food_at": START, "death_at": 0, "born_at": START - Care.WEAN_AGE,
				"natural_at": START + 790 * Care.DAY, "ate_at": 0, "drank_at": 0, "ran_at": 0, "waste_at": START},
		],
		"album": [], "tutorial_seen": true, "sound": false,
	}
	var path := file + ".legacy"
	var migrated := Care.new(path)
	for elapsed in [24, 31]:
		legacy.now = START + elapsed * H
		var source := FileAccess.open(path, FileAccess.WRITE)
		source.store_string(JSON.stringify(legacy))
		source.close()
		check(migrated.load_or_start(legacy.now), "旧版独立水量存档可迁移")
		check(migrated.last_visit(0, "喝") == START, "迁移保留各自喝水作息")
		if elapsed == 24:
			check(is_equal_approx(migrated.water_fill(), 0.1), "迁移保留旧档里实际显示的水位")
		else:
			check(migrated.water_remaining() == -H, "迁移后从原水壶归零时间接着计算缺水")
	DirAccess.remove_absolute(path)
