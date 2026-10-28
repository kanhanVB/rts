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
## 轻 RTS 的"钉子"：谁把我钉住了（近战兵 1v1 独占）。被钉住的怪按自己的索敌逻辑停下互殴，
## 这只标记只是让别的兵别来抢同一个目标，以及兵死了/脱岗时好清干净
var pinned_by: Node2D = null
var _attack_fx: Array = []        # [{to: Vector2, t: 剩余秒数}]
## 战斗单位当前攻击目标（基类声明，子类复用）。
## 清空时顺手把 cmd_target 一起清掉——用 setter 是为了不让哪条路忘了清：
## 以前"玩家点名的目标"和"自动索敌挑中的目标"共用这一个字段，结果自动挑中的那个
## 跑出十万八千里也还挂在身上，整队兵被一只逃跑的 Goo 牵着走
var attack_target: Node2D = null:
	set(v):
		attack_target = v
		if v == null:
			cmd_target = null
## 玩家亲手点名的目标：追到底，不因为"跑远了"而松口。
## 自动索敌挑中的目标只拴在 AUTO_LEASH 个索敌圈内（见 _acquire_target）
var cmd_target: Node2D = null
const AUTO_LEASH := 1.5    # 自动目标拴绳：跑出 aggro_range 的这么多倍就松口
var _path: PackedVector2Array = PackedVector2Array()   # A* 路径（为空 = 无路径）
var _path_idx := 0                # 当前走到的路径点下标
## 这条路径是奔哪儿去的（_find_path 记下）。_move_toward 用它判断"路和目标对不上"，
## 差得太多就丢掉旧路直线走——见 _move_toward 开头的注释
var _path_want := Vector2.INF
const STALE_PATH_GAP := 40.0      # 比 REPATH_GAP(20) 大一圈：没重算路但目标小挪一下是正常的
var _lane_off := Vector2.ZERO     # 天生车道偏移：同路径的群单位不叠成一条线

# 动画状态（KR 式小人用）
var anim_t := 0.0        # 动画相位：走路摆腿、待机轻晃
var moving := false      # 本帧是否在移动（_move_toward 里置位）
var walk_ph := 0.0       # 走路步态相位：按实际走过的距离推进，跑得快步子就快，停下就停
var _vel_dir := Vector2.ZERO   # 本帧移动方向（靠右让路用）
var attack_anim := 0.0   # 1 → 0 递减，驱动挥刀/抡锤动画

# 卡住检测：被人群挤着到不了目标点时停止移动，不原地抽搐
var _stuck_pos := Vector2.ZERO
var _stuck_t := 0.0

