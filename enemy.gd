extends Unit
class_name Goo
## Goofy Goo 的小怪：朝玩家建筑推进，单位贴脸才咬，被打了必还手。
## 三个品种（etype）：普通 Goo / 窜窜（快、脆、一路冲基地）/ 岩壳（慢、厚、带甲、专拆箭塔）。
## 箭塔是塔防的主角：普通 Goo 和窜窜够不着塔上的弓手，从塔下走过只能挨射；岩壳会停下来拆塔，得派剑士去护。

const TYPES := {
	"goo": {"name": "Goo", "hp": 45.0, "speed": 62.0, "radius": 10.0, "dmg": 7.0, "cd": 1.0, "armor": 0.0,
		"siege": 1.0, "hunt": 70.0, "hop": 1.0, "color": Color(0.55, 0.6, 0.34),
		"tip": "沿路推进，啃路边的房子、咬挡路的人；够不着箭塔"},
	"runner": {"name": "窜窜", "hp": 24.0, "speed": 118.0, "radius": 8.0, "dmg": 5.0, "cd": 0.7, "armor": 0.0,
		"siege": 1.0, "hunt": 0.0, "hop": 1.9, "color": Color(0.5, 0.4, 0.75),
		"tip": "跑得飞快、血薄：路边什么都不理，一路冲基地；只有贴身挨打才还手"},
	"brute": {"name": "岩壳", "hp": 240.0, "speed": 36.0, "radius": 15.0, "dmg": 14.0, "cd": 1.5, "armor": 4.0,
		"siege": 2.5, "hunt": 45.0, "hop": 0.6, "color": Color(0.5, 0.44, 0.38),
		"tip": "又慢又厚，护甲 4（每下少吃 4 点）：专找箭塔拆，拆房伤害 ×2.5——派剑士去顶"},
}
var etype := "goo"
var siege := 1.0      # 打建筑 / 工地的伤害倍率
var hunt_r := 70.0    # 多近的玩家单位会被主动咬（窜窜 0 = 不理人）

## 按品种生成（add_child 之前调，_ready 里按 etype 套数值）
static func make(t: String) -> Goo:
	var g := Goo.new()
	g.etype = t if TYPES.has(t) else "goo"
	return g

var attack_range: float = 28.0    # 必须 > 单位分离距离(约23)，否则永远咬不到人
var attack_damage: float = 7.0
var attack_cooldown: float = 1.0
var _cd: float = 0.0
var _scan_t := 0.0                      # 距下次重新索敌的倒计时
var _cached_target: Node2D = null       # 上次扫描到的目标
var _repath_cd := 0.0                   # 重算路径的冷却
var _path_goal := Vector2(-9999, -9999)  # 上次寻路时的目标位置
var _chase_who: Node2D = null            # 正在追谁（换目标时重置下面的停滞统计）
var _chase_best := INF                   # 追这个目标以来最近的距（越小越近）
var _chase_stall := 0.0                  # 多久没能更近一步了

const HUNT_RADIUS := 70.0    # 普通 Goo：贴脸（70px 内）才咬单位；建筑才是行军目标，不计距离（各品种见 TYPES.hunt）
## 波次刷出来的 Goo 沿土路行军（王国保卫战式）：只有路边 LANE_AGGRO 内的建筑/工地会被盯上，
## 走到路尽头（基地门口）才退回"找最近建筑"。手动放出来的（测试里）照旧直奔最近建筑。
const LANE_AGGRO := 150.0
var lane := false
var _lane: Array = []
var _lane_idx := 0
var _lane_fighting := false
var _lane_best := INF
var _lane_stall := 0.0
var _lane_probe := 0.0          # 隔一会儿探一次"前方路还通不通"（土路被玩家挖断时用）
## 场上有没有被挖断的土路（main.cut_road_at / road_reclaim 维护）。
## 没人断过的时候这个探测一点用都没有，关掉能省下"每只怪每 0.35 秒一次密集采样"
static var lane_hazard := false

