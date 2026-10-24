extends Unit
class_name Worker
## 工人：可操控的"供应链"。采资源 -> 物理扛回基地，资源不会凭空入账。
## 也能进熔炉/木工台当工人：守线读条、把成品扛回仓库、顺路从仓库扛原料（State.OPERATE）。
## 还能去野地捡宝箱 / 遗物（State.FETCH）：走过去弯腰扛起来，扛回基地 / 仓库 / 前哨才算到手；半路被打死就掉在原地。
## 警钟（State.SHELTER）：放下手上的活，跑进最近有空位的基地 / 仓库 / 前哨 / 箭塔躲着；解除后接着干原来的活。
## 自保（flee_to）：被怪近身（或被咬了一口）自动跑到最近的房子墙边，怪走远了自己回去接着干——不用玩家点名。

enum State { IDLE, TO_NODE, GATHERING, TO_BASE, OPERATE, FETCH, SHELTER }

const CARRY_CAP := 10.0
const GATHER_RATE := 4.0     # 每秒采集量

## 研究过手推车 / 精工工具就多扛、采得快（见 tech.gd）
static func carry_cap() -> float:
	return CARRY_CAP * (Tech.CART_MULT if Tech.has("up_cart") else 1.0)

static func gather_rate() -> float:
	return GATHER_RATE * (Tech.TOOLS_MULT if Tech.has("up_tools") else 1.0) * Relic.gather_mult()

var state: int = State.IDLE
var node_target: ResNode = null
var carry_kind: String = ""       # "" / "ore" / "wood"
var carry_amount: float = 0.0
## 玩家手动指定的交货点（null = 自动：就近仓库/基地）。
## 加工厂不会自动抢货——全自动加工会把原料烧光，连农民都造不出来；
## 想加工就得玩家自己圈农民右键加工厂，这个选择权在玩家手上。
var deliver_to: Building = null
var _want_kind := ""    # 玩家最后派的工种（先回去交旧货时记着，交完按它找下一处）
## 加工线岗位：在哪条线上干活、干到哪一步
var work_at: Building = null
var op_phase := ""      # go（回工位，可能扛着原料）/ work（守线干活）/ trip（扛成品去仓库、顺路取料）
var _op_think := 0.0
var _op_stuck_n := 0
var _op_stuck_at := Vector2.INF
var _op_back := false    # 守线时被挤开、正在走回工位
## 捡宝：去哪件、手上扛着哪件（{kind, loot, relic}；空 = 没扛）
const PICK_TIME := 0.8   # 弯腰扛起来要多久

## ---------- 自保：怪靠近就撤，危险过去再回来 ----------
## 跟警钟（B）分工：警钟是玩家下令、全城进屋（绝对安全，但自己不干活）；
## 这里是被动反射——只有身边那几只自己跑，跑到最近的房子墙边贴着，不动其他人的活儿
const FLEE_R := 95.0          # 这个圈里有怪 = 放下活开跑
const FLEE_SAFE_R := 260.0    # 怪退出这个圈 = 安全，回去接着干
const FLEE_MAX_T := 9.0       # 最多躲这么久（怪卡在房子后面看不见时也能自己回去）
const FLEE_SPEED := 1.35      # 逃跑时腿快 35%
## 躲到离墙点这么近就算站稳了。别小步追到 2px：
## 门口是队友送货的必经之路，被挤开两三像素就回头走一步，
## 再配上"靠右让路"的偏航，屏幕上就是在门口一直转圈
const FLEE_ARRIVE := 24.0

var flee_to := Vector2.INF    # INF = 没在逃
var _flee_t := 0.0

func is_fleeing() -> bool:
	return flee_to != Vector2.INF

func flee_time() -> float:
	return _flee_t

## 起跑：跑到最近的基地/仓库/前哨/箭塔墙边（不进屋——进屋是警钟的事）
func start_flee() -> void:
	if dead or is_garrisoned() or state == State.SHELTER or flee_to != Vector2.INF:
		return
	var b := _nearest_safe()
	if b == null:
		return    # 附近一座自己的房子都没有：只能听天由命
	_remember_job()
	_leave_work()    # 加工线的工位先让出来，别占着炉子不干活
	waypoints.clear()
	fetch_target = null
	_pick_t = 0.0
	var away := (position - b.position)
	away = away.normalized() if away.length() > 0.001 else Vector2(0, 1)
	# 沿墙拉开一点：几个人一起躲别都挤在同一个点上（按自己的车道角选左右）
	var tangent := Vector2(-away.y, away.x)
	var side := 1.0 if _lane_off.dot(tangent) >= 0.0 else -1.0
	var slide := tangent * side * (10.0 + _lane_off.length() * 4.0)
	flee_to = b.position + away * (b.size * 0.5 + 30.0) + slide
	_flee_t = 0.0
	move_target = flee_to
	_path = _find_path(flee_to)
	_path_idx = 0

func _step_flee(delta: float) -> void:
	_flee_t += delta
	if state == State.SHELTER:
		flee_to = Vector2.INF    # 玩家敲了警钟：交给屋里那套
		return
	# 到墙根了：站着等，别再一步步追那个点（被挤开一点点也接着站）。
	# 只靠这个死区、不另记"已经站好"：死区是自适应的，万一被挤远了会自己走回来
	if position.distance_to(flee_to) <= FLEE_ARRIVE:
		move_target = position
		_path = PackedVector2Array()
		_path_idx = 0
		return
	_move_toward(flee_to, delta * FLEE_SPEED)

