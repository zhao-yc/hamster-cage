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
	check(care.remaining(0, "water") == 24 * H and care.remaining(1, "food") == 42 * H, "独立容量")
	check(care.save(), "首次存档")
	care.settle(START + 24 * H)
	check(care.remaining(0, "water") == 0 and care.alive(0), "水耗尽不立即离世")
	care.settle(START + 90 * H)
	care.refill("water")
	care.refill("food")
	care.replace_bedding()
	check(care.save(), "宽限期内补给并存档")
	var restored := Care.new(file)
	check(restored.load_or_start(START + 96 * H), "重新打开")
	check(restored.settle(START + 96 * H).is_empty() and restored.bedding_at == START + 90 * H, "跨天离线结算")
	restored.settle(START)
	check(restored.now == START + 96 * H, "时钟回拨")
	check(restored.settle(START + 186 * H) == [0], "灰灰在阈值时离世")
	check(restored.settle(START + 186 * H).is_empty(), "重复结算不重复离世")
	check(restored.settle(START + 192 * H) == [1], "白白独立离世")
	check(restored.adopt(0) and not restored.adopt(0), "只能补领空位")
	check(restored.alive(0) and not restored.alive(1) and restored.album.size() == 2, "保留同伴与照片")
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
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(file + suffix):
			DirAccess.remove_absolute(file + suffix)
	DirAccess.remove_absolute(folder)
	print("照料测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)
