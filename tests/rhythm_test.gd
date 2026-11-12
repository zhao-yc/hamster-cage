extends SceneTree

const Care = preload("res://care.gd")
const Rhythm = preload("res://hamster_rhythm.gd")
const START := 1700006400
var failures := 0

func _initialize() -> void:
	var offset := -posmod(START, Care.DAY)
	for index in range(2):
		for task in ["吃", "喝", "跑"]:
			var last := 0
			var total := 0
			var night := 0
			for minute in range(1440):
				var time := START + minute * 60
				if Rhythm.visit_due(task, time, offset, index, last):
					last = time
					total += 1
					if Rhythm.is_night(time, offset):
						night += 1
					_check(not Rhythm.visit_due(task, time + 30, offset, index, last), "同一时段不重复安排")
			_check(total == Rhythm.VISITS[task].size() and night > total / 2.0, "全天分次活动且偏向夜间 " + task)
			if task == "跑":
				_check(total == night, "自主跑轮安排在晚上")
	_check(not Rhythm.awake(START + 12 * Care.HOUR, offset, 0), "白天有长休息时段")
	_check(Rhythm.awake(START + 22 * Care.HOUR, offset, 0), "夜间更活跃")

	var path := "user://rhythm-test-%d.json" % OS.get_process_id()
	var care := Care.new(path)
	care.load_or_start(START)
	var initial_end: int = care.pets[0].natural_at
	_check(initial_end != int(care.pets[1].natural_at), "两只仓鼠的自然寿命独立")
	_check(initial_end - int(care.pets[0].born_at) >= 730 * Care.DAY and initial_end - int(care.pets[0].born_at) <= 1095 * Care.DAY, "自然寿命约两到三年")
	care.record_visit(0, "吃")
	care.settle(START + 12 * Care.HOUR)
	var groups := care.droppings.size()
	_check(groups > 4 and groups < 24, "离线半天留下间隔分布的小簇便便")
	for group in care.droppings:
		_check(group.count in [1, 2, 3], "单次显示少量颗粒")
	care.settle(care.now)
	_check(care.droppings.size() == groups, "重复结算不重复生成")
	_check(care.save(), "保存节奏与寿命")
	var reopened := Care.new(path)
	_check(reopened.load_or_start(care.now) and reopened.pets[0].natural_at == initial_end, "重开后寿命不重抽")
	_check(reopened.last_visit(0, "吃") == START and reopened.pending_waste(0) < 0, "重开保留上次进食与排便进度")
	reopened.replace_bedding()
	reopened.settle(reopened.now + 121)
	_check(reopened.droppings.size() <= 2, "换垫料后离线不会补回旧便便")
	var first := 0 if reopened.pets[0].natural_at < reopened.pets[1].natural_at else 1
	var natural_at: int = reopened.pets[first].natural_at
	# 放到自然寿命边界前，模拟一直有照顾的情况。
	reopened.now = natural_at - 1
	reopened.refill("food")
	reopened.refill("water")
	_check(reopened.settle(natural_at - 1).is_empty() and reopened.senior(first) > 0.0, "寿命到期前仍在，且进入老年")
	_check(reopened.settle(natural_at) == [first] and reopened.alive(1 - first), "照料充足也会自然老去")
	_check(reopened.album[-1].cause == "age" and reopened.album[-1].at == natural_at, "纪念记录保留自然离世时间")
	_check(reopened.settle(natural_at + 1).is_empty() and reopened.album.size() == 1, "自然离世只记录一次")
	_check(reopened.adopt(first) and reopened.age_days(first) == 21 and reopened.pets[first].natural_at > natural_at, "领养后重新开始一生")
	for suffix in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("作息与寿命测试完成，失败项：", failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("未通过：", message)