## 收工前的保险：原来那份活还在怪跟前就别回去。
## 只看"怪离我多远"是不够的——躲到墙根以后离怪自然就远了，于是收工往回走，
## 走回矿堆又近到 95 以内再跑，位置在矿堆和基地之间无限往返，看着就是在门口打转
func _resume_point() -> Vector2:
	var r := _resume
	var wa = r.get("work_at")
	if is_instance_valid(wa) and wa is Building:
		return wa.position
	var f = r.get("fetch")
	if is_instance_valid(f) and f is Treasure:
		return f.position
	var n = r.get("node")
	if is_instance_valid(n) and n is ResNode:
		return n.position
	var mv = r.get("move")
	if mv is Vector2 and mv != Vector2.INF:
		return mv
	return Vector2.INF

## 干活的地方有没有怪（没有活 = 没有地方，返回 false）
func _job_unsafe() -> bool:
	var p := _resume_point()
	if p == Vector2.INF:
		return false
	for e in _group("enemies"):
		if is_instance_valid(e) and e.get("dead") != true and e.position.distance_to(p) < FLEE_R:
			return true
	return false

## 危险过去了：回去接着干原来的活（采原来那处 / 回加工线 / 先把手上的货交了）
func end_flee() -> void:
	if flee_to == Vector2.INF:
		return
	if _job_unsafe():
		return    # 矿堆上还站着怪：在墙根接着等，别出去两秒又被吓回来
	flee_to = Vector2.INF
	_flee_t = 0.0
	_path = PackedVector2Array()
	_path_idx = 0
	move_target = position
	_resume_work()

func _nearest_safe() -> Building:
	var best: Building = null
	var best_d := INF
	for b in _group("buildings"):
		if not is_instance_valid(b) or b.team != 0:
			continue
		if b.kind not in ["base", "warehouse", "outpost", "tower"]:
			continue
		var d := position.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

var fetch_target: Treasure = null
var treasure := {}
var _pick_t := 0.0
var _claim_t := 0.0
## 警钟：占了位子正往那儿跑的房子 / 躲在哪座房子里（躲着时节点藏起来、停处理、不在 units 组）
var shelter_at: Building = null
var shelter_in: Building = null
var _shelter_wait: Building = null    # 哪儿都满了：在这座门口等空位
var _shelter_t := 0.0
var _resume := {}                     # 躲之前在干什么（警报解除后接着干）

func _ready() -> void:
	super()
	hp = 30.0
	max_hp = 30.0
	speed = 85.0
	radius = 7.5
	body_color = Color(0.95, 0.78, 0.2)
	display_name = "农民"