## ---------- 每帧共享缓存（性能） ----------
## 以前每个单位每帧都 get_nodes_in_group() 好几次（每次分配新数组），
## 分离力还是全员两两比较 O(n²)。现在每帧只取一次组成员，
## 再按格子分桶做空间哈希，分离只看周围 3×3 桶。
## 桶边长必须 ≥ 场上最大的分离距离（radius*2+2），否则两只大块头正好落在隔一格的
## 两个桶里、3×3 邻域够不着，就会直接叠在一起——岩壳 radius 15，15+15+2=32
const HASH_CELL := 32.0
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
	if not waypoints.is_empty() and _done_with_order():
		var wp: Dictionary = waypoints.pop_front()
		if wp.attack:
			command_attack_move(wp.pos)
		else:
			command_move(wp.pos)
	var ter := Terrain.current
	if ter != null and ter.has_solids():
		position += ter.push_out(position, radius * 0.8)    # 被挤进树林/矿堆就推回来，贴着林边走会顺着边滑
	# 卡住检测：0.7 秒净挪不到 8px（被人群挤住 / 撞在岸边来回顶）→ 交给子类脱困。
	# 阈值原来是 2.5px，但"走一帧被推回来一帧"的震荡每帧就有 3px，
	# 每次都够格去刷新起点，_stuck_t 永远累积不起来 —— 看着在原地磨一分钟也判不出来。
	# 8px 对正常行走是安全的：最快的怪 62 速度也就 1px/帧，8px 要 8 帧（0.13 秒），
	# 远够不到 0.7 秒的线
	if moving:
		if position.distance_to(_stuck_pos) < 8.0:
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
	# 路径和这次要去的目标对不上（调用方换了目标却没重算路）：
	# 照着旧路走会一路滑向老目的地——"换了目标却还在走老路""站着不动却一直挪"
	# 都是这么来的（A 移动来回拉锯、门口转圈都栽在这上面）。
	# 只在"本来该站住"的情况下判定（新目标就在脚下 60px 内），追移动目标时不受影响，
	# 那样最多直线走一帧，需要绕障碍的调用方本来就会自己 _find_path
	if not _path.is_empty() and position.distance_to(pos) < 60.0 \
			and _path_want.distance_to(pos) > STALE_PATH_GAP:
		_path = PackedVector2Array()
		_path_idx = 0
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
		walk_ph += speed_now * delta * WALK_RATE
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
	var yielded := false
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
				# 闲着的己方被走路的队友挤：主动让开（帝国式让路），别当路障
				if not moving and u.moving and u.team == team and _can_yield():
					push = off / d * (min_d - d) * 0.6
					yielded = true
				# 双方都在走 + 大致对向/交汇 → 往自己右手侧让。
				# 这里的"对向"必须真判一下：同向并排的两个人右手是同一边，
				# 一让两人一起往那边偏，推不开还把整队带得斜着走，
				# _move_toward 再把人拉回来——队伍在路上就一扭一扭的。
				# dot < 0.35 约等于夹角超过 70°：正对向(-1)、垂直交汇(0) 都让，并排同向(+1) 不让
				if moving and u.moving and _vel_dir != Vector2.ZERO and _vel_dir.dot(u._vel_dir) < 0.35:
					var right := Vector2(_vel_dir.y, -_vel_dir.x)    # 移动方向的右侧法线
					push += right * (min_d - d) * 0.4
				position += push
	if yielded:
		move_target = position    # 让完就站在新位置，别再走回去

## 能不能给队友让路：没路要走、没在打、已经到位（子类再加条件）
func _can_yield() -> bool:
	return _path.is_empty() and attack_target == null and position.distance_to(move_target) < 24.0

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
## Shift+右键排的后续路点（帝国式）：手上这一步走完了才接着走下一个
var waypoints: Array = []    # [{pos, attack}]

## 新的普通指令会冲掉排好的路点 / 巡逻 / 原地驻守（main 下令前调用）
func cancel_orders() -> void:
	waypoints.clear()

## 手上的指令干完了没有（排的下一个路点可以接上了）；子类按自己的状态机细化
func _done_with_order() -> bool:
	return not moving and attack_target == null and position.distance_to(move_target) < 20.0

## Shift+右键：闲着就马上走，忙着就排到后面
func queue_move(pos: Vector2, attack := false) -> void:
	if waypoints.is_empty() and _done_with_order():
		if attack:
			command_attack_move(pos)
		else:
			command_move(pos)
	else:
		waypoints.append({"pos": pos, "attack": attack})

## S 停止：扔下手上所有事，原地站着
func command_stop() -> void:
	waypoints.clear()
	attack_target = null
	move_target = position
	_path = PackedVector2Array()
	_path_idx = 0

## 最后一个排队路点（画路点连线用）
func order_points() -> Array:
	var pts: Array = []
	if position.distance_to(move_target) > 20.0:
		pts.append(move_target)
	for w in waypoints:
		pts.append(w.pos)
	return pts

func command_move(pos: Vector2) -> void:
	move_target = pos
	_path = _find_path(pos)
	_path_idx = 0

## 从当前位置到目标点的寻路（有地形层就绕开阻挡，否则空=直线）
func _find_path(pos: Vector2) -> PackedVector2Array:
	_path_want = pos    # 记下"这条路由哪儿算的"：_move_toward 靠它识别过期的路
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

var hop_rate := 1.0    # 黏液怪一跳一跳的快慢（窜窜快、岩壳慢）
var dead := false    # 已经死了（等 queue_free 生效）：同一帧再挨打不能再死一次

func take_damage(amount: float, from: Node2D = null) -> void:
	if dead:
		return
	hp -= maxf(amount - armor, 1.0)    # 护甲减免，保底 1 点伤害
	_hurt_until = Time.get_ticks_msec() + 140
	if hp <= 0.0:
		dead = true
		_credit_killer(from)
		_death_fx()
		_report_death()
		died.emit(self)
		queue_free()

