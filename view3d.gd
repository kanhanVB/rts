class_name View3D
extends Node3D
## 3D 表现层：把 2D 逻辑世界"镜像"成王国保卫战式的 3D 场景。
## 只读逻辑节点的状态（位置/血量/动画相位/选中），从不改动玩法——
## 所以玩法、数值、自动化测试完全不受影响。逻辑的 (x, y) 像素 → 3D 的 (x/32, 0, y/32) 米。

const S := Models.S
const PITCH := deg_to_rad(52.0)    # 俯视角：王国保卫战那种"斜上方看沙盘"
const FOV := 32.0
const BASE_DIST := 46.0            # 缩放 1 倍时镜头距离（正好看全地图）

var main: Node2D
var cam3d: Camera3D
var _mirrors := {}                 # instance_id -> 记录
var _t := 0.0
var _cam_target := Vector3.ZERO
var _cam_dist := BASE_DIST

# 特效池
var _arrows: Array = []
var _sparks: Array = []
var _fx_used := {"arrow": 0, "spark": 0}
var _poofs: Array = []             # [{node, t}]
var _floaters: Array = []          # [{node, t}]
var _markers: Array = []           # [{node, t}]
var _ghost: Node3D = null
var _ghost_kind := ""
var _ghost_pad: MeshInstance3D

func _init(m: Node2D) -> void:
	main = m

func _ready() -> void:
	_build_env()
	_build_ground()
	_build_decor()
	cam3d = Camera3D.new()
	cam3d.fov = FOV
	cam3d.near = 0.5
	cam3d.far = 300.0
	add_child(cam3d)
	cam3d.make_current()
	_sync_camera(1.0)

## ================================================================ 环境
func _build_env() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.27, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.72, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.06
	env.adjustment_brightness = 0.96
	env.glow_enabled = false
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