func _step(delta: float) -> void:
	# 正在躲怪：这一帧只管跑，别的状态机都停摆（跑到了就贴着房子等）
	if flee_to != Vector2.INF:
		_step_flee(delta)
		return
	match state:
		State.TO_NODE:
			if node_target == null or not is_instance_valid(node_target):
				node_target = _nearest_node(carry_kind)
				if node_target == null:
					state = State.IDLE
					move_target = position
				else:
					# 换了矿点必须重新寻路：旧路径通往被采空的那个点，不重算会先白跑过去
					_path = _find_path(node_target.position)
					_path_idx = 0
				return
			_move_toward(node_target.position, delta)
			# 到达判定必须用真实距离：_move_toward 的返回值是"到当前路径点"的距离，
			# 路径拐点/起点格心离工人常小于 24px，用它判定会半路误入采集。
			# 实心的树/矿（随机图）人进不去，贴到格子边上就算到
			if position.distance_to(node_target.position) < _reach(node_target):
				state = State.GATHERING

		State.GATHERING:
			if node_target == null or not is_instance_valid(node_target):
				_after_node_gone()
				return
			# 保险：离资源点太远却处于采集中 = 误判，重新走过去
			if position.distance_to(node_target.position) > _reach(node_target) + 24.0:
				state = State.TO_NODE
				_path = _find_path(node_target.position)
				_path_idx = 0
				return
			# 实采量 = min(采集速度, 剩余储量, 背包余量)：
			# 以前最后一下会超采（储量扣成负数，背包照涨，多人同采时更明显），
			# 背包满的那一帧又会多扣储量
			var cap := carry_cap()
			var take := minf(gather_rate() * delta, minf(node_target.amount, cap - carry_amount))
			carry_amount += maxf(take, 0.0)
			node_target.amount -= maxf(take, 0.0)
			if node_target.amount <= 0.001:
				node_target.deplete()    # 扬尘 + 树桩，格子变回空地
				node_target = null
			if carry_amount >= cap:
				_back_to_base()
			elif node_target == null:
				_after_node_gone()

		State.TO_BASE:
			var depot := _depot()
			if depot == null:
				state = State.IDLE
				return
			if depot != _path_depot:
				_repath(depot)    # 收货点变了（原来的被拆/新盖了更近的仓库）：按新地址重新寻路
			_move_toward(depot.position, delta)
			# 同 TO_NODE：用真实距离判定到收货点，路径拐点会让 _move_toward 返回值提前小于 50
			if position.distance_to(depot.position) < 50.0:
				# 加工厂：对口的原料卸进料场（等工人加工，不直接入账）；
				# 不对口的（木材送熔炉）/ 料场满了放不下的，照原料入库
				var game := get_tree().get_first_node_in_group("game")
				if game and carry_amount > 0.0:
					var rest := carry_amount
					if _output_kind(depot) == "":
						var used: float = depot.put_input(carry_amount)
						rest -= used
						if used >= 0.5:
							Fx.spawn(get_parent(), "floater", position + Vector2(0, -34), {"life": 1.1,
								"text": "料场 +%d" % int(round(used)), "color": Color(0.9, 0.85, 0.75)})
					if rest > 0.0:
						game.economy.add(carry_kind, rest)
						_floater(rest, carry_kind)
				carry_amount = 0.0
				# 扛回来的宝箱 / 遗物：到手。原来在采的那处还在就接着采，否则原地待命（不自动乱派）
				if not treasure.is_empty():
					_claim(depot)
					if node_target == null or not is_instance_valid(node_target):
						state = State.IDLE
						move_target = position
						_path = PackedVector2Array()
						_path_idx = 0
						return
				# 换工种的农民交完货要按新岗位认货种，否则"扛着木材去挖矿"会把木材记成矿石。
				# node_target 空了就保持原货种，好让它接着找同类的下一处（树砍完换棵树）
				if is_instance_valid(node_target):
					carry_kind = node_target.kind
				elif _want_kind != "":
					carry_kind = _want_kind    # 派去的矿点在回程路上被采空了：照新工种找下一处，别回去砍树
				if node_target == null or not is_instance_valid(node_target):
					node_target = _nearest_node(carry_kind)
				if node_target == null:
					state = State.IDLE
				else:
					state = State.TO_NODE
					# 交货后必须重新寻路：_path 已走完被清空，直线走会被河/障碍卡死
					_path = _find_path(node_target.position)
					_path_idx = 0
		State.OPERATE:
			_step_operate(delta)
		State.FETCH:
			_step_fetch(delta)
		State.SHELTER:
			_step_shelter(delta)
		_:
			# 空闲：执行玩家的移动指令（没有就原地站着）
			_move_toward(move_target, delta)
			# 扛着宝贝被手动带到收货点旁边：放下就算到手
			_claim_t -= delta
			if _claim_t <= 0.0 and not treasure.is_empty():
				_claim_t = 0.5
				var st := _store()
				if st != null and position.distance_to(st.position) < 60.0:
					_claim(st)

## 入账漂字（纯视觉；零头不弹"+0"）
func _floater(n: float, k: String) -> void:
	if n < 0.5:
		return
	Fx.spawn(get_parent(), "floater", position + Vector2(0, -34), {"life": 1.1,
		"text": "+%d %s" % [int(round(n)), Economy.KIND_SHORT.get(k, k)],
		"color": Color(1.0, 0.86, 0.3) if k in ["ore", "ingot"] else Color(0.65, 1.0, 0.45)})

## ---------- 加工线工人 ----------
## 进厂：工位在建筑门口。手上有对口原料就顺手带进料场；扛着别的货先交回仓库再上岗。
func command_operate(b: Building) -> bool:
	if b == null or not is_instance_valid(b) or not b.is_processor():
		return false
	_drop_shelter()
	if work_at == b and state == State.OPERATE:
		return true
	_leave_work()
	if not b.add_operator(self):
		return false
	work_at = b
	state = State.OPERATE
	node_target = null
	deliver_to = null
	_want_kind = ""
	if (carry_amount >= 0.5 and carry_kind != b.recipe().in) or not treasure.is_empty():
		_op_trip(false)    # 扛着别的货 / 宝贝：先送回仓库
	else:
		_op_go()
	return true

## 离岗（被派去干别的 / 放人）：手上的货留着，下一份差事自己处理
func _leave_work() -> void:
	if work_at != null and is_instance_valid(work_at):
		work_at.remove_operator(self)
	work_at = null
	op_phase = ""
	if state == State.OPERATE:
		state = State.IDLE
		move_target = position
		_path = PackedVector2Array()
		_path_idx = 0

## 厂子没了（被打爆/被拆）：手上有货送回仓库，空手原地待命
func _lose_work() -> void:
	work_at = null
	op_phase = ""
	if carry_amount >= 0.5:
		_back_to_base()
	else:
		state = State.IDLE
		move_target = position
		_path = PackedVector2Array()
		_path_idx = 0

func _op_go() -> void:
	op_phase = "go"
	if is_instance_valid(work_at):
		_path = _find_path(work_at.work_spot(self))
		_path_idx = 0

## 出门跑一趟：take_out = 顺手把门口的成品扛上（一次最多 LOAD）
func _op_trip(take_out: bool) -> void:
	if take_out and carry_amount < 0.5 and is_instance_valid(work_at):
		var n: float = work_at.take_output(Building.LOAD)
		if n > 0.0:
			carry_kind = work_at.recipe().out
			carry_amount = n
	op_phase = "trip"
	_repath(_store())

