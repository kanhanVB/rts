extends Node2D
class_name Unit
## 所有单位的基类：移动、血量、选中、绘制。
## 原型阶段不用物理引擎——手动移动 + 软性分离，够用且好懂。

signal died(unit)

const SKIN := Color(0.87, 0.7, 0.52)          # KR 式暖棕肤色
const OUTLINE := Color(0.2, 0.14, 0.1)        # 深棕描边（KR 不用纯黑）

var team: int = 0                 # 0 = 玩家, 1 = Goofy Goo
var hp: float = 50.0
var max_hp: float = 50.0
var speed: float = 90.0
var radius: float = 12.0
var body_color: Color = Color(0.9, 0.8, 0.2)
var selected: bool = false

# 数值面板用的统一属性（子类在 _ready/setup 里填）
var display_name := "单位"
var armor := 0.0          # 受击减免（最低保底 1 点伤害）
var atk := 0.0            # 攻击力，0 = 非战斗单位
var atk_range := 0.0
var atk_cd := 0.0

var move_target: Vector2
var _attack_fx: Array = []        # [{to: Vector2, t: 剩余秒数}]
var attack_target: Node2D = null  # 战斗单位当前攻击目标（基类声明，子类复用）
var _path: PackedVector2Array = PackedVector2Array()   # A* 路径（为空 = 无路径）
var _path_idx := 0                # 当前走到的路径点下标
var _lane_off := Vector2.ZERO     # 天生车道偏移：同路径的群单位不叠成一条线

# 动画状态（KR 式小人用）
var anim_t := 0.0        # 动画相位：走路摆腿、待机轻晃
var moving := false      # 本帧是否在移动（_move_toward 里置位）
var _vel_dir := Vector2.ZERO   # 本帧移动方向（靠右让路用）
var attack_anim := 0.0   # 1 → 0 递减，驱动挥刀/抡锤动画

# 卡住检测：被人群挤着到不了目标点时停止移动，不原地抽搐
var _stuck_pos := Vector2.ZERO
var _stuck_t := 0.0

## ---------- 每帧共享缓存（性能） ----------
## 以前每个单位每帧都 get_nodes_in_group() 好几次（每次分配新数组），
## 分离力还是全员两两比较 O(n²)。现在每帧只取一次组成员，
## 再按格子分桶做空间哈希，分离只看周围 3×3 桶。
const HASH_CELL := 28.0           # 桶边长：必须 ≥ 最大分离距离（12+12+2=26px），越小混战里扫的邻居越少
static var _cache_frame := -1
static var _group_cache := {}     # 组名 -> Array（本帧快照）
static var _hash := {}            # Vector2i -> Array[Unit]

static func _sync_frame(tree: SceneTree) -> void:
	var f := Engine.get_process_frames()
	if f == _cache_frame:
		return
	_cache_frame = f
	_group_cache.clear()
	_hash.clear()
	for u in tree.get_nodes_in_group("units"):
		var k := Vector2i(floori(u.position.x / HASH_CELL), floori(u.position.y / HASH_CELL))
		if _hash.has(k):
			_hash[k].append(u)
		else:
			_hash[k] = [u]

## 本帧的组成员快照（同一帧内多次调用不重复分配）
func _group(name: String) -> Array:
	_sync_frame(get_tree())
	if not _group_cache.has(name):
		_group_cache[name] = get_tree().get_nodes_in_group(name)
	return _group_cache[name]

func _ready() -> void:
	move_target = position
	_lane_off = Vector2.from_angle(randf() * TAU) * randf_range(3.0, 8.0)
	add_to_group("units")
	add_to_group("player_units" if team == 0 else "enemies")

func _process(delta: float) -> void:
	moving = false
	_step(delta)          # 子类的 AI/状态机
	if not moving:
		_vel_dir = Vector2.ZERO    # 停下就清方向，下次起步重新加速转向
	_separate()           # 单位之间互相推开，别叠成一坨
	_avoid_obstacles()    # 撞上建筑/树就往侧面滑，别顶死
	# 卡住检测：0.7 秒挪了不到 2.5px（被人群挤住）→ 就地停下列队
	if moving:
		if position.distance_to(_stuck_pos) < 2.5:
			_stuck_t += delta
			if _stuck_t > 0.7:
				_stuck_t = 0.0
				_on_stuck()
		else:
			_stuck_pos = position
			_stuck_t = 0.0
	anim_t += delta * 10.0    # 恒速推进相位；只有移动/干活时的动作会用到它
	attack_anim = maxf(0.0, attack_anim - delta * 3.5)
	for fx in _attack_fx:
		fx.t -= delta
	_attack_fx = _attack_fx.filter(func(f): return f.t > 0.0)
	queue_redraw()

