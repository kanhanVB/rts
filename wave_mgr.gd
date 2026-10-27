class_name WaveManager
extends Node
## 波次系统：倒计时 → 按配表一只只放怪（不是一坨刷出来）→ 十波全清判胜。
## 三种怪：Goo（普通）、窜窜（快、脆、直冲基地）、岩壳（慢、厚、带甲、专拆箭塔）。
## 提前叫波（王国保卫战式）：倒计时没走完就放下一波，剩几秒奖励多少矿和木。

const FIRST_WAVE_AT := 60.0    # 第一波倒计时（城堡箭塔 + 首批兵刚好赶得上）
const WAVE_INTERVAL := 45.0
const MAX_WAVES := 10
const EARLY_BONUS := 0.6       # 提前叫波：每提前 1 秒奖励矿、木各这么多
## 每波的配表：[[品种, 只数], ...]，按顺序一组组出
const WAVES := [
	[["goo", 2]],
	[["goo", 3], ["runner", 2]],
	[["goo", 4], ["runner", 3]],
	[["goo", 4], ["brute", 1], ["runner", 3]],
	[["goo", 6], ["runner", 4], ["brute", 1]],
	[["runner", 5], ["goo", 6], ["brute", 2]],
	[["goo", 8], ["brute", 2], ["runner", 6]],
	[["goo", 9], ["runner", 6], ["brute", 2]],
	[["brute", 3], ["goo", 10], ["runner", 8]],
	[["goo", 12], ["runner", 8], ["brute", 4]],
]
const GAP := {"goo": 0.6, "runner": 0.35, "brute": 1.4}    # 同一波里每只之间隔几秒

var wave := 0
var wave_timer := FIRST_WAVE_AT
var _queue: Array = []     # 这一波还没放出来的怪（品种名）
var _gap_t := 0.0

func _ready() -> void:
	add_to_group("wave_mgr")

func _game() -> Node2D:
	return get_tree().get_first_node_in_group("game")

func update(delta: float) -> void:
	wave_timer -= delta
	if wave_timer <= 0.0 and wave < MAX_WAVES:
		_start_wave()
	# 按间隔一只只放
	if not _queue.is_empty():
		_gap_t -= delta
		if _gap_t <= 0.0:
			var t: String = _queue.pop_front()
			_spawn(t)
			_gap_t = float(GAP.get(t, 0.6))
	if wave >= MAX_WAVES and _queue.is_empty() and wave_enemies().is_empty():
		var g := _game()
		if g:
			g._end("win", "十波全清，守住了！")

func _start_wave() -> void:
	wave += 1
	wave_timer = WAVE_INTERVAL
	var fresh: Array = []
	for grp in WAVES[wave - 1]:
		for i in int(grp[1]):
			_queue.append(grp[0])
		if not _seen(grp[0], wave - 1) and not fresh.has(grp[0]):
			fresh.append(grp[0])
	# 头一回出现的品种：喊一嗓子说清楚它是什么、怎么对付（王国保卫战的"新敌人"提示）
	var g := _game()
	# 波次号角：每波一次，是"节奏点"。只有横幅没有声音的话，玩家在忙别的就错过了
	if g != null and g.has_method("sfx_play"):
		g.sfx_play("horn_wave")
	if g != null and not fresh.is_empty() and wave > 1:
		var parts: Array = []
		for t in fresh:
			parts.append("%s——%s" % [Goo.TYPES[t].name, Goo.TYPES[t].tip])
		g._hud_msg("第 %d 波来了新怪：%s" % [wave, "；".join(parts)])
	# 巢穴把最早断的一段土路重新踩平：你断，它填。
	# 不然挖一次沟就能让所有怪绕一辈子，这条机制就变成"一次性开关"了
	if g != null and g.has_method("road_reclaim"):
		g.road_reclaim()
		# 掘地的窝：再额外踩平一段。对这类窝来说"断道"要断两次才顶用，
		# 不然玩家学会断道之后所有巢穴都一个解法，脾气就白抽了
		var extra := 0
		for h in g.hives:
			if is_instance_valid(h) and String(h.get("persona")) == "digger":
				if g.road_reclaim(true):
					extra += 1
		if extra > 0:
			g._hud_msg("掘地的巢穴把断掉的路又接上了一段")

