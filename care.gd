extends RefCounted

const Rhythm = preload("res://hamster_rhythm.gd")
const HOUR := 3600
const DAY := 24 * HOUR
const WEAN_AGE := 21 * DAY
const ADULT_AGE := 84 * DAY
const GROWTH_TIME := ADULT_AGE - WEAN_AGE
const BABY_SCALE := 0.57
const GROWTH_CURVE := [Vector2(21, BABY_SCALE), Vector2(28, 0.68), Vector2(42, 0.82), Vector2(63, 0.93), Vector2(84, 1.0)]
const VISIT_KEYS := {"吃": "ate_at", "喝": "drank_at", "跑": "ran_at"}
const GRACE := 72 * HOUR
const BEDDING_TIME := 48 * HOUR
const WATER_DURATION := DAY
const LEGACY_WATER := [24 * HOUR, 30 * HOUR]
const FOOD := [36 * HOUR, 42 * HOUR]
const NAMES := ["肥嘟嘟", "好可爱"]
const VERSION := 3
const SAVE_PATH := "user://hamsters.json"

var path: String
var now := 0
var bedding_at := 0
var water_until := 0
var pets: Array = []
var album: Array = []
var tutorial_seen := false
var sound := true
var droppings: Array = []

func _init(save_path: String = SAVE_PATH) -> void:
	path = save_path

func load_or_start(wall_time: int) -> bool:
	if _load_save(path):
		return true
	if path == SAVE_PATH and OS.has_feature("pc"):
		# 桌面端的默认用户目录随项目名变更。读到旧进度后，下次保存写入新目录。
		var parent := ProjectSettings.globalize_path("user://").trim_suffix("/").get_base_dir()
		if _load_save(parent.path_join("灰灰和白白/hamsters.json")):
			return true
	now = wall_time
	bedding_at = now
	water_until = now + WATER_DURATION
	pets = [_new_pet(0), _new_pet(1)]
	return false

func _load_save(save_path: String) -> bool:
	# 临时档已写完、主档还没替换时，也能找回刚刚完成的照料。
	for suffix in [".tmp", "", ".bak"]:
		var candidate: String = save_path + suffix
		if not FileAccess.file_exists(candidate):
			continue
		var data: Variant = _read(candidate)
		if _valid(data):
			now = int(data.now)
			bedding_at = int(data.bedding_at)
			pets = data.pets
			album = data.album
			tutorial_seen = data.tutorial_seen
			sound = data.sound
			droppings = data.get("droppings", [])
			if data.version == 1:
				_migrate_life()
			if data.version < VERSION:
				_migrate_water()
			else:
				water_until = int(data.water_until)
			return true
	return false

func _read(candidate: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(candidate)) == OK else null