## 子类覆写：每帧行为（战斗 / 采集 / 巡逻）
func _step(_delta: float) -> void:
	pass

## 卡住回调（0.7 秒挪了不到 2.5px）：默认就地停下列队，
## 有持续目标（采集/赶路）的子类覆写它重新寻路绕行。
func _on_stuck() -> void:
	move_target = position

## 朝目标点走一步，返回走之前与目标的距离。
## 若寻路路径存在，先沿路径点走；走完最后一个点再直线逼近目标。
func _move_toward(pos: Vector2, delta: float) -> float:
	var target := pos
	if not _path.is_empty() and _path_idx < _path.size():
		target = _path[_path_idx]
		if position.distance_to(target) < 6.0:
			_path_idx += 1
			if _path_idx < _path.size():
				target = _path[_path_idx]
	var d := position.distance_to(target)
	if d > 2.0:
		var speed_now := speed * _terrain_speed_factor()
		var want := (target - position).normalized()
		if d < 40.0:
			# 近距离直接对齐：贴着目标点时目标方向变得剧烈，
			# 慢转向会追不上方向变化，绕着点转圈进不去
			_vel_dir = want
		else:
			# 远距离转向平滑：方向渐变（约 0.12s 收敛），拐点划弧线不生硬
			var turn := clampf(delta * 8.0, 0.0, 1.0)
			_vel_dir = _vel_dir.lerp(want, turn).normalized()
		if _vel_dir == Vector2.ZERO:
			_vel_dir = want
		position += _vel_dir * speed_now * delta
		moving = true
	if _path_idx >= _path.size():
		_path = PackedVector2Array()
		_path_idx = 0
	return d

## 查询当前所在格子的地形移速倍率
func _terrain_speed_factor() -> float:
	var t := Terrain.current
	if t == null:
		return 1.0
	return t.speed_factor(position)

## 射程修正（森林减射程）
func _terrain_range_factor() -> float:
	var t := Terrain.current
	if t == null:
		return 1.0
	return t.range_factor(position)

## 软性分离：所有单位互相排斥，挤在一起时各自让开。
## 战斗中贴脸的目标不推（否则近战双方被分离力顶开、站位来回抖）。
## 靠右通行：两个都在移动的单位相遇时，除了沿连线推开，还各自往自己的
## 右侧多让一点——相向而行的两人会错开肩膀通过，不再面对面顶牛。
func _separate() -> void:
	_sync_frame(get_tree())
	var cx := floori(position.x / HASH_CELL)
	var cy := floori(position.y / HASH_CELL)
	# 直接遍历 3×3 桶，不拼临时数组（混战里这是每帧最热的循环）
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var bucket = _hash.get(Vector2i(cx + dx, cy + dy))
			if bucket == null:
				continue
			for u in bucket:
				if u == self or not is_instance_valid(u):
					continue
				var off: Vector2 = position - u.position
				var min_d: float = radius + u.radius + 2.0
				var d2 := off.length_squared()
				if d2 >= min_d * min_d or d2 < 0.0001:
					continue
				if _is_attacking(u):    # 正跟它贴脸互殴就不推它
					continue
				var d := sqrt(d2)
				var push: Vector2 = off / d * (min_d - d) * 0.3
				# 双方都在走 + 大致对向/交汇 → 往自己右手侧让
				if moving and u.moving and _vel_dir != Vector2.ZERO:
					var right := Vector2(_vel_dir.y, -_vel_dir.x)    # 移动方向的右侧法线
					push += right * (min_d - d) * 0.4
				position += push

## 是否正在攻击这个目标（贴脸互殴中）：有 attack_target 且距离在攻击范围内
func _is_attacking(other: Node2D) -> bool:
	if attack_target == null or attack_target != other:
		return false
	return position.distance_to(other.position) <= 40.0

