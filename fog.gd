extends Node2D
class_name Fog
## 战争迷雾（随机图）：没去过的地方一片黑；去过、现在没人看着的地方蒙一层灰（地形、房子、宝箱照常看得见，怪看不见）；
## 己方的人、房子、工地周围一圈才看得见敌人。32px 一格，每 0.2 秒按视野重算；两张图在着色器里淡入淡出，边缘用噪声扭开，不显格子。
## 开局就知道：主城周围、土路沿线（怪从哪来）、巢穴。小地图同样蒙一层（hud.gd 的 Minimap 叠 mini_tex）。

const CELL := 32.0
const STEP := 0.2           # 多久重算一次
const DIM := 110            # 去过没人看着：遮罩值（0 = 看得见，255 = 没去过）
const SIGHT := {"worker": 200.0, "engineer": 240.0, "sword": 230.0, "archer": 280.0,
	"base": 420.0, "tower": 300.0, "outpost": 320.0, "building": 220.0, "site": 150.0}
const START_BASE := 650.0   # 开局主城周围
const START_ROAD := 150.0   # 开局土路两侧
const START_HIVE := 300.0   # 开局巢穴周围

const SHADER := """
shader_type canvas_item;
uniform sampler2D fog_a : filter_linear, repeat_disable;
uniform sampler2D fog_b : filter_linear, repeat_disable;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform float k = 1.0;
uniform vec2 grid;
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	vec2 n = vec2(texture(noise, wp / 260.0).r, texture(noise, wp / 260.0 + vec2(0.43, 0.17)).r) - 0.5;
	vec2 uv = UV + n * (1.7 / grid);
	float a = mix(texture(fog_a, uv).r, texture(fog_b, uv).r, k);
	float fine = texture(noise, wp / 150.0 + vec2(0.71, 0.29)).r;
	float dark = smoothstep(0.58, 0.95, a + (fine - 0.5) * 0.12);
	float dim = smoothstep(0.06, 0.36, a);
	float cloud = texture(noise, wp / 520.0 + vec2(TIME * 0.004, TIME * 0.0025)).r;
	vec3 col = mix(vec3(0.07, 0.09, 0.13), vec3(0.035, 0.045, 0.075) + (cloud - 0.5) * 0.05, dark);
	COLOR = vec4(col, max(dim * 0.46, dark));
}
"""

var gw := 0
var gh := 0
var enabled := true
var explored := PackedByteArray()
var vis := PackedByteArray()
var _shown := PackedByteArray()
var _img_a: ImageTexture
var _img_b: ImageTexture
var _mat: ShaderMaterial
var mini_tex: ImageTexture       # 小地图那层：LA8，每格一像素
var _t := 0.0
var _blend := 1.0
var _discs := {}                 # 半径（格）→ 圆内的格子偏移

func _ready() -> void:
	z_index = 30
	add_to_group("fog")

func setup(w: float, h: float) -> void:
	gw = int(ceil(w / CELL))
	gh = int(ceil(h / CELL))
	explored = PackedByteArray()
	explored.resize(gw * gh)
	vis = PackedByteArray()
	vis.resize(gw * gh)
	_shown = _mask_bytes()
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_L8, _shown)
	_img_a = ImageTexture.create_from_image(img)
	_img_b = ImageTexture.create_from_image(img)
	mini_tex = ImageTexture.create_from_image(_mini_image())
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("fog_a", _img_a)
	_mat.set_shader_parameter("fog_b", _img_b)
	_mat.set_shader_parameter("noise", Ground._noise_tex(97, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 3))
	_mat.set_shader_parameter("grid", Vector2(gw, gh))
	_mat.set_shader_parameter("k", 1.0)
	material = _mat
	queue_redraw()

## 开局就知道的地方（main 建完地图调一次）
func reveal(p: Vector2, r: float) -> void:
	_stamp(explored, p, r)

func reveal_road(pts: Array, r: float) -> void:
	var last := Vector2.INF
	for i in pts.size():
		if last == Vector2.INF or pts[i].distance_to(last) >= CELL or i == pts.size() - 1:
			_stamp(explored, pts[i], r)
			last = pts[i]

func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	refresh()

func visible_at(p: Vector2) -> bool:
	if not enabled or gw == 0:
		return true
	var i := _idx(p)
	return i >= 0 and vis[i] == 1

