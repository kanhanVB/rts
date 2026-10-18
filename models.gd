class_name Models
extends RefCounted
## 3D 造型库：王国保卫战式卡通低多边形（toon 光照 + 深棕描边 + 大头小身 + 饱和暖色）。
## 全部用基础几何体拼出来，零外部素材。坐标约定：2D 逻辑的 1 像素 = 1/32 米，
## 2D 的 (x, y) 对应 3D 的 (x, 0, y)。模型默认面朝 +X，镜头从 +Z 方向斜俯视。

const S := 1.0 / 32.0
const OUTLINE := Color(0.16, 0.1, 0.06)
const SKIN := Color(0.97, 0.77, 0.6)

static var _mats := {}
static var _meshes := {}
static var _outlines := {}

## ---------------------------------------------------------------- 材质
## 描边：背面外扩一圈纯色（经典 inverted hull）。圆滑体沿法线外扩，方块沿各轴外扩（角上不裂缝）
const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.16, 0.1, 0.06, 1.0);
uniform float width = 0.025;
uniform bool box = false;
void vertex() {
	if (box) {
		VERTEX += sign(VERTEX) * width;
	} else {
		VERTEX += NORMAL * width;
	}
}
void fragment() {
	ALBEDO = color.rgb;
}
"""

static func _outline(box: bool, width: float) -> ShaderMaterial:
	var key := "%s|%.3f" % [box, width]
	if _outlines.has(key):
		return _outlines[key]
	var sh := Shader.new()
	sh.code = OUTLINE_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("box", box)
	m.set_shader_parameter("width", width)
	m.set_shader_parameter("color", OUTLINE)
	_outlines[key] = m
	return m

## 卡通材质。outline: 0 无 / 1 圆滑体描边 / 2 方块描边
static func mat(c: Color, outline := 1, width := 0.022, emit := 0.0, gloss := false) -> StandardMaterial3D:
	var key := "%s|%d|%.3f|%.2f|%s" % [c.to_html(), outline, width, emit, gloss]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	m.roughness = 0.35 if gloss else 0.9
	m.metallic_specular = 0.6 if gloss else 0.2
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.7
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	if outline == 1:
		m.next_pass = _outline(false, width)
	elif outline == 2:
		m.next_pass = _outline(true, width)
	_mats[key] = m
	return m

## 不受光的纯色（血条、选中圈、提示圈）。on_top = 永远画在最上层
static func flat(c: Color, on_top := false, prio := 10) -> StandardMaterial3D:
	var key := "flat|%s|%s|%d" % [c.to_html(), on_top, prio]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	if c.a < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if on_top:
		m.no_depth_test = true
		m.render_priority = prio
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

## ---------------------------------------------------------------- 网格（按参数缓存复用）
static func box(sz: Vector3) -> BoxMesh:
	var key := "box|%s" % sz
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = sz
		_meshes[key] = m
	return _meshes[key]

static func sphere(r: float, h := -1.0, seg := 18, hemi := false) -> SphereMesh:
	var hh := r * 2.0 if h < 0.0 else h
	var key := "sph|%.3f|%.3f|%d|%s" % [r, hh, seg, hemi]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = hh * (0.5 if hemi else 1.0)
		m.radial_segments = seg
		m.rings = max(6, seg / 2)
		m.is_hemisphere = hemi
		_meshes[key] = m
	return _meshes[key]

static func cyl(top: float, bottom: float, h: float, seg := 14) -> CylinderMesh:
	var key := "cyl|%.3f|%.3f|%.3f|%d" % [top, bottom, h, seg]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = seg
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]

static func capsule(r: float, h: float) -> CapsuleMesh:
	var key := "cap|%.3f|%.3f" % [r, h]
	if not _meshes.has(key):
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 14
		m.rings = 4
		_meshes[key] = m
	return _meshes[key]

## 三棱柱：屋脊沿 X 轴（size.x = 长度, size.y = 高, size.z = 进深）
static func prism(sz: Vector3) -> PrismMesh:
	var key := "pri|%s" % sz
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = Vector3(sz.z, sz.y, sz.x)
		_meshes[key] = m
	return _meshes[key]

static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "tor|%.3f|%.3f" % [inner, outer]
	if not _meshes.has(key):
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 32
		m.ring_segments = 8
		_meshes[key] = m
	return _meshes[key]

static func quad(sz: Vector2) -> QuadMesh:
	var key := "quad|%s" % sz
	if not _meshes.has(key):
		var m := QuadMesh.new()
		m.size = sz
		_meshes[key] = m
	return _meshes[key]

## 往 parent 上挂一个零件
static func part(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

## 三棱柱屋顶（屋脊沿 X）
static func _roof(p: Node3D, length: float, h: float, depth: float, c: Color, y: float, z := 0.0, w := 0.035) -> void:
	part(p, prism(Vector3(length, h, depth)), mat(c, 2, w), Vector3(0, y + h * 0.5, z), Vector3(0, PI * 0.5, 0))
	# 屋脊高光条
	part(p, box(Vector3(length * 1.02, 0.07, 0.1)), mat(c.lightened(0.25), 2, w), Vector3(0, y + h, z))

## ---------------------------------------------------------------- 小人
## 王国保卫战式 Q 版：大头、小身、短腿，武器超大号。
## kind: worker 农民 / engineer 工程师 / sword 剑士 / archer 弓手
## 动画挂点存在 meta：rig（整体朝向/起伏）、legL/legR、armR（武器手）、armL
static func human(kind: String, s := 1.0) -> Node3D:
	var root := Node3D.new()
	var rig := Node3D.new()
	root.add_child(rig)
	var body := Node3D.new()
	body.scale = Vector3.ONE * s
	rig.add_child(body)
	root.set_meta("rig", rig)

	var torso := Color(0.78, 0.6, 0.34)
	var legs := Color(0.42, 0.31, 0.21)
	var hat := "straw"
	var weapon := "pick"
	match kind:
		"engineer":
			torso = Color(0.95, 0.52, 0.16)
			legs = Color(0.33, 0.29, 0.26)
			hat = "hardhat"
			weapon = "hammer"
		"sword":
			torso = Color(0.24, 0.44, 0.82)
			legs = Color(0.36, 0.36, 0.42)
			hat = "helm"
			weapon = "sword"
		"archer":
			torso = Color(0.3, 0.6, 0.3)
			legs = Color(0.42, 0.32, 0.22)
			hat = "hood"
			weapon = "bow"

	# 腿：胯部做支点，走路前后摆
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0, 0.36, side * 0.11)
		body.add_child(hip)
		part(hip, capsule(0.085, 0.36), mat(legs), Vector3(0, -0.17, 0))
		part(hip, sphere(0.1, 0.12), mat(legs.darkened(0.35)), Vector3(0.04, -0.34, 0))   # 靴子
		root.set_meta("legL" if side < 0.0 else "legR", hip)
	# 身子 + 腰带
	part(body, capsule(0.2, 0.52), mat(torso), Vector3(0, 0.6, 0))
	part(body, cyl(0.205, 0.205, 0.07), mat(Color(0.36, 0.24, 0.14), 0), Vector3(0, 0.47, 0))
	part(body, sphere(0.04), mat(Color(0.95, 0.8, 0.3), 0), Vector3(0.2, 0.47, 0))       # 腰带扣
	# 头（占半个身高）
	part(body, sphere(0.27), mat(SKIN), Vector3(0.02, 1.08, 0))
	_hat(body, hat)
	# 左臂（摆臂 / 持弓 / 挎盾）
	var arm_l := Node3D.new()
	arm_l.position = Vector3(0, 0.78, -0.24)
	body.add_child(arm_l)
	part(arm_l, capsule(0.065, 0.32), mat(torso.darkened(0.15)), Vector3(0, -0.14, 0))
	part(arm_l, sphere(0.075), mat(SKIN, 0), Vector3(0, -0.3, 0))
	root.set_meta("armL", arm_l)
	# 右臂 + 武器
	var arm_r := Node3D.new()
	arm_r.position = Vector3(0, 0.78, 0.24)
	body.add_child(arm_r)
	part(arm_r, capsule(0.065, 0.32), mat(torso.darkened(0.15)), Vector3(0, -0.14, 0))
	part(arm_r, sphere(0.075), mat(SKIN, 0), Vector3(0, -0.3, 0))
	root.set_meta("armR", arm_r)
	_weapon(arm_r, arm_l, body, weapon)
	return root

static func _hat(body: Node3D, hat: String) -> void:
	var hy := 1.08
	match hat:
		"straw":    # 农民草帽：宽檐 + 圆顶 + 帽带
			var straw := Color(0.93, 0.78, 0.4)
			part(body, cyl(0.44, 0.46, 0.04, 20), mat(straw), Vector3(0, hy + 0.15, 0))
			part(body, cyl(0.17, 0.23, 0.17, 16), mat(straw.lightened(0.08)), Vector3(0, hy + 0.25, 0))
			part(body, cyl(0.235, 0.235, 0.045, 16), mat(Color(0.75, 0.3, 0.22), 0), Vector3(0, hy + 0.19, 0))
		"helm":     # 剑士铁盔：钢灰半球 + 帽檐 + 红缨
			var steel := Color(0.72, 0.75, 0.8)
			part(body, sphere(0.3, -1.0, 18, true), mat(steel, 1, 0.022, 0.0, true), Vector3(0.0, hy + 0.02, 0))
			part(body, cyl(0.31, 0.31, 0.05, 20), mat(steel.darkened(0.15), 0), Vector3(0, hy + 0.03, 0))
			part(body, box(Vector3(0.34, 0.12, 0.06)), mat(Color(0.86, 0.22, 0.18), 2), Vector3(-0.02, hy + 0.34, 0))
			part(body, box(Vector3(0.05, 0.16, 0.05)), mat(steel.darkened(0.1), 0), Vector3(0.28, hy - 0.05, 0))   # 护鼻
		"hood":     # 弓手兜帽：罩住后脑，脸露在前面，后面拖个尖
			var cloth := Color(0.2, 0.42, 0.24)
			part(body, sphere(0.31), mat(cloth), Vector3(-0.05, hy + 0.03, 0))
			part(body, sphere(0.23), mat(SKIN, 0), Vector3(0.11, hy - 0.02, 0))
			part(body, cyl(0.0, 0.12, 0.28, 10), mat(cloth), Vector3(-0.3, hy + 0.12, 0), Vector3(0, 0, 1.2))
		"hardhat":  # 工程师安全帽：亮黄半球 + 帽檐 + 中脊
			var yel := Color(1.0, 0.78, 0.15)
			part(body, sphere(0.29, -1.0, 18, true), mat(yel, 1, 0.022, 0.0, true), Vector3(0, hy + 0.06, 0))
			part(body, cyl(0.35, 0.35, 0.04, 20), mat(yel.darkened(0.1)), Vector3(0.04, hy + 0.06, 0))
			part(body, box(Vector3(0.5, 0.06, 0.07)), mat(yel.lightened(0.15), 0), Vector3(0, hy + 0.32, 0))

static func _weapon(arm_r: Node3D, arm_l: Node3D, body: Node3D, weapon: String) -> void:
	var wood := Color(0.55, 0.36, 0.2)
	var tool := Node3D.new()
	tool.position = Vector3(0, -0.3, 0)
	arm_r.add_child(tool)
	match weapon:
		"pick":
			tool.rotation = Vector3(0, 0, -0.9)
			part(tool, cyl(0.03, 0.03, 0.6, 8), mat(wood), Vector3(0, 0.22, 0))
			part(tool, box(Vector3(0.42, 0.07, 0.07)), mat(Color(0.7, 0.72, 0.76), 2), Vector3(0, 0.5, 0), Vector3(0, 0, 0.15))
		"hammer":
			tool.rotation = Vector3(0, 0, -0.8)
			part(tool, cyl(0.035, 0.035, 0.55, 8), mat(wood), Vector3(0, 0.2, 0))
			part(tool, box(Vector3(0.3, 0.2, 0.2)), mat(Color(0.6, 0.62, 0.68), 2), Vector3(0, 0.5, 0))
		"sword":
			tool.rotation = Vector3(0, 0, -0.6)
			part(tool, cyl(0.035, 0.035, 0.16, 8), mat(wood), Vector3(0, 0.02, 0))
			part(tool, box(Vector3(0.07, 0.05, 0.3)), mat(Color(0.95, 0.76, 0.28), 2), Vector3(0, 0.11, 0))
			part(tool, box(Vector3(0.05, 0.62, 0.13)), mat(Color(0.88, 0.9, 0.95), 2, 0.022, 0.0, true), Vector3(0, 0.44, 0))
			part(tool, sphere(0.05), mat(Color(0.95, 0.76, 0.28), 0), Vector3(0, -0.08, 0))
			# 圆木盾挎在左边
			var sh := Node3D.new()
			sh.position = Vector3(0.06, 0.6, -0.34)
			body.add_child(sh)
			part(sh, cyl(0.26, 0.26, 0.06, 20), mat(Color(0.66, 0.46, 0.26)), Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
			part(sh, torus(0.22, 0.27), mat(Color(0.62, 0.64, 0.7), 0), Vector3(0, 0, -0.02), Vector3(PI * 0.5, 0, 0))
			part(sh, sphere(0.08), mat(Color(0.75, 0.77, 0.82), 0, 0.02, 0.0, true), Vector3(0, 0, -0.05))
			part(sh, box(Vector3(0.06, 0.34, 0.02)), mat(Color(0.24, 0.44, 0.82), 0), Vector3(0, 0, -0.035))
		"bow":
			tool.rotation = Vector3(0, 0, -0.9)
			part(tool, cyl(0.025, 0.025, 0.32, 6), mat(Color(0.85, 0.8, 0.7), 0), Vector3(0, 0.12, 0))   # 箭
			# 长弓拿在左手：上下两段弓臂 + 弓弦
			var bow := Node3D.new()
			bow.position = Vector3(0.12, -0.3, 0.0)
			arm_l.add_child(bow)
			var bc := Color(0.5, 0.32, 0.18)
			part(bow, box(Vector3(0.05, 0.36, 0.05)), mat(bc, 2), Vector3(0.05, 0.17, 0), Vector3(0, 0, 0.3))
			part(bow, box(Vector3(0.05, 0.36, 0.05)), mat(bc, 2), Vector3(0.05, -0.17, 0), Vector3(0, 0, -0.3))
			part(bow, box(Vector3(0.012, 0.66, 0.012)), mat(Color(0.95, 0.92, 0.85), 0), Vector3(-0.02, 0, 0))
			# 箭筒背在背上
			part(body, cyl(0.08, 0.07, 0.42, 10), mat(Color(0.55, 0.3, 0.18)), Vector3(-0.24, 0.72, 0.06), Vector3(0.3, 0, 0.4))

## ---------------------------------------------------------------- Goo 黏液怪
## 无脸剪影：堆叠山包 + 底缘黏液滴 + 湿亮高光。meta: rig, body
static func goo(s := 1.0) -> Node3D:
	var root := Node3D.new()
	var rig := Node3D.new()
	root.add_child(rig)
	var body := Node3D.new()
	body.scale = Vector3.ONE * s
	rig.add_child(body)
	root.set_meta("rig", rig)
	root.set_meta("body", body)
	var c := Color(0.52, 0.74, 0.26)
	var m := mat(c, 1, 0.025, 0.0, true)
	part(body, sphere(0.45, 0.7), m, Vector3(0, 0.33, 0))
	part(body, sphere(0.27), m, Vector3(-0.14, 0.62, -0.1))
	part(body, sphere(0.21), m, Vector3(0.14, 0.56, 0.14))
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		part(body, sphere(0.1), m, Vector3(cos(a) * 0.38, 0.06, sin(a) * 0.38))
	# 暗面泡泡 + 高光
	part(body, sphere(0.07), mat(c.darkened(0.25), 0), Vector3(0.25, 0.42, 0.3))
	part(body, sphere(0.05), mat(c.darkened(0.25), 0), Vector3(-0.3, 0.3, 0.28))
	part(body, sphere(0.09, 0.06), flat(Color(0.92, 1.0, 0.8)), Vector3(-0.1, 0.72, 0.12))
	part(body, sphere(0.05, 0.035), flat(Color(0.92, 1.0, 0.8)), Vector3(0.05, 0.6, 0.33))
	return root

## ---------------------------------------------------------------- 建筑
## size = 2D 里的体量（像素）。meta: smoke（熔炉烟）/ glow（巢穴红光）/ flag（旗）
static func building(kind: String, size_px: float) -> Node3D:
	var root := Node3D.new()
	var w := size_px * S
	var stone := Color(0.66, 0.66, 0.68)
	var stone_l := Color(0.76, 0.73, 0.68)
	var dark_wood := Color(0.36, 0.23, 0.14)
	var ow := 0.04    # 建筑描边略粗
	match kind:
		"base":
			part(root, box(Vector3(w * 1.05, 0.3, w * 0.92)), mat(stone, 2, ow), Vector3(0, 0.15, 0))
			var wh := w * 0.5
			part(root, box(Vector3(w * 0.78, wh, w * 0.62)), mat(stone_l, 2, ow), Vector3(0, 0.3 + wh * 0.5, 0))
			# 石缝
			for i in 3:
				part(root, box(Vector3(w * 0.79, 0.04, w * 0.63)), mat(stone.darkened(0.1), 0), Vector3(0, 0.3 + wh * (i + 1) / 4.0, 0))
			_roof(root, w * 0.95, w * 0.45, w * 0.78, Color(0.27, 0.47, 0.82), 0.3 + wh, 0.0, ow)
			# 前面两座圆塔 + 尖顶
			for sx in [-1.0, 1.0]:
				var tp := Vector3(sx * w * 0.42, 0, w * 0.3)
				var th := w * 0.78
				part(root, cyl(w * 0.15, w * 0.16, th, 16), mat(stone_l, 1, ow), tp + Vector3(0, th * 0.5, 0))
				part(root, cyl(w * 0.17, w * 0.17, 0.12, 16), mat(stone, 1, ow), tp + Vector3(0, th, 0))
				part(root, cyl(0.0, w * 0.2, w * 0.38, 16), mat(Color(0.27, 0.47, 0.82), 1, ow), tp + Vector3(0, th + 0.06 + w * 0.19, 0))
				part(root, box(Vector3(0.1, 0.18, 0.04)), mat(Color(1.0, 0.85, 0.4), 0, 0.02, 1.2), tp + Vector3(0, th * 0.62, w * 0.155))
			# 拱门 + 暖窗
			part(root, box(Vector3(w * 0.22, w * 0.3, 0.06)), mat(dark_wood, 2, ow), Vector3(0, 0.3 + w * 0.15, w * 0.31))
			part(root, cyl(w * 0.11, w * 0.11, 0.06, 16), mat(dark_wood, 0), Vector3(0, 0.3 + w * 0.3, w * 0.31), Vector3(PI * 0.5, 0, 0))
			for sx in [-1.0, 1.0]:
				part(root, box(Vector3(0.18, 0.22, 0.04)), mat(Color(1.0, 0.85, 0.4), 0, 0.02, 1.2), Vector3(sx * w * 0.2, 0.3 + wh * 0.62, w * 0.315))
			_flag(root, Vector3(0, 0.3 + wh + w * 0.45, 0), w * 0.45, Color(0.27, 0.47, 0.82))
		"barracks":
			part(root, box(Vector3(w * 1.0, 0.25, w * 0.86)), mat(stone, 2, ow), Vector3(0, 0.125, 0))
			var wh := w * 0.48
			part(root, box(Vector3(w * 0.82, wh, w * 0.64)), mat(Color(0.96, 0.89, 0.72), 2, ow), Vector3(0, 0.25 + wh * 0.5, 0))
			# 木架：竖梁 + 横梁 + 斜撑（只贴正面和侧面）
			for x in [-0.39, -0.13, 0.13, 0.39]:
				part(root, box(Vector3(0.09, wh, 0.05)), mat(dark_wood, 0), Vector3(x * w, 0.25 + wh * 0.5, w * 0.325))
			part(root, box(Vector3(w * 0.84, 0.09, 0.05)), mat(dark_wood, 0), Vector3(0, 0.25 + wh * 0.96, w * 0.325))
			part(root, box(Vector3(w * 0.84, 0.08, 0.05)), mat(dark_wood, 0), Vector3(0, 0.25 + wh * 0.5, w * 0.325))
			_roof(root, w * 0.98, w * 0.44, w * 0.8, Color(0.74, 0.32, 0.2), 0.25 + wh, 0.0, ow)
			part(root, box(Vector3(w * 0.18, w * 0.26, 0.06)), mat(dark_wood, 2, ow), Vector3(0, 0.25 + w * 0.13, w * 0.33))
			# 盾徽
			part(root, cyl(0.2, 0.2, 0.05, 18), mat(Color(0.8, 0.22, 0.18)), Vector3(w * 0.26, 0.25 + wh * 0.7, w * 0.34), Vector3(PI * 0.5, 0, 0))
			part(root, box(Vector3(0.05, 0.24, 0.02)), mat(Color(0.98, 0.9, 0.6), 0), Vector3(w * 0.26, 0.25 + wh * 0.7, w * 0.37))
			# 门口的训练木桩
			var dp := Vector3(w * 0.62, 0, w * 0.3)
			part(root, cyl(0.06, 0.06, 0.9, 8), mat(Color(0.6, 0.42, 0.24)), dp + Vector3(0, 0.45, 0))
			part(root, box(Vector3(0.08, 0.08, 0.55)), mat(Color(0.6, 0.42, 0.24), 2), dp + Vector3(0, 0.7, 0))
			part(root, sphere(0.15), mat(Color(0.9, 0.82, 0.6)), dp + Vector3(0, 0.98, 0))
			_flag(root, Vector3(-w * 0.3, 0.25 + wh + w * 0.3, 0), w * 0.42, Color(0.84, 0.25, 0.2))
		"warehouse":
			part(root, box(Vector3(w * 1.0, 0.22, w * 0.86)), mat(stone, 2, ow), Vector3(0, 0.11, 0))
			var wh := w * 0.46
			var plank := Color(0.76, 0.54, 0.32)
			part(root, box(Vector3(w * 0.8, wh, w * 0.64)), mat(plank, 2, ow), Vector3(0, 0.22 + wh * 0.5, 0))
			for i in 3:
				part(root, box(Vector3(w * 0.81, 0.035, w * 0.65)), mat(plank.darkened(0.25), 0), Vector3(0, 0.22 + wh * (i + 1) / 4.0, 0))
			_roof(root, w * 0.98, w * 0.46, w * 0.82, Color(0.55, 0.33, 0.2), 0.22 + wh, 0.0, ow)
			part(root, box(Vector3(w * 0.3, w * 0.3, 0.06)), mat(dark_wood, 2, ow), Vector3(0, 0.22 + w * 0.15, w * 0.325))
			part(root, box(Vector3(0.04, w * 0.3, 0.07)), mat(Color(0.2, 0.12, 0.07), 0), Vector3(0, 0.22 + w * 0.15, w * 0.33))
			# 门前货堆：木箱 + 金矿堆 + 麻袋
			for i in 3:
				var cp := Vector3(-w * 0.42 + (i % 2) * 0.34, 0.17 + int(i / 2) * 0.32, w * 0.5)
				part(root, box(Vector3(0.32, 0.32, 0.32)), mat(Color(0.72, 0.52, 0.3), 2, 0.03), cp, Vector3(0, 0.2 * i, 0))
			for i in 4:
				part(root, sphere(0.13), mat(Color(1.0, 0.8, 0.25), 1, 0.02, 0.15), Vector3(w * 0.3 + (i % 2) * 0.2, 0.12 + int(i / 2) * 0.16, w * 0.5 + (i % 3) * 0.06))
			part(root, sphere(0.2, 0.32), mat(Color(0.9, 0.82, 0.62)), Vector3(w * 0.55, 0.16, w * 0.25))
		"smelter":
			part(root, box(Vector3(w * 1.0, 0.22, w * 0.86)), mat(stone, 2, ow), Vector3(0, 0.11, 0))
			var wh := w * 0.44
			var brick := Color(0.74, 0.44, 0.32)
			part(root, box(Vector3(w * 0.72, wh, w * 0.58)), mat(brick, 2, ow), Vector3(-w * 0.04, 0.22 + wh * 0.5, 0))
			part(root, sphere(w * 0.3, w * 0.36, 18, true), mat(brick.darkened(0.1), 1, ow), Vector3(-w * 0.04, 0.22 + wh, 0))
			# 炉口：深色框 + 橙光 + 亮芯
			var mp := Vector3(-w * 0.04, 0.22 + wh * 0.4, w * 0.295)
			part(root, box(Vector3(w * 0.3, w * 0.24, 0.05)), mat(Color(0.22, 0.14, 0.1), 0), mp)
			part(root, box(Vector3(w * 0.22, w * 0.16, 0.06)), mat(Color(1.0, 0.45, 0.1), 0, 0.02, 2.2), mp + Vector3(0, 0, 0.01))
			part(root, box(Vector3(w * 0.1, w * 0.07, 0.07)), mat(Color(1.0, 0.85, 0.35), 0, 0.02, 2.5), mp + Vector3(0, -0.02, 0.015))
			# 烟囱
			var cp := Vector3(w * 0.26, 0, -w * 0.12)
			var ch := w * 1.05
			part(root, cyl(w * 0.1, w * 0.12, ch, 12), mat(Color(0.5, 0.48, 0.48), 1, ow), cp + Vector3(0, ch * 0.5, 0))
			part(root, cyl(w * 0.13, w * 0.13, 0.1, 12), mat(Color(0.38, 0.36, 0.36), 1, ow), cp + Vector3(0, ch, 0))
			var smoke: Array = []
			for i in 3:
				smoke.append(part(root, sphere(0.2), mat(Color(0.85, 0.85, 0.85), 1, 0.02), cp + Vector3(0, ch + 0.3 + i * 0.35, 0)))
			root.set_meta("smoke", smoke)
			root.set_meta("smoke_base", cp + Vector3(0, ch + 0.15, 0))
			# 铁砧 + 铁锭堆
			var ap := Vector3(w * 0.42, 0.22, w * 0.42)
			part(root, box(Vector3(0.18, 0.2, 0.18)), mat(Color(0.35, 0.33, 0.33), 2), ap + Vector3(0, 0.1, 0))
			part(root, box(Vector3(0.38, 0.1, 0.2)), mat(Color(0.42, 0.42, 0.45), 2, 0.02, 0.0, true), ap + Vector3(0, 0.25, 0))
			for i in 3:
				part(root, box(Vector3(0.26, 0.09, 0.13)), mat(Color(0.85, 0.87, 0.9), 2, 0.02, 0.0, true), Vector3(-w * 0.42 + (i % 2) * 0.15, 0.27 + int(i / 2) * 0.09, w * 0.45))
		"workshop":
			part(root, box(Vector3(w * 1.0, 0.18, w * 0.86)), mat(Color(0.6, 0.42, 0.26), 2, ow), Vector3(0, 0.09, 0))
			var ph := w * 0.62
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					part(root, cyl(0.07, 0.08, ph, 8), mat(Color(0.55, 0.36, 0.2)), Vector3(sx * w * 0.42, 0.18 + ph * 0.5, sz * w * 0.33))
			_roof(root, w * 1.04, w * 0.32, w * 0.86, Color(0.42, 0.6, 0.32), 0.18 + ph, 0.0, ow)
			# 工作台 + 锯 + 木板 + 原木堆
			part(root, box(Vector3(w * 0.5, 0.08, w * 0.26)), mat(Color(0.8, 0.6, 0.36), 2), Vector3(0, 0.58, 0.05))
			for sx in [-1.0, 1.0]:
				part(root, box(Vector3(0.06, 0.38, 0.06)), mat(Color(0.55, 0.36, 0.2), 0), Vector3(sx * w * 0.2, 0.37, 0.05))
			part(root, box(Vector3(0.42, 0.12, 0.02)), mat(Color(0.88, 0.9, 0.94), 2, 0.015, 0.0, true), Vector3(0.05, 0.7, 0.05), Vector3(0, 0, -0.3))
			for i in 3:
				part(root, box(Vector3(0.1, 0.8, 0.22)), mat(Color(0.92, 0.74, 0.46), 2, 0.02), Vector3(-w * 0.32 + i * 0.12, 0.58, -w * 0.2), Vector3(0, 0, 0.12))
			for i in 3:
				part(root, cyl(0.12, 0.12, 0.6, 10), mat(Color(0.6, 0.4, 0.22)), Vector3(w * 0.52, 0.12 + int(i / 2) * 0.2, w * 0.3 + (i % 2) * 0.24 - int(i / 2) * 0.12), Vector3(PI * 0.5, 0, 0))
		"hive":
			part(root, cyl(w * 0.78, w * 0.8, 0.03, 24), mat(Color(0.36, 0.5, 0.2), 0), Vector3(0, 0.015, 0))
			var rock := Color(0.46, 0.4, 0.46)
			var rm := mat(rock, 1, ow)
			part(root, sphere(w * 0.42, w * 0.7), rm, Vector3(0, w * 0.3, -w * 0.05))
			part(root, sphere(w * 0.28), rm, Vector3(-w * 0.32, w * 0.18, w * 0.08))
			part(root, sphere(w * 0.3, w * 0.5), rm, Vector3(w * 0.34, w * 0.2, 0))
			part(root, sphere(w * 0.26), rm, Vector3(-w * 0.05, w * 0.6, -w * 0.12))
			# 骨刺
			for sp in [Vector3(-0.2, 0.72, -0.1), Vector3(0.02, 0.86, -0.15), Vector3(0.24, 0.66, -0.05), Vector3(-0.4, 0.38, 0.0), Vector3(0.48, 0.36, 0.05)]:
				var p: Vector3 = sp * w
				part(root, cyl(0.0, w * 0.07, w * 0.3, 10), mat(Color(0.94, 0.9, 0.78), 1, 0.025), p + Vector3(0, w * 0.12, 0), Vector3(0.1, 0, (p.x / w) * -1.2))
			# 红光洞口
			var mouth := Vector3(0, w * 0.2, w * 0.3)
			part(root, sphere(w * 0.21, w * 0.34), mat(Color(0.12, 0.05, 0.08), 0), mouth)
			var glow := part(root, sphere(w * 0.12, w * 0.2), mat(Color(1.0, 0.25, 0.12), 0, 0.02, 2.5), mouth + Vector3(0, -0.02, 0.08))
			root.set_meta("glow", glow)
			# 黏液滴
			for dx in [-0.42, 0.44, 0.15]:
				part(root, sphere(0.13), mat(Color(0.52, 0.74, 0.26), 1, 0.02, 0.0, true), Vector3(dx * w, 0.12, w * 0.3))
	return root

## 旗杆 + 飘旗（meta flag = 旗面，用来飘动）
static func _flag(root: Node3D, base: Vector3, h: float, c: Color) -> void:
	part(root, cyl(0.035, 0.035, h, 6), mat(Color(0.4, 0.28, 0.18), 0), base + Vector3(0, h * 0.5, 0))
	part(root, sphere(0.06), mat(Color(0.95, 0.78, 0.3), 0), base + Vector3(0, h, 0))
	var pivot := Node3D.new()
	pivot.position = base + Vector3(0, h * 0.82, 0)
	root.add_child(pivot)
	part(pivot, box(Vector3(0.5, 0.3, 0.03)), mat(c, 2, 0.02), Vector3(0.27, 0, 0))
	root.set_meta("flag", pivot)

## ---------------------------------------------------------------- 资源点
## 矿：灰石座 + 金色水晶簇；树：王国保卫战式圆团树（每棵按位置随机变体）
static func res_node(kind: String, seed_v: int) -> Node3D:
	var root := Node3D.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var inner := Node3D.new()
	root.add_child(inner)
	root.set_meta("inner", inner)
	inner.rotation.y = rng.randf() * TAU
	if kind == "ore":
		part(inner, sphere(0.36, 0.42), mat(Color(0.6, 0.57, 0.55)), Vector3(0, 0.1, 0))
		part(inner, sphere(0.2, 0.26), mat(Color(0.52, 0.5, 0.48)), Vector3(0.3, 0.06, 0.12))
		var gold := mat(Color(1.0, 0.78, 0.18), 1, 0.02, 0.35, true)
		var crystals := [[Vector3(0, 0.38, 0), 0.0, 0.5], [Vector3(0.16, 0.3, 0.1), 0.5, 0.36],
			[Vector3(-0.14, 0.28, 0.1), -0.55, 0.34], [Vector3(0.02, 0.26, -0.18), 0.35, 0.3]]
		for c in crystals:
			part(inner, cyl(0.0, 0.11, c[2], 6), gold, c[0], Vector3(c[1] * 0.6, 0, c[1]))
	else:
		var trunk := Color(0.5, 0.33, 0.2)
		part(inner, cyl(0.08, 0.12, 0.7, 8), mat(trunk), Vector3(0, 0.35, 0))
		var g1 := Color(0.3, 0.6, 0.26).lerp(Color(0.4, 0.66, 0.24), rng.randf())
		var sc := rng.randf_range(0.9, 1.12)
		part(inner, sphere(0.46 * sc), mat(g1), Vector3(0, 1.0 * sc, 0))
		part(inner, sphere(0.34 * sc), mat(g1.lightened(0.08)), Vector3(-0.2, 0.8 * sc, 0.16))
		part(inner, sphere(0.36 * sc), mat(g1.darkened(0.06)), Vector3(0.22, 0.82 * sc, -0.12))
		part(inner, sphere(0.3 * sc), mat(g1.lightened(0.14)), Vector3(0.02, 1.32 * sc, 0.05))
	return root

## ---------------------------------------------------------------- 资源 / 按钮图标模型
static func item(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"ore":
			var gold := mat(Color(1.0, 0.78, 0.18), 1, 0.03, 0.35, true)
			part(root, cyl(0.0, 0.22, 0.8, 6), gold, Vector3(0, 0.4, 0))
			part(root, cyl(0.0, 0.18, 0.6, 6), gold, Vector3(0.3, 0.28, 0.05), Vector3(0, 0, -0.5))
			part(root, cyl(0.0, 0.16, 0.55, 6), gold, Vector3(-0.28, 0.26, 0.05), Vector3(0, 0, 0.55))
			part(root, sphere(0.4, 0.3), mat(Color(0.6, 0.57, 0.55), 1, 0.03), Vector3(0, 0.05, 0))
		"wood":
			for i in 3:
				var p := Vector3((i - 1) * 0.3 + (0.15 if i == 2 else 0.0), 0.18 + (0.28 if i == 2 else 0.0), 0)
				if i == 2:
					p.x = 0.0
				part(root, cyl(0.16, 0.16, 0.9, 12), mat(Color(0.62, 0.4, 0.22), 1, 0.03), p, Vector3(PI * 0.5, 0, 0))
				part(root, cyl(0.13, 0.13, 0.92, 12), mat(Color(0.95, 0.8, 0.55), 0), p, Vector3(PI * 0.5, 0, 0))
		"ingot":
			for i in 3:
				var p := Vector3((i % 2) * 0.42 - 0.21 + (0.21 if i == 2 else 0.0), 0.12 + int(i / 2) * 0.24, 0)
				part(root, box(Vector3(0.38, 0.22, 0.6)), mat(Color(0.82, 0.85, 0.9), 2, 0.03, 0.0, true), p)
		"plank":
			for i in 3:
				part(root, box(Vector3(0.9, 0.12, 0.32)), mat(Color(0.94, 0.74, 0.44), 2, 0.03), Vector3(0, 0.08 + i * 0.14, 0), Vector3(0, 0.25 * (i - 1), 0))
	return root

## 统一入口：图标 / 头像用的模型
static func icon_model(key: String) -> Node3D:
	match key:
		"worker", "engineer", "sword", "archer":
			return human(key)
		"goo":
			return goo()
		"base", "barracks", "warehouse", "smelter", "workshop", "hive":
			var sz := {"base": 76.0, "barracks": 60.0, "warehouse": 64.0, "smelter": 56.0, "workshop": 56.0, "hive": 84.0}
			return building(key, sz[key])
		"ore", "wood", "ingot", "plank":
			return item(key)
	return Node3D.new()

## 单位 → 模型 key
static func key_of(n: Node) -> String:
	if n is Worker:
		return "worker"
	if n is Engineer:
		return "engineer"
	if n is Soldier:
		return "archer" if n.is_ranged else "sword"
	if n is Goo:
		return "goo"
	if n is Building:
		return n.kind
	return ""