## 草地：程序化噪声深浅斑 + 基地到巢穴的土路 + 地图外压暗
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_toon, specular_disabled;
uniform vec2 path_pts[5];
uniform vec2 map_size = vec2(40.0, 22.5);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float seg_d(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a; vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	float n = noise(p * 0.22) * 0.55 + noise(p * 0.9) * 0.3 + noise(p * 3.5) * 0.15;
	// 卡通草地：大块深浅斑（分两档硬边）+ 细碎噪点
	vec3 g_dark = vec3(0.33, 0.54, 0.21);
	vec3 g_mid = vec3(0.41, 0.62, 0.25);
	vec3 g_light = vec3(0.49, 0.69, 0.29);
	vec3 col = n < 0.42 ? g_dark : (n < 0.62 ? g_mid : g_light);
	col *= 0.95 + noise(p * 9.0) * 0.08;
	// 土路：中心浅、边缘深，带一点抖动的边
	float d = 1e5;
	for (int i = 0; i < 4; i++) { d = min(d, seg_d(p, path_pts[i], path_pts[i + 1])); }
	float pw = 0.78 + (noise(p * 1.4) - 0.5) * 0.3;
	vec3 dirt = mix(vec3(0.78, 0.62, 0.4), vec3(0.86, 0.72, 0.5), noise(p * 2.5));
	if (noise(p * 7.0) > 0.78) { dirt *= 0.88; }
	if (d < pw) { col = dirt; }
	else if (d < pw + 0.14) { col = vec3(0.55, 0.42, 0.26); }
	else if (d < pw + 0.4) { col *= 0.9; }
	// 地图外：压暗成林地，暗示边界
	float edge_d = min(min(p.x, map_size.x - p.x), min(p.y, map_size.y - p.y));
	col = mix(col * vec3(0.62, 0.7, 0.6), col, smoothstep(-1.2, 0.4, edge_d));
	ALBEDO = col;
}
"""

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(140, 110)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	var pts := PackedVector2Array()
	for p in main.DIRT_PATH:
		pts.append(p * S)
	m.set_shader_parameter("path_pts", pts)
	m.set_shader_parameter("map_size", Vector2(main.W, main.H) * S)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = m
	mi.position = Vector3(main.W * S * 0.5, 0, main.H * S * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## 装饰：地图外一圈密林（框住画面）+ 场内的花、草丛、小石头。全用 MultiMesh，几乎零开销
func _build_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mw: float = main.W * S
	var mh: float = main.H * S
	var tree_xf: Array = []
	var tree_col: Array = []
	var x := -14.0
	while x < mw + 14.0:
		var z := -12.0
		while z < mh + 12.0:
			var px := x + rng.randf_range(-0.7, 0.7)
			var pz := z + rng.randf_range(-0.7, 0.7)
			var out := px < -0.6 or px > mw + 0.6 or pz < -0.9 or pz > mh + 0.6
			if out:
				var sc := rng.randf_range(1.0, 1.6)
				tree_xf.append(Transform3D(Basis.from_scale(Vector3.ONE * sc).rotated(Vector3.UP, rng.randf() * TAU), Vector3(px, 0, pz)))
				tree_col.append(Color(0.24, 0.5, 0.22).lerp(Color(0.36, 0.6, 0.24), rng.randf()))
			z += 1.15
		x += 1.15
	# 树干
	var trunks := _multimesh(Models.cyl(0.1, 0.14, 0.8, 6), Models.mat(Color(0.45, 0.3, 0.18), 0), tree_xf, [])
	trunks.position.y = 0.4
	add_child(trunks)
	# 树冠（每棵一个颜色）
	var crown_m := Models.mat(Color.WHITE, 1, 0.04)
	crown_m = crown_m.duplicate()
	crown_m.vertex_color_use_as_albedo = true
	var crowns := _multimesh(Models.sphere(0.62, 1.1, 10), crown_m, tree_xf, tree_col)
	crowns.position.y = 1.15
	add_child(crowns)
	# 场内小装饰：避开土路和资源点
	var flowers_xf: Array = []
	var flowers_col: Array = []
	var tufts_xf: Array = []
	var rocks_xf: Array = []
	var palette := [Color(1.0, 0.82, 0.3), Color(1.0, 0.82, 0.3), Color(0.95, 0.45, 0.5), Color(0.7, 0.6, 1.0)]
	for i in 420:
		var p := Vector2(rng.randf_range(0.5, mw - 0.5), rng.randf_range(0.5, mh - 0.5))
		if _near_path(p, 1.3) or _near_res(p, 1.2):
			continue
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.7, 1.3)).rotated(Vector3.UP, rng.randf() * TAU), Vector3(p.x, 0, p.y))
		var r := rng.randf()
		if r < 0.22:
			flowers_xf.append(xf)
			flowers_col.append(palette[rng.randi() % palette.size()])
		elif r < 0.93:
			tufts_xf.append(xf)
		else:
			rocks_xf.append(xf)
	var fm := Models.flat(Color.WHITE).duplicate()
	fm.vertex_color_use_as_albedo = true
	var fl := _multimesh(Models.sphere(0.06, 0.08, 6), fm, flowers_xf, flowers_col)
	fl.position.y = 0.06
	add_child(fl)
	var tm := _multimesh(Models.cyl(0.0, 0.07, 0.22, 4), Models.mat(Color(0.36, 0.6, 0.22), 0), tufts_xf, [])
	tm.position.y = 0.1
	add_child(tm)
	var rk := _multimesh(Models.sphere(0.14, 0.14, 6), Models.mat(Color(0.62, 0.6, 0.58), 1, 0.02), rocks_xf, [])
	rk.position.y = 0.03
	add_child(rk)

func _multimesh(mesh: Mesh, m: Material, xfs: Array, cols: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if mm.use_colors:
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	return mmi

func _near_path(p: Vector2, r: float) -> bool:
	var pts: Array = main.DIRT_PATH
	for i in pts.size() - 1:
		var a: Vector2 = pts[i] * S
		var b: Vector2 = pts[i + 1] * S
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < r:
			return true
	return false

func _near_res(p: Vector2, r: float) -> bool:
	for n in get_tree().get_nodes_in_group("res_nodes"):
		if (n.position * S).distance_to(p) < r:
			return true
	for b in get_tree().get_nodes_in_group("buildings"):
		if (b.position * S).distance_to(p) < b.size * S * 0.8:
			return true
	return false

## ================================================================ 每帧
func _process(delta: float) -> void:
	_t += delta
	_sync_camera(delta)
	_fx_used = {"arrow": 0, "spark": 0}
	var seen := {}
	for g in ["units", "buildings", "res_nodes", "sites"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n) or n.is_queued_for_deletion():
				continue
			var id := n.get_instance_id()
			seen[id] = true
			var rec: Dictionary = _mirrors.get(id, {})
			if rec.is_empty():
				rec = _create(n, g)
				_mirrors[id] = rec
			_update(rec, delta)
	# 逻辑节点没了 → 播放消散特效再删镜像
	for id in _mirrors.keys():
		if not seen.has(id):
			var rec: Dictionary = _mirrors[id]
			_on_removed(rec)
			rec.node.queue_free()
			_mirrors.erase(id)
	_hide_unused_fx()
	_tick_effects(delta)
	_update_ghost()

func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x * S, y, p.y * S)

## 镜头跟随 2D 镜头的状态（位置 + 缩放）：贴边滚屏、滚轮缩放的逻辑原样复用
func _sync_camera(delta: float) -> void:
	var c: Camera2D = main.cam
	if c == null:
		return
	var want_t := to3(c.position) + Vector3(0, 0, 1.2)
	var want_d := BASE_DIST / c.zoom.x
	var k := clampf(delta * 10.0, 0.0, 1.0)
	_cam_target = _cam_target.lerp(want_t, k)
	_cam_dist = lerpf(_cam_dist, want_d, k)
	cam3d.position = _cam_target + Vector3(0, sin(PITCH), cos(PITCH)) * _cam_dist
	cam3d.look_at(_cam_target, Vector3.UP)

## 立刻对齐镜头（缩放朝鼠标时要用最新镜头做换算）
func snap_camera() -> void:
	_sync_camera(1.0)

## ================================================================ 镜像的创建与更新
func _create(n: Node, group: String) -> Dictionary:
	var rec := {"src": n, "group": group, "is_goo": n is Goo, "last_hp": -1.0, "punch": 0.0, "yaw": 0.0,
		"last_pos": n.position, "last_carry": 0.0}
	var node := Node3D.new()
	add_child(node)
	rec.node = node
	if n is CanvasItem:
		n.visible = false    # 2D 画法藏起来（建筑挂在 BuildManager 这种普通 Node 下，不会继承 main 的隐藏）
	match group:
		"units":
			var s: float = n.radius / 9.0
			var model: Node3D
			if n is Goo:
				model = Models.goo(n.radius / 8.0)
			else:
				model = Models.human(Models.key_of(n), s)
			node.add_child(model)
			rec.model = model
			rec.h = 1.5 * s
			rec.ring = _ring(node, n.radius * S * 1.25, Color(0.45, 1.0, 0.45) if n.team == 0 else Color(1.0, 0.35, 0.3))
			rec.bar = _bar(node, 0.8 * s, 1.75 * s, n.team == 0)
			if n is Worker:
				var ore := Models.item("ore")
				ore.scale = Vector3.ONE * 0.3
				ore.position.y = 1.62 * s
				model.get_meta("rig").add_child(ore)
				var wood := Models.item("wood")
				wood.scale = Vector3.ONE * 0.32
				wood.position.y = 1.62 * s
				model.get_meta("rig").add_child(wood)
				rec.carry_ore = ore
				rec.carry_wood = wood
				rec.dot = Models.part(node, Models.sphere(0.08), Models.flat(Color(0.35, 0.82, 1.0)), Vector3(0.0, 0.05, 0.42))
		"buildings":
			var model := Models.building(n.kind, n.size)
			node.add_child(model)
			rec.model = model
			rec.h = n.size * S * 1.2
			rec.ring = _ring(node, n.size * S * 0.78, Color(0.45, 1.0, 0.45) if n.team == 0 else Color(1.0, 0.35, 0.3))
			rec.bar = _bar(node, n.size * S * 0.9, n.size * S * 1.35, n.team == 0)
		"res_nodes":
			var model := Models.res_node(n.kind, int(n.position.x * 31 + n.position.y * 17))
			node.add_child(model)
			rec.model = model
			rec.base_scale = 1.55 if n.kind == "wood" else 1.4
			rec.h = 1.2 * rec.base_scale
			rec.last_amount = n.amount
		"sites":
			_build_site(rec, n)
	node.position = to3(n.position)
	return rec

func _update(rec: Dictionary, delta: float) -> void:
	var n = rec.src
	var node: Node3D = rec.node
	node.position = to3(n.position)
	match rec.group:
		"units":
			_update_unit(rec, n, delta)
		"buildings":
			_update_building(rec, n, delta)
		"res_nodes":
			var inner: Node3D = rec.model.get_meta("inner")
			var ratio := clampf(n.amount / 250.0, 0.0, 1.0)
			rec.model.scale = Vector3.ONE * (0.6 + 0.4 * ratio) * rec.base_scale
			# 正在被采：轻轻抖
			var mined: bool = n.amount < rec.last_amount - 0.0001
			rec.last_amount = n.amount
			inner.position.x = sin(_t * 40.0) * 0.03 if mined else 0.0
		"sites":
			_update_site(rec, n)

func _update_unit(rec: Dictionary, u: Node, delta: float) -> void:
	var model: Node3D = rec.model
	var rig: Node3D = model.get_meta("rig")
	var s: float = u.radius / 9.0
	# 朝向：有攻击特效就面朝目标，否则朝移动方向
	var mv: Vector2 = u.position - rec.last_pos
	rec.last_pos = u.position
	var face_dir := Vector2.ZERO
	if not u._attack_fx.is_empty():
		face_dir = u._attack_fx[0].to - u.position
	elif u.moving and mv.length() > 0.05:
		face_dir = mv
	elif u is Worker and u.state == Worker.State.GATHERING and is_instance_valid(u.node_target):
		face_dir = u.node_target.position - u.position
	if face_dir.length() > 0.01:
		rec.yaw = lerp_angle(rec.yaw, atan2(-face_dir.y, face_dir.x), clampf(delta * 12.0, 0.0, 1.0))
	rig.rotation.y = rec.yaw
	# 挨打：弹一下
	if rec.last_hp >= 0.0 and u.hp < rec.last_hp:
		rec.punch = 1.0
	rec.last_hp = u.hp
	rec.punch = maxf(0.0, rec.punch - delta * 5.0)
	var ph: float = u.anim_t
	if u is Goo:
		var body: Node3D = model.get_meta("body")
		var hop := absf(sin(ph * 0.5)) if u.moving else 0.0
		rig.position.y = hop * 0.22
		var sq := (0.12 * sin(ph * 1.0)) if u.moving else 0.04 * sin(_t * 3.0 + rec.node.get_instance_id())
		body.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq) * (u.radius / 8.0) * (1.0 + 0.2 * rec.punch)
		body.position.x = u.attack_anim * 0.25
	else:
		var walk: bool = u.moving
		rig.position.y = absf(sin(ph)) * 0.07 * s if walk else 0.0
		var sw := sin(ph) * 0.7 if walk else 0.0
		model.get_meta("legL").rotation.z = sw
		model.get_meta("legR").rotation.z = -sw
		var arm_r: Node3D = model.get_meta("armR")
		var arm_l: Node3D = model.get_meta("armL")
		var atk: float = u.attack_anim
		if u is Worker and u.state == Worker.State.GATHERING:
			atk = 0.5 + 0.5 * sin(ph * 0.9)
		if u is Soldier and u.is_ranged:
			# 弓手：左手举弓瞄准，右手拉弦
			var aim := 1.0 if (atk > 0.0 or u._auto_target != null or u.attack_target != null) else 0.0
			arm_l.rotation.z = lerpf(arm_l.rotation.z, 1.5 * aim - sw * 0.5 * (1.0 - aim), clampf(delta * 12.0, 0.0, 1.0))
			arm_r.rotation.z = 1.2 * aim + atk * -0.8 + sw * 0.4 * (1.0 - aim)
		else:
			arm_l.rotation.z = -sw * 0.6
			arm_r.rotation.z = 0.25 + atk * 2.1 + sw * 0.3
		rig.scale = Vector3.ONE * (1.0 + 0.15 * rec.punch)
	# 选中圈 + 血条
	rec.ring.visible = u.selected
	if u.selected:
		rec.ring.scale = Vector3.ONE * (1.0 + 0.05 * sin(_t * 6.0))
	_set_bar(rec.bar, u.hp, u.max_hp)
	# 农民：头顶扛货 + 脚下蓝点（手动指派过交货点）
	if u is Worker:
		var carrying: bool = u.carry_amount > 0.5
		rec.carry_ore.visible = carrying and u.carry_kind == "ore"
		rec.carry_wood.visible = carrying and u.carry_kind == "wood"
		rec.dot.visible = is_instance_valid(u.deliver_to)
		if rec.last_carry > 0.5 and u.carry_amount < 0.01:
			var kind: String = u.carry_kind
			var d = u._depot()
			if d != null:
				kind = u._output_kind(d)
			floater(u.position, "+%d %s" % [int(round(rec.last_carry)), Economy.KIND_SHORT.get(kind, kind)],
				Color(1.0, 0.85, 0.3) if kind in ["ore", "ingot"] else Color(0.6, 1.0, 0.45))
		rec.last_carry = u.carry_amount
	# 攻击特效：弓手射箭，其余近战火花
	for fx in u._attack_fx:
		var p: float = clampf(1.0 - fx.t / 0.12, 0.0, 1.0)
		if u is Soldier and u.is_ranged:
			_arrow(to3(u.position, 0.9), to3(fx.to, 0.6), p)
		elif p > 0.4:
			_spark(to3(fx.to, 0.55), p)

func _update_building(rec: Dictionary, b: Node, delta: float) -> void:
	var model: Node3D = rec.model
	if rec.last_hp >= 0.0 and b.hp < rec.last_hp:
		rec.punch = 1.0
	rec.last_hp = b.hp
	rec.punch = maxf(0.0, rec.punch - delta * 6.0)
	model.position.x = sin(_t * 60.0) * 0.05 * rec.punch
	rec.ring.visible = b.selected
	_set_bar(rec.bar, b.hp, b.max_hp)
	if model.has_meta("flag"):
		model.get_meta("flag").rotation.y = sin(_t * 2.6 + b.position.x) * 0.3
	if model.has_meta("smoke"):
		var base: Vector3 = model.get_meta("smoke_base")
		var arr: Array = model.get_meta("smoke")
		for i in arr.size():
			var ph := fmod(_t * 0.45 + i / 3.0, 1.0)
			var puff: MeshInstance3D = arr[i]
			puff.position = base + Vector3(sin(ph * 4.0 + i) * 0.15 + ph * 0.4, ph * 1.6, 0)
			puff.scale = Vector3.ONE * (0.5 + ph * 1.3)
			puff.transparency = ph
	if model.has_meta("glow"):
		var g: Node3D = model.get_meta("glow")
		g.scale = Vector3.ONE * (1.0 + 0.18 * sin(_t * 3.0))

## 工地：土台 + 脚手架 + 正在"长高"的目标建筑
func _build_site(rec: Dictionary, n: Node) -> void:
	var node: Node3D = rec.node
	var w: float = n.size * S
	Models.part(node, Models.cyl(w * 0.72, w * 0.75, 0.06, 20), Models.mat(Color(0.64, 0.5, 0.32), 0), Vector3(0, 0.03, 0))
	var target := Models.building(n.kind, {"barracks": 60.0, "warehouse": 64.0, "smelter": 56.0, "workshop": 56.0}.get(n.kind, 60.0))
	node.add_child(target)
	rec.model = target
	var pole := Models.mat(Color(0.7, 0.52, 0.3))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Models.part(node, Models.cyl(0.05, 0.05, 1.6, 6), pole, Vector3(sx * w * 0.5, 0.8, sz * w * 0.42))
	for y in [0.55, 1.15]:
		for sz in [-1.0, 1.0]:
			Models.part(node, Models.box(Vector3(w * 1.05, 0.06, 0.06)), Models.mat(Color(0.7, 0.52, 0.3), 2, 0.015), Vector3(0, y, sz * w * 0.42))
	rec.h = 1.9
	rec.bar = _bar(node, w * 0.9, 2.1, true)
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 12
	lbl.font_size = 40
	lbl.outline_size = 12
	lbl.pixel_size = 0.013
	lbl.modulate = Color(1.0, 0.95, 0.75)
	lbl.outline_modulate = Color(0.2, 0.12, 0.06)
	lbl.position.y = 2.45
	node.add_child(lbl)
	rec.label = lbl

func _update_site(rec: Dictionary, n: Node) -> void:
	var prog: float = clampf(n.progress, 0.0, 1.0)
	rec.model.scale = Vector3(1.0, maxf(0.05, prog), 1.0)
	_set_bar(rec.bar, prog, 1.0, true)
	rec.label.text = "等待工程师" if n.assigned == null else "施工中 %d%%" % int(prog * 100.0)

## ================================================================ 血条 / 选中圈
func _ring(parent: Node3D, r: float, c: Color) -> MeshInstance3D:
	var ring := Models.part(parent, Models.torus(r * 0.86, r), Models.flat(c), Vector3(0, 0.04, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	return ring

func _bar(parent: Node3D, w: float, y: float, friendly: bool) -> Dictionary:
	var bar := Node3D.new()
	bar.position.y = y
	parent.add_child(bar)
	var bg := Models.part(bar, Models.quad(Vector2(w + 0.08, 0.17)), Models.flat(Color(0.12, 0.07, 0.04), true, 10))
	var fill := Models.part(bar, Models.quad(Vector2(w, 0.1)), Models.flat(Color(0.45, 0.92, 0.3) if friendly else Color(0.95, 0.3, 0.22), true, 11))
	bg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.visible = false
	return {"node": bar, "fill": fill, "w": w}

func _set_bar(bar: Dictionary, v: float, mx: float, always := false) -> void:
	var node: Node3D = bar.node
	node.visible = always or v < mx - 0.01
	if not node.visible:
		return
	node.global_basis = cam3d.global_basis
	var r := clampf(v / mx, 0.0, 1.0)
	var fill: MeshInstance3D = bar.fill
	fill.scale.x = maxf(r, 0.001)
	fill.position.x = -(1.0 - r) * bar.w * 0.5

## ================================================================ 特效
func _arrow(a: Vector3, b: Vector3, p: float) -> void:
	var node: Node3D
	if _fx_used.arrow < _arrows.size():
		node = _arrows[_fx_used.arrow]
	else:
		node = Node3D.new()
		Models.part(node, Models.box(Vector3(0.03, 0.03, 0.5)), Models.mat(Color(0.6, 0.42, 0.24), 0), Vector3(0, 0, 0))
		Models.part(node, Models.cyl(0.0, 0.05, 0.12, 6), Models.mat(Color(0.8, 0.82, 0.86), 0), Vector3(0, 0, -0.3), Vector3(-PI * 0.5, 0, 0))
		Models.part(node, Models.box(Vector3(0.1, 0.01, 0.12)), Models.flat(Color(0.95, 0.95, 0.9)), Vector3(0, 0, 0.22))
		add_child(node)
		_arrows.append(node)
	_fx_used.arrow += 1
	node.visible = true
	var pos := a.lerp(b, p) + Vector3(0, sin(p * PI) * 0.5, 0)
	var nxt := a.lerp(b, minf(p + 0.05, 1.0)) + Vector3(0, sin(minf(p + 0.05, 1.0) * PI) * 0.5, 0)
	if nxt.distance_to(pos) > 0.001:
		node.look_at_from_position(pos, nxt, Vector3.UP)
	else:
		node.position = pos

func _spark(at: Vector3, p: float) -> void:
	var node: MeshInstance3D
	if _fx_used.spark < _sparks.size():
		node = _sparks[_fx_used.spark]
	else:
		node = Models.part(self, Models.sphere(0.16, 0.16, 8), Models.flat(Color(1.0, 0.95, 0.6)))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sparks.append(node)
	_fx_used.spark += 1
	node.visible = true
	node.position = at
	node.scale = Vector3.ONE * (0.4 + p * 1.2)
	node.transparency = p

func _hide_unused_fx() -> void:
	for i in range(_fx_used.arrow, _arrows.size()):
		_arrows[i].visible = false
	for i in range(_fx_used.spark, _sparks.size()):
		_sparks[i].visible = false

## 消散：单位倒下 / 建筑被拆 / 资源采空
func _on_removed(rec: Dictionary) -> void:
	var p: Vector3 = rec.node.position
	match rec.group:
		"units":
			var c := Color(0.55, 0.78, 0.3) if rec.is_goo else Color(0.92, 0.9, 0.86)
			_poof(p, c, 0.35, 6)
		"buildings":
			_poof(p, Color(0.75, 0.68, 0.58), 1.0, 10)
		"res_nodes":
			_poof(p, Color(0.85, 0.82, 0.7), 0.3, 5)

func _poof(at: Vector3, c: Color, size: float, count: int) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = at
	for i in count:
		var a := TAU * i / count
		var mi := Models.part(node, Models.sphere(size * 0.45, -1.0, 10), Models.mat(c, 1, 0.02),
			Vector3(cos(a), 0.3, sin(a)) * size * 0.6 + Vector3(0, size * 0.4, 0))
		mi.set_meta("dir", Vector3(cos(a), 0.6, sin(a)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_poofs.append({"node": node, "t": 0.0, "size": size})

## 漂字（交货入账 "+10 矿"）
func floater(pos2d: Vector2, text: String, c: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 15
	lbl.font_size = 44
	lbl.outline_size = 14
	lbl.pixel_size = 0.013
	lbl.modulate = c
	lbl.outline_modulate = Color(0.18, 0.1, 0.05)
	lbl.position = to3(pos2d, 1.9)
	add_child(lbl)
	_floaters.append({"node": lbl, "t": 0.0})

## 右键落点提示圈：移动 = 绿，攻击 = 红
func marker(pos2d: Vector2, attack: bool) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = to3(pos2d, 0.05)
	var c := Color(1.0, 0.35, 0.25) if attack else Color(0.5, 1.0, 0.45)
	var r := Models.part(node, Models.torus(0.42, 0.52), Models.flat(c), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.2, 1))
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var r2 := Models.part(node, Models.torus(0.18, 0.24), Models.flat(c), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.2, 1))
	r2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_markers.append({"node": node, "t": 0.0})

func _tick_effects(delta: float) -> void:
	for e in _poofs:
		e.t += delta
		var k: float = e.t / 0.55
		for mi in e.node.get_children():
			mi.position += mi.get_meta("dir") * delta * e.size * 2.2
			mi.scale = Vector3.ONE * (1.0 + k * 0.8)
			mi.transparency = clampf(k, 0.0, 1.0)
	for e in _floaters:
		e.t += delta
		e.node.position.y += delta * 0.9
		e.node.modulate.a = clampf(1.6 - e.t * 1.6, 0.0, 1.0)
		e.node.outline_modulate.a = e.node.modulate.a
	for e in _markers:
		e.t += delta
		var k: float = e.t / 0.5
		e.node.scale = Vector3.ONE * (1.3 - k * 0.6)
		for mi in e.node.get_children():
			mi.transparency = clampf(k, 0.0, 1.0)
	_expire(_poofs, 0.55)
	_expire(_floaters, 1.0)
	_expire(_markers, 0.5)

func _expire(arr: Array, life: float) -> void:
	for e in arr.duplicate():
		if e.t >= life:
			e.node.queue_free()
			arr.erase(e)

## ================================================================ 放置预览
func _update_ghost() -> void:
	var kind: String = main._placing_kind
	if kind == "":
		if _ghost != null:
			_ghost.visible = false
		return
	if _ghost == null or _ghost_kind != kind:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = Node3D.new()
		add_child(_ghost)
		var m := Models.building(kind, 60.0)
		_ghost.add_child(m)
		_set_transparency(m, 0.45)
		_ghost_pad = Models.part(_ghost, Models.cyl(1.25, 1.25, 0.04, 28), Models.flat(Color(0.4, 1.0, 0.4, 0.45)), Vector3(0, 0.03, 0))
		_ghost_kind = kind
	_ghost.visible = true
	var mp := ground_at(get_viewport().get_mouse_position())
	_ghost.position = to3(mp)
	var ok := _placement_ok(kind, mp)
	_ghost_pad.material_override = Models.flat(Color(0.4, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.3, 0.25, 0.5))

func _placement_ok(kind: String, pos: Vector2) -> bool:
	if pos.x < 40.0 or pos.x > main.W - 40.0 or pos.y < 90.0 or pos.y > main.H - 80.0:
		return false
	for b in get_tree().get_nodes_in_group("buildings"):
		if pos.distance_to(b.position) < b.size + 40.0:
			return false
	return main.economy.can_afford(BuildManager.COST_TABLE.get(kind, {}))

func _set_transparency(n: Node, t: float) -> void:
	if n is GeometryInstance3D:
		n.transparency = t
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_transparency(c, t)

## ================================================================ 拾取（给输入用）
## 屏幕点 → 地面上的 2D 逻辑坐标
func ground_at(screen: Vector2) -> Vector2:
	var o := cam3d.project_ray_origin(screen)
	var d := cam3d.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector2.ZERO
	var t := -o.y / d.y
	var hit := o + d * t
	return Vector2(hit.x, hit.z) / S

## 屏幕点下面的实体（单位/建筑/资源点）：按投影后的屏幕距离挑，模型有高度也点得中。
## filter(node) -> bool 决定哪些算数
func pick(screen: Vector2, filter: Callable) -> Node2D:
	var best: Node2D = null
	var best_score := INF
	for id in _mirrors:
		var rec: Dictionary = _mirrors[id]
		var n = rec.src
		if not is_instance_valid(n) or not filter.call(n):
			continue
		var base := to3(n.position)
		var center := base + Vector3(0, rec.get("h", 1.0) * 0.45, 0)
		if cam3d.is_position_behind(center):
			continue
		var sc := cam3d.unproject_position(center)
		var r_world: float
		if rec.group == "buildings":
			r_world = n.size * S * 0.6
		elif rec.group == "units":
			r_world = maxf(n.radius * S * 1.4, 0.55)
		elif rec.group == "sites":
			r_world = n.size * S * 0.6
		else:
			r_world = 0.6
		var r_px := cam3d.unproject_position(center + cam3d.global_basis.x * r_world).distance_to(sc)
		var d := sc.distance_to(screen)
		if d <= r_px + 4.0:
			var score := d / maxf(r_px, 1.0) + (0.0 if rec.group == "units" else 0.5)
			if score < best_score:
				best_score = score
				best = n
	return best

## 屏幕框选：投影落在框里的己方单位
func units_in_rect(rect: Rect2) -> Array:
	var out: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		var c := to3(u.position, 0.5)
		if cam3d.is_position_behind(c):
			continue
		if rect.has_point(cam3d.unproject_position(c)):
			out.append(u)
	return out

## 3D 点 → 屏幕（小地图 / UI 用）
func screen_of(pos2d: Vector2, y := 0.0) -> Vector2:
	return cam3d.unproject_position(to3(pos2d, y))
