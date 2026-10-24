class_name RiverArt
extends Node2D
## 河上的木桥：垫在单位下面（z = -1，和地面装饰一层），只画一次。
## KR 式：石头桥墩 + 一块块木板桥面（深色缝、亮色上沿）+ 两侧木栏杆（远侧栏杆先画，近侧压在桥面上）。
## 桥的两头 a/b 是土路刚出水的那两个点（map_gen 算的），桥面顺着路的方向。

const DECK_HALF := 34.0
const OUT := Color(0.2, 0.13, 0.08)
var bridges: Array = []    # [{a, b}]
var stones: Array = []     # 浅滩里的垫脚石 [{pos, rx, ry}]
## 当前地图的河（{pts, hw}）：水车放置 / 轮子朝向按真正画出来的水面算（格子太粗，深水格会比水面宽出半格）
static var river := {}
const EDGE_K := 1.08       # 画出来的水面边 ≈ 半宽 × 这个（ground.gd 的河遮罩 0.46 处）

func _ready() -> void:
	z_index = -1

func _exit_tree() -> void:
	river = {}

func setup(list: Array, river_ := {}, fords := []) -> void:
	bridges = list.duplicate()
	stones = []
	RiverArt.river = river_
	if not river.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for fp in fords:
			# 两排错开的垫脚石，从这岸铺到那岸
			var n := cross_dir(river, fp)
			var along := n.orthogonal()
			var hw := half_at(river, fp)
			var d := -hw - 4.0
			var k := 0
			while d <= hw + 4.0:
				var side := (k % 2) * 2.0 - 1.0
				stones.append({"pos": fp + n * d + along * side * 9.0 + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)),
					"rx": rng.randf_range(8.0, 11.0), "ry": rng.randf_range(5.5, 7.0)})
				d += 15.0
				k += 1
	queue_redraw()

func _draw() -> void:
	for st in stones:
		_step_stone(st.pos, st.rx, st.ry)
	for br in bridges:
		_bridge(br.a, br.b)

## 垫脚石：扁圆石头，脚下一圈白浪
func _step_stone(p: Vector2, rx: float, ry: float) -> void:
	_oval(p + Vector2(0, 2.5), rx + 3.0, ry + 2.5, Color(0.9, 0.97, 0.96, 0.55))
	_oval(p, rx + 1.5, ry + 1.5, OUT)
	_oval(p, rx, ry, Color(0.55, 0.53, 0.47))
	_oval(p + Vector2(-rx * 0.15, -ry * 0.25), rx * 0.7, ry * 0.55, Color(0.7, 0.68, 0.61))