func _step_operate(delta: float) -> void:
	var b := work_at
	if b == null or not is_instance_valid(b) or b.is_queued_for_deletion() or b.hp <= 0.0:
		_lose_work()
		return
	match op_phase:
		"go":
			var spot := b.work_spot(self)
			_move_toward(spot, delta)
			if position.distance_to(spot) < 10.0:
				_op_arrive(b)
		"trip":
			var st := _store()
			if st == null:
				_op_go()
				return
			if st != _path_depot:
				_repath(st)
			_move_toward(st.position, delta)
			if position.distance_to(st.position) < 50.0:
				_op_at_store(b)
		_:
			# 守线：被人挤开了就挪回工位；每 0.3 秒看一眼要不要出门
			var spot := b.work_spot(self)
			var off := position.distance_to(spot)
			if off > 12.0:
				_op_back = true
			if _op_back:
				_move_toward(spot, delta)    # 被挤开太远才挪回去（挪就挪到位），别在工位上来回抖
				if off < 4.0:
					_op_back = false
			_op_think -= delta
			if _op_think <= 0.0:
				_op_think = 0.3
				if b.task_for(self) == "trip":
					_op_trip(true)

## 到工位：带着对口原料就卸进料场，然后开干
func _op_arrive(b: Building) -> void:
	if carry_amount >= 0.5 and carry_kind == b.recipe().in:
		carry_amount -= b.put_input(carry_amount)
	if carry_amount < 0.5:
		carry_amount = 0.0
		op_phase = "work"
		_op_think = 0.0
		_path = PackedVector2Array()
	else:
		_op_trip(false)    # 料场被送货的塞满了：剩下的扛回仓库

## 到仓库：成品入账；开着自取就顺路扛一趟原料回去（仓库留底）
func _op_at_store(b: Building) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game != null and carry_amount >= 0.5:
		game.economy.add(carry_kind, carry_amount)
		_floater(carry_amount, carry_kind)
	carry_amount = 0.0
	if not treasure.is_empty():
		var st := _store()
		if st != null:
			_claim(st)
	if game != null:
		var n: float = b.fetch_amount(self)
		if n >= 1.0:
			game.economy.spend({b.recipe().in: n})
			b.fetched_total += n
			carry_kind = b.recipe().in
			carry_amount = n
	_op_go()

## 加工线工人的"仓库"：离自己最近的仓库/基地
func _store() -> Building:
	var best: Building = null
	var best_d := INF
	for b in _group("buildings"):
		if not is_instance_valid(b) or b.team != 0:
			continue
		if b.kind != "warehouse" and b.kind != "base" and b.kind != "outpost":
			continue
		var d := position.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

## 当前干的活（信息栏用）
func job_text() -> String:
	if state == State.SHELTER:
		if is_instance_valid(shelter_at):
			return "警钟：跑去%s躲着" % shelter_at.display_name
		return "警钟：能躲的地方都满了，在门口等空位"
	if not treasure.is_empty():
		return "扛着%s回去" % ("遗物 · " + Relic.relic_name(treasure.get("relic", "")) if treasure.get("kind", "") == "relic" else "宝箱")
	if state == State.FETCH and is_instance_valid(fetch_target):
		return "去捡" + ("遗物" if fetch_target.kind == "relic" else "宝箱")
	if state == State.OPERATE and is_instance_valid(work_at):
		var what := "守线"
		if op_phase == "trip":
			what = "扛货去仓库" if carry_amount >= 0.5 else "去仓库取料"
		elif op_phase == "go":
			what = "扛料回厂" if carry_amount >= 0.5 else "回工位"
		return "%s工人 · %s" % [work_at.display_name, what]
	return ""

## ---------- 捡宝 ----------
## 右键宝箱 / 遗物：走过去扛起来再扛回去。原来在采的那处记着，送完接着采
func command_fetch(t: Treasure) -> bool:
	if t == null or not is_instance_valid(t) or t.is_queued_for_deletion():
		return false
	_drop_shelter()
	_leave_work()
	if not treasure.is_empty():
		_back_to_base()    # 一次只扛得动一件：先把手上这件送回去
		return false
	fetch_target = t
	state = State.FETCH
	_pick_t = 0.0
	move_target = t.position
	_path = _find_path(t.position)
	_path_idx = 0
	return true

func _step_fetch(delta: float) -> void:
	var t := fetch_target
	if t == null or not is_instance_valid(t) or t.is_queued_for_deletion():
		# 被别人先扛走了：原地待命
		fetch_target = null
		state = State.IDLE
		move_target = position
		_path = PackedVector2Array()
		_path_idx = 0
		return
	if position.distance_to(t.position) > Treasure.PICK_R + radius:
		_pick_t = 0.0
		_move_toward(t.position, delta)
		return
	_pick_t += delta
	if _pick_t < PICK_TIME:
		return
	treasure = t.take()
	fetch_target = null
	_back_to_base()

## 到手：交给 main 记账（宝箱开资源 / 遗物生效）
func _claim(at: Building) -> void:
	var d := treasure
	treasure = {}
	var game := get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("claim_treasure"):
		game.claim_treasure(d, at.position if at != null else position, self)

## 扛着宝贝死了：东西掉在原地，再派人来捡
func _death_fx() -> void:
	if not treasure.is_empty():
		var game := get_tree().get_first_node_in_group("game")
		if game != null and game.has_method("spawn_treasure"):
			game.spawn_treasure(treasure, position)
		treasure = {}
	super()

