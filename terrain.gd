extends Node2D
class_name Terrain
## 地形层：网格化管理地形类型，提供 A* 寻路 + 地形效果查询。
## 格子类型：EMPTY 平地 / SHALLOW 浅水(减速) / DEEP 深水(阻挡) /
##           CLIFF 悬崖(阻挡) / FOREST 森林(减速+减射程) /
##           TREE 能砍的树(阻挡，砍光变平地) / WOODS 地图边缘的装饰密林(阻挡，不能砍) / ORE 矿堆(阻挡，采空变平地)
## 网格大小跟地图走：setup(宽, 高) 重新分配（经典 1280×720 = 40×23 格，随机图更大）。

const CELL := 32.0            # 格子边长
var GRID_W := 40              # 1280 / 32
var GRID_H := 23              # 720 / 32 向上取整

enum T { EMPTY, SHALLOW, DEEP, CLIFF, FOREST, TREE, WOODS, ORE }
const SHALLOW_COST := 3.0

var grid: Array = []          # grid[y * GRID_W + x] = 地形类型 int
## 建筑/工地占格（引用计数，和地形类型分开存）：>0 就挡路，A* 绕着房子走，别再直线穿墙顶死
var _occ := PackedInt32Array()
## 原生 A*（C++ 实现）：比 GDScript 手写版快一到两个数量级。
## 阻挡格与 grid 同步：paint() 时增量更新，不必整张重建。
var _astar := AStarGrid2D.new()
var _solid_count := 0         # 阻挡格数量：为 0 时视线检查直接放行（当前全平原）

## 当前地形层的直接引用：单位每帧查移速/射程，别再走 get_first_node_in_group
static var current: Terrain = null

func _init() -> void:
	_init_grid()

## 按地图像素尺寸重建网格（全部清成平地）
func setup(w_px: float, h_px: float) -> void:
	GRID_W = int(ceil(w_px / CELL))
	GRID_H = int(ceil(h_px / CELL))
	_solid_count = 0
	_init_grid()

static func is_solid_type(t: int) -> bool:
	return t == T.DEEP or t == T.CLIFF or t == T.TREE or t == T.WOODS or t == T.ORE

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
	_occ = PackedInt32Array()
	_occ.resize(GRID_W * GRID_H)
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
			set_cell(Vector2i(gx, gy), type)

## 设一个格子的地形（砍光一棵树 = 把它的格子设回 EMPTY）
func set_cell(c: Vector2i, type: int) -> void:
	if not in_bounds(c.x, c.y):
		return
	var i := c.y * GRID_W + c.x
	grid[i] = type
	_sync(c)
	# 浅滩能走但慢：寻路按 3 倍代价算，有桥就绕桥，绕太远才趟水
	_astar.set_point_weight_scale(c, SHALLOW_COST if type == T.SHALLOW else 1.0)

## 格子的阻挡状态 = 地形挡路 或 有建筑压着；和 A* 同步并维护阻挡格计数
func _sync(c: Vector2i) -> void:
	var i := c.y * GRID_W + c.x
	var was_solid := _astar.is_point_solid(c)
	var solid: bool = is_solid_type(grid[i]) or _occ[i] > 0
	if solid != was_solid:
		_astar.set_point_solid(c, solid)
		_solid_count += int(solid) - int(was_solid)

## 建筑脚下压住的格子：格心落在 ±(半边长-8) 方框里的格子（比贴图略小，单位能贴墙站），
## 至少包含建筑中心所在那格
func footprint(pos: Vector2, half: float) -> Array:
	var out: Array = []
	var h := maxf(4.0, half - 8.0)
	var x0 := int(floor((pos.x - h) / CELL - 0.5))
	var x1 := int(ceil((pos.x + h) / CELL - 0.5))
	var y0 := int(floor((pos.y - h) / CELL - 0.5))
	var y1 := int(ceil((pos.y + h) / CELL - 0.5))
	for gy in range(y0, y1 + 1):
		for gx in range(x0, x1 + 1):
			if not in_bounds(gx, gy):
				continue
			var cc := Vector2(gx + 0.5, gy + 0.5) * CELL
			if absf(cc.x - pos.x) <= h and absf(cc.y - pos.y) <= h:
				out.append(Vector2i(gx, gy))
	var own := _cell(pos)
	if in_bounds(own.x, own.y) and not out.has(own):
		out.append(own)
	return out

