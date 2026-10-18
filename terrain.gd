extends Node2D
class_name Terrain
## 地形层：网格化管理地形类型，提供 A* 寻路 + 地形效果查询。
## 格子类型：EMPTY 平地 / SHALLOW 浅水(减速) / DEEP 深水(阻挡) /
##           CLIFF 悬崖(阻挡) / FOREST 森林(减速+减射程)
## 全部代码生成，无素材。

const CELL := 32.0            # 格子边长
const GRID_W := 40            # 1280 / 32
const GRID_H := 23            # 720 / 32 向上取整

enum T { EMPTY, SHALLOW, DEEP, CLIFF, FOREST }

var grid: Array = []          # grid[y * GRID_W + x] = 地形类型 int
## 原生 A*（C++ 实现）：比 GDScript 手写版快一到两个数量级。
## 阻挡格与 grid 同步：paint() 时增量更新，不必整张重建。
var _astar := AStarGrid2D.new()
var _solid_count := 0         # 阻挡格数量：为 0 时视线检查直接放行（当前全平原）

## 当前地形层的直接引用：单位每帧查移速/射程，别再走 get_first_node_in_group
static var current: Terrain = null

func _init() -> void:
	_init_grid()

func _ready() -> void:
	add_to_group("terrain")
	current = self

func _exit_tree() -> void:
	if current == self:
		current = null

func _init_grid() -> void:
	grid.clear()
	grid.resize(GRID_W * GRID_H)
	for i in GRID_W * GRID_H:
		grid[i] = T.EMPTY
	_astar.region = Rect2i(0, 0, GRID_W, GRID_H)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.offset = Vector2(CELL * 0.5, CELL * 0.5)    # 路径点落在格心，和旧实现一致
	# 防斜穿墙角：对角移动要求两侧正交格都可走（与旧实现同规则）
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()

## 把一块矩形区域设成某种地形（x,y 为世界坐标左上角）
func paint(rect: Rect2, type: int) -> void:
	var x0 := int(rect.position.x / CELL)
	var y0 := int(rect.position.y / CELL)
	var x1 := int((rect.position.x + rect.size.x) / CELL)
	var y1 := int((rect.position.y + rect.size.y) / CELL)
	for gy in range(max(0, y0), min(GRID_H, y1 + 1)):
		for gx in range(max(0, x0), min(GRID_W, x1 + 1)):
			var was_solid := _astar.is_point_solid(Vector2i(gx, gy))
			var solid := type == T.DEEP or type == T.CLIFF
			grid[gy * GRID_W + gx] = type
			_astar.set_point_solid(Vector2i(gx, gy), solid)
			_solid_count += int(solid) - int(was_solid)

## 世界坐标 → 格子坐标
func _cell(world: Vector2) -> Vector2i:
	return Vector2i(int(world.x / CELL), int(world.y / CELL))

func in_bounds(gx: int, gy: int) -> bool:
	return gx >= 0 and gx < GRID_W and gy >= 0 and gy < GRID_H

## 查询世界坐标处的地形类型
func type_at(world: Vector2) -> int:
	var c := _cell(world)
	if not in_bounds(c.x, c.y):
		return T.EMPTY
	return grid[c.y * GRID_W + c.x]

## 该格是否可通行（阻挡 = 深水/悬崖）
func walkable(gx: int, gy: int) -> bool:
	if not in_bounds(gx, gy):
		return false
	var t: int = grid[gy * GRID_W + gx]
	return t != T.DEEP and t != T.CLIFF
## 地形对移速的倍率（浅水/森林减速）
func speed_factor(world: Vector2) -> float:
	match type_at(world):
		T.SHALLOW:
			return 0.45
		T.FOREST:
			return 0.7
		_:
			return 1.0

## 地形对射程的倍率（森林减射程）
func range_factor(world: Vector2) -> float:
	if type_at(world) == T.FOREST:
		return 0.7
	return 1.0

## ---------- A* 寻路 ----------
## 从 start 到 goal（世界坐标）返回路径点数组；不可达返回空数组。
## 格子编码统一用「行优先」：key = y * GRID_W + x，与 grid 数组下标一致。
func find_path(start: Vector2, goal: Vector2) -> PackedVector2Array:
	var s := _cell(start)
	var g := _cell(goal)
	if not walkable(s.x, s.y) or not walkable(g.x, g.y):
		return PackedVector2Array()
	if s == g:
		return PackedVector2Array([goal])
	var pts := _astar.get_point_path(s, g)
	if pts.is_empty():
		return PackedVector2Array()
	# 去掉起点格（单位已经站在里面），与旧实现输出一致
	return _smooth(start, pts.slice(1))

## 两点连线是否全程可走（沿线密集采样 + 两侧留出单位半径）
func line_walkable(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var len := d.length()
	if len < 0.001 or _solid_count == 0:
		return true
	var steps := int(ceil(len / (CELL * 0.35)))
	var perp := Vector2(-d.y, d.x).normalized() * 6.0    # 近似单位半径的横向留边
	for i in range(steps + 1):
		var p := a + d * (float(i) / steps)
		var pr := p + perp
		var pl := p - perp
		if not walkable(int(p.x / CELL), int(p.y / CELL)):
			return false
		if not walkable(int(pr.x / CELL), int(pr.y / CELL)):
			return false
		if not walkable(int(pl.x / CELL), int(pl.y / CELL)):
			return false
	return true

## 视线简化（string pulling）：从起点出发尽量直达最远的可视路径点，
## 去掉格心折线里多余的锯齿拐点，走自然的切线。
func _smooth(start: Vector2, points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var out := PackedVector2Array()
	var from := start
	var idx := 0
	var guard := 0
	while idx < points.size() and guard < 512:
		guard += 1
		var far := idx
		for j in range(points.size() - 1, idx, -1):
			if line_walkable(from, points[j]):
				far = j
				break
		out.append(points[far])
		from = points[far]
		idx = far + 1
	return out

## ---------- 绘制 ----------
func _draw() -> void:
	for gy in GRID_H:
		for gx in GRID_W:
			var t: int = grid[gy * GRID_W + gx]
			if t == T.EMPTY:
				continue
			var r := Rect2(gx * CELL, gy * CELL, CELL, CELL)
			match t:
				T.SHALLOW:
					draw_rect(r, Color(0.4, 0.65, 0.75, 0.55))
				T.DEEP:
					draw_rect(r, Color(0.22, 0.4, 0.6))
					draw_rect(r, Color(0.12, 0.25, 0.4, 0.4))
				T.CLIFF:
					draw_rect(r, Color(0.45, 0.4, 0.34))
					draw_line(r.position, r.position + r.size, Color(0.3, 0.26, 0.2), 2.0)
					draw_line(Vector2(r.position.x + r.size.x, r.position.y), Vector2(r.position.x, r.position.y + r.size.y), Color(0.3, 0.26, 0.2), 2.0)
				T.FOREST:
					draw_rect(r, Color(0.22, 0.42, 0.24, 0.35))