func start_lane(points: Array) -> void:
	if points.size() < 2:
		return
	var off := Vector2(0, randf_range(-14.0, 14.0))
	_lane.clear()
	for i in range(points.size() - 1, -1, -1):    # 道路数据从基地端到巢穴端，Goo 反着走
		var p: Vector2 = points[i] + off
		# 路的起点压在巢穴脚下、终点压在主城脚下：那几个点根本走不到（会被建筑推开），跳过
		# （不然窜窜走到主城门口，对着城里的路点一个个干等 4 秒才开始啃）
		var blocked := false
		for b in _group("buildings"):
			if is_instance_valid(b) and (b.team == 1 or b.kind == "base") and p.distance_to(b.position) < b.size * 0.8:
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
	var T: Dictionary = TYPES[etype]
	hp = T.hp
	max_hp = T.hp
	speed = T.speed
	radius = T.radius    # 贴图宽（Goo 约 38px），半径别太小，不然一群 Goo 叠成一坨
	body_color = T.color
	display_name = T.name
	armor = T.armor
	attack_damage = T.dmg
	attack_cooldown = T.cd
	attack_range = radius + 18.0    # 必须 > 分离距离（两者半径和 + 2），否则永远咬不到
	siege = T.siege
	hunt_r = T.hunt
	hop_rate = T.hop
	atk = attack_damage
	atk_range = attack_range
	atk_cd = attack_cooldown

## 拉仇恨：被谁打了就还手谁，防止被远程单位白白放风筝
func take_damage(amount: float, from: Node2D = null) -> void:
	if from != null and from is Unit and from.team == 0:
		if is_guard():
			# 守军：回窝路上不理人；没在回窝就还手，并喊全窝一起上（追得太远的不管）
			if not returning and from.position.distance_to(home) < GUARD_LEASH:
				attack_target = from
				_rally_pack(from)
		# 窜窜只还手贴身的（远处弓手放冷箭，它照样往基地冲）
		elif etype != "runner" or position.distance_to(from.position) < 60.0:
			attack_target = from
	super(amount, from)

## ---------- 据点守军（野怪式，据点见 camp.gd）----------
## 站在窝边不走土路；玩家的人进了警戒圈（离窝 GUARD_AGGRO）才扑上来，一只发现全窝一起上；
## 追出拴绳（离岗位 GUARD_LEASH）就掉头回窝，回窝路上不理人；没架打时慢慢回血、在岗位边挪两步
const GUARD_AGGRO := 190.0
const GUARD_LEASH := 400.0
const GUARD_REGEN := 0.06       # 没架打时每秒回最大血量的 6%
const RETURN_MAX := 9.0         # 回窝最多走这么久（被挤住也算到家）
var pack_center := Vector2.INF  # 守哪个窝（据点位置；窝拆了也认这个点）
var home := Vector2.INF         # 自己的岗位
var returning := false
var _return_t := 0.0
var _idle_t := 0.0
var _idle_spot := Vector2.INF

## 设成据点守军（add_child 之前调）
func guard(center: Vector2, post: Vector2) -> void:
	pack_center = center
	home = post
	_idle_spot = post
	lane = false

func is_guard() -> bool:
	return home != Vector2.INF

## 有人来犯：没在回窝、手上没架打的就扑过去（离窝太远的不追）
func alert(t: Node2D) -> void:
	if returning or t == null or not is_instance_valid(t) or t.position.distance_to(home) > GUARD_LEASH:
		return
	if attack_target == null or not is_instance_valid(attack_target):
		attack_target = t

## 喊同一个窝的守军一起上
func _rally_pack(t: Node2D) -> void:
	for e in _group("enemies"):
		if e != self and is_instance_valid(e) and e is Goo and e.pack_center == pack_center:
			e.alert(t)

func _regen(delta: float) -> void:
	if hp < max_hp:
		hp = minf(max_hp, hp + max_hp * GUARD_REGEN * delta)

