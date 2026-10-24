extends Unit
class_name Soldier
## 战斗单位：剑士（近战肉盾）/ 弓手（远程脆皮）。
## 轻 RTS 路线（KR 式防守）：兵只听**兵营的集结点**——出厂时领一个防区站位点，
## 只在自己防区里迎击，近战 1v1 把怪钉住（怪停下互殴，谁也不许抢），打完回位；
## 没人给它岗位（手搓的兵 / 测试）或玩家强行下令过的，退回老的"自由索敌 + 追击"。

var is_ranged: bool = false
var attack_range: float = 30.0
var attack_damage: float = 12.0
var attack_cooldown: float = 0.8
var aggro_range: float = 150.0
var _cd: float = 0.0
var _amove_dest := Vector2.ZERO    # A 移动的目的地（非零表示正在 A 移动）
var _ignore_aggro := false         # 普通移动途中：不自动索敌，到站后恢复
var _engaged := false              # 上一帧是否在交战（打完后用来恢复 A 移动）
var _auto_target: Node2D = null    # 自动索敌选中的目标（有粘性）
var _scan_t := 0.0                 # 距下次重新扫描索敌的倒计时
var hold := false                  # D 原地驻守：只打够得着的，不追
var patrol := false                # F 巡逻：在两点之间来回 A 移动
var _patrol_a := Vector2.ZERO
var _patrol_b := Vector2.ZERO

## ---------- 防区站位（KR 式）----------
const PIN_RANGE := 115.0     # 防区半径：站位点这个圈里冒出没被钉住的怪，就迎上去
const POST_LEASH := 200.0    # 追出去超过离站位点这么远：松口先回位（不追到天涯）
const POST_BACK := 18.0      # 回到站位点这么近算站好
const REPATH_GAP := 20.0     # 目标挪动超过这么远才重新算路径（每帧 A* 太贵）
var post_home: Building = null    # 听哪个兵营的集结点
var post_off := Vector2.ZERO      # 相对集结点的站位偏移（一队人散开站）
var post_fixed := Vector2.INF     # 兵营没了 / 没设集结点时的落脚点
var pin_target: Node2D = null     # 正在钉的那只怪（近战 1v1）
var _hurt_target: Node2D = null   # 刚咬过我的那只：优先还手（去岗位的路上被怪拦住也打）
var _goal := Vector2.INF          # 当前在走的目的地（防区模式自己算路用）

## 兵营给的岗位：从这座兵营的集结点散开站（off = 相对集结点的偏移，集结点改了兵自动跟过去）
func set_post(b: Building, off: Vector2) -> void:
	post_home = b
	post_off = off
	post_fixed = position
	_unpin()
	attack_target = null
	_auto_target = null
	_amove_dest = Vector2.ZERO
	_ignore_aggro = false
	hold = false
	patrol = false
	waypoints.clear()
	if b != null:
		position = open_spawn(position)
	_goal = Vector2.INF

## 有没有岗位：有的走 KR 式防区，没有的走老的自由索敌
func has_post() -> bool:
	return post_home != null or post_fixed != Vector2.INF

## 站位点（集结点 + 自己的偏移；没设集结点就在兵营门口）
func post_pos() -> Vector2:
	var b := post_home
	if is_instance_valid(b):
		return b.rally_point() + post_off
	return post_fixed

## 出兵挤在墙里时挪到最近的空地上（寻路失败就原地，不影响逻辑）
func open_spawn(p: Vector2) -> Vector2:
	var g := get_tree().get_first_node_in_group("game")
	if g != null and g.has_method("open_point"):
		return g.open_point(p)
	return p

func post_text() -> String:
	if not has_post():
		return ""
	if is_instance_valid(post_home):
		return "防区：%s的集结点" % post_home.display_name
	return "防区：原地"


func setup(ranged: bool) -> void:
	is_ranged = ranged
	if ranged:
		hp = 45.0
		max_hp = 45.0
		attack_range = 140.0
		attack_damage = 8.0
		attack_cooldown = 1.2
		speed = 85.0
		radius = 7.5
		body_color = Color(0.55, 0.75, 0.95)
		display_name = "弓手"
		armor = 0.0
		atk = attack_damage
		atk_range = attack_range
		atk_cd = attack_cooldown
	else:
		hp = 85.0
		max_hp = 85.0
		attack_range = 30.0
		attack_damage = 12.0
		attack_cooldown = 0.8
		speed = 95.0
		radius = 9.0
		body_color = Color(0.3, 0.5, 0.95)
		display_name = "剑士"
		armor = 2.0
		atk = attack_damage
		atk_range = attack_range
		atk_cd = attack_cooldown
	_base = {"hp": max_hp, "atk": attack_damage, "range": attack_range, "armor": armor, "aggro": aggro_range}
	apply_techs()