## 场上还活着的波次怪（据点守军不算：十波打完就赢，不用去清野）
func wave_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return is_instance_valid(e) and not (e is Goo and e.is_guard()))

## 前 n 波里出现过这个品种没有
func _seen(t: String, n: int) -> bool:
	for i in mini(n, WAVES.size()):
		for grp in WAVES[i]:
			if grp[0] == t:
				return true
	return false

## 第 i 波（1 起）的配表文字："Goo×4 窜窜×3 岩壳×1"
static func wave_text(i: int) -> String:
	if i < 1 or i > WAVES.size():
		return ""
	var counts := {}
	var order: Array = []
	for grp in WAVES[i - 1]:
		if not counts.has(grp[0]):
			order.append(grp[0])
		counts[grp[0]] = int(counts.get(grp[0], 0)) + int(grp[1])
	var parts: Array = []
	for t in order:
		parts.append("%s×%d" % [Goo.TYPES[t].name, counts[t]])
	return " ".join(parts)

## 提前叫波：还没到最后一波、倒计时还剩 2 秒以上
func can_call_early() -> bool:
	return wave < MAX_WAVES and wave_timer > 2.0

func early_bonus() -> int:
	return int(maxf(wave_timer, 0.0) * EARLY_BONUS)

## 立刻放下一波，按剩余秒数奖励矿和木（不进产能统计）；返回奖励数，不能叫 = -1
func call_early() -> int:
	if not can_call_early():
		return -1
	var n := early_bonus()
	var g := _game()
	if g != null:
		g.economy.ore += n
		g.economy.wood += n
	_start_wave()
	return n

func spawning() -> bool:
	return not _queue.is_empty()

## 孵化：从**指定**巢穴派一队走土路。不算波次、不进 _queue，
## 所以 wave_enemies() 照样把它算成"场上的怪"——它不是守军，清掉才算完
func spawn_brood(h: Node2D, kinds: Array) -> Array:
	var g := _game()
	var made: Array = []
	if g == null or h == null or not is_instance_valid(h):
		return made
	var rd: Array = g.road_for(h)
	var out_dir := Vector2(0, 1)
	if rd.size() >= 2:
		out_dir = (rd[maxi(rd.size() - 6, 0)] - h.position).normalized()
	for t in kinds:
		var goo := Goo.make(t)
		goo.position = h.position + out_dir * randf_range(60.0, 90.0) \
			+ out_dir.orthogonal() * randf_range(-40.0, 40.0)
		g.add_child(goo)
		goo.max_hp *= 1.0 + 0.06 * maxf(wave - 1, 0)
		goo.hp = goo.max_hp
		# 疾行的窝：它派出来的怪整条路都跑得更快（不止波次怪，孵出来的也一样，
		# 不然"这窝的怪更快"这句提示会在孵化的那一窝上当场失效）
		var hb := h as Building
		if hb != null:
			goo.speed *= hb.lane_speed_mult()
		goo.start_lane(rd)
		made.append(goo)
	return made

## 每只怪轮流从还活着的巢穴出来，沿那个巢穴自己的土路走
var _spawn_i := 0

func _spawn(t: String) -> Goo:
	var g := _game()
	if g == null:
		return null
	var alive: Array = g.hives.filter(func(h): return is_instance_valid(h))
	if alive.is_empty():
		return null
	var h: Node2D = alive[_spawn_i % alive.size()]
	_spawn_i += 1
	var goo := Goo.make(t)
	var rd: Array = g.road_for(h)
	# 出生点：巢穴脚下朝路的方向偏一点（别刷在巢穴背后的林子里）
	var out_dir := Vector2(0, 1)
	if rd.size() >= 2:
		out_dir = (rd[maxi(rd.size() - 6, 0)] - h.position).normalized()
	goo.position = h.position + out_dir * randf_range(60.0, 90.0) + out_dir.orthogonal() * randf_range(-40.0, 40.0)
	g.add_child(goo)
	# 血量每波 +6%：后期光靠堆人数不够，得配弓手 / 升级箭塔
	goo.max_hp *= 1.0 + 0.06 * maxf(wave - 1, 0)
	goo.hp = goo.max_hp
	var hb2 := h as Building
	if hb2 != null:
		goo.speed *= hb2.lane_speed_mult()    # 疾行
	goo.start_lane(rd)
	return goo
