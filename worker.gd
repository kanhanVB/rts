extends Unit
class_name Worker
## 工人：可操控的"供应链"。采资源 -> 物理扛回基地，资源不会凭空入账。

enum State { IDLE, TO_NODE, GATHERING, TO_BASE }

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
			# 路径拐点/起点格心离工人常小于 24px，用它判定会半路误入采集
			if position.distance_to(node_target.position) < 24.0:
				state = State.GATHERING

		State.GATHERING:
			if node_target == null or not is_instance_valid(node_target):
				_after_node_gone()
				return
			# 保险：离资源点太远却处于采集中 = 误判，重新走过去
			if position.distance_to(node_target.position) > 48.0:
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
				if not node_target.is_queued_for_deletion():
					Fx.spawn(get_parent(), "dust", node_target.position, {"size": 46.0, "life": 0.6})
					node_target.queue_free()
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
				# 加工厂把原料加工成二级材料入账，仓库/基地则原样入库（保住原料）
				var game := get_tree().get_first_node_in_group("game")
				if game and carry_amount > 0.0:
					var out_k := _output_kind(depot)
					game.economy.add(out_k, carry_amount)
					# 入账漂字（纯视觉；零头不弹"+0"）
					if carry_amount >= 0.5:
						Fx.spawn(get_parent(), "floater", position + Vector2(0, -34), {"life": 1.1,
							"text": "+%d %s" % [int(round(carry_amount)), Economy.KIND_SHORT.get(out_k, out_k)],
							"color": Color(1.0, 0.86, 0.3) if out_k in ["ore", "ingot"] else Color(0.65, 1.0, 0.45)})
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
		_:
			# 空闲：执行玩家的移动指令（没有就原地站着）
			_move_toward(move_target, delta)

## ---------- 指令 ----------
func command_gather(node: ResNode) -> void:
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
	super(pos)            # 先走过去
	state = State.IDLE    # 手动移动会打断采集
	node_target = null

## 手动指派交货点：右键己方收货建筑（基地/仓库/熔炉/木工台）。
## 手上有货就立刻掉头去交；正在采集的话采完这一趟再按新地址走。
func set_deliver_to(b: Building) -> void:
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
				_path = _find_path(node_target.position)
				_path_idx = 0
		State.TO_BASE:
			var b := _depot()
			if b != null:
				_repath(b)
		_:
			pass

## 收货点：玩家指派 > 就近仓库/基地。
## 加工厂故意不参与自动挑选：以前"有熔炉就一定送熔炉"，结果木材全变木板，
## 造农民要的 30 木永远攒不出来。现在只有玩家点名，原料才进加工线。
func _depot() -> Building:
	if deliver_to != null and is_instance_valid(deliver_to) and deliver_to.team == 0:
		return deliver_to
	# 自动：在仓库和基地里挑最近的——仓库盖得远就没意义了
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

## 交货后的产出：进加工厂才算加工，否则原样入库（保住原料）
func _output_kind(depot: Building) -> String:
	if depot.kind == "smelter" and carry_kind == "ore":
		return "ingot"
	if depot.kind == "workshop" and carry_kind == "wood":
		return "plank"
	return carry_kind

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

func _nearest_node(kind: String) -> ResNode:
	var best: ResNode = null
	var best_d := INF
	for n in _group("res_nodes"):
		# 跳过已采空、等待销毁的资源点，别白跑一趟
		if n.kind == kind and n.amount > 0.001 and not n.is_queued_for_deletion():
			var d := position.distance_to(n.position)
			if d < best_d:
				best_d = d
				best = n
	return best

## ---------- 贴图版 ----------
func _art_key() -> String:
	return "worker"

func _art_pose() -> String:
	if state == State.GATHERING:
		return "act" if sin(anim_t * 0.9) > 0.0 else "idle"
	if carry_amount > 0.5 and moving:
		return "carry"
	return "idle"

func _face_x() -> float:
	if state == State.GATHERING and is_instance_valid(node_target):
		return node_target.position.x
	return NAN

func _art_extra(feet: Vector2, h: float) -> void:
	if is_instance_valid(deliver_to):
		# 脚下亮蓝点 = 玩家手动指派过交货点
		Art.ellipse(self, feet + Vector2(0, 1), 4.0, Color(0.2, 0.15, 0.1))
		Art.ellipse(self, feet + Vector2(0, 1), 3.0, Color(0.35, 0.82, 1.0))
	if carry_amount > 0.5:
		var item := "items/ore" if carry_kind == "ore" else "items/wood"
		var top := feet - Vector2(-_face * 1.0, h - 2.0)
		Art.draw(self, item, top, 10.0)

## ---------- 绘制：KR 小人（草帽 + 镐），采集时挥镐，扛货顶头上 ----------
func _body_draw() -> void:
	# 采集中：镐跟着节奏挥
	if state == State.GATHERING:
		attack_anim = 0.5 + 0.5 * sin(anim_t * 0.9)
	_kr_body(Color(0.7, 0.6, 0.38), Color(0.4, 0.32, 0.24), "straw", "pick")
	var s := radius / 12.0
	if is_instance_valid(deliver_to):
		# 脚下亮蓝点 = 玩家手动指派过交货点，不是自动跑腿
		_outlined_circle(Vector2(0, 14.0 * s), 2.2 * s, Color(0.35, 0.82, 1.0))
	if carry_amount > 0.5:
		var c := Color(0.85, 0.6, 0.1) if carry_kind == "ore" else Color(0.25, 0.65, 0.3)
		_outlined_circle(Vector2(6.5 * s, -16.5 * s), 4.2 * s, c)
