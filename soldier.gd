extends Unit
class_name Soldier
## 战斗单位：剑士（近战肉盾）/ 弓手（远程脆皮）。
## 自动索敌开打；玩家右键点敌人 = 优先追杀目标。

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

func _step(delta: float) -> void:
	_cd = max(0.0, _cd - delta)
	_scan_t -= delta
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
			if _cd <= 0.0:
				_cd = attack_cooldown
				attack_anim = 1.0    # 挥刀/拉弓动画
				t.take_damage(attack_damage, self)
				attack_fx_to(t.position)
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
func _on_stuck() -> void:
	if _amove_dest != Vector2.ZERO and position.distance_to(_amove_dest) > 60.0:
		_go(_amove_dest)
		return
	_amove_dest = Vector2.ZERO
	_ignore_aggro = false
	move_target = position

## ---------- 指令 ----------
func command_attack(t: Node2D) -> void:
	attack_target = t
	_ignore_aggro = false
	move_target = t.position
	_path = _find_path(t.position)
	_path_idx = 0

func command_move(pos: Vector2) -> void:
	super(pos)
	attack_target = null
	_auto_target = null
	_amove_dest = Vector2.ZERO
	_ignore_aggro = true

## A 移动：走向目的地，路上索敌圈内遇敌自动开打，打完继续赶路
func command_attack_move(pos: Vector2) -> void:
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