## 疾风靴：农民跑得快
func _terrain_speed_factor() -> float:
	return super() * Relic.speed_mult()

## ---------- 警钟：进屋躲着 ----------
func is_garrisoned() -> bool:
	return is_in_group("garrisoned")

## 敲警钟：放下手上的活跑去躲（手上的货、扛的宝贝带着走，进了收货点顺手交掉）
func seek_shelter() -> void:
	if dead or is_garrisoned():
		return
	if state != State.SHELTER:
		_remember_job()
		_leave_work()    # 加工线的工位先让出来（回来再上岗）
		waypoints.clear()
		fetch_target = null
		_pick_t = 0.0
		state = State.SHELTER
		flee_to = Vector2.INF    # 进屋了就不用再跑
	_pick_shelter()

## 记下手上在干什么：警钟躲藏 / 遇敌逃跑都用它，危险过去照原样接着干
func _remember_job() -> void:
	if not _resume.is_empty():
		return    # 已经记过一次（逃跑途中又敲警钟），别把"逃跑"记成原来的活
	match state:
		State.TO_NODE, State.GATHERING, State.TO_BASE:
			_resume = {"node": node_target, "kind": _want_kind if _want_kind != "" else carry_kind}
		State.OPERATE:
			_resume = {"work_at": work_at}
		State.FETCH:
			_resume = {"fetch": fetch_target}
		_:
			_resume = {"move": move_target} if position.distance_to(move_target) > 20.0 else {}

## 警钟响着时右键基地 / 仓库 / 前哨 / 箭塔：指定躲进这座（满了返回 false，照旧自己找）
func shelter_into(b: Building) -> bool:
	if b == null or not is_instance_valid(b) or not b.can_shelter() or b.shelter_free(self) <= 0:
		return false
	if state != State.SHELTER:
		seek_shelter()
	if is_instance_valid(shelter_at) and shelter_at != b:
		shelter_at.unreserve_shelter(self)
	_go_shelter(b)
	return true

## 挑离自己最近、还有空位的避难所；全满了就去最近那座门口等着（隔一秒看一眼有没有空出来）
func _pick_shelter() -> void:
	var best: Building = null
	var best_d := INF
	var near: Building = null
	var near_d := INF
	for b in _group("buildings"):
		if not is_instance_valid(b) or not b.can_shelter():
			continue
		var d := position.distance_to(b.position)
		if d < near_d:
			near_d = d
			near = b
		if d < best_d and b.shelter_free(self) > 0:
			best_d = d
			best = b
	if is_instance_valid(shelter_at) and shelter_at != best:
		shelter_at.unreserve_shelter(self)
	if best != null:
		_go_shelter(best)
		return
	shelter_at = null
	_shelter_wait = near
	_shelter_t = 1.0
	_path = _find_path(near.position) if near != null else PackedVector2Array()
	_path_idx = 0
	move_target = near.position if near != null else position

func _go_shelter(b: Building) -> void:
	shelter_at = b
	_shelter_wait = null
	b.reserve_shelter(self)
	_path = _find_path(b.position)
	_path_idx = 0
	move_target = b.position

func _step_shelter(delta: float) -> void:
	var b := shelter_at
	if b != null and (not is_instance_valid(b) or not b.can_shelter()):
		shelter_at = null
		_pick_shelter()    # 要去的房子塌了：换一处
		b = shelter_at
	if b == null:
		_shelter_t -= delta
		if _shelter_t <= 0.0:
			_pick_shelter()
			if shelter_at != null:
				return
		var wt := _shelter_wait
		if is_instance_valid(wt) and position.distance_to(wt.position) > wt.size * 0.5 + 34.0:
			_move_toward(wt.position, delta)
		return
	_move_toward(b.position, delta)
	if position.distance_to(b.position) < b.size * 0.5 + 26.0:
		_enter_shelter(b)

## 进门：收货点顺手把货卸了（入账）、宝贝到手；箭塔不收货，攥在手里带进去
func _enter_shelter(b: Building) -> void:
	if not b.admit(self):
		shelter_at = null
		_pick_shelter()
		return
	var game := get_tree().get_first_node_in_group("game")
	if b.kind != "tower" and game != null:
		if carry_amount >= 0.5:
			game.economy.add(carry_kind, carry_amount)
			_floater(carry_amount, carry_kind)
		carry_amount = 0.0
		if not treasure.is_empty():
			_claim(b)
	shelter_at = null
	_shelter_wait = null
	shelter_in = b
	selected = false
	if game != null:
		game.selected.erase(self)
	moving = false
	_path = PackedVector2Array()
	_path_idx = 0
	position = b.position
	move_target = position
	visible = false
	remove_from_group("units")
	remove_from_group("player_units")
	add_to_group("garrisoned")
	process_mode = Node.PROCESS_MODE_DISABLED