## ---------- 科技加成（tech.gd）：出生时、每次研究完都按基础数值重算一遍，不会叠两次 ----------
var _base := {}
var _calm_t := 0.0    # 离开战斗多久了（挨打、出手都清零）：战地包扎按它回血

func apply_techs() -> void:
	if _base.is_empty():
		return
	var mail := Tech.has("up_mail")
	var new_max: float = _base.hp + (Tech.MAIL_HP if mail else 0.0)
	if new_max > max_hp:
		hp += new_max - max_hp    # 血上限涨了：涨的那截直接补上
	max_hp = new_max
	hp = minf(hp, max_hp)
	armor = _base.armor + (Tech.MAIL_ARMOR if mail else 0.0)
	attack_damage = _base.atk
	attack_range = _base.range
	aggro_range = _base.aggro
	if not is_ranged and Tech.has("up_blade"):
		attack_damage += Tech.BLADE_BONUS
	if is_ranged and Tech.has("up_longbow"):
		attack_damage += Tech.LONGBOW_DMG
		attack_range += Tech.LONGBOW_RANGE
		aggro_range = maxf(aggro_range, attack_range + 10.0)    # 射得远也要看得远，不然自动索敌还是 150 才开弓
	atk = attack_damage
	atk_range = attack_range

func take_damage(amount: float, from: Node2D = null) -> void:
	_calm_t = 0.0
	# 防区模式下被怪咬：记下是谁，下一帧就还手（哪怕正在走去岗位、哪怕它在防区外）
	if not dead and has_post() and from is Unit and from.team == 1:
		if position.distance_to(from.position) < PIN_RANGE:
			_hurt_target = from
	super(amount, from)
	if dead:
		_unpin()    # 死了得把钉子松开：怪才能接着往前走

## 战地包扎：脱战 MEDIC_DELAY 秒后慢慢回血
func _medic(delta: float) -> void:
	_calm_t += delta
	if hp < max_hp and _calm_t >= Tech.MEDIC_DELAY and Tech.has("up_medic") and not dead:
		hp = minf(max_hp, hp + Tech.MEDIC_RATE * delta)

## ---------- KR 式防区：只在自己这一小片地拦，近战 1v1 钉住 ----------
## 一个近战兵最多钉一只怪（怪身上 pinned_by 记着是谁），别的近战不抢；
## 弓手不钉人、也不挡路（射程内站着射，怪照样能走过去）——和 KR 里弓塔不拦路一个道理
func _step_post(delta: float) -> void:
	var home := post_pos()
	# 钉子断了（目标死了 / 走出防区太远 / 被清）：先松口
	if pin_target != null and (not is_instance_valid(pin_target) or pin_target.get("dead") == true):
		_unpin()
	var t := _pick_pin()
	if t == null:
		if position.distance_to(home) > POST_BACK:
			_walk(home, delta)     # 没仗打：走回站位点站好
		else:
			move_target = position
		return
	# 有目标：贴上去。进射程就站定输出（这就是"钉住"——怪会停下跟他对砍）
	var d := position.distance_to(t.position)
	var reach := attack_range * _terrain_range_factor()
	if d <= reach:
		move_target = position
		_calm_t = 0.0
		if _cd <= 0.0:
			_cd = attack_cooldown
			attack_anim = 1.0
			t.take_damage(attack_damage, self)
			attack_fx_to(t.position)
		return
	_walk(t.position, delta)

## 选一个钉子：刚咬我的 > 已钉住的 > 防区里最近的没被钉的怪
func _pick_pin() -> Node2D:
	var home := post_pos()
	# 正在咬我的那只优先：哪怕还没走到岗位、哪怕它在防区外面，也不能一路挨打不还手
	var hb := _hurt_target
	if hb != null and is_instance_valid(hb) and hb.get("dead") != true \
			and position.distance_to(hb.position) < PIN_RANGE * 1.4 and _can_pin(hb):
		_pin(hb)
		return hb
	_hurt_target = null
	if pin_target != null and is_instance_valid(pin_target) and pin_target.get("dead") != true:
		if pin_target.position.distance_to(home) <= POST_LEASH:
			return pin_target
		_unpin()    # 追出防区拴绳：松口回位
		return null
	pin_target = null
	var best: Node2D = null
	var best_d := INF
	for e in _group("enemies"):
		if not is_instance_valid(e) or e.get("dead") == true:
			continue
		if e.position.distance_to(home) > PIN_RANGE:
			continue        # 只打自己防区里的
		if not _can_pin(e):
			continue        # 已经有人在钉这只了：找下一只
		var d := position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		_pin(best)
	return best

