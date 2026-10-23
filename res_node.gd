extends Node2D
class_name ResNode
## 资源点：矿（琥珀石）/ 树（双冠小树），被工人采空就消失。富矿（据点守着的）泛金光、储量 600。
## KR 式画法：先画一层深色放大版做描边，再叠填充，最后点高光。

var kind: String = "ore"    # ore / wood
var amount: float = 250.0
var radius: float = 16.0    # 绕障用的碰撞半径
## 随机图上的树/矿是实心的：占一个地形格子（挡路、不能盖房），采空了格子变回空地。
## 经典测试图上的资源点不占格（老规矩：人能从中间穿过去）
var solid := false
var cell := Vector2i(-1, -1)
var tree_h := 66.0          # 树的显示高度（随机图上的树高矮有点差别）
## 富矿：Goo 据点守着的那片（金闪闪、个头大、每堆 600）。guard_at = 守它的据点位置
const RICH_AMOUNT := 600.0
var rich := false
var guard_at := Vector2.INF
var _guard_ms := -1000
var _guarded := false

func _ready() -> void:
	add_to_group("res_nodes")
	set_process(kind == "ore")    # 只有矿堆要按储量换图（富矿还要闪），树不用每帧跑
	var t := Terrain.current
	if solid and t != null:
		cell = Vector2i(int(position.x / Terrain.CELL), int(position.y / Terrain.CELL))
		t.set_cell(cell, Terrain.T.ORE if kind == "ore" else Terrain.T.TREE)

func _exit_tree() -> void:
	var t := Terrain.current
	if solid and cell.x >= 0 and t != null and is_instance_valid(t) and not t.is_queued_for_deletion():
		t.set_cell(cell, Terrain.T.EMPTY)
		var g := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
		if g != null and g.has_method("on_cell_cleared"):
			g.on_cell_cleared(cell)

## 变成富矿（add_child 之后调）：储量 600、归 camp_pos 那个据点看守
func make_rich(camp_pos: Vector2) -> void:
	rich = true
	amount = RICH_AMOUNT
	guard_at = camp_pos
	_stage = ""
	queue_redraw()

## 还有人看着吗：据点没拆、或者守军还有活着的（拆了窝剩下的守军照样守在原地）。半秒算一次
func guarded() -> bool:
	if guard_at == Vector2.INF or not is_inside_tree():
		return false
	var now := Time.get_ticks_msec()
	if now - _guard_ms < 500:
		return _guarded
	_guard_ms = now
	_guarded = false
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.kind == "camp" and b.position.distance_to(guard_at) < 4.0 and b.hp > 0.0:
			_guarded = true
			return true
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and e.get("pack_center") != null and e.pack_center.distance_to(guard_at) < 4.0:
			_guarded = true
			return true
	return false

## 采空：扬尘 + 树留个树桩，然后消失
func deplete() -> void:
	if is_queued_for_deletion():
		return
	Fx.spawn(get_parent(), "dust", position, {"size": 46.0, "life": 0.6})
	var g := get_tree().get_first_node_in_group("game")
	if kind == "wood" and g != null and g.has_method("add_stump"):
		g.add_stump(position + Vector2(0, 10))
	queue_free()

## 这堆资源有没有能站人的邻格（树林中间的树够不着，得先把外面一圈砍掉）
func reachable() -> bool:
	if not solid:
		return true
	var t := Terrain.current
	if t == null:
		return true
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var q: Vector2i = cell + d
		if t.walkable(q.x, q.y):
			return true
	return false

## ---------- 贴图版 ----------
const START_AMOUNT := 250.0
var _variant := -1
var _stage := ""

func _art_key() -> String:
	if kind == "ore":
		var r := amount / (RICH_AMOUNT if rich else START_AMOUNT)
		return "resources/ore_full" if r > 0.66 else ("resources/ore_half" if r > 0.33 else "resources/ore_low")
	if _variant < 0:
		_variant = int(absf(position.x * 7.0 + position.y * 13.0)) % 3 + 1
	return "resources/tree_%d" % _variant

## 采矿会让矿堆变小：换档时重画
func _process(_delta: float) -> void:
	if kind == "ore":
		var k := _art_key()
		if k != _stage or rich:    # 富矿的金光一闪一闪，每帧重画（全图就十几堆）
			_stage = k
			queue_redraw()

