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
		if d < best_d:
			best_d = d
			best = b
	for s in _group("sites"):
		if not is_instance_valid(s):
			continue
		var d := position.distance_to(s.position)
		if d < best_d:
			best_d = d
			best = s
	return best

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