## 软性绕障：只绕建筑（大体积会顶死），资源点小、软分离已经够用。
## 撞上建筑被推向侧面，贴着边缘滑过去（轻量寻路）
func _avoid_obstacles() -> void:
	var push := Vector2.ZERO
	for b in _group("buildings"):
		if not is_instance_valid(b):
			continue
		var r: float = b.size * 0.5 + radius
		var d: float = position.distance_to(b.position)
		if d < r and d > 0.01:
			push += (position - b.position).normalized() * (r - d)
	if push.length() > 0.01:
		position += push.limit_length(speed * 0.16)

## ---------- 玩家指令 ----------
func command_move(pos: Vector2) -> void:
	move_target = pos
	_path = _find_path(pos)
	_path_idx = 0

## 从当前位置到目标点的寻路（有地形层就绕开阻挡，否则空=直线）
func _find_path(pos: Vector2) -> PackedVector2Array:
	var t := Terrain.current
	if t == null:
		return PackedVector2Array()
	var p: PackedVector2Array = t.find_path(position, pos)
	# 车道偏移：中间路径点各加一个天生随机偏移，同路径的群单位
	# 不会叠在同一条线上（对向通行也更顺）；偏进阻挡格就退回原点
	if p.size() > 2:
		for i in range(p.size() - 1):
			var q := p[i] + _lane_off
			if t.walkable(int(q.x / t.CELL), int(q.y / t.CELL)):
				p[i] = q
	return p

## A 移动：默认就当成普通移动，战斗单位（剑士/弓手）会覆写加入沿途索敌
func command_attack_move(pos: Vector2) -> void:
	command_move(pos)

func take_damage(amount: float, from: Node2D = null) -> void:
	hp -= maxf(amount - armor, 1.0)    # 护甲减免，保底 1 点伤害
	_hurt_until = Time.get_ticks_msec() + 140
	if hp <= 0.0:
		_death_fx()
		died.emit(self)
		queue_free()

## 攻击时画一条亮线，纯反馈
func attack_fx_to(pos: Vector2) -> void:
	_attack_fx.append({"to": pos, "t": 0.12})

## ---------- 绘制：有美术素材就画贴图（_art_draw），没有就退回色块风 ----------
## 显示高度（像素，缩放 1 倍时）。素材是 160px 高的大图，缩小画更清晰
const ART_H := {"worker": 40.0, "engineer": 46.0, "swordsman": 46.0, "archer": 44.0, "goo": 30.0}
var _face := 1.0              # 朝向：1 右 / -1 左（停下也保持，不会突然转回去）
var _hurt_until := 0          # 挨打闪红到这个时间（毫秒）

## 子类覆写：素材 key（"worker" / "swordsman" ...），空串 = 没有素材
func _art_key() -> String:
	return ""

## 子类覆写：当前用哪张姿势图（idle / act / carry）
func _art_pose() -> String:
	return "act" if attack_anim > 0.35 else "idle"

## 子类覆写：朝向参考点（返回 NAN 表示没有，按移动方向）
func _face_x() -> float:
	return NAN

func _draw() -> void:
	var key := _art_key()
	if key != "" and Art.has("units/%s_idle" % key):
		_art_draw(key)
		return
	_shadow()
	for fx in _attack_fx:
		draw_line(Vector2.ZERO, fx.to - position, Color(1, 1, 1, 0.7), 1.5)
	if selected:
		draw_arc(Vector2.ZERO, radius + 5.0, 0, TAU, 24, Color(1, 1, 1, 0.9), 1.5)
	if hp < max_hp:
		var w := radius * 2.0
		draw_rect(Rect2(-w / 2.0, -radius - 10.0, w, 4.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-w / 2.0, -radius - 10.0, w * hp / max_hp, 4.0), Color(0.3, 0.9, 0.3))
	_body_draw()

## 子类覆写：画自己的身体
func _body_draw() -> void:
	draw_circle(Vector2.ZERO, radius, body_color)

