extends RefCounted

const Habitat = preload("res://habitat.gd")
const RADII := [0.88, 0.79]
const ADULT_SPACING := 1.67
const ADULT_BOWL_CLEARANCE := Habitat.BOWL_RADIUS + 0.53 * Habitat.ADULT_SIZE[0]

static func spacing(actors: Array) -> float:
	return RADII[0] * float(actors[0].get("size_ratio", 1.0)) + RADII[1] * float(actors[1].get("size_ratio", 1.0))

static func bowl_clearance(index: int, size_ratio: float) -> float:
	# 身体转向时，最长的一侧也要留在陶碗外。
	return Habitat.BOWL_RADIUS + 0.53 * Habitat.ADULT_SIZE[index] * size_ratio

static func outside_bowl(point: Vector2, clearance: float) -> Vector2:
	var offset := point - Habitat.BOWL
	if offset.length_squared() >= clearance * clearance:
		return point
	var outward := offset.normalized() if offset.length_squared() > 0.000001 else Vector2.DOWN
	return Habitat.BOWL + outward * clearance

static func bowl_route(start: Vector2, waypoints: Array, clearance: float) -> Array[Vector2]:
	var route: Array[Vector2] = []
	var from := outside_bowl(start, clearance)
	for waypoint: Vector2 in waypoints:
		var to := outside_bowl(waypoint, clearance + 0.035)
		var nearest := Geometry2D.get_closest_point_to_segment(Habitat.BOWL, from, to)
		if nearest.distance_to(Habitat.BOWL) < clearance - 0.001:
			# 沿较短一侧绕行，给弧线之间的直线路段留出余量。
			var start_angle := (from - Habitat.BOWL).angle()
			var turn := angle_difference(start_angle, (to - Habitat.BOWL).angle())
			var steps := maxi(1, ceili(absf(turn) / (PI * 0.25)))
			for step in range(steps + 1):
				var angle := start_angle + turn * float(step) / steps
				route.append(Habitat.BOWL + Vector2.from_angle(angle) * (clearance + 0.20))
		route.append(to)
		from = to
	return route

static func constrain_bowl(actor: Dictionary) -> void:
	var position: Vector2 = actor.pos
	var safe := outside_bowl(position, float(actor.get("bowl_clearance", ADULT_BOWL_CLEARANCE)))
	if position.is_equal_approx(safe):
		return
	actor.pos = safe
	var outward := (safe - Habitat.BOWL).normalized()
	var velocity: Vector2 = actor.velocity
	actor.velocity -= outward * minf(0.0, velocity.dot(outward))

static func safe_floor(point: Vector2, bowl_margin: float) -> Vector2:
	var p := point.clamp(Vector2(-4.6, 0.65), Vector2(4.6, 4.15))
	if p.distance_to(Habitat.BOWL) < bowl_margin:
		p.y = maxf(p.y, Habitat.BOWL.y)
		p = outside_bowl(p, bowl_margin)
	return p

static func drop(point: Vector2, other: Vector2, other_alive: bool, at_entrance: bool, clearance: float, bowl_margin: float) -> Vector2:
	# 设施入口有预设落点，空地才使用笼子前方的范围限制。
	var candidate := outside_bowl(point, bowl_margin) if at_entrance else safe_floor(point, bowl_margin)
	if not other_alive or candidate.distance_to(other) >= clearance:
		return candidate
	var best := Vector2(0, 3.2)
	var distance := INF
	# 在可行走地面寻找最近空位，不能把抱起的仓鼠放入食盆、滚轮或同伴身体。
	for row in range(15):
		for col in range(31):
			var p := safe_floor(Vector2(-4.5 + col * 0.3, 0.65 + row * 0.25), bowl_margin)
			if p.distance_to(other) < clearance:
				continue
			if p.distance_squared_to(point) < distance:
				distance = p.distance_squared_to(point)
				best = p
	return best

static func face(actor: Dictionary, target: float, delta: float) -> void:
	# 路点和状态切换只改变目标朝向，限速及角加速度共同避免一帧内突然扭头。
	var difference := angle_difference(float(actor.dir), target)
	var desired := clampf(difference * 6.0, -3.0, 3.0)
	actor.turn_speed = move_toward(float(actor.turn_speed), desired, delta * 9.0)
	var turn: float = actor.turn_speed * delta
	if absf(turn) > absf(difference) and turn * difference >= 0:
		turn = difference
		actor.turn_speed = 0.0
	actor.dir = wrapf(float(actor.dir) + turn, -PI, PI)

static func advance(actor: Dictionary, other: Vector2, avoid: bool, index: int, delta: float, minimum: float = ADULT_SPACING) -> void:
	var from: Vector2 = actor.pos
	var distance := from.distance_to(actor.goal)
	if distance < 0.008 and actor.velocity.length() < 0.14:
		actor.pos = actor.goal
		actor.velocity = Vector2.ZERO
		return
	var direction: Vector2 = (actor.goal - from).normalized()
	var avoidance_range := minimum + 1.13
	if avoid and from.distance_to(other) < avoidance_range:
		var away := from - other
		if away.length_squared() < 0.01:
			away = Vector2(-1 if index == 0 else 1, 0)
		var proximity := 1.0 - smoothstep(minimum + 0.05, avoidance_range, away.length())
		var approaching := 1.0 - smoothstep(-0.8, 0.5, direction.dot(away.normalized()))
		var weight := proximity * approaching
		var tangent := Vector2(-away.y, away.x).normalized()
		# 避让随距离连续加入，两只保持相同绕行方向，不在阈值两侧反复切换。
		direction = (direction * (1.0 - weight * 0.7) + tangent * weight * 1.6 + away.normalized() * weight * 0.65).normalized()
	actor.facing = atan2(direction.x, direction.y)
	face(actor, actor.facing, delta)
	var alignment := Vector2(sin(actor.dir), cos(actor.dir)).dot(direction)
	var pace := sqrt(float(actor.get("size_ratio", 1.0))) * lerpf(1.0, 0.70, float(actor.get("senior", 0.0)))
	var speed := minf(1.2 * pace, distance * 5.0) * smoothstep(-0.2, 0.9, alignment)
	actor.velocity = actor.velocity.move_toward(direction * speed, delta * 3.0)
	var movement: Vector2 = actor.velocity * delta
	if movement.length() > distance and movement.normalized().dot((actor.goal - from).normalized()) > 0.98:
		movement = actor.goal - from
		actor.velocity = Vector2.ZERO
	actor.pos += movement

static func separate(actors: Array, alive: Array, held: int) -> void:
	if not alive[0] or not alive[1] or held >= 0:
		return
	var offset: Vector2 = actors[1].pos - actors[0].pos
	var distance := offset.length()
	var minimum := spacing(actors)
	if distance >= minimum:
		return
	var direction := offset / distance if distance > 0.001 else Vector2.RIGHT
	var shift := direction * (minimum - distance + 0.002)
	if actors[0].state in ["跑", "睡", "吃"]:
		actors[1].pos += shift
	elif actors[1].state in ["跑", "睡", "吃"]:
		actors[0].pos -= shift
	else:
		actors[0].pos -= shift * 0.5
		actors[1].pos += shift * 0.5
	# 分离后去掉继续挤向同伴的速度，避免下一帧又撞回同一位置。
	for i in range(2):
		var inward := direction if i == 0 else -direction
		var velocity: Vector2 = actors[i].velocity
		actors[i].velocity -= inward * maxf(0, velocity.dot(inward))