## 击杀记账（老兵成长用）：只认**兵的最后一刀**。
## 箭塔、基地、据点守军打死的都不算——那些是"设施的战果"，不是哪个人的战功。
## 判断 team 不相等是为了防自己人误伤算账（也防兵打自家建筑时莫名其妙涨星）
func _credit_killer(from) -> void:
	if from == null or not is_instance_valid(from):
		return
	if from is Soldier and from != self and from.team != team:
		from.credit_kill()

## 直接删掉（Del 键）：照常走死亡流程，编队/统计都会跟着更新
func kill() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	_death_fx()
	_report_death()
	died.emit(self)
	queue_free()

## 统计上报：一局打下来杀了多少、死了多少（main.stats / 结算页用）。
## 放在基类里，剑士弓手农民工程师、怪全走这一处，不用到处挂信号
func _report_death() -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g != null and g.has_method("note_death"):
		g.note_death(self)

## 攻击时画一条亮线，纯反馈
func attack_fx_to(pos: Vector2) -> void:
	_attack_fx.append({"to": pos, "t": 0.12})

## ---------- 绘制：有美术素材就画贴图（_art_draw），没有就退回色块风 ----------
## 显示高度（像素，缩放 1 倍时）。素材是 160px 高的大图，缩小画更清晰
## 动作图和站姿图同一比例导出（tools/prepare_art.py），按贴图高度之比画，动作时人不会忽大忽小
static func pose_scale(key: String, pkey: String) -> float:
	var hi: float = Art.info("units/%s_idle" % key).get("h", 0.0)
	var hp: float = Art.info(pkey).get("h", 0.0)
	return hp / hi if hi > 0.0 and hp > 0.0 else 1.0

## 按王国保卫战：起源实测比例定（小兵约屏高 3%、英雄约 4.5%、怪物不比小兵小），
## 地图上画的树和起源同尺度，所以小人按树来比：小兵约树高的 1/3
const ART_H := {"worker": 22.0, "engineer": 29.0, "swordsman": 24.0, "archer": 23.0, "goo": 19.0, "runner": 15.0, "brute": 29.0}
## 黏液一族（没腿，一跳一跳走；死了是一滩黏液）
const BLOBS := ["goo", "runner", "brute"]
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
		_badge_draw()
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
	_badge_draw()

## 子类覆写：画在身体之上、两条绘制路径（贴图 / 手绘小人）都会走到的小挂件。
## 老兵星级就挂这儿——只塞进 _body_draw 的话，有贴图的兵根本画不出来
func _badge_draw() -> void:
	pass

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
	var is_goo: bool = key in BLOBS
	# 程序化走路的步态（有逐帧走路图 / Goo 不用）
	var stepping := moving and not is_goo and _art_pose() != "act" and _walk_frames(key) == 0
	var g := gait(walk_ph) if stepping else PackedFloat32Array()
	var hop: float = g[0] if stepping else 0.0
	# 投影 + 选中圈（人蹦起来投影缩小变淡，投影本身留在地上）
	Art.ellipse(self, feet, radius * 1.25 * (1.0 - hop * 1.4), Color(0.05, 0.1, 0.02, 0.32 * (1.0 - hop * 1.6)))
	if selected:
		var ring := Color(0.55, 1.0, 0.35) if team == 0 else Color(1.0, 0.35, 0.25)
		Art.ellipse(self, feet, radius * 1.6, ring, false, 2.4)
	# 身体动作
	var now := Time.get_ticks_msec() / 1000.0
	var bob := 0.0
	var rot := 0.0
	var sq := Vector2.ONE
	var pose := _art_pose()
	var pkey := "units/%s_%s" % [key, pose]
	if not Art.has(pkey):
		pkey = "units/%s_idle" % key
	var walking := moving and pose != "act"
	if moving:
		if is_goo:
			var ph := absf(sin(anim_t * 0.5 * hop_rate))
			bob = ph * 5.0 * h / 19.0    # 跳的高度跟着个头走（岩壳蹦得沉、窜窜蹦得碎）
			sq = Vector2(1.0 - ph * 0.08 + (1.0 - ph) * 0.08, 1.0 + ph * 0.1 - (1.0 - ph) * 0.08)
		# 人形单位的蹦步 / 前倾 / 挤压都在 _draw_stride 里按步态关键帧算
	else:
		var br := sin(now * 2.6 + float(get_instance_id() % 97)) * 0.025
		sq = Vector2(1.0 - br * 0.5, 1.0 + br)
	var lunge := attack_anim * 5.0 * _face
	var mod := Color.WHITE
	if Time.get_ticks_msec() < _hurt_until:
		mod = Color(1.0, 0.5, 0.45)
	var hh := h * pose_scale(key, pkey)
	var at := feet + Vector2(lunge, -bob)
	_head_off = Vector2.ZERO
	# 有逐帧走路图（units/<key>_walk1..N）就播帧；没有就把站姿图切成 上身 + 左右腿 程序化迈步
	var frames := _walk_frames(key) if walking else 0
	if frames > 0:
		var fk := "units/%s_walk%d" % [key, int(walk_ph / TAU * frames) % frames + 1]
		Art.draw(self, fk, at, h * pose_scale(key, fk), _face < 0.0, mod, rot * _face, sq)
	elif stepping:
		_draw_stride(pkey, at, hh, mod, g)
	else:
		Art.draw(self, pkey, at, hh, _face < 0.0, mod, rot * _face, sq)
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
			Art.draw(self, "fx/hit", to - Vector2(0, 8), 8.0 + 10.0 * p, false, Color(1, 1, 1, 1.2 - p))
	# 血条：掉血或选中时显示
	if hp < max_hp or selected:
		Art.hp_bar(self, feet - Vector2(0, h + 5.0), 16.0, hp / max_hp, team == 0)