## 贴图版：脚下投影/选中圈 → 身体（走路颠、待机呼吸、出手前冲、挨打闪红）→ 箭/打击火花 → 血条
func _art_draw(key: String) -> void:
	var fx_x := _face_x()
	if not _attack_fx.is_empty():
		var dx: float = _attack_fx[0].to.x - position.x
		if absf(dx) > 1.0:
			_face = signf(dx)
	elif not is_nan(fx_x) and absf(fx_x - position.x) > 1.0:
		_face = signf(fx_x - position.x)
	elif moving and absf(move_target.x - position.x) > 2.0:
		_face = signf(move_target.x - position.x)
	var h: float = ART_H.get(key, 44.0)
	var feet := Vector2(0, radius * 0.55)
	var is_goo := key == "goo"
	# 投影 + 选中圈
	Art.ellipse(self, feet, radius * 1.25, Color(0.05, 0.1, 0.02, 0.32))
	if selected:
		var ring := Color(0.55, 1.0, 0.35) if team == 0 else Color(1.0, 0.35, 0.25)
		Art.ellipse(self, feet, radius * 1.6, ring, false, 2.4)
	# 身体动作
	var now := Time.get_ticks_msec() / 1000.0
	var bob := 0.0
	var rot := 0.0
	var sq := Vector2.ONE
	if moving:
		if is_goo:
			var ph := absf(sin(anim_t * 0.5))
			bob = ph * 5.0
			sq = Vector2(1.0 - ph * 0.08 + (1.0 - ph) * 0.08, 1.0 + ph * 0.1 - (1.0 - ph) * 0.08)
		else:
			bob = absf(sin(anim_t * 0.6)) * 2.6
			rot = sin(anim_t * 0.6) * 0.07
	else:
		var br := sin(now * 2.6 + float(get_instance_id() % 97)) * 0.025
		sq = Vector2(1.0 - br * 0.5, 1.0 + br)
	var lunge := attack_anim * 5.0 * _face
	var mod := Color.WHITE
	if Time.get_ticks_msec() < _hurt_until:
		mod = Color(1.0, 0.5, 0.45)
	var pose := _art_pose()
	var pkey := "units/%s_%s" % [key, pose]
	if not Art.has(pkey):
		pkey = "units/%s_idle" % key
	Art.draw(self, pkey, feet + Vector2(lunge, -bob), h, _face < 0.0, mod, rot * _face, sq)
	_art_extra(feet, h)
	# 攻击特效：弓手射箭，其余打击火花
	for fx in _attack_fx:
		var p: float = clampf(1.0 - fx.t / 0.12, 0.0, 1.0)
		var to: Vector2 = fx.to - position
		if atk_range > 60.0 and Art.has("fx/arrow"):
			var from := Vector2(_face * 8.0, -h * 0.55)
			var pt := from.lerp(to, p) - Vector2(0, sin(p * PI) * 14.0)
			var nx := from.lerp(to, minf(p + 0.08, 1.0)) - Vector2(0, sin(minf(p + 0.08, 1.0) * PI) * 14.0)
			Art.draw(self, "fx/arrow", pt, 5.0, false, Color.WHITE, (nx - pt).angle())
		elif p > 0.3 and Art.has("fx/hit"):
			Art.draw(self, "fx/hit", to - Vector2(0, 10), 10.0 + 12.0 * p, false, Color(1, 1, 1, 1.2 - p))
	# 血条：掉血或选中时显示
	if hp < max_hp or selected:
		Art.hp_bar(self, feet - Vector2(0, h + 8.0), 26.0, hp / max_hp, team == 0)

## 子类覆写：贴图之外的附加物（农民头顶的货、交货点蓝点）
func _art_extra(_feet: Vector2, _h: float) -> void:
	pass

## 死亡：留一具会淡出的尸体（Goo 是一滩黏液），纯视觉
func _death_fx() -> void:
	var key := _art_key()
	if key == "" or not Art.enabled or is_queued_for_deletion():
		return
	var par := get_parent()
	if key == "goo":
		Fx.spawn(par, "splat", position + Vector2(0, radius * 0.55), {"size": 34.0, "life": 1.2})
	if Art.has("units/%s_dead" % key):
		Fx.spawn(par, "corpse", position + Vector2(0, radius * 0.55), {"key": "units/%s_dead" % key, "size": ART_H.get(key, 44.0) * (0.75 if key != "goo" else 0.6), "flip": _face < 0.0, "life": 1.8})