## 追出拴绳 / 正在回窝：一路走回岗位、不理人。返回 true = 这一帧归它管
func _guard_busy(delta: float) -> bool:
	var dh := position.distance_to(home)
	if not returning and dh > GUARD_LEASH:
		returning = true
		_return_t = 0.0
		attack_target = null
		_cached_target = null
		_path_goal = home
		_path = _find_path(home)
		_path_idx = 0
	if not returning:
		return false
	_regen(delta)
	_return_t += delta
	if dh < 16.0 or _return_t > RETURN_MAX:
		returning = false
		_path = PackedVector2Array()
		move_target = position
		_idle_spot = home
		_scan_t = 0.0
		return false
	move_target = home
	_move_toward(home, delta)
	return true

## 没架打：回血；打完架离岗位远了就走回去（路上有人来照样打），到了在岗位边偶尔挪两步
func _guard_idle(delta: float) -> void:
	_regen(delta)
	if position.distance_to(home) > 40.0:
		_repath_cd -= delta
		# 追人留下的旧路径终点是那个人（多半已经死了）：作废，马上算回岗位的路；
		# 路走完了还没到（被挤开）隔一秒再算
		if _path_goal.distance_to(home) > 24.0 or (_repath_cd <= 0.0 and _path.is_empty()):
			_repath_cd = 1.0
			_path_goal = home
			_path = _find_path(home)
			_path_idx = 0
		move_target = home
		_move_toward(home, delta)
		return
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = randf_range(2.5, 5.0)
		_idle_spot = home + Vector2(randf_range(-16.0, 16.0), randf_range(-9.0, 9.0))
	if position.distance_to(_idle_spot) > 5.0:
		move_target = _idle_spot
		_move_toward(_idle_spot, delta)
	else:
		move_target = position

## 守军索敌：正在追的人没跑出拴绳就接着追；否则找进了警戒圈的玩家单位（离自己最近的），
## 没人再看窝边有没有玩家的工地/房子（平时窝边不让盖，这里兜底）。找到了就喊全窝
func _guard_scan() -> Node2D:
	var cur := _cached_target
	if cur != null and is_instance_valid(cur) and cur.get("dead") != true and cur.position.distance_to(home) < GUARD_LEASH:
		return cur
	var best: Node2D = null
	var best_d := INF
	for u in _group("player_units"):
		if not is_instance_valid(u) or u.position.distance_to(pack_center) > GUARD_AGGRO:
			continue
		var d := position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	if best == null:
		for grp in ["sites", "buildings"]:
			for b in _group(grp):
				if not is_instance_valid(b) or (grp == "buildings" and (b.team != 0 or (b.kind == "tower" and etype != "brute"))):
					continue
				if b.position.distance_to(pack_center) > GUARD_AGGRO + b.size * 0.5:
					continue
				var d := position.distance_to(b.position)
				if d < best_d:
					best_d = d
					best = b
	if best != null:
		_rally_pack(best)
	return best

## 品种说明（信息栏用）
func type_tip() -> String:
	return TYPES[etype].tip

func _step(delta: float) -> void:
	_cd = max(0.0, _cd - delta)
	if is_guard() and _guard_busy(delta):
		return
	var t := _acquire_target()
	if t == null and is_guard():
		_guard_idle(delta)
		return
	if t == null and lane:
		_follow_lane(delta)
		return
	_lane_fighting = t != null
	if t:
		if t != _chase_who:
			_chase_who = t
			_chase_best = INF
			_chase_stall = 0.0
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
				t.take_damage(attack_damage * (siege if (t is Building or t is ConstructionSite) else 1.0), self)    # 带上自己：玩家那边据此报警
				attack_fx_to(t.position)
			return
		# 追了 3 秒还没能离目标更近（撞在岸边来回顶、挤在缝里）：走一次脱困。
		# 光靠 unit.gd 那个"位置没挪动"判不出来——那种走一帧被推回来一帧的震荡，
		# 来回幅度能超过 8px 的门槛，起点每帧都被刷新，_stuck_t 永远攒不起来。
		# 这里直接盯"离目标有没有变近"，震荡再大也藏不住
		if d < _chase_best - 20.0:
			_chase_best = d
			_chase_stall = 0.0
		else:
			_chase_stall += delta
			if _chase_stall > 3.0:
				_chase_stall = 0.0
				_on_stuck()
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