## ---------- 走路动画（照王国保卫战原版小兵的逐帧图量出来的节奏） ----------
## KR 的人形小兵走路其实是"一步一蹦"：每步约 0.35 秒，蹬地 → 整个人离地（脚离地约身高的 14%）、两腿前后劈开
## → 落地那一下拉长约 7% → 接着压扁 7~10%、两腿收拢到身子底下 → 换另一条腿再蹦。投影留在地上，人蹦高了投影变小。
## 我们每个角色只有一张站姿图，所以做成"剪纸骨骼"：整个人按关键帧蹦、挤压，上身前倾；
## 两条腿切成竖条网格，胯跟着上身，脚按关键帧前后劈开 / 收拢 / 腾空收脚。
const WALK_RATE := 0.12        # 每走 1px 步态相位前进多少弧度（约 52px 一个完整步态 = 左右各蹦一步，剑士每秒 3 步多）
# 一个完整步态 12 个关键姿势（左右腿各 6 个：着地、蹬起、最高、下落、落地拉长、压扁），数值是照 KR 帧图量的
const G_KEYS := [
	[0.0, 0.07, 0.14, 0.11, 0.0, 0.0],     # 脚离地高度 / 身高
	[1.0, 1.05, 1.0, 1.04, 1.08, 0.9],     # 竖向拉伸（<1 = 压扁，横向反过来胖一点）
	[0.6, 1.0, 1.0, 0.8, 0.35, 0.0],       # 两脚前后劈开程度（换腿时变号）
	[0.0, 0.6, 1.0, 0.6, 0.0, 0.0],        # 腾空时两脚往上收
	[0.04, 0.1, 0.08, 0.05, 0.0, 0.03],    # 上身前倾（切变量）
]
const G_STEPPED := true       # 姿势按关键帧一格一格跳（像 KR 的逐帧图）；false = 关键帧之间平滑插值
const STRIDE_K := 0.13         # 两脚劈开最大幅度 / 贴图高
const TUCK_K := 0.07           # 腾空收脚高度 / 贴图高
const FAR_LEG := Color(0.8, 0.78, 0.76)   # 远侧那条腿压暗一点，两腿交叉时看得清
var _head_off := Vector2.ZERO  # 本帧头顶相对站姿的偏移（头顶扛的货跟着颠）
static var _legs := {}         # 贴图 key → 腿部切分 {gx, top, cut, l, r}，空字典 = 这张图找不到两条腿
static var _walk_n := {}       # 角色 key → 逐帧走路图张数

