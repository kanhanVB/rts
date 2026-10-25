extends Unit
class_name Engineer
## 工程师：负责建造建筑，能抡锤子自保，死后 15 秒免费复活。
## 施工优先于战斗；闲着的时候自动认领无主的工地、贴脸小范围反击、去修打坏了的房子。

enum State { IDLE, TO_SITE, BUILDING, TO_FIX, FIXING }

var state: int = State.IDLE
var build_site: ConstructionSite = null

## ---------- 修理：闲着的时候自己去修打坏了的房子 ----------
## 以前建筑一掉血就是永久残血：只能拆了重盖（还不退资源），一座被岩壳啃掉半条的箭塔
## 就废了。工程师盖完房子正好在旁边站着，是场上最闲的人。
## 不加按键：闲着、没仗打、没工地要盖，就自己去修最近该修的那座；
## 玩家选中他右键点一座受损的己方建筑也能点名（见 main._issue_command）。
const FIX_RATE := 0.06        # 每秒回最大血量的 6%（一条残血的箭塔修满约 15 秒）
const FIX_MIN := 20.0         # 缺口小于 max(这个, 12% 血) 不值当跑一趟
const FIX_GIVE_UP := 16.0     # 走了这么久还没到就不修了（隔着河 / 被顶在缝里）
const FIX_SKIP_T := 30.0      # 放弃过的房子这么多秒内不再考虑，别一直在路上折返
var fix_target: Building = null
var _fix_think := 0.0         # 多久之后再扫一遍有没有要修的
var _fix_wait := 0.0          # 这一趟已经走了多久
var _fix_fx := 0.0            # 下一次飘 "+N"
var _fix_skip: Building = null
var _fix_skip_t := 0.0
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
	_fix_skip_t = maxf(0.0, _fix_skip_t - delta)
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

		State.TO_FIX:
			if not _fix_ok():
				_drop_fix()
				return
			_fix_wait += delta
			if _fix_wait > FIX_GIVE_UP:
				# 走不到（隔着河 / 被挤在缝里顶不过去）：先不管这座，过一会儿再说
				_fix_skip = fix_target
				_fix_skip_t = FIX_SKIP_T
				_drop_fix()
				return
			_move_toward(_fix_spot(fix_target), delta)
			if position.distance_to(fix_target.position) < fix_target.size * 0.5 + 30.0:
				state = State.FIXING

		State.FIXING:
			if not _fix_ok():
				_drop_fix()
				return
			move_target = position
			# 有怪贴上来：先放下锤子。不回 IDLE 之外的地方——IDLE 那条分支会抡锤自卫，
			# 玩家也能趁机把它调走。这座房子不打标记，回头敌人没了它自己会接着修
			if _acquire_target() != null:
				_drop_fix()
				return
			var b := fix_target
			b.hp = minf(b.max_hp, b.hp + b.max_hp * FIX_RATE * delta)
			b.queue_redraw()    # 建筑平时只在挨打/选中变化时才重画，血条得跟着修涨
			if _cd <= 0.0:
				_cd = 0.4
				attack_anim = 1.0    # 抡锤
				attack_fx_to(b.position)
			_fix_fx -= delta
			if _fix_fx <= 0.0:
				_fix_fx = 0.7
				Fx.spawn(get_parent(), "floater", b.position + Vector2(0, -b.size * 0.9), {"life": 0.9,
					"text": "+%d" % maxi(1, int(round(b.max_hp * FIX_RATE * 0.7))), "color": Color(0.55, 0.95, 0.5)})
			if b.hp >= b.max_hp - 0.5:
				b.hp = b.max_hp
				_drop_fix()

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
					if not s.has_builder():
						command_build(s)
						break
			if state != State.IDLE:
				return
			# 闲着就把"要去的地方"收回脚下：不然 move_target 还停在很久以前
			# 玩家点名让他去过的那一头，_can_yield() 判"还没走到"→ 站着不给队友
			# 让路，在门口当路障（打转检测里就是这么发现他的：IDLE 却记着 1200px 外的点）
			move_target = position
			# 贴脸自卫
			var t := _acquire_target()
			if t != null:
				_fight(t, delta)
				return
			# 没仗打、也没工地要盖：看有没有打坏的房子要修。
			# 每 0.5 秒扫一次（建筑多，别每帧遍历全场）
			_fix_think -= delta
			if _fix_think <= 0.0:
				_fix_think = 0.5
				var b := _nearest_damaged()
				if b != null:
					command_fix(b)

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

## ---------- 修理 ----------
## 这座房子还值得修吗（被别人拆光 / 满血了就不修了）
func _fix_ok() -> bool:
	return fix_target != null and is_instance_valid(fix_target) and not fix_target.is_queued_for_deletion() \
		and fix_target.team == 0 and fix_target.hp < fix_target.max_hp - 0.5

## 站在房子哪一侧修：偏右下，避开加工线门口那两个工位（±size*0.3）
func _fix_spot(b: Building) -> Vector2:
	return b.position + Vector2(b.size * 0.55, b.size * 0.46)