func _valid(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	# JSON 读出的版本号可能是浮点数，逐一比较数值以兼容旧档。
	var version: Variant = data.get("version")
	if not _time_value(version, VERSION) or version < 1:
		return false
	if not _time_value(data.get("now")) or not _time_value(data.get("bedding_at"), data.now):
		return false
	if not data.get("pets") is Array or data.pets.size() != 2 or not data.get("album") is Array:
		return false
	if version == VERSION and not _time_value(data.get("water_until"), data.now + WATER_DURATION):
		return false
	for pet in data.pets:
		if not pet is Dictionary:
			return false
		for key in ["food_at", "death_at"]:
			if not _time_value(pet.get(key), data.now):
				return false
		var last_alive: int = int(pet.death_at) if pet.death_at > 0 else int(data.now)
		if pet.has("born_at") and not _time_value(pet.born_at, last_alive):
			return false
		if version < VERSION and not _time_value(pet.get("water_at"), data.now):
			return false
		if version == VERSION and not _time_value(pet.get("joined_at"), last_alive):
			return false
		if version >= 2:
			if not _time_value(pet.get("born_at"), last_alive) or not _time_value(pet.get("natural_at")):
				return false
			if pet.natural_at <= pet.born_at:
				return false
			for key in ["ate_at", "drank_at", "ran_at", "waste_at"]:
				if not _time_value(pet.get(key), data.now):
					return false
	for record in data.album:
		if not record is Dictionary or not _time_value(record.get("pet"), 1):
			return false
		if not _time_value(record.get("at"), data.now):
			return false
	var waste: Variant = data.get("droppings", [])
	if not waste is Array or waste.size() > 80:
		return false
	for item in waste:
		if not item is Dictionary:
			return false
		if item.has("count") and (not _time_value(item.count, 3) or item.count < 1):
			return false
		for axis in ["x", "z"]:
			var value: Variant = item.get(axis)
			if not (value is int or value is float) or not is_finite(float(value)) or absf(value) > 10:
				return false
	return data.get("tutorial_seen") is bool and data.get("sound") is bool

func _time_value(value: Variant, maximum: float = 9e15) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and floor(value) == value

func _new_pet(index: int) -> Dictionary:
	var pet := {"food_at": now, "joined_at": now, "death_at": 0, "born_at": maxi(0, now - WEAN_AGE)}
	_init_rhythm(pet, index)
	return pet

func _init_rhythm(pet: Dictionary, index: int) -> void:
	# 约 2～3 年的自然寿命只在创建或迁移时确定，重开不会重抽。
	@warning_ignore("integer_division")
	var birth_day: int = int(pet.born_at) / DAY
	pet.natural_at = int(pet.born_at) + (730 + posmod(birth_day * 37 + index * 173, 366)) * DAY
	pet.ate_at = 0
	pet.drank_at = 0
	pet.ran_at = 0
	pet.waste_at = now

func _migrate_life() -> void:
	# 旧 born_at 记录的是到家时间。把旧体型映射为新的日龄，避免已长大的仓鼠突然变小。
	for index in range(pets.size()):
		var pet: Dictionary = pets[index]
		var last_alive: int = int(pet.death_at) if pet.death_at > 0 else now
		var age := ADULT_AGE
		if pet.has("born_at"):
			var elapsed := last_alive - int(pet.born_at)
			if elapsed >= 7 * DAY:
				age += elapsed - 7 * DAY
			else:
				var old_size := lerpf(BABY_SCALE, 1.0, clampf(float(elapsed) / (7 * DAY), 0.0, 1.0))
				for i in range(1, GROWTH_CURVE.size()):
					var from: Vector2 = GROWTH_CURVE[i - 1]
					var to: Vector2 = GROWTH_CURVE[i]
					if old_size <= to.y:
						age = roundi(lerpf(from.x, to.x, inverse_lerp(from.y, to.y, old_size)) * DAY)
						break
		pet.born_at = maxi(0, last_alive - age)
		_init_rhythm(pet, index)

func _migrate_water() -> void:
	# 延续旧档显示的水位。如果水壶已空，从旧水位实际归零的时间接着计时。
	var fill := 0.0
	var residents := 0
	var last_empty := 0
	for index in range(pets.size()):
		var pet: Dictionary = pets[index]
		var capacity: int = LEGACY_WATER[index]
		var empty_at := int(pet.water_at) + capacity
		if alive(index):
			fill += clampf(float(empty_at - now) / capacity, 0.0, 1.0)
			residents += 1
			last_empty = maxi(last_empty, empty_at)
		pet.erase("water_at")
		pet.joined_at = 0
	water_until = now + roundi(WATER_DURATION * fill / residents) if fill > 0.0 else last_empty

func age_seconds(index: int) -> int:
	var pet: Dictionary = pets[index]
	var last_alive: int = int(pet.death_at) if pet.death_at > 0 else now
	return last_alive - int(pet.get("born_at", last_alive - ADULT_AGE))

func growth_scale(index: int) -> float:
	var days := float(age_seconds(index)) / DAY
	for i in range(1, GROWTH_CURVE.size()):
		var from: Vector2 = GROWTH_CURVE[i - 1]
		var to: Vector2 = GROWTH_CURVE[i]
		if days <= to.x:
			return lerpf(from.y, to.y, clampf(inverse_lerp(from.x, to.x, days), 0.0, 1.0))
	return 1.0

func age_days(index: int) -> int:
	@warning_ignore("integer_division")
	return age_seconds(index) / DAY

func senior(index: int) -> float:
	return smoothstep(540.0, 760.0, float(age_seconds(index)) / DAY)

func last_visit(index: int, task: String) -> int:
	return int(pets[index][VISIT_KEYS[task]])

func record_visit(index: int, task: String) -> void:
	pets[index][VISIT_KEYS[task]] = now

func alive(index: int) -> bool:
	return pets[index].death_at == 0

func remaining(index: int, kind: String) -> int:
	return int(pets[index].food_at) + FOOD[index] - now if kind == "food" else water_remaining()

func water_remaining() -> int:
	return water_until - now

func water_fill() -> float:
	return clampf(float(water_remaining()) / WATER_DURATION, 0.0, 1.0)

func settle(wall_time: int) -> Array[int]:
	# 存档的时钟只向前走，重复恢复或设备时钟回拨不会退回进度。
	var previous := now
	now = maxi(now, wall_time)
	var departures: Array[int] = []
	for index in range(pets.size()):
		if not alive(index):
			continue
		var natural_at: int = int(pets[index].natural_at)
		# 领养时如果水壶已空，新来的仓鼠从入住开始计算缺水时间。
		var dry_since := maxi(water_until, int(pets[index].joined_at))
		var care_limit := mini(now + remaining(index, "food"), dry_since) + GRACE
		var limit := mini(natural_at, care_limit)
		if now >= limit:
			pets[index].death_at = limit
			var cause := "age" if limit == natural_at else "care"
			pets[index].death_cause = cause
			album.append({"pet": index, "at": limit, "cause": cause})
			departures.append(index)
	if now - previous > 120:
		_settle_offline_waste(previous)
	return departures

func pending_waste(index: int) -> int:
	var time := Rhythm.last_waste(now, index)
	if not alive(index) or time <= maxi(bedding_at, int(pets[index].waste_at)) or remaining(index, "food") <= 0:
		return -1
	return time

func leave_waste(index: int, time: int, point: Vector2) -> void:
	pets[index].waste_at = time
	add_dropping(point, Rhythm.waste_count(time, index))

func _settle_offline_waste(previous: int) -> void:
	# 只补上离线期间遗漏的点位，补算有上限，换过垫料的旧点位不回来。
	var start := maxi(maxi(previous, bedding_at), now - 3 * DAY)
	for block in range(Rhythm.waste_block(start), Rhythm.waste_block(now) + 1):
		for index in range(pets.size()):
			var pet: Dictionary = pets[index]
			var time := Rhythm.waste_at(block, index)
			if time <= maxi(start, int(pet.waste_at)) or time > now:
				continue
			if (pet.death_at > 0 and time >= int(pet.death_at)) or time > int(pet.food_at) + FOOD[index]:
				continue
			leave_waste(index, time, Rhythm.toilet_point(time, index))

func refill(kind: String) -> void:
	if kind == "water":
		water_until = now + WATER_DURATION
		return
	for index in range(pets.size()):
		if alive(index):
			pets[index].food_at = now

func replace_bedding() -> void:
	bedding_at = now
	droppings.clear()

func add_dropping(point: Vector2, count: int = 3) -> void:
	if droppings.size() >= 80:
		droppings.pop_front()
	droppings.append({"x": point.x, "z": point.y, "count": count})

func adopt(index: int) -> bool:
	if alive(index):
		return false
	pets[index] = _new_pet(index)
	return true

func save() -> bool:
	var data := {
		"version": VERSION, "now": now, "bedding_at": bedding_at,
		"water_until": water_until,
		"pets": pets, "album": album, "tutorial_seen": tutorial_seen, "sound": sound,
		"droppings": droppings
	}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return false
	# 只用可读的主档更新备份，避免损坏的主档覆盖最后一个好档。
	if FileAccess.file_exists(path):
		if _valid(_read(path)):
			if DirAccess.copy_absolute(path, path + ".bak.tmp") != OK:
				return false
			if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
				return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