## ---------- KR 风（王国保卫战）小工具：投影 / 描边 / 表情 ----------
## 椭圆软投影，垫在所有东西下面
func _shadow() -> void:
	draw_set_transform(Vector2(0, radius * 0.7), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius * 1.1, Color(0.08, 0.12, 0.05, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 填充圆 + 深色厚描边
func _outlined_circle(pos: Vector2, r: float, fill: Color) -> void:
	draw_circle(pos, r, fill)
	draw_arc(pos, r, 0, TAU, 40, Color(0.16, 0.13, 0.09), 2.5)

## ---------- KR 式小人通用绘制 ----------
## 大头小身子：腿随走路摆动、身体有呼吸起伏、武器随 attack_anim 挥动、
## 朝移动方向整体镜像。hat: straw草帽/helm铁盔/hood兜帽/hardhat安全帽
## weapon: pick镐/sword剑/bow弓/hammer锤/none
func _kr_body(torso: Color, legs: Color, hat: String, weapon: String) -> void:
	var s := radius / 12.0
	# 朝向：往左走整体翻转
	var face := 1.0
	if moving and absf(move_target.x - position.x) > 2.0:
		face = signf(move_target.x - position.x)
	var bob := absf(sin(anim_t)) * 1.4 * s if moving else 0.0    # 只在走路时起伏，待机完全静止
	var stride := sin(anim_t) * 0.8 if moving else 0.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(face, 1.0))
	# 短腿（KR 的腿就是两个小墩子）
	var hip := Vector2(0, 1.2 * s)
	_limb(hip + Vector2(-2.6 * s, 0), hip + Vector2(-2.6 * s + stride * 4.0 * s, 5.4 * s), 3.6 * s, legs)
	_limb(hip + Vector2(2.6 * s, 0), hip + Vector2(2.6 * s - stride * 4.0 * s, 5.4 * s), 3.6 * s, legs)
	# 小身板
	var tr := Rect2(-3.8 * s, -4.6 * s - bob, 7.6 * s, 7.2 * s)
	draw_rect(tr, OUTLINE)
	draw_rect(tr.grow(-1.1 * s), torso)
	# 后手：剑士挎 KR 民兵同款圆木盾，其余人摆臂
	var sh_back := Vector2(-3.2 * s, -2.8 * s - bob)
	if weapon == "sword":
		var sc := sh_back + Vector2(-1.8 * s, 2.6 * s)
		draw_circle(sc, 4.6 * s + 1.6, OUTLINE)
		draw_circle(sc, 4.6 * s, Color(0.63, 0.48, 0.31))
		draw_arc(sc, 4.6 * s, 0, TAU, 28, Color(0.45, 0.33, 0.21), 1.6 * s)
		draw_circle(sc, 1.5 * s, Color(0.5, 0.38, 0.25))
	else:
		_limb(sh_back, sh_back + Vector2(-1.8 * s - stride * 1.8 * s, 4.2 * s), 2.8 * s, torso.darkened(0.25))
	# 大头（占半个身高）
	var head := Vector2(0.4 * s, -8.8 * s - bob)
	draw_circle(head, 5.4 * s + 1.6, OUTLINE)
	draw_circle(head, 5.4 * s, SKIN)
	# 帽子（脸保持干净，不画五官）
	_kr_hat(hat, head, s, face)
	# 武器手 + 超大号武器
	var sh := Vector2(3.2 * s, -3.0 * s - bob)
	var swing := 0.55 - attack_anim * 1.9
	var hand := sh + Vector2(2.0 * s, 3.4 * s).rotated(swing)
	_limb(sh, hand, 2.8 * s, torso.darkened(0.25))
	_kr_weapon(weapon, hand, s, swing)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _limb(from: Vector2, to: Vector2, width: float, color: Color) -> void:
	draw_line(from, to, OUTLINE, width + 1.8)
	draw_line(from, to, color, width)

func _kr_hat(hat: String, head: Vector2, s: float, face: float) -> void:
	match hat:
		"straw":    # 农民草帽：宽檐 + 圆顶（做旧麦色）
			draw_set_transform(head + Vector2(0, -1.8 * s), 0.0, Vector2(1.7, 0.55))
			draw_circle(Vector2.ZERO, 5.8 * s, Color(0.78, 0.66, 0.36))
			draw_arc(Vector2.ZERO, 5.8 * s, 0, TAU, 32, OUTLINE, 1.4)
			draw_set_transform(head + Vector2(0, -2.6 * s), 0.0, Vector2(1.0, 0.8))
			draw_circle(Vector2.ZERO, 3.2 * s, Color(0.84, 0.73, 0.44))
			draw_arc(Vector2.ZERO, 3.2 * s, 0, TAU, 24, OUTLINE, 1.4)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(face, 1.0))
		"helm":     # 剑士铁盔：哑光钢灰 + 帽檐 + 中脊
			draw_set_transform(head + Vector2(0, -1.2 * s), 0.0, Vector2(1.05, 0.95))
			draw_circle(Vector2.ZERO, 5.2 * s, Color(0.6, 0.63, 0.68))
			draw_arc(Vector2.ZERO, 5.2 * s, 0, TAU, 24, OUTLINE, 1.6)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(face, 1.0))
			draw_line(head + Vector2(0, -6.2 * s), head + Vector2(0, -1.0 * s), OUTLINE, 1.6)
			draw_line(head + Vector2(-4.8 * s, -1.4 * s), head + Vector2(4.8 * s, -1.4 * s), OUTLINE, 1.6)
		"hood":     # 弓手兜帽：哑光墨青罩头只露脸
			draw_circle(head, 5.9 * s, Color(0.34, 0.44, 0.5))
			draw_arc(head, 5.9 * s, 0, TAU, 28, OUTLINE, 1.6)
			draw_circle(head + Vector2(0.9 * s, 1.4 * s), 3.9 * s, SKIN)
		"hardhat":  # 工程师安全帽：做旧黄 + 帽檐
			draw_set_transform(head + Vector2(0, -1.4 * s), 0.0, Vector2(1.15, 0.85))
			draw_circle(Vector2.ZERO, 4.8 * s, Color(0.85, 0.68, 0.25))
			draw_arc(Vector2.ZERO, 4.8 * s, 0, TAU, 24, OUTLINE, 1.6)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(face, 1.0))
			var brim := Rect2(head.x - 6.4 * s, head.y - 2.2 * s, 12.8 * s, 1.8 * s)
			draw_rect(brim, OUTLINE)
			draw_rect(brim.grow(-0.5), Color(0.85, 0.68, 0.25))

