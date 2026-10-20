extends Unit
class_name Engineer
## 工程师：负责建造建筑，能抡锤子自保，死后 15 秒免费复活。
## 施工优先于战斗；闲着的时候自动认领无主的工地、贴脸小范围反击。

enum State { IDLE, TO_SITE, BUILDING }

var state: int = State.IDLE
var build_site: ConstructionSite = null
var attack_range: float = 30.0
var attack_damage: float = 6.0
var attack_cooldown: float = 0.9
var aggro_range: float = 70.0
var _cd: float = 0.0
var move_order := false   # 玩家右键点过地板：走路优先，走完再自动找活
var _amove := false       # 这趟是 A 移动：路上贴脸遇敌先打，打完接着走
var _amove_dest := Vector2.ZERO
var _amove_fight := false

func _ready() -> void:
	super()
	hp = 70.0
	max_hp = 70.0
	speed = 95.0
	radius = 9.0
	body_color = Color(0.95, 0.55, 0.2)    # 橙色，和黄色工人区分开
	display_name = "英雄·工程师"
	armor = 1.0
	atk = attack_damage
	atk_range = attack_range
	atk_cd = attack_cooldown
	add_to_group("engineers")

func _step(delta: float) -> void:
	_cd = max(0.0, _cd - delta)
	match state:
		State.TO_SITE:
			if build_site == null or not is_instance_valid(build_site):
				_drop_site()
				return
			_move_toward(build_site.position, delta)
			# 到达判定用真实距离：_move_toward 返回的是到当前路径点的距离，
			# 拐点会让它提前小于阈值，导致半路凭空开工
			if position.distance_to(build_site.position) < build_site.size * 0.5 + 30.0:
				state = State.BUILDING
		State.BUILDING:
			if build_site == null or not is_instance_valid(build_site):
				_drop_site()
				return
			# 抡锤特效
			if _cd <= 0.0:
				_cd = 0.4
				attack_anim = 1.0    # 抡锤动画
				attack_fx_to(build_site.position)
			build_site.progress += delta / build_site.build_time
			if build_site.progress >= 1.0:
				var game := get_tree().get_first_node_in_group("game")
				if game:
					get_tree().get_first_node_in_group("build_mgr").complete_site(build_site)
				build_site = null
				state = State.IDLE

		_:
			# 玩家点名要他走：走路优先，到站之前不接活
			if move_order:
				# A 移动：路上贴脸遇敌先抡锤（以前这里直接 return，A 移动 = 普通移动）
				var foe: Node2D = _acquire_target() if _amove else null
				if foe != null:
					if not _amove_fight:
						_amove_fight = true
						_path = PackedVector2Array()    # 放下行军路径直接扑过去，否则会沿旧路径走
					_fight(foe, delta)
					return
				if _amove_fight:
					_amove_fight = false
					move_target = _amove_dest
					_path = _find_path(_amove_dest)
					_path_idx = 0
				if position.distance_to(move_target) > 6.0:
					_move_toward(move_target, delta)
					return
				move_order = false
				_amove = false
				move_target = position
			# 闲逛：自动认领无主工地（玩家点名要打的目标还活着就先打完，别扔下去盖房）
			if attack_target == null or not is_instance_valid(attack_target):
				var sites := _group("sites")
				for s in sites:
					if not is_instance_valid(s):
						continue
					if s.assigned == null:
						command_build(s)
						break
			if state != State.IDLE:
				return
			# 贴脸自卫
			var t := _acquire_target()
			if t == null:
				return
			_fight(t, delta)

## 贴脸才抡锤，够不着就追
func _fight(t: Node2D, delta: float) -> void:
	var d := position.distance_to(t.position)
	if d <= attack_range:
		move_target = position
		if _cd <= 0.0:
			_cd = attack_cooldown
			attack_anim = 1.0    # 抡锤自卫
			t.take_damage(attack_damage, self)
			attack_fx_to(t.position)
	else:
		move_target = t.position
		_move_toward(move_target, delta)

## 索敌逻辑同剑士：玩家指定优先，否则找索敌圈内的 Goo
func _acquire_target() -> Node2D:
	if attack_target != null:
		if is_instance_valid(attack_target):
			return attack_target
		attack_target = null
	var best: Node2D = null
	var best_d := aggro_range
	for e in _group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best

## ---------- 指令 ----------
func _on_stuck() -> void:
	move_target = position
	# 赶去工地路上被顶住：从当前位置重新寻路绕行
	if state == State.TO_SITE and build_site != null and is_instance_valid(build_site):
		_path = _find_path(build_site.position)
		_path_idx = 0

func command_build(site: ConstructionSite) -> void:
	# 手上还占着别的工地就先放回去：不然旧工地认领关系还在自己身上，
	# 别人接不了手、自己又跑来盖新的，旧工地就永远烂在那儿了
	if build_site != null and is_instance_valid(build_site) and build_site != site:
		_drop_site()
	build_site = site
	site.assigned = self
	attack_target = null
	move_order = false
	_path = _find_path(site.position)
	_path_idx = 0
	state = State.TO_SITE

func command_attack(t: Node2D) -> void:
	attack_target = t
	move_target = t.position
	_path = _find_path(t.position)
	_path_idx = 0
	move_order = false

func command_move(pos: Vector2) -> void:
	super(pos)
	move_order = true     # 到点之前别自动接活
	_amove = false
	_amove_fight = false
	attack_target = null  # 别惦记旧目标
	_drop_site()
	state = State.IDLE

## A 移动：工程师也支持——走到目的地，贴脸遇敌抡锤自卫
func command_attack_move(pos: Vector2) -> void:
	super(pos)
	move_order = true
	_amove = true
	_amove_dest = pos
	_amove_fight = false
	attack_target = null
	_drop_site()
	state = State.IDLE

func command_stop() -> void:
	super()
	_drop_site()
	state = State.IDLE
	move_order = true     # 站住别动，别马上又去认领工地（下一次闲下来再说）
	_amove = false
	_amove_fight = false

## 只有闲着的工程师才给队友让路（施工中的不动）
func _can_yield() -> bool:
	return state == State.IDLE and super()

func _done_with_order() -> bool:
	return state == State.IDLE and not move_order and attack_target == null

func _drop_site() -> void:
	if build_site != null and is_instance_valid(build_site):
		build_site.assigned = null    # 工地无主，别的工程师可以接手
	build_site = null

## ---------- 绘制：KR 小人（橙色工装 + 黄安全帽 + 大锤） ----------
## ---------- 贴图版 ----------
func _art_key() -> String:
	return "engineer"

func _face_x() -> float:
	if state == State.BUILDING and build_site != null and is_instance_valid(build_site):
		return build_site.position.x
	return NAN

func _body_draw() -> void:
	_kr_body(Color(0.82, 0.46, 0.2), Color(0.35, 0.3, 0.26), "hardhat", "hammer")
