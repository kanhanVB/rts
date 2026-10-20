extends Node2D
class_name ResNode
## 资源点：矿（琥珀石）/ 树（双冠小树），被工人采空就消失。
## KR 式画法：先画一层深色放大版做描边，再叠填充，最后点高光。

var kind: String = "ore"    # ore / wood
var amount: float = 250.0
var radius: float = 16.0    # 绕障用的碰撞半径
## 随机图上的树/矿是实心的：占一个地形格子（挡路、不能盖房），采空了格子变回空地。
## 经典测试图上的资源点不占格（老规矩：人能从中间穿过去）
var solid := false
var cell := Vector2i(-1, -1)
var tree_h := 66.0          # 树的显示高度（随机图上的树高矮有点差别）

func _ready() -> void:
	add_to_group("res_nodes")
	set_process(kind == "ore")    # 只有矿堆要按储量换图，树不用每帧跑
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
		var r := amount / START_AMOUNT
		return "resources/ore_full" if r > 0.66 else ("resources/ore_half" if r > 0.33 else "resources/ore_low")
	if _variant < 0:
		_variant = int(absf(position.x * 7.0 + position.y * 13.0)) % 3 + 1
	return "resources/tree_%d" % _variant

## 采矿会让矿堆变小：换档时重画
func _process(_delta: float) -> void:
	if kind == "ore":
		var k := _art_key()
		if k != _stage:
			_stage = k
			queue_redraw()

func _draw() -> void:
	var key := _art_key()
	if Art.has(key):
		Art.ellipse(self, Vector2(0, 10), 17.0, Color(0.05, 0.1, 0.02, 0.3))
		if kind == "ore":
			Art.draw_w(self, key, Vector2(0, 12), 44.0 * float(Art.info(key).w) / float(Art.info("resources/ore_full").w))
		else:
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