func _kr_weapon(weapon: String, hand: Vector2, s: float, swing: float) -> void:
	match weapon:
		"pick":     # 镐：木柄 + 大弯钩头
			var tip := hand + Vector2(0, -8.5 * s).rotated(swing * 0.9)
			_limb(hand, tip, 2.0 * s, Color(0.45, 0.32, 0.2))
			draw_arc(tip + Vector2(0, 1.0 * s), 3.4 * s, -PI * 0.85, PI * 0.05, 10, Color(0.58, 0.58, 0.62), 2.0 * s)
		"sword":    # KR 民兵大砍剑：宽刃 + 金护手
			var tip := hand + Vector2(0, -13.0 * s).rotated(swing * 0.9)
			_limb(hand, tip, 3.0 * s, Color(0.76, 0.78, 0.82))
			draw_line(hand + Vector2(-2.6 * s, -1.0 * s).rotated(swing * 0.9),
				hand + Vector2(2.6 * s, -1.0 * s).rotated(swing * 0.9),
				Color(0.72, 0.58, 0.28), 2.2 * s)
			draw_circle(hand, 1.8 * s, Color(0.45, 0.32, 0.2))
		"bow":      # 长弓：弓身 + 弦
			draw_arc(hand + Vector2(1.0 * s, 0), 7.5 * s, -PI * 0.75, PI * 0.75, 16, Color(0.45, 0.32, 0.2), 2.0 * s)
			var t := 5.3 * s
			draw_line(hand + Vector2(1.0 * s - t, -t), hand + Vector2(1.0 * s - t, t), Color(0.88, 0.84, 0.78), 0.9 * s)
		"hammer":   # 大锤：短柄 + 方头
			var tip := hand + Vector2(0, -8.0 * s).rotated(swing * 0.9)
			_limb(hand, tip, 2.2 * s, Color(0.45, 0.32, 0.2))
			var hh := Rect2(tip + Vector2(-3.0 * s, -4.6 * s), Vector2(6.0 * s, 4.4 * s))
			draw_rect(hh, OUTLINE)
			draw_rect(hh.grow(-1.0 * s), Color(0.55, 0.55, 0.6))
		"none":
			pass
