extends RefCounted

const DAY := 86400
const HOUR := 3600
const WASTE_PERIOD := 85 * 60
const VISITS := {
	"吃": [70, 295, 590, 915, 1195, 1350],
	"喝": [25, 165, 305, 550, 965, 1150, 1275, 1385],
	"跑": [35, 205, 330, 1160, 1280, 1400],
}
const MIN_GAPS := {"吃": 65 * 60, "喝": 35 * 60, "跑": 55 * 60}

static func minute_of_day(now: int, offset: int) -> int:
	@warning_ignore("integer_division")
	return posmod(now + offset, DAY) / 60

static func is_night(now: int, offset: int) -> bool:
	var minute := minute_of_day(now, offset)
	return minute >= 18 * 60 + 30 or minute < 6 * 60 + 30

static func _jitter(seed: int, index: int, span: int) -> int:
	# 固定抖动可重算，重开游戏也不会重抽今天的时段。
	return posmod(((seed + (index + 1) * 3571) * 1103515245) ^ (seed * 7046029), span)

static func _recent_slot(slots: Array, now: int, offset: int, index: int, window: int) -> int:
	var local := now + offset
	@warning_ignore("integer_division")
	var day := local / DAY
	var latest := -1
	for date in [day - 1, day]:
		for minute in slots:
			var shift := _jitter(date * 1441 + int(minute), index, 41) - 20
			var time: int = date * DAY + (minute + shift) * 60 - offset
			if time <= now and now - time < window:
				latest = maxi(latest, time)
	return latest

static func visit_due(task: String, now: int, offset: int, index: int, last_visit: int) -> bool:
	# 参考叙利亚仓鼠的分次进食与夜间活动规律，窗口是游戏拟合值。
	var gap: int = MIN_GAPS[task]
	if now - last_visit < gap or (task == "跑" and not is_night(now, offset)):
		return false
	return _recent_slot(VISITS[task], now, offset, index, 15 * 60) > last_visit

static func awake(now: int, offset: int, index: int) -> bool:
	return is_night(now, offset) or _recent_slot([525, 765, 975], now, offset, index, 10 * 60) >= 0

static func waste_block(time: int) -> int:
	@warning_ignore("integer_division")
	return time / WASTE_PERIOD

static func waste_at(block: int, index: int) -> int:
	# 少量、非整点的排便机会贯穿昼夜，显示的是木屑中能看到的一小部分。
	return block * WASTE_PERIOD + (20 + _jitter(block, index, 43)) * 60

static func last_waste(now: int, index: int) -> int:
	var block := waste_block(now)
	var time := waste_at(block, index)
	return time if time <= now else waste_at(block - 1, index)

static func waste_count(time: int, index: int) -> int:
	return 1 + _jitter(waste_block(time) + 13, index, 3)

static func toilet_point(time: int, index: int) -> Vector2:
	var block := waste_block(time)
	var side := -1.0 if index == 0 else 1.0
	return Vector2(side * (3.05 + _jitter(block + 21, index, 27) * 0.047),
		2.45 + _jitter(block + 51, index, 31) * 0.040)
