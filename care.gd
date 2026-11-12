extends RefCounted

const HOUR := 3600
const GRACE := 72 * HOUR
const BEDDING_TIME := 48 * HOUR
const WATER := [24 * HOUR, 30 * HOUR]
const FOOD := [36 * HOUR, 42 * HOUR]
const NAMES := ["肥嘟嘟", "好可爱"]
const VERSION := 1

var path: String
var now := 0
var bedding_at := 0
var pets: Array = []
var album: Array = []
var tutorial_seen := false
var sound := true
var droppings: Array = []

func _init(save_path: String = "user://hamsters.json") -> void:
	path = save_path

func load_or_start(wall_time: int) -> bool:
	# 临时档已写完、主档还没替换时，也能找回刚刚完成的照料。
	for suffix in [".tmp", "", ".bak"]:
		var candidate: String = path + suffix
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
			return true
	now = wall_time
	bedding_at = now
	pets = [_new_pet(), _new_pet()]
	return false

func _read(candidate: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(candidate)) == OK else null

func _valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != VERSION:
		return false
	if not _time_value(data.get("now")) or not _time_value(data.get("bedding_at"), data.now):
		return false
	if not data.get("pets") is Array or data.pets.size() != 2 or not data.get("album") is Array:
		return false
	for pet in data.pets:
		if not pet is Dictionary:
			return false
		for key in ["food_at", "water_at", "death_at"]:
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
		for axis in ["x", "z"]:
			var value: Variant = item.get(axis)
			if not (value is int or value is float) or not is_finite(float(value)) or absf(value) > 10:
				return false
	return data.get("tutorial_seen") is bool and data.get("sound") is bool

func _time_value(value: Variant, maximum: float = 9e15) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and floor(value) == value

func _new_pet() -> Dictionary:
	return {"food_at": now, "water_at": now, "death_at": 0}

func alive(index: int) -> bool:
	return pets[index].death_at == 0

func remaining(index: int, kind: String) -> int:
	var duration: int = FOOD[index] if kind == "food" else WATER[index]
	return int(pets[index][kind + "_at"]) + duration - now

func settle(wall_time: int) -> Array[int]:
	# 存档的时钟只向前走，重复恢复或设备时钟回拨不会退回进度。
	now = maxi(now, wall_time)
	var departures: Array[int] = []
	for index in range(pets.size()):
		if not alive(index):
			continue
		var limit := now + mini(remaining(index, "food"), remaining(index, "water")) + GRACE
		if now >= limit:
			pets[index].death_at = limit
			album.append({"pet": index, "at": limit})
			departures.append(index)
	return departures

func refill(kind: String) -> void:
	for index in range(pets.size()):
		if alive(index):
			pets[index][kind + "_at"] = now

func replace_bedding() -> void:
	bedding_at = now
	droppings.clear()

func add_dropping(point: Vector2) -> void:
	if droppings.size() >= 80:
		droppings.pop_front()
	droppings.append({"x": point.x, "z": point.y})

func adopt(index: int) -> bool:
	if alive(index):
		return false
	pets[index] = _new_pet()
	return true

func save() -> bool:
	var data := {
		"version": VERSION, "now": now, "bedding_at": bedding_at,
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