## 卡住了（撞在岸边 / 挤在窄缝里顶不进去）：侧向挪半步换个角度，并作废旧路径。
## 基类那个 _on_stuck 只把 move_target 按回脚下，而 _step 下一帧又把它设回目标点——
## 追建筑时目标根本不动，272 行那条"目标挪了 24px 才重算"永远不成立，
## 于是 _path 一直是用同一个起点算的老路，撞上河/林子就只能顶着磨几分钟。
## 所以这里必须自己清 _path_goal / _repath_cd：让下一步无条件重算一条新路
func _on_stuck() -> void:
	if is_guard():
		move_target = position    # 守军在窝边小范围巡守，挪不远是常态，别折腾
		return
	var to_go: Vector2 = move_target - position
	move_target = position
	if to_go.length() < 40.0:
		return    # 目的地就在脚下（待命 / 正在咬）：不动是正常的
	var side := to_go.orthogonal().normalized()
	if side == Vector2.ZERO:
		side = Vector2.RIGHT
	position += side * radius    # 挪一个身位，脱离卡住的格子边缘
	_path = PackedVector2Array()
	_path_idx = 0
	_path_goal = Vector2(-9999, -9999)
	_repath_cd = 0.0
	_stuck_pos = position

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
		_path = PackedVector2Array()    # 换路点了：上一段算的绕行路作废
		_lane_probe = 0.0               # 新的一段要立刻探一次通不通
	# 玩家把土路挖断了（main.cut_road_at 在地形上刷壕沟）：前方直线过不去就别硬顶，
	# 自己算一条绕行路从林子里绕。每 0.35 秒才探一次——line_walkable 是密集采样，
	# 每帧每只怪都调太贵
	_lane_probe -= delta
	if lane_hazard and _path.is_empty() and _lane_probe <= 0.0:
		_lane_probe = 0.35
		var ter := Terrain.current
		if ter != null and not ter.line_walkable(position, wp):
			_path = _find_path(wp)
			_path_goal = wp
			_path_idx = 0
	move_target = wp
	_move_toward(wp, delta)

## 索敌优先级：还手目标 > 贴脸单位 > 最近的玩家建筑/工地（工地也会被啃！）
## 每 0.15 秒才重新扫描一次，期间沿用上次结果——以前每只 Goo 每帧
## 都把全部玩家单位 + 建筑 + 工地扫一遍，是混战掉帧的第二大来源
func _acquire_target() -> Node2D:
	if attack_target != null:
		if is_instance_valid(attack_target) and not _hid(attack_target):
			return attack_target
		attack_target = null
	_scan_t -= get_process_delta_time()
	if _scan_t > 0.0 and _cached_target != null and is_instance_valid(_cached_target) and not _hid(_cached_target):
		return _cached_target
	_scan_t = 0.15
	_cached_target = _scan_target()
	return _cached_target

## 追着的农民躲进屋了（警钟）：换目标
static func _hid(t: Node2D) -> bool:
	return t is Worker and t.is_garrisoned()

func _scan_target() -> Node2D:
	if is_guard():
		return _guard_scan()
	var best: Node2D = null
	var best_d := hunt_r
	for u in _group("player_units"):
		if not is_instance_valid(u):
			continue
		var d := position.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	if best:
		return best
	# 窜窜在路上什么建筑都不理，跑到路尽头才啃（基地）
	if etype == "runner" and lane:
		return null
	best = null
	best_d = INF
	for b in _group("buildings"):
		if not is_instance_valid(b):
			continue
		if b.team != 0:
			continue
		var tower: bool = b.kind == "tower"
		if tower and etype != "brute":
			continue    # 普通 Goo / 窜窜够不着塔上的弓手：从塔下走过只能挨射
		var d := position.distance_to(b.position)
		var aggro: float = LANE_AGGRO + b.size * 0.5 + (90.0 if tower else 0.0)    # 岩壳隔老远就盯上箭塔
		if lane and d > aggro:
			continue
		var score: float = d - (400.0 if tower else 0.0)    # 岩壳：先拆塔，再拆别的
		if score < best_d:
			best_d = score
			best = b
	if etype == "runner":
		return best
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
	return etype

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