## 出门（警报解除 / 房子塌了）：从门口冒出来；警钟还响着就去别处躲，否则接着干原来的活
func leave_shelter() -> void:
	if not is_garrisoned():
		return
	var b := shelter_in
	shelter_in = null
	var door := position + Vector2(randf_range(-14.0, 14.0), 40.0)
	if is_instance_valid(b):
		b.sheltered.erase(self)
		b.queue_redraw()    # 房顶人数牌跟着变
		door = b.position + Vector2(randf_range(-0.3, 0.3) * b.size, b.size * 0.5 + 12.0)
	var game := get_tree().get_first_node_in_group("game")
	if game != null:
		door = game.open_point(door)
	position = door
	move_target = door
	_stuck_pos = door
	_stuck_t = 0.0
	remove_from_group("garrisoned")
	add_to_group("units")
	add_to_group("player_units")
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	if game != null and game.alarm_on:
		state = State.SHELTER
		_pick_shelter()
	else:
		_resume_work()

## 警报解除：屋里的出来、路上的掉头，各回各的活
func end_alarm() -> void:
	if is_garrisoned():
		leave_shelter()
	elif state == State.SHELTER:
		if is_instance_valid(shelter_at):
			shelter_at.unreserve_shelter(self)
		shelter_at = null
		_shelter_wait = null
		_resume_work()

## 接着干躲之前的活：加工线 > 捡宝 > 手上还有货先交（交完照原来的活接着干）> 采原来那处 / 同类最近的一处 > 原来要走去哪
func _resume_work() -> void:
	var r := _resume
	_resume = {}
	state = State.IDLE
	move_target = position
	_path = PackedVector2Array()
	_path_idx = 0
	var wa = r.get("work_at")
	if is_instance_valid(wa) and wa is Building and not wa.is_queued_for_deletion() and command_operate(wa):
		return
	var f = r.get("fetch")
	if is_instance_valid(f) and f is Treasure and not f.is_queued_for_deletion() and treasure.is_empty() and command_fetch(f):
		return
	var n = r.get("node")
	if not (is_instance_valid(n) and n is ResNode and not n.is_queued_for_deletion() and n.amount > 0.001):
		n = null
	var kind: String = r.get("kind", "")
	if carry_amount >= 0.5 or not treasure.is_empty():
		node_target = n
		if kind != "":
			_want_kind = kind
		_back_to_base()
		return
	if n != null:
		command_gather(n)
	elif kind == "ore" or kind == "wood":
		var alt := _nearest_node(kind)
		if alt != null:
			command_gather(alt)
	elif r.has("move"):
		command_move(r.move)

## 玩家亲自下令（右键 / 停止 / 招工…）：不躲了，听玩家的；躲之前的活也不记了
func _drop_shelter() -> void:
	if is_instance_valid(shelter_at):
		shelter_at.unreserve_shelter(self)
	shelter_at = null
	_shelter_wait = null
	if state == State.SHELTER:
		state = State.IDLE
		move_target = position
	flee_to = Vector2.INF    # 逃跑也一起收：玩家点名就是最高优先级
	_flee_t = 0.0
	_resume = {}

## 被怪打：报警（小地图闪 + 号角，main 节流）+ 立刻自己撤（不等下一轮扫描）；躲在屋里的打不着
func take_damage(amount: float, from: Node2D = null) -> void:
	if is_garrisoned():
		return
	if not dead and team == 0 and from != null and is_instance_valid(from) and from.get("team") == 1:
		var game := get_tree().get_first_node_in_group("game")
		if game != null and game.has_method("alert_attack"):
			game.alert_attack(position, "worker")
		start_flee()
	super(amount, from)

## ---------- 指令 ----------
func command_gather(node: ResNode) -> void:
	_drop_shelter()
	_leave_work()
	# 点了树林正中间够不着的树：改派离它最近、外圈够得着的那棵
	if not node.reachable():
		var alt := _nearest_node(node.kind, node.position)
		if alt != null:
			node = alt
	node_target = node
	_want_kind = node.kind
	fetch_target = null
	# 帝国式：手上扛着别的东西被派去新岗位，先把旧货交回仓库再上岗。
	# 直接改 carry_kind 会把"木材"记成"矿石"，账就错了；扛着宝贝也先送回去
	if (carry_amount >= 0.5 and carry_kind != node.kind) or not treasure.is_empty():
		_back_to_base()
		return
	carry_kind = node.kind
	if carry_amount >= carry_cap():
		state = State.TO_BASE
		var d := _depot()
		_path = PackedVector2Array()
		_repath(d)
	else:
		state = State.TO_NODE
		_path = _find_path(node.position)
	_path_idx = 0

func command_move(pos: Vector2) -> void:
	_drop_shelter()
	_leave_work()
	super(pos)            # 先走过去
	state = State.IDLE    # 手动移动会打断采集
	node_target = null
	fetch_target = null

func command_stop() -> void:
	_drop_shelter()
	_leave_work()
	super()
	state = State.IDLE
	node_target = null
	fetch_target = null

## 只有闲着的农民才给队友让路（采集/搬运中的不动）。
## 守线的工人也让：工位就在门口，出门的搭档常从这儿过，不让就两人顶死；让完自己走回工位
func _can_yield() -> bool:
	if state == State.OPERATE:
		return op_phase == "work" and attack_target == null
	return state == State.IDLE and super()

func _done_with_order() -> bool:
	return state == State.IDLE and position.distance_to(move_target) < 20.0

## 农民当前算不算闲着（"." 键 / 闲置农民按钮找的就是这种）
func is_idle() -> bool:
	return state == State.IDLE and not moving

