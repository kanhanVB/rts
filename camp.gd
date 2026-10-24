extends Building
class_name Camp
## Goo 据点（野怪小窝）：随机图上守着一片富矿。守军站在窝边不走土路，玩家的人进了警戒圈才一窝蜂扑上来，
## 追出拴绳就掉头回窝、回窝路上不理人、到家慢慢回血（守军逻辑在 enemy.gd 的"据点守军"一节）。
## 窝还在就隔一阵补一只守军；拆了窝缴获一笔矿木（剩下的守军还守在原地，清掉它们富矿才算安全）。
## 不出波次、不算胜负（只有巢穴算）：是给玩家抢的分矿，带兵清野、再在旁边盖仓库，就是 RTS 的扩张。

## 两档：近处 3 只 Goo；远处（离主城 1000 以上）再加 1 只岩壳，缴获也多
const TIERS := {
	1: {"hp": 420.0, "garrison": ["goo", "goo", "goo"], "loot": {"ore": 80, "wood": 60}},
	2: {"hp": 560.0, "garrison": ["goo", "goo", "goo", "brute"], "loot": {"ore": 150, "wood": 100}},
}
const REINFORCE := 40.0     # 守军少了：每隔这么久补一只
const NO_BUILD_R := 320.0   # 据点没拆之前，这么近不许盖房（不然箭塔贴脸白嫖守军）
const SPOT_R := 430.0       # 玩家的人走到这么近：横幅提示"发现据点"

var tier := 1
var guards: Array = []
var spotted := false
var _reinforce_t := REINFORCE
var _looted := false
var loot_mult := 1.0        # Goo 回来重新占的窝：缴获按比例打折（见 ruins.gd）

## 定档（add_child 之前调）
func setup_camp(t: int) -> void:
	tier = t if TIERS.has(t) else 1
	setup("camp")
	team = 1
	hp = float(TIERS[tier].hp)
	max_hp = hp

func garrison() -> Array:
	return TIERS[tier].garrison

func loot() -> Dictionary:
	var lt: Dictionary = TIERS[tier].loot
	if loot_mult == 1.0:
		return lt
	var out := {}
	for k in lt:
		out[k] = int(round(float(lt[k]) * loot_mult))
	return out

## 守军（已死的剔掉）
func alive_guards() -> Array:
	guards = guards.filter(func(g): return is_instance_valid(g) and not g.dead)
	return guards

## 开局把守军全刷出来（add_child 之后调，守军挂在 game 下面）
func spawn_garrison() -> void:
	var list: Array = garrison()
	for i in list.size():
		_spawn_guard(list[i], i, list.size())

## 第 i 个站岗点：窝的前面和两侧排开（不站窝背后的富矿上）
func post(i: int, n: int) -> Vector2:
	var g := get_tree().get_first_node_in_group("game")
	var away := Vector2.DOWN
	if g != null and is_instance_valid(g.get("base")):
		away = (position - g.base.position).normalized()
	var a: float = (-away).angle() + (float(i) - (n - 1) * 0.5) * 0.85
	var p := position + Vector2.from_angle(a) * (size * 0.5 + 30.0)
	return g.open_point(p) if g != null and g.has_method("open_point") else p

func _spawn_guard(t: String, i: int, n: int) -> Goo:
	var g := get_tree().get_first_node_in_group("game")
	if g == null:
		return null
	var goo := Goo.make(t)
	var home := post(i, n)
	goo.position = home
	goo.guard(position, home)
	g.add_child(goo)
	guards.append(goo)
	return goo

## 窝挨打：谁打的守军就扑谁
func take_damage(amount: float, from: Node2D = null) -> void:
	if is_queued_for_deletion():
		return
	if from != null and is_instance_valid(from) and from is Unit and from.team == 0:
		for gd in alive_guards():
			gd.alert(from)
	super(amount, from)
	if hp <= 0.0 and not _looted:
		_looted = true
		var g := get_tree().get_first_node_in_group("game")
		if g != null and g.has_method("on_camp_destroyed"):
			g.on_camp_destroyed(self)

func _process(delta: float) -> void:
	super(delta)
	var g := get_tree().get_first_node_in_group("game")
	if g == null or g.game_state != "play":
		return
	# 缺几只补几只：一次一只，隔 REINFORCE 秒；从窝口钻出来走回岗位
	var list: Array = garrison()
	if alive_guards().size() >= list.size():
		_reinforce_t = REINFORCE
		return
	_reinforce_t -= delta
	if _reinforce_t > 0.0:
		return
	_reinforce_t = REINFORCE
	var need := {}
	for t in list:
		need[t] = int(need.get(t, 0)) + 1
	for gd in guards:
		need[gd.etype] = int(need.get(gd.etype, 0)) - 1
	for i in list.size():
		if int(need.get(list[i], 0)) > 0:
			var goo := _spawn_guard(list[i], i, list.size())
			if goo != null:
				goo.position = position + Vector2(0, size * 0.45)    # 从窝口钻出来
			break

## 补下一只还要几秒（不缺人 = -1）
func reinforce_left() -> float:
	return _reinforce_t if alive_guards().size() < garrison().size() else -1.0