func _oval(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

func _bridge(a0: Vector2, b0: Vector2) -> void:
	var u := (b0 - a0).normalized()
	var a := a0 - u * 8.0
	var b := b0 + u * 8.0
	var n := u.orthogonal()
	if n.y > 0.0:
		n = -n    # n 指向屏幕上方（远侧）
	var len := a.distance_to(b)
	var far_a := a + n * DECK_HALF
	var far_b := b + n * DECK_HALF
	var near_a := a - n * DECK_HALF
	var near_b := b - n * DECK_HALF
	# 水面上的投影
	var sh := Vector2(0, 7)
	draw_colored_polygon(PackedVector2Array([far_a + sh, far_b + sh, near_b + sh, near_a + sh]), Color(0.04, 0.14, 0.22, 0.35))
	# 桥墩：四个角各一块石头
	for p in [far_a, far_b, near_a, near_b]:
		_stone(p + (b - a).normalized() * (6.0 if p == far_a or p == near_a else -6.0))
	# 桥面底色 + 描边
	var deck := PackedVector2Array([far_a, far_b, near_b, near_a])
	draw_colored_polygon(deck, Color(0.5, 0.34, 0.2))
	# 木板：顺着桥走一块块横铺，颜色轻微错开
	var step := 11.0
	var k := 0
	var t := 1.5
	while t < len - 1.0:
		var t1 := minf(t + step - 2.0, len - 1.5)
		var p0 := a + u * t
		var p1 := a + u * t1
		var shade := 0.94 + 0.08 * float((k * 7919) % 5) / 4.0
		var col := Color(0.70, 0.5, 0.3) * shade
		col.a = 1.0
		var hw := DECK_HALF - 3.0
		draw_colored_polygon(PackedVector2Array([p0 + n * hw, p1 + n * hw, p1 - n * hw, p0 - n * hw]), col)
		# 上沿一道亮边（靠远侧那头）
		draw_line(p0 + n * hw, p1 + n * hw, Color(0.84, 0.66, 0.44), 1.5)
		t += step
		k += 1
	draw_polyline(PackedVector2Array([far_a, far_b, near_b, near_a, far_a]), OUT, 2.5)
	# 两侧纵梁
	draw_line(far_a, far_b, Color(0.36, 0.23, 0.13), 5.0)
	_rail(far_a, far_b)
	draw_line(near_a, near_b, Color(0.36, 0.23, 0.13), 5.0)
	draw_line(near_a + Vector2(0, 2.5), near_b + Vector2(0, 2.5), OUT, 1.5)
	_rail(near_a, near_b)

## 一侧栏杆：每隔 ~30px 一根立柱（往屏幕上方立 13px），柱顶一根横杆
func _rail(a: Vector2, b: Vector2) -> void:
	var len := a.distance_to(b)
	var n := maxi(2, int(len / 30.0) + 1)
	var up := Vector2(0, -13)
	draw_line(a + up, b + up, OUT, 6.0)
	draw_line(a + up, b + up, Color(0.62, 0.43, 0.25), 3.5)
	draw_line(a + up + Vector2(0, -1), b + up + Vector2(0, -1), Color(0.8, 0.62, 0.4), 1.2)
	for i in n:
		var p := a.lerp(b, float(i) / (n - 1))
		var r := Rect2(p + Vector2(-3.0, -16.0), Vector2(6.0, 17.0))
		draw_rect(r.grow(1.5), OUT)
		draw_rect(r, Color(0.5, 0.33, 0.19))
		draw_rect(Rect2(r.position, Vector2(2.0, r.size.y)), Color(0.66, 0.47, 0.28))

## 桥墩石块：圆角灰石，上亮下暗
func _stone(p: Vector2) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(p + Vector2(cos(a) * 11.0, sin(a) * 8.0 + 3.0))
	draw_colored_polygon(pts, OUT)
	var inner := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		inner.append(p + Vector2(cos(a) * 9.0, sin(a) * 6.3 + 2.5))
	draw_colored_polygon(inner, Color(0.6, 0.58, 0.53))
	draw_circle(p + Vector2(-2.5, 0.0), 3.0, Color(0.74, 0.72, 0.66))

## ---------- 浅滩 ----------
## 河在 p 附近的横穿方向（垂直于河的流向，单位向量）
static func cross_dir(rv: Dictionary, p: Vector2) -> Vector2:
	var i := _nearest(rv, p)
	var pts: Array = rv.pts
	var t: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
	return t.orthogonal()

## p 在水面里多深（正 = 在水里、离岸多远；负 = 在岸上、离水多远）；没有河 = -INF
static func water_depth(p: Vector2) -> float:
	return depth_in(river, p)

## 同上，河换成 rv（生成地图时用，那会儿 river 还没装上）
static func depth_in(rv: Dictionary, p: Vector2) -> float:
	if rv.is_empty():
		return -INF
	var pts: Array = rv.pts
	var hws: Array = rv.hw
	var i := _nearest(rv, p)
	var best := INF
	var best_hw: float = hws[i]
	for j in [i - 1, i]:
		if j < 0 or j + 1 >= pts.size():
			continue
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[j + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if d < best:
			best = d
			var t := clampf(a.distance_to(q) / maxf(a.distance_to(b), 0.001), 0.0, 1.0)
			best_hw = lerpf(hws[j], hws[j + 1], t)
	return best_hw * EDGE_K - best

## 河在 p 附近的半宽
static func half_at(rv: Dictionary, p: Vector2) -> float:
	return float(rv.hw[_nearest(rv, p)])

static func _nearest(rv: Dictionary, p: Vector2) -> int:
	var best := 0
	var bd := INF
	var pts: Array = rv.pts
	for i in pts.size():
		var d: float = p.distance_squared_to(pts[i])
		if d < bd:
			bd = d
			best = i
	return best