## 逐帧走路图有几张（units/<key>_walk1、_walk2…；美术补上就自动用，不用改代码）
static func _walk_frames(key: String) -> int:
	if not _walk_n.has(key):
		var n := 0
		while Art.has("units/%s_walk%d" % [key, n + 1]):
			n += 1
		_walk_n[key] = n
	return _walk_n[key]

## 从贴图 alpha 里找两腿：底部往上，两脚之间那道透明缝一直到裆部 → 缝的 x、裆的高度、两脚左右边界。
## 每张图只分析一次。找不到（Goo 这种没腿的、腿太短的）返回空字典。
static func leg_split(pkey: String) -> Dictionary:
	if _legs.has(pkey):
		return _legs[pkey]
	var out := {}
	var t := Art.tex(pkey)
	var d := Art.info(pkey)
	if t != null and not d.is_empty():
		var img := t.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			var bottom := h - 1
			while bottom > h / 2 and not _row_solid(img, bottom, 0, w):
				bottom -= 1
			var ax := int(d.ax)
			var best_x := -1
			var best_top := bottom
			for cx in range(maxi(1, ax - 25), mini(w - 1, ax + 25)):
				var y := bottom
				while y > h / 2 and not _row_solid(img, y, cx - 1, cx + 2):
					y -= 1
				if y < best_top:
					best_top = y
					best_x = cx
			var gap := bottom - best_top
			if best_x >= 0 and gap > h * 0.06:
				# 脚的左右边界：最底下几行的不透明范围
				var l := w
				var r := 0
				for y in range(bottom - 6, bottom + 1):
					for x in w:
						if img.get_pixel(x, y).a > 0.25:
							l = mini(l, x)
							r = maxi(r, x)
				out = {"gx": best_x, "top": best_top, "cut": best_top + int(gap * 0.3), "l": maxi(0, l - 3), "r": mini(w, r + 4), "h": h, "w": w}
	_legs[pkey] = out
	return out

static func _row_solid(img: Image, y: int, x0: int, x1: int) -> bool:
	for x in range(x0, x1):
		if img.get_pixel(x, y).a > 0.25:
			return true
	return false

## 步态采样：返回 [离地, 竖拉伸, 劈腿(带正负), 收脚, 前倾]；G_STEPPED 关掉时关键帧之间用 Catmull-Rom 平滑插值
static func gait(ph: float) -> PackedFloat32Array:
	var u := fposmod(ph / TAU, 1.0) * 12.0
	var i := int(u) % 12
	# KR 是逐帧动画、一张姿势停两帧（约 15~20 张/秒），姿势"一格一格"跳才有那股弹劲；位置照样平滑移动
	var f := 0.0 if G_STEPPED else u - floorf(u)
	var out := PackedFloat32Array()
	for c in G_KEYS.size():
		var row: Array = G_KEYS[c]
		var p := PackedFloat32Array()
		for j in range(-1, 3):
			var q := (i + j + 12) % 12
			var v: float = row[q % 6]
			if c == 2 and q >= 6:
				v = -v
			p.append(v)
		out.append(0.5 * (2.0 * p[1] + (p[2] - p[0]) * f + (2.0 * p[0] - 5.0 * p[1] + 4.0 * p[2] - p[3]) * f * f + (3.0 * p[1] - p[0] - 3.0 * p[2] + p[3]) * f * f * f))
	out[0] = maxf(out[0], 0.0)
	out[3] = maxf(out[3], 0.0)
	return out