func explored_at(p: Vector2) -> bool:
	if not enabled or gw == 0:
		return true
	var i := _idx(p)
	return i >= 0 and explored[i] == 1

## 某个东西有多远的视野
static func sight_of(n: Node) -> float:
	if n is Worker:
		return SIGHT.worker
	if n is Engineer:
		return SIGHT.engineer
	if n is Soldier:
		return SIGHT.archer if n.is_ranged else SIGHT.sword
	if n is ConstructionSite:
		return SIGHT.site
	if n is Building:
		return float(SIGHT.get(n.kind, SIGHT.building))
	return SIGHT.building

func _process(delta: float) -> void:
	if gw == 0:
		return
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / STEP)
		_mat.set_shader_parameter("k", _blend)
	_t -= delta
	if _t <= 0.0:
		_t = STEP
		refresh()

## 按现在的视野重算一遍：谁看得见、哪里去过、哪些怪藏起来
func refresh() -> void:
	if gw == 0:
		return
	var tree := get_tree()
	vis.fill(0)
	if enabled:
		for u in tree.get_nodes_in_group("player_units"):
			if is_instance_valid(u) and not u.dead:
				_stamp_vis(u.position, sight_of(u))
		for b in tree.get_nodes_in_group("buildings"):
			if is_instance_valid(b) and b.team == 0:
				_stamp_vis(b.position, sight_of(b))
		for s in tree.get_nodes_in_group("sites"):
			if is_instance_valid(s):
				_stamp_vis(s.position, SIGHT.site)
	# 怪只在看得见的地方露面；敌方房子、废墟、宝箱去过就一直看得见
	for e in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.visible = visible_at(e.position)
	for b in tree.get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.team != 0:
			b.visible = explored_at(b.position)
	for t in tree.get_nodes_in_group("treasures"):
		if is_instance_valid(t):
			t.visible = explored_at(t.position)
	# 遮罩图：上一张淡出、这张淡入
	var next := _mask_bytes()
	if next != _shown:
		_img_a.update(Image.create_from_data(gw, gh, false, Image.FORMAT_L8, _shown))
		_shown = next
		_img_b.update(Image.create_from_data(gw, gh, false, Image.FORMAT_L8, _shown))
		_blend = 0.0
		_mat.set_shader_parameter("k", 0.0)
		mini_tex.update(_mini_image())

func _mask_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(gw * gh)
	if not enabled:
		return out
	for i in gw * gh:
		out[i] = 0 if vis[i] == 1 else (DIM if explored[i] == 1 else 255)
	return out

func _mini_image() -> Image:
	var d := PackedByteArray()
	d.resize(gw * gh * 2)
	for i in gw * gh:
		d[i * 2] = 14
		d[i * 2 + 1] = 0 if _shown[i] == 0 else (110 if _shown[i] == DIM else 235)
	return Image.create_from_data(gw, gh, false, Image.FORMAT_LA8, d)

func _idx(p: Vector2) -> int:
	var x := int(p.x / CELL)
	var y := int(p.y / CELL)
	if x < 0 or y < 0 or x >= gw or y >= gh:
		return -1
	return y * gw + x

func _disc(r: float) -> Array:
	var key := int(round(r / CELL * 2.0))
	if _discs.has(key):
		return _discs[key]
	var rc := key * 0.5
	var out: Array = []
	var n := int(ceil(rc))
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			if dx * dx + dy * dy <= rc * rc:
				out.append(Vector2i(dx, dy))
	_discs[key] = out
	return out

func _stamp(arr: PackedByteArray, p: Vector2, r: float) -> void:
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	for o in _disc(r):
		var x: int = cx + o.x
		var y: int = cy + o.y
		if x >= 0 and y >= 0 and x < gw and y < gh:
			arr[y * gw + x] = 1

## 看得见的同时也算去过
func _stamp_vis(p: Vector2, r: float) -> void:
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	for o in _disc(r):
		var x: int = cx + o.x
		var y: int = cy + o.y
		if x >= 0 and y >= 0 and x < gw and y < gh:
			var i := y * gw + x
			vis[i] = 1
			explored[i] = 1

func _draw() -> void:
	if gw == 0 or not enabled:
		return
	draw_texture_rect(_img_b, Rect2(Vector2.ZERO, Vector2(gw, gh) * CELL), false)