## 放下锤子（不打"暂时别修"的标记：回头敌人走了，扫描会把它重新挑出来）
func _drop_fix() -> void:
	fix_target = null
	_fix_wait = 0.0
	if state == State.TO_FIX or state == State.FIXING:
		state = State.IDLE
		move_target = position
		_path = PackedVector2Array()
		_path_idx = 0

## 挑一座该修的房子：掉血够多才算，按"距离 - 缺口"打分（基地/前哨被打掉就输了，加权往前排）
func _nearest_damaged() -> Building:
	var best: Building = null
	var best_s := INF
	for b in _group("buildings"):
		if not is_instance_valid(b) or b.team != 0 or b.is_queued_for_deletion():
			continue
		if b == _fix_skip and _fix_skip_t > 0.0:
			continue    # 刚放弃过：走不到，别在人家的路上来回折返
		var miss: float = b.max_hp - b.hp
		if miss < maxf(FIX_MIN, b.max_hp * 0.12):
			continue
		var d: float = position.distance_to(b.position)
		var s: float = d * (0.45 if (b.kind == "base" or b.kind == "outpost") else 1.0) - miss * 2.0
		if s < best_s:
			best_s = s
			best = b
	return best

## 点名去修一座建筑（玩家右键 / 闲着自动挑的活都走这里）
func command_fix(b: Building) -> bool:
	if b == null or not is_instance_valid(b) or b.is_queued_for_deletion():
		return false
	if b.team != 0 or b.hp >= b.max_hp - 0.5:
		return false
	if fix_target == b and (state == State.TO_FIX or state == State.FIXING):
		return true    # 已经在修这座了
	_drop_site()
	attack_target = null
	move_order = false
	_amove = false
	_amove_fight = false
	fix_target = b
	_fix_wait = 0.0
	_fix_fx = 0.0
	var spot := _fix_spot(b)
	_path = _find_path(spot)
	_path_idx = 0
	move_target = spot
	state = State.TO_FIX
	return true

## 现在在修哪座（信息栏 / 测试用；没在修返回 null）
func fixing_at() -> Building:
	return fix_target if (state == State.TO_FIX or state == State.FIXING) and is_instance_valid(fix_target) else null

## ---------- 指令 ----------
func _on_stuck() -> void:
	move_target = position
	# 赶去工地路上被顶住：从当前位置重新寻路绕行
	if state == State.TO_SITE and build_site != null and is_instance_valid(build_site):
		_path = _find_path(build_site.position)
		_path_idx = 0
	elif state == State.TO_FIX and _fix_ok():
		_path = _find_path(_fix_spot(fix_target))
		_path_idx = 0

func command_build(site: ConstructionSite) -> void:
	# 手上还占着别的工地就先放回去：不然旧工地认领关系还在自己身上，
	# 别人接不了手、自己又跑来盖新的，旧工地就永远烂在那儿了
	if build_site != null and is_instance_valid(build_site) and build_site != site:
		_drop_site()
	_drop_fix()    # 有房子要盖就先去盖，修理往后排
	build_site = site
	site.assigned = self
	attack_target = null
	move_order = false
	_path = _find_path(site.position)
	_path_idx = 0
	state = State.TO_SITE

func command_attack(t: Node2D) -> void:
	_drop_fix()
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
	_drop_fix()
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
	_drop_fix()
	state = State.IDLE

func command_stop() -> void:
	super()
	_drop_site()
	_drop_fix()
	state = State.IDLE
	move_order = true     # 站住别动，别马上又去认领工地（下一次闲下来再说）
	_amove = false
	_amove_fight = false

## 只有闲着的工程师才给队友让路（施工/修理中的不动）
func _can_yield() -> bool:
	return state == State.IDLE and super()

func _done_with_order() -> bool:
	# 修理是它自己接的活：玩家下指令时不用等它修完（command_move 会把状态打断）
	if state == State.TO_FIX or state == State.FIXING:
		return not move_order and attack_target == null
	return state == State.IDLE and not move_order and attack_target == null

func _drop_site() -> void:
	if build_site != null and is_instance_valid(build_site):
		build_site.assigned = null    # 工地无主，别的工程师可以接手
	build_site = null

## 阵亡 / 被删：把手上的工地松开。
## 不松的话工地一直挂着"施工中"，而别的工程师只认 assigned == null 的工地，
## 于是谁也不会接手，那个工地就永远烂在那儿（显示施工中，进度一动不动）
func _exit_tree() -> void:
	_drop_site()

## ---------- 绘制：KR 小人（橙色工装 + 黄安全帽 + 大锤） ----------
## ---------- 贴图版 ----------
## 疾风靴：工程师也跑得快
func _terrain_speed_factor() -> float:
	return super() * Relic.speed_mult()

func _art_key() -> String:
	return "engineer"

func _face_x() -> float:
	if state == State.BUILDING and build_site != null and is_instance_valid(build_site):
		return build_site.position.x
	if state == State.FIXING and fix_target != null and is_instance_valid(fix_target):
		return fix_target.position.x
	return NAN

func _body_draw() -> void:
	_kr_body(Color(0.82, 0.46, 0.2), Color(0.35, 0.3, 0.26), "hardhat", "hammer")
