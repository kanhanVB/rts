extends Unit
class_name Goo
## Goofy Goo 的小怪：朝玩家建筑推进，单位贴脸才咬，被打了必还手。

var attack_range: float = 28.0    # 必须 > 单位分离距离(约23)，否则永远咬不到人
var attack_damage: float = 7.0
var attack_cooldown: float = 1.0
var _cd: float = 0.0
var _scan_t := 0.0                      # 距下次重新索敌的倒计时
var _cached_target: Node2D = null       # 上次扫描到的目标
var _repath_cd := 0.0                   # 重算路径的冷却
var _path_goal := Vector2(-9999, -9999)  # 上次寻路时的目标位置

const HUNT_RADIUS := 70.0    # 贴脸（70px 内）才咬单位；建筑才是行军目标，不计距离
## 波次刷出来的 Goo 沿土路行军（王国保卫战式）：只有路边 LANE_AGGRO 内的建筑/工地会被盯上，
## 走到路尽头（基地门口）才退回"找最近建筑"。手动放出来的（测试里）照旧直奔最近建筑。
const LANE_AGGRO := 150.0
var lane := false
var _lane: Array = []
var _lane_idx := 0
var _lane_fighting := false
var _lane_best := INF
var _lane_stall := 0.0

func start_lane(points: Array) -> void:
	if points.size() < 2:
		return
	var off := Vector2(0, randf_range(-14.0, 14.0))
	_lane.clear()
	for i in range(points.size() - 1, -1, -1):    # 道路数据从基地端到巢穴端，Goo 反着走
		var p: Vector2 = points[i] + off
		# 路的起点压在巢穴脚下：那几个点根本走不到（会被建筑推开），跳过
		var blocked := false
		for b in _group("buildings"):
			if is_instance_valid(b) and b.team == 1 and p.distance_to(b.position) < b.size * 0.8:
				blocked = true
		if not blocked:
			_lane.append(p)
	lane = true
	_lane_idx = _nearest_lane_idx()

## 下一个该去的路点：离自己最近的那个，已经走过它一半就去下一个
func _nearest_lane_idx() -> int:
	var best := 0
	var bd := INF
	for i in _lane.size():
		var d := position.distance_to(_lane[i])
		if d < bd:
			bd = d
			best = i
	if best + 1 < _lane.size():
		var a: Vector2 = _lane[best]
		var b: Vector2 = _lane[best + 1]
		if (position - a).dot(b - a) > 0.0:
			best += 1
	return maxi(best, _lane_idx)

func _ready() -> void:
	team = 1        # 必须在 super() 之前设，进组用
	super()
	hp = 45.0
	max_hp = 45.0
	speed = 62.0
	radius = 11.0
	body_color = Color(0.55, 0.6, 0.34)
	display_name = "Goo"
	armor = 0.0
	atk = attack_damage
	atk_range = attack_range
	atk_cd = attack_cooldown

## 拉仇恨：被谁打了就还手谁，防止被远程单位白白放风筝
func take_damage(amount: float, from: Node2D = null) -> void:
	if from != null and from is Unit and from.team == 0:
		attack_target = from
	super(amount, from)

func _step(delta: float) -> void:
	_cd = max(0.0, _cd - delta)
	var t := _acquire_target()
	if t == null and lane:
		_follow_lane(delta)
		return
	_lane_fighting = t != null
	if t:
		var d := position.distance_to(t.position)
		var reach := attack_range * _terrain_range_factor()
		if t is Building:
			reach += t.size * 0.5
		elif t is ConstructionSite:
			reach += t.size * 0.5
		if d <= reach:
			move_target = position
			if _cd <= 0.0:
				_cd = attack_cooldown
				t.take_damage(attack_damage)
				attack_fx_to(t.position)
			return
		# 目标挪动明显（>24px）且冷却到了才重算路径（绕开悬崖/深水）。
		# 以前追移动中的单位时 t.position 每帧都变，每只 Goo 每帧跑一次 A*
		move_target = t.position
		_repath_cd -= delta
		if _repath_cd <= 0.0 and t.position.distance_to(_path_goal) > 24.0:
			_repath_cd = 0.4
			_path_goal = t.position
			_path = _find_path(t.position)
			_path_idx = 0
	_move_toward(move_target, delta)

func _follow_lane(delta: float) -> void:
	if _lane_fighting:    # 打完一架回到路上：从最近的路点接着走
		_lane_fighting = false
		_lane_idx = _nearest_lane_idx()
		_lane_best = INF
		_lane_stall = 0.0
	if _lane_idx >= _lane.size():
		lane = false      # 走到头了：改成直奔最近建筑（就是基地）
		_scan_t = 0.0
		return
	var wp: Vector2 = _lane[_lane_idx]
	var dist := position.distance_to(wp)
	# 被挤住 4 秒没走近这个路点：直接换下一个，别原地发呆
	if dist < _lane_best - 2.0:
		_lane_best = dist
		_lane_stall = 0.0
	else:
		_lane_stall += delta
	if dist < 26.0 or _lane_stall > 4.0:
		_lane_idx += 1
		_lane_best = INF
		_lane_stall = 0.0
	_path = PackedVector2Array()
	move_target = wp
	_move_toward(wp, delta)