## 手动指派交货点：右键己方收货建筑（基地/仓库/熔炉/木工台）。
## 手上有货就立刻掉头去交；正在采集的话采完这一趟再按新地址走。
func set_deliver_to(b: Building) -> void:
	if b != null:
		_drop_shelter()    # 玩家点名送货：不躲了
	if b != null and work_at != null:
		_leave_work()    # 加工线工人被改派送货：先离岗
	deliver_to = b
	if b == null:
		if state == State.TO_BASE:
			_repath(_depot())
		return
	if state == State.TO_BASE:
		_repath(_depot())
	elif carry_amount >= carry_cap() or (state == State.IDLE and (carry_amount >= 0.5 or not treasure.is_empty())):
		_back_to_base()    # 闲着手里还有半车货（守线工人被叫走时扛着的成品）：也去交，不然一直攥在手里不入账

## 开局自动派活
func auto_assign(kind: String) -> void:
	var n := _nearest_node(kind)
	if n:
		command_gather(n)

var _path_depot: Building = null    # 当前 _path 通往的收货点

func _repath(b: Building) -> void:
	_path_depot = b
	if b == null:
		return
	_path = _find_path(b.position)
	_path_idx = 0

## 手上的资源点没了（被采空/被别人采空）：手里有货就回去交，
## 空手（刚到就被别人采完）直接去下一处同类资源，别白跑回家弹个"+0"
func _after_node_gone() -> void:
	node_target = null
	if carry_amount >= 0.5:
		_back_to_base()
		return
	node_target = _nearest_node(carry_kind)
	if node_target == null:
		if carry_amount > 0.0:
			_back_to_base()
		else:
			state = State.IDLE
			move_target = position
		return
	state = State.TO_NODE
	_path = _find_path(node_target.position)
	_path_idx = 0

## ---------- 工具 ----------
func _back_to_base() -> void:
	state = State.TO_BASE
	_repath(_depot())

## 卡住（被对向工人顶住/被人群挤住）：从当前位置重新寻路。
## 配合基类"靠右让路"，错开肩膀后就能继续走完新路径。
func _on_stuck() -> void:
	move_target = position
	match state:
		State.TO_NODE:
			if node_target != null and is_instance_valid(node_target):
				# 已经贴到跟前还挤不进去（那棵树周围站满了人）：换旁边一棵
				if node_target.solid and position.distance_to(node_target.position) < 90.0:
					var alt := _nearest_node(node_target.kind, Vector2.INF, node_target)
					if alt != null and alt.position.distance_to(node_target.position) < 160.0:
						node_target = alt
				_path = _find_path(node_target.position)
				_path_idx = 0
		State.TO_BASE:
			var b := _depot()
			if b != null:
				_repath(b)
		State.FETCH:
			if is_instance_valid(fetch_target):
				_path = _find_path(fetch_target.position)
				_path_idx = 0
		State.SHELTER:
			var sb: Building = shelter_at if is_instance_valid(shelter_at) else _shelter_wait
			if is_instance_valid(sb):
				if sb == shelter_at and position.distance_to(sb.position) < sb.size * 0.5 + 48.0:
					_enter_shelter(sb)    # 门口挤满了人：就地算进门
					return
				_path = _find_path(sb.position)
				_path_idx = 0
		State.OPERATE:
			if not is_instance_valid(work_at):
				return
			var spot: Vector2 = work_at.work_spot(self)
			if op_phase == "go" and position.distance_to(spot) < 24.0:
				_op_arrive(work_at)    # 工位旁边被人挤着进不去：就地算到岗
				return
			var goal: Vector2 = spot
			if op_phase == "trip":
				var st := _store()
				if st == null:
					return
				_repath(st)
				goal = st.position
			else:
				_path = _find_path(spot)
				_path_idx = 0
			if op_phase == "work":
				return    # 守线时被挤住：按新路走回工位就行，别往侧面乱绕
			# 连着卡两回（同一处被人/墙角顶住）：先往侧面绕一步再走
			_op_stuck_n = _op_stuck_n + 1 if position.distance_to(_op_stuck_at) < 12.0 else 1
			_op_stuck_at = position
			if _op_stuck_n >= 2:
				var dir := (goal - position).normalized()
				var side := Vector2(-dir.y, dir.x) * (1.0 if randf() < 0.5 else -1.0)
				_path.insert(0, position + side * 22.0 - dir * 6.0)
				_path_idx = 0
		_:
			pass

## 收货点：玩家指派 > 就近仓库/基地。
## 加工厂故意不参与自动挑选：以前"有熔炉就一定送熔炉"，结果木材全变木板，
## 造农民要的 30 木永远攒不出来。现在只有玩家点名，原料才进加工线。
func _depot() -> Building:
	if deliver_to != null and is_instance_valid(deliver_to) and deliver_to.team == 0 and (treasure.is_empty() or not deliver_to.is_processor()):
		return deliver_to
	# 自动：在仓库和基地里挑最近的——仓库盖得远就没意义了
	return _store()

## 交货后记成什么账："" = 对口原料卸进加工厂料场（等工人加工），否则原样入库（保住原料）
func _output_kind(depot: Building) -> String:
	if depot.is_processor() and carry_kind == depot.recipe().in:
		return ""
	return carry_kind