## 建筑落地 +1 / 拆掉 -1
func occupy(cells: Array, d: int) -> void:
	for c in cells:
		var i: int = c.y * GRID_W + c.x
		_occ[i] = maxi(0, _occ[i] + d)
		_sync(c)

func occupied(c: Vector2i) -> bool:
	return in_bounds(c.x, c.y) and _occ[c.y * GRID_W + c.x] > 0

func cell_type(c: Vector2i) -> int:
	if not in_bounds(c.x, c.y):
		return T.WOODS
	return grid[c.y * GRID_W + c.x]

## 世界坐标处是不是挡路的格子（树/矿/边缘密林/悬崖/深水；出了地图也算挡）
func solid_at(world: Vector2) -> bool:
	var c := _cell(world)
	return not walkable(c.x, c.y)

func has_solids() -> bool:
	return _solid_count > 0

## 离 p 最近的能站人的点：p 本身能走就原样返回，否则找最近的空格格心（同一圈里挑离 prefer 近的）
func open_point(p: Vector2, prefer := Vector2.INF) -> Vector2:
	var c := _cell(p)
	if walkable(c.x, c.y):
		return p
	var ref := p if prefer == Vector2.INF else prefer
	for r in range(1, 12):
		var best := Vector2.INF
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if not walkable(q.x, q.y):
					continue
				var w := Vector2(q) * CELL + Vector2(CELL, CELL) * 0.5
				# 先按离 p 的距离挑（贴着点的那棵树），差不多近的再挑离 prefer（单位自己）近的
				var d := w.distance_to(p) * 4.0 + w.distance_to(ref)
				if d < best_d:
					best_d = d
					best = w
		if best != Vector2.INF:
			return best
	return p

## 圆（单位）和周围阻挡格的碰撞：返回把它推出去的位移（没撞就是零）。
## 单位被人群挤进树林/矿堆时靠它推回来，贴着林子边走时自然顺着边滑
func push_out(p: Vector2, r: float) -> Vector2:
	if _solid_count == 0:
		return Vector2.ZERO
	var c := _cell(p)
	var push := Vector2.ZERO
	if not walkable(c.x, c.y):
		# 整个人已经陷在格子里：直接拉到最近的空格
		var o := open_point(p)
		return (o - p).limit_length(6.0) if o != p else Vector2.ZERO
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var q := c + Vector2i(dx, dy)
			if walkable(q.x, q.y):
				continue
			var lo := Vector2(q) * CELL
			var closest := Vector2(clampf(p.x, lo.x, lo.x + CELL), clampf(p.y, lo.y, lo.y + CELL))
			var off := p - closest
			var d := off.length()
			if d < r and d > 0.001:
				push += off / d * (r - d)
	return push

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
	var i := gy * GRID_W + gx
	return not is_solid_type(grid[i]) and _occ[i] == 0
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
## 目标在树/矿上（去砍树、采矿）：路径终点改成它旁边离自己最近的空格，走到那里再贴上去。
## 起点被挤进阻挡格也一样先挪到最近的空格。
func find_path(start: Vector2, goal: Vector2) -> PackedVector2Array:
	var s := _cell(start)
	var g := _cell(goal)
	if not walkable(s.x, s.y):
		s = _cell(open_point(start))
		if not walkable(s.x, s.y):
			return PackedVector2Array()
	var end := goal
	if not walkable(g.x, g.y):
		end = open_point(goal, start)
		g = _cell(end)
		if not walkable(g.x, g.y):
			return PackedVector2Array()
	if s == g:
		return PackedVector2Array([end])
	var pts := _astar.get_point_path(s, g)
	if pts.is_empty():
		return PackedVector2Array()
	if end != goal:
		pts[pts.size() - 1] = end
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
## 浅水/深水/悬崖/森林的调试色块；树、矿、边缘密林都有自己的贴图节点，这里不画
var draw_cells := true
func _draw() -> void:
	if not draw_cells:
		return
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