const RICH_MOD := Color(1.22, 1.02, 0.6)    # 富矿：石头泛金
## 富矿上一闪一闪的四角星（位置按矿堆坐标错开相位，不会整片同时闪）
func _sparkles(w: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var ph := fmod(position.x * 0.37 + position.y * 0.61, TAU)
	var spots := [Vector2(-0.22, -0.55), Vector2(0.2, -0.3), Vector2(0.02, -0.78)]
	for i in spots.size():
		var a := sin(t * 2.6 + ph + i * 2.1)
		if a <= 0.15:
			continue
		var c: Vector2 = Vector2(spots[i].x * w, 12.0 + spots[i].y * w * 0.5)
		var r := (2.0 + 3.2 * a) * (w / 52.0)
		var pts := PackedVector2Array()
		for k in 8:
			var rr := r if k % 2 == 0 else r * 0.28
			pts.append(c + Vector2.from_angle(k * PI / 4.0 - PI / 2.0) * rr)
		draw_colored_polygon(pts, Color(1.0, 0.98, 0.8, 0.9 * a))
		draw_circle(c, r * 0.32, Color(1, 1, 1, a))

## 每堆矿长得不太一样（按坐标算，重画也不变）：大小 0.82~1.14、左右翻、深浅，脚边撒一两块碎石
## ——一片矿看着是天然的一窝，不是同一块石头复制粘贴
var _look := {}
func _ore_look() -> Dictionary:
	if _look.is_empty():
		var r := RandomNumberGenerator.new()
		r.seed = hash(Vector2i(roundi(position.x), roundi(position.y)))
		var chips: Array = []
		for i in r.randi_range(1, 2):
			var side := -1.0 if r.randf() < 0.5 else 1.0
			chips.append({"p": Vector2(side * r.randf_range(16.0, 24.0), r.randf_range(6.0, 13.0)),
				"r": r.randf_range(2.6, 4.0), "gold": r.randf() < 0.35, "a": r.randf() * TAU})
		_look = {"s": r.randf_range(0.82, 1.14), "flip": r.randf() < 0.5, "v": r.randf_range(0.9, 1.04), "chips": chips}
	return _look

## 脚边的碎石：深色描边 + 灰石块（有的带一点琥珀矿）
func _chip(ch: Dictionary, k: float) -> void:
	var c: Vector2 = ch.p * k
	var r: float = ch.r * k
	var pts := PackedVector2Array()
	var rim := PackedVector2Array()
	for i in 5:
		var a: float = ch.a + i * TAU / 5.0
		var rr := r * (1.0 if i % 2 == 0 else 0.8)
		var d := Vector2(cos(a), sin(a) * 0.72)
		pts.append(c + d * rr)
		rim.append(c + d * (rr + 1.4))
	draw_colored_polygon(rim, Color(0.16, 0.13, 0.09))
	draw_colored_polygon(pts, Color(0.93, 0.7, 0.2) if ch.gold else Color(0.56, 0.55, 0.52))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color(1, 1, 0.9, 0.55))

func _draw() -> void:
	var key := _art_key()
	if Art.has(key):
		if kind == "ore":
			var lk := _ore_look()
			var s: float = lk.s * (1.12 if rich else 1.0)
			Art.ellipse(self, Vector2(0, 10), 17.0 * s, Color(0.05, 0.1, 0.02, 0.3))
			for ch in lk.chips:
				_chip(ch, s)
			var ow := (48.0 if rich else 44.0) * s
			var v: float = lk.v
			Art.draw_w(self, key, Vector2(0, 12), ow * float(Art.info(key).w) / float(Art.info("resources/ore_full").w),
				RICH_MOD * Color(v, v, v) if rich else Color(v, v, v), lk.flip)
			if rich:
				_sparkles(ow)
			return
		Art.ellipse(self, Vector2(0, 10), 17.0, Color(0.05, 0.1, 0.02, 0.3))
		Art.draw(self, key, Vector2(0, 12), tree_h, _variant == 2)
		return
	var dark := Color(0.16, 0.13, 0.09)
	# 软投影
	draw_set_transform(Vector2(0, 11), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 16.0, Color(0.08, 0.12, 0.05, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if kind == "ore":
		# 描边层
		draw_circle(Vector2(-4, -3), 12.0, dark)
		draw_circle(Vector2(6, 3), 9.0, dark)
		# 填充层：石座 + 两块矿
		draw_circle(Vector2(0, 4), 10.0, Color(0.5, 0.47, 0.42))
		draw_circle(Vector2(-4, -3), 10.0, Color(0.85, 0.66, 0.16))
		draw_circle(Vector2(6, 3), 7.0, Color(0.95, 0.8, 0.3))
		draw_arc(Vector2(-4, -3), 10.0, 0, TAU, 24, dark, 2.0)
		draw_arc(Vector2(6, 3), 7.0, 0, TAU, 20, dark, 2.0)
		draw_circle(Vector2(-7, -7), 2.5, Color(1, 1, 0.85, 0.85))
	else:
		# 描边层（树冠三团 + 树干）
		draw_circle(Vector2(-5, -6), 13.0, dark)
		draw_circle(Vector2(6, -3), 11.0, dark)
		draw_circle(Vector2(0, -12), 11.0, dark)
		draw_rect(Rect2(-4.5, 1, 9, 14), dark)
		# 填充层
		draw_rect(Rect2(-3, 2, 6, 12), Color(0.45, 0.3, 0.18))
		draw_circle(Vector2(-5, -6), 11.0, Color(0.3, 0.62, 0.3))
		draw_circle(Vector2(6, -3), 9.0, Color(0.34, 0.68, 0.32))
		draw_circle(Vector2(0, -12), 9.0, Color(0.38, 0.72, 0.34))
		draw_circle(Vector2(-2, -14), 2.5, Color(0.75, 0.95, 0.6, 0.7))