## 程序化走路：先画两条腿（远侧压暗），再画上身盖住腿根，腿两侧的东西（盾、镐把）跟着上身。
## 找不到腿的图（腿被挡住）就整张图跟着蹦。
func _draw_stride(pkey: String, pos: Vector2, height: float, mod: Color, g: PackedFloat32Array) -> void:
	var t := Art.tex(pkey)
	var d := Art.info(pkey)
	var L := leg_split(pkey)
	var k := height / float(d.h)
	var ox: float = -d.ax
	var oy: float = -d.ay
	var th: float = float(d.h)
	var sy: float = g[1]
	var sx := 1.0 - (sy - 1.0) * 0.6
	var lean: float = g[4]
	var crotch: float = oy + (float(L.cut) if not L.is_empty() else th * 0.8)
	# 整个人（贴图坐标，原点 = 脚底锚点）：绕脚底挤压 → 整体离地；上身再绕胯切变前倾
	var whole := Transform2D(Vector2(sx, 0.0), Vector2(0.0, sy), Vector2(0.0, -g[0] * th))
	var body := whole * Transform2D(Vector2(1.0, 0.0), Vector2(-lean, 1.0), Vector2(lean * crotch, 0.0))
	var base := Transform2D(0.0, Vector2(k * _face, k), 0.0, pos)
	var head := Vector2(0.0, oy)
	_head_off = (body * head - head) * Vector2(k * _face, k)
	if L.is_empty():
		draw_set_transform_matrix(base * body)
		draw_texture(t, Vector2(ox, oy), mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var w: float = L.w
	var hh: float = L.h
	var gx: float = L.gx
	var top: float = L.top - 6.0       # 腿条从裆上一点开始，被上身盖住，劈腿时不露缝
	var cut: float = L.cut             # 上身画到这里，往下是会动的小腿和脚
	var l: float = L.l
	var r: float = L.r
	var stride: float = STRIDE_K * th * g[2]
	var tuck: float = TUCK_K * th * g[3]
	draw_set_transform_matrix(base)
	# 两腿一前一后：远侧（贴图左半）先画、压暗；近侧后画压在上面
	var rows := [top, cut, cut + (hh - cut) * 0.45, cut + (hh - cut) * 0.78, hh]
	for leg in [[l, gx, 1.0, mod * FAR_LEG], [gx, r, -1.0, mod]]:
		var x0: float = leg[0]
		var x1: float = leg[1]
		var foot := Vector2(stride * float(leg[2]), -tuck)
		var c: Color = leg[3]
		var cols := PackedColorArray([c, c, c, c])
		var prev_a := Vector2.ZERO
		var prev_b := Vector2.ZERO
		for j in rows.size():
			var v: float = rows[j]
			var wt := clampf((v - cut) / maxf(hh - cut, 1.0), 0.0, 1.0)
			var pa := Vector2(ox + x0, oy + v)
			var pb := Vector2(ox + x1, oy + v)
			var na := (body * pa).lerp(whole * (pa + foot), wt)
			var nb := (body * pb).lerp(whole * (pb + foot), wt)
			if j > 0:
				var v0: float = rows[j - 1]
				draw_primitive(PackedVector2Array([prev_a, prev_b, nb, na]), cols,
					PackedVector2Array([Vector2(x0 / w, v0 / hh), Vector2(x1 / w, v0 / hh), Vector2(x1 / w, v / hh), Vector2(x0 / w, v / hh)]), t)
			prev_a = na
			prev_b = nb
	# 上身 + 腿两侧不随腿动的部分
	draw_set_transform_matrix(base * body)
	draw_texture_rect_region(t, Rect2(ox, oy, w, cut), Rect2(0, 0, w, cut), mod)
	if l > 0.0:
		draw_texture_rect_region(t, Rect2(ox, oy + cut, l, hh - cut), Rect2(0, cut, l, hh - cut), mod)
	if r < w:
		draw_texture_rect_region(t, Rect2(ox + r, oy + cut, w - r, hh - cut), Rect2(r, cut, w - r, hh - cut), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 子类覆写：贴图之外的附加物（农民头顶的货、交货点蓝点）
func _art_extra(_feet: Vector2, _h: float) -> void:
	pass

## 死亡：留一具会淡出的尸体（Goo 是一滩黏液），纯视觉
func _death_fx() -> void:
	var key := _art_key()
	if key == "" or not Art.enabled or is_queued_for_deletion():
		return
	var par := get_parent()
	if key in BLOBS:
		var tint: Color = {"runner": Color(0.75, 0.6, 1.15), "brute": Color(0.85, 0.72, 0.6)}.get(key, Color.WHITE)
		Fx.spawn(par, "splat", position + Vector2(0, radius * 0.55), {"size": 34.0 * ART_H[key] / 19.0, "life": 1.2, "color": tint})
	if Art.has("units/%s_dead" % key):
		Fx.spawn(par, "corpse", position + Vector2(0, radius * 0.55), {"key": "units/%s_dead" % key, "size": ART_H.get(key, 44.0) * pose_scale(key, "units/%s_dead" % key), "flip": _face < 0.0, "life": 1.8})

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