## 这只怪能不能被我钉：近战 1v1 独占（弓手只输出、不占位）
func _can_pin(e: Node2D) -> bool:
	if is_ranged:
		return true
	var holder = e.get("pinned_by")
	return holder == null or holder == self or not is_instance_valid(holder)

func _pin(e: Node2D) -> void:
	pin_target = e
	attack_target = e
	_auto_target = e
	if not is_ranged:
		e.set("pinned_by", self)    # 近战独占；弓手只输出不占位

func _unpin() -> void:
	if pin_target != null and is_instance_valid(pin_target) and pin_target.get("pinned_by") == self:
		pin_target.set("pinned_by", null)
	pin_target = null
	_hurt_target = null
	if attack_target != null and not (attack_target is Building):
		attack_target = null

## 防区里走得动就行：目标挪了才重算路（每帧 A* 会把帧数吃光）
func _walk(p: Vector2, delta: float) -> void:
	if _goal.distance_to(p) > REPATH_GAP:
		_goal = p
		_path = _find_path(p)
		_path_idx = 0
	move_target = p
	_move_toward(p, delta)

## 命令卡「回位」：放弃手上的目标，走回兵营给的站位点（岗位本身不变）
func command_recall() -> void:
	_unpin()
	_auto_target = null
	_amove_dest = Vector2.ZERO
	patrol = false
	hold = false
	_goal = Vector2.INF
	move_target = position

func _step(delta: float) -> void:
	_cd = max(0.0, _cd - delta)
	_scan_t -= delta
	_medic(delta)
	# 有防区岗位：走 KR 式（只拦不追），别的一概不管
	if has_post():
		_step_post(delta)
		return
	# 帝国式移动：普通右键移动途中不被沿路敌人勾走（撤退/转进才撤得下来），
	# 到站后恢复自动索敌；玩家点名的目标和 A 移动不受影响
	var t: Node2D = null
	if not _ignore_aggro or attack_target != null:
		t = _acquire_target()
	if t:
		_engaged = true
		var d := position.distance_to(t.position)
		var reach := attack_range * _terrain_range_factor()
		if t is Building:
			reach += t.size * 0.5      # 打建筑按体量放宽射程
		if d <= reach:
			move_target = position     # 站定输出
			_calm_t = 0.0
			if _cd <= 0.0:
				_cd = attack_cooldown
				attack_anim = 1.0    # 挥刀/拉弓动画
				t.take_damage(attack_damage, self)
				attack_fx_to(t.position)
			return
		if hold:
			# 驻守：够不着就不追（敌人跑出射程也不跟），人站原地
			_engaged = false
			move_target = position
			if attack_target == t and not is_instance_valid(attack_target):
				attack_target = null
			_auto_target = null
			return
		move_target = t.position       # 追击
	elif _engaged:
		# 刚打完一仗：A 移动就接着赶路（以前会原地站死，A 移动只生效一次）
		_engaged = false
		if _amove_dest != Vector2.ZERO:
			_go(_amove_dest)
	# 没指定目标：A 移动模式下沿途索敌，遇敌开打
	if _amove_dest != Vector2.ZERO and attack_target == null:
		var e := _nearest_enemy(aggro_range)
		if e != null:
			command_attack(e)
			return
	_move_toward(move_target, delta)   # 没仗打就执行玩家的移动令
	# 到站：清掉 A 移动标记、恢复自动索敌（被人群挤住时放宽判定）
	var arrive := 12.0 if moving else 40.0
	if position.distance_to(move_target) < arrive:
		_ignore_aggro = false
		if _amove_dest != Vector2.ZERO and position.distance_to(_amove_dest) < arrive:
			_amove_dest = Vector2.ZERO
			if patrol:
				# 巡逻：到一头就掉头 A 移动去另一头
				var nxt := _patrol_a if _patrol_b.distance_to(position) < _patrol_a.distance_to(position) else _patrol_b
				command_attack_move(nxt)

func _done_with_order() -> bool:
	return _amove_dest == Vector2.ZERO and not _engaged and attack_target == null and position.distance_to(move_target) < 20.0

## 让路：还得没在打、没在 A 移动；钉着怪的时候绝对不让（让一下就被推走了）
func _can_yield() -> bool:
	if pin_target != null:
		return false
	return super() and not _engaged and _amove_dest == Vector2.ZERO