## 索敌优先级：还手目标 > 贴脸单位 > 最近的玩家建筑/工地（工地也会被啃！）
## 每 0.15 秒才重新扫描一次，期间沿用上次结果——以前每只 Goo 每帧
## 都把全部玩家单位 + 建筑 + 工地扫一遍，是混战掉帧的第二大来源
func _acquire_target() -> Node2D:
	if attack_target != null:
		if is_instance_valid(attack_target):
			return attack_target
		attack_target = null
	_scan_t -= get_process_delta_time()
	if _scan_t > 0.0 and _cached_target != null and is_instance_valid(_cached_target):
		return _cached_target
	_scan_t = 0.15
	_cached_target = _scan_target()
	return _cached_target

func _scan_target() -> Node2D:
	var best: Node2D = null
	var best_d := HUNT_RADIUS
	for u in _group("player_units"):
		if not is_instance_valid(u):
			continue
		var d := position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	if best:
		return best
	best = null
	best_d = INF
	for b in _group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.team != 0:
			continue
		var d := position.distance_to(b.position)
		if lane and d > LANE_AGGRO + b.size * 0.5:
			continue
		if d < best_d:
			best_d = d
			best = b
	for s in _group("sites"):
		if not is_instance_valid(s):
			continue
		var d := position.distance_to(s.position)
		if lane and d > LANE_AGGRO + s.size * 0.5:
			continue
		if d < best_d:
			best_d = d
			best = s
	return best

## ---------- 贴图版 ----------
func _art_key() -> String:
	return "goo"

## ---------- 绘制：KR 黏液怪：无脸纯剪影——堆叠圆山包 + 厚描边 + 暗面色带 + 高光 ----------
func _body_draw() -> void:
	var s := radius / 11.0
	# 走路 = 一跳一跳（带落地挤压），待机完全静止；咬人 = 往前扑
	var phase := sin(anim_t * 5.0)
	var hop := absf(phase) if moving else 0.0
	var lift := hop * 3.0 * s
	var squash := phase * 0.06 if moving else 0.0
	var lunge := attack_anim * 0.18
	var org := Vector2(lunge * radius, radius * 0.35 - lift)
	var body_scale := Vector2(1.0 + squash + lunge, 1.0 - squash - lunge)
	draw_set_transform(org, 0.0, body_scale)
	# 山包轮廓：主团 + 两个错位的圆，堆出黏液堆的剪影
	var lumps := [
		[Vector2.ZERO, radius],
		[Vector2(-radius * 0.38, -radius * 0.5), radius * 0.6],
		[Vector2(radius * 0.42, -radius * 0.38), radius * 0.48],
	]
	# 底缘黏液滴（走路时滴溜溜颤）
	var drips: Array = []
	for i in 3:
		var dy := radius * 0.75 + (sin(anim_t * 5.0 + i * 2.1) * 1.2 * s if moving else 0.0)
		drips.append([Vector2((i - 1) * radius * 0.5, dy), (2.8 - absf(i - 1) * 0.8) * s])
	# 先画整圈深色放大版 = 一体化厚描边（KR 的上色套路）
	for L in lumps:
		draw_circle(L[0], L[1] + 2.2, OUTLINE)
	for D in drips:
		draw_circle(D[0], D[1] + 1.4, OUTLINE)
	# 再叠体色
	for L in lumps:
		draw_circle(L[0], L[1], body_color)
	for D in drips:
		draw_circle(D[0], D[1], body_color)
	# 底部暗面色带（体积感）
	draw_set_transform(org + Vector2(0, radius * 0.62), 0.0, Vector2(body_scale.x * 0.78, body_scale.y * 0.36))
	draw_circle(Vector2.ZERO, radius * 0.95, Color(0.45, 0.49, 0.28))
	draw_set_transform(org, 0.0, body_scale)
	# 表面小气泡
	draw_circle(Vector2(radius * 0.45, -radius * 0.08), 2.0 * s, Color(0.6, 0.66, 0.4))
	draw_circle(Vector2(-radius * 0.18, -radius * 0.12), 1.4 * s, Color(0.6, 0.66, 0.4))
	# 左上高光
	draw_set_transform(org + Vector2(-radius * 0.42, -radius * 0.55), 0.0,
		Vector2(body_scale.x * 0.7, body_scale.y * 0.42))
	draw_circle(Vector2.ZERO, radius * 0.4, Color(0.68, 0.74, 0.46))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
