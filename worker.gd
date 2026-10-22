extends Unit
class_name Worker
## 工人：可操控的"供应链"。采资源 -> 物理扛回基地，资源不会凭空入账。
## 也能进熔炉/木工台当工人：守线读条、把成品扛回仓库、顺路从仓库扛原料（State.OPERATE）。

enum State { IDLE, TO_NODE, GATHERING, TO_BASE, OPERATE }

const CARRY_CAP := 10.0
const GATHER_RATE := 4.0     # 每秒采集量

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

func _ready() -> void:
	super()
	hp = 30.0
	max_hp = 30.0
	speed = 85.0
	radius = 7.5
	body_color = Color(0.95, 0.78, 0.2)
	display_name = "农民"

func _step(delta: float) -> void:
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
			var take := minf(GATHER_RATE * delta, minf(node_target.amount, CARRY_CAP - carry_amount))
			carry_amount += maxf(take, 0.0)
			node_target.amount -= maxf(take, 0.0)
			if node_target.amount <= 0.001:
				node_target.deplete()    # 扬尘 + 树桩，格子变回空地
				node_target = null
			if carry_amount >= CARRY_CAP:
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
		_:
			# 空闲：执行玩家的移动指令（没有就原地站着）
			_move_toward(move_target, delta)

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
	if carry_amount >= 0.5 and carry_kind != b.recipe().in:
		_op_trip(false)
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
			if position.distance_to(spot) > 6.0:
				_move_toward(spot, delta)
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
		if b.kind != "warehouse" and b.kind != "base":
			continue
		var d := position.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

## 当前干的活（信息栏用）
func job_text() -> String:
	if state == State.OPERATE and is_instance_valid(work_at):
		var what := "守线"
		if op_phase == "trip":
			what = "扛货去仓库" if carry_amount >= 0.5 else "去仓库取料"
		elif op_phase == "go":
			what = "扛料回厂" if carry_amount >= 0.5 else "回工位"
		return "%s工人 · %s" % [work_at.display_name, what]
	return ""

## ---------- 指令 ----------
func command_gather(node: ResNode) -> void:
	_leave_work()
	# 点了树林正中间够不着的树：改派离它最近、外圈够得着的那棵
	if not node.reachable():
		var alt := _nearest_node(node.kind, node.position)
		if alt != null:
			node = alt
	node_target = node
	_want_kind = node.kind
	# 帝国式：手上扛着别的东西被派去新岗位，先把旧货交回仓库再上岗。
	# 直接改 carry_kind 会把"木材"记成"矿石"，账就错了
	if carry_amount >= 0.5 and carry_kind != node.kind:
		_back_to_base()
		return
	carry_kind = node.kind
	if carry_amount >= CARRY_CAP:
		state = State.TO_BASE
		var d := _depot()
		_path = PackedVector2Array()
		_repath(d)
	else:
		state = State.TO_NODE
		_path = _find_path(node.position)
	_path_idx = 0

func command_move(pos: Vector2) -> void:
	_leave_work()
	super(pos)            # 先走过去
	state = State.IDLE    # 手动移动会打断采集
	node_target = null

func command_stop() -> void:
	_leave_work()
	super()
	state = State.IDLE
	node_target = null

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
	if b != null and work_at != null:
		_leave_work()    # 加工线工人被改派送货：先离岗
	deliver_to = b
	if b == null:
		if state == State.TO_BASE:
			_repath(_depot())
		return
	if state == State.TO_BASE:
		_repath(b)
	elif carry_amount >= CARRY_CAP:
		_back_to_base()

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
	if deliver_to != null and is_instance_valid(deliver_to) and deliver_to.team == 0:
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

## 离 from（默认自己）最近的同类资源点；树林里面够不着的树跳过，except 也跳过（卡住时换一棵）
func _nearest_node(kind: String, from := Vector2.INF, except: ResNode = null) -> ResNode:
	var o := position if from == Vector2.INF else from
	var best: ResNode = null
	var best_d := INF
	for n in _group("res_nodes"):
		# 跳过已采空、等待销毁的资源点，别白跑一趟
		if n.kind == kind and n != except and n.amount > 0.001 and not n.is_queued_for_deletion():
			var d := o.distance_to(n.position)
			if d < best_d and n.reachable():
				best_d = d
				best = n
	return best

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
	if carry_amount > 0.5 and moving:
		return "carry"
	return "idle"

func _face_x() -> float:
	if state == State.GATHERING and is_instance_valid(node_target):
		return node_target.position.x
	if state == State.OPERATE and op_phase == "work" and is_instance_valid(work_at):
		return work_at.position.x
	return NAN

func _art_extra(feet: Vector2, h: float) -> void:
	if is_instance_valid(deliver_to):
		# 脚下亮蓝点 = 玩家手动指派过交货点
		Art.ellipse(self, feet + Vector2(0, 1), 4.0, Color(0.2, 0.15, 0.1))
		Art.ellipse(self, feet + Vector2(0, 1), 3.0, Color(0.35, 0.82, 1.0))
	elif state == State.OPERATE:
		# 脚下橙点 = 加工线工人
		Art.ellipse(self, feet + Vector2(0, 1), 4.0, Color(0.2, 0.15, 0.1))
		Art.ellipse(self, feet + Vector2(0, 1), 3.0, Color(1.0, 0.62, 0.2))
	if carry_amount > 0.5:
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