## 闲置军队（"," 键 / 闲置军队按钮）：站岗的兵不算闲着，找的是真没事干的
func is_idle() -> bool:
	if has_post():
		return false
	return _done_with_order() and not patrol and waypoints.is_empty() and not moving

func cancel_orders() -> void:
	super()
	hold = false
	patrol = false

func command_stop() -> void:
	super()
	_auto_target = null
	_amove_dest = Vector2.ZERO
	_ignore_aggro = false
	_engaged = false
	patrol = false

## D 原地驻守（老的自由模式：自己原地不动，只打够得着的）
func command_hold() -> void:
	command_stop()
	_leave_post()
	hold = true

## F 巡逻：从现在的位置到 pos 来回走，路上遇敌就打
func command_patrol(pos: Vector2) -> void:
	waypoints.clear()
	hold = false
	patrol = true
	_patrol_a = position
	_patrol_b = pos
	command_attack_move(pos)

func _nearest_enemy(dist: float) -> Node2D:
	var best: Node2D = null
	var best_d := dist
	for e in _group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	if best != null:
		return best
	# 附近没有怪，就打索敌圈里的敌方建筑（巢穴）：以前站在巢穴脚下都不会自己动手
	for b in _group("buildings"):
		if not is_instance_valid(b) or b.team != 1:
			continue
		var d: float = position.distance_to(b.position) - b.size * 0.5
		if d < best_d:
			best_d = d
			best = b
	return best

## 玩家指定的目标优先追到底；否则自动索敌。
## 自动目标有粘性：还活着且没跑出索敌圈就继续打，每 0.25 秒才重新扫一次——
## 以前每帧都换"最近的那个"，混战里会在两只 Goo 之间来回切、白跑腿
func _acquire_target() -> Node2D:
	if attack_target != null:
		if is_instance_valid(attack_target):
			return attack_target
		attack_target = null
	if _auto_target != null and is_instance_valid(_auto_target) \
			and position.distance_to(_auto_target.position) <= aggro_range * 1.2 \
			and _scan_t > 0.0:
		return _auto_target
	_scan_t = 0.25
	_auto_target = _nearest_enemy(aggro_range)
	return _auto_target

func _go(pos: Vector2) -> void:
	move_target = pos
	_path = _find_path(pos)
	_path_idx = 0

## 卡住：A 移动途中被挤住就重新寻路接着走，离终点很近就算到站
## 卡住：防区模式下清掉目标点让它重算；自由模式按 A 移动 / 到站处理
func _on_stuck() -> void:
	if has_post():
		_goal = Vector2.INF
		return
	if _amove_dest != Vector2.ZERO and position.distance_to(_amove_dest) > 60.0:
		_go(_amove_dest)
		return
	_amove_dest = Vector2.ZERO
	_ignore_aggro = false
	move_target = position

## ---------- 指令 ----------
## 玩家（或老代码）强行给令 = 脱离兵营的防区，回到"自由索敌"那套。
## UI 层已经不把移动令发给兵了（见 main._command_at），这些入口留给测试 / 特殊单位
func _leave_post() -> void:
	_unpin()
	post_home = null
	post_fixed = Vector2.INF
	_goal = Vector2.INF

func command_attack(t: Node2D) -> void:
	_leave_post()
	attack_target = t
	_ignore_aggro = false
	move_target = t.position
	_path = _find_path(t.position)
	_path_idx = 0

func command_move(pos: Vector2) -> void:
	_leave_post()
	super(pos)
	attack_target = null
	_auto_target = null
	_amove_dest = Vector2.ZERO
	_ignore_aggro = true

## A 移动：走向目的地，路上索敌圈内遇敌自动开打，打完继续赶路
func command_attack_move(pos: Vector2) -> void:
	_leave_post()
	super(pos)
	attack_target = null
	_auto_target = null
	_amove_dest = pos
	_ignore_aggro = false

## ---------- 贴图版 ----------
func _art_key() -> String:
	return "archer" if is_ranged else "swordsman"

func _art_pose() -> String:
	# 弓手：有目标就一直拉弓瞄着；剑士出手那一下换劈砍姿势
	if is_ranged and (attack_anim > 0.05 or is_instance_valid(_auto_target) or is_instance_valid(attack_target)):
		return "act"
	return "act" if attack_anim > 0.35 else "idle"

## ---------- 绘制：KR 小人（剑士铁盔配剑 / 弓手兜帽配弓） ----------
func _body_draw() -> void:
	if is_ranged:
		_kr_body(Color(0.5, 0.56, 0.6), Color(0.28, 0.3, 0.32), "hood", "bow")
	else:
		_kr_body(Color(0.44, 0.52, 0.62), Color(0.3, 0.3, 0.34), "helm", "sword")