## 是不是正在给某种原料跑采集（右键加工厂时：采对口原料的 = 送货工，其余的 = 进厂当工人）
func feeds(kind: String) -> bool:
	return state in [State.TO_NODE, State.GATHERING, State.TO_BASE] and carry_kind == kind

## 队里最近的某类己方设施
func _nearest_kind(kind: String) -> Building:
	var best: Building = null
	var best_d := INF
	for b in _group("buildings"):
		if not is_instance_valid(b) or b.team != 0 or b.kind != kind:
			continue
		var d := position.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

## 离 from（默认自己）最近的同类资源点；树林里面够不着的树跳过，except 也跳过（卡住时换一棵）。
## Goo 据点还守着的富矿也跳过（自动派活别把农民送进野怪窝）——除非人已经在那片矿上了（玩家自己派过去的）
func _nearest_node(kind: String, from := Vector2.INF, except: ResNode = null) -> ResNode:
	var o := position if from == Vector2.INF else from
	var best: ResNode = null
	var best_d := INF
	for n in _group("res_nodes"):
		# 跳过已采空、等待销毁的资源点，别白跑一趟
		if n.kind == kind and n != except and n.amount > 0.001 and not n.is_queued_for_deletion():
			var d := o.distance_to(n.position)
			if d < best_d and n.reachable() and not (n.rich and d > GUARDED_SKIP_R and n.guarded()):
				best_d = d
				best = n
	return best
const GUARDED_SKIP_R := 260.0

## 走到离资源点多近算到：实心的（占格的树/矿）人站在旁边格子里，放宽到 40
static func _reach(n: ResNode) -> float:
	return 40.0 if n.solid else 24.0

## ---------- 贴图版 ----------
func _art_key() -> String:
	return "worker"

func _working_line() -> bool:
	return state == State.OPERATE and op_phase == "work" and is_instance_valid(work_at) and work_at.batch_on

func _art_pose() -> String:
	if state == State.GATHERING:
		return "act" if sin(anim_t * 0.9) > 0.0 else "idle"
	if _working_line():
		return "act" if sin(anim_t * (0.9 if work_at.kind == "smelter" else 1.5)) > 0.0 else "idle"
	if state == State.FETCH and _pick_t > 0.0:
		return "act"    # 弯腰扛
	if (carry_amount > 0.5 or not treasure.is_empty()) and moving:
		return "carry"
	return "idle"

func _face_x() -> float:
	if state == State.GATHERING and is_instance_valid(node_target):
		return node_target.position.x
	if state == State.OPERATE and op_phase == "work" and is_instance_valid(work_at):
		return work_at.position.x
	return NAN

func _art_extra(feet: Vector2, h: float) -> void:
	if state == State.SHELTER or is_fleeing():
		# 警钟响着还在外面跑 / 被怪盯上正在撤：头顶一个红"!"
		Art.text(self, feet - Vector2(0, h + 7.0) + _head_off, "!", 15, Color(1.0, 0.42, 0.3))
	if is_instance_valid(deliver_to):
		# 脚下亮蓝点 = 玩家手动指派过交货点
		Art.ellipse(self, feet + Vector2(0, 1), 4.0, Color(0.2, 0.15, 0.1))
		Art.ellipse(self, feet + Vector2(0, 1), 3.0, Color(0.35, 0.82, 1.0))
	elif state == State.OPERATE:
		# 脚下橙点 = 加工线工人
		Art.ellipse(self, feet + Vector2(0, 1), 4.0, Color(0.2, 0.15, 0.1))
		Art.ellipse(self, feet + Vector2(0, 1), 3.0, Color(1.0, 0.62, 0.2))
	if not treasure.is_empty():
		# 扛着宝箱 / 遗物：顶在头上（比资源大一圈，远远就看得出谁扛着宝贝）
		Treasure.draw_icon(self, treasure, feet - Vector2(-_face * 1.0, h - 3.0) + _head_off, 15.0)
	elif carry_amount > 0.5:
		var item := "items/" + carry_kind if Art.has("items/" + carry_kind) else "items/ore"
		var top := feet - Vector2(-_face * 1.0, h - 2.0) + _head_off    # 跟着走路一颠一颠
		Art.draw(self, item, top, 10.0)

## ---------- 绘制：KR 小人（草帽 + 镐），采集时挥镐，扛货顶头上 ----------
func _body_draw() -> void:
	# 采集中：镐跟着节奏挥
	if state == State.GATHERING or _working_line():
		attack_anim = 0.5 + 0.5 * sin(anim_t * 0.9)
	_kr_body(Color(0.7, 0.6, 0.38), Color(0.4, 0.32, 0.24), "straw", "pick")
	var s := radius / 12.0
	if is_instance_valid(deliver_to):
		# 脚下亮蓝点 = 玩家手动指派过交货点，不是自动跑腿
		_outlined_circle(Vector2(0, 14.0 * s), 2.2 * s, Color(0.35, 0.82, 1.0))
	if carry_amount > 0.5:
		var c: Color = {"ore": Color(0.85, 0.6, 0.1), "ingot": Color(0.78, 0.8, 0.85), "plank": Color(0.85, 0.68, 0.42)}.get(carry_kind, Color(0.25, 0.65, 0.3))
		_outlined_circle(Vector2(6.5 * s, -16.5 * s), 4.2 * s, c)
