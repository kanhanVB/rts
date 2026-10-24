class_name Ground
extends Node2D
## 随机地图的地面：一张铺满全图的矩形 + 着色器。
## 草地深浅斑、土路（沙色路面 + 下沿暗边 + 锯齿草边 + 小石子）、林下暗地、巢穴周围的黏液地，
## 都由一张低分辨率遮罩（1 像素 = 8 世界像素）+ 无缝噪声在 GPU 上算出来，边缘是硬朗的 KR 卡通色块。
## 遮罩通道：R = 土路距离场（0.5 = 路边）/ G = 林地覆盖 / B = 巢穴黏液 / A = 矿场（矿堆脚下踩秃的土）
## 第二张遮罩 mask2：R = 河的距离场（0.5 = 岸边）/ G = 浅滩（0.5 以内是能趟的浅水）

const MASK_PX := 8.0
const ROAD_HALF := 25.0     # 土路半宽（世界像素）
const PLAZA_R := 118.0      # 主城脚下那片空地的半径
const QUARRY_REACH := 64.0  # 每堆矿脚下的秃地：横向离矿心约 32px、纵向压扁 1.35 倍是边，几堆连成一片、边缘随噪声起伏
const QUARRY_SQUASH := 1.35

const SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_linear, repeat_disable;
uniform sampler2D mask2 : filter_linear, repeat_disable;
uniform sampler2D blobs : filter_linear, repeat_enable;
uniform sampler2D fine : filter_linear, repeat_enable;
uniform sampler2D cells : filter_linear, repeat_enable;
uniform vec2 world_size;
uniform vec2 mask_px;
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	vec2 uv = wp / world_size;
	float b1 = texture(blobs, wp / 1100.0).r;
	float b2 = texture(blobs, wp / 420.0 + vec2(0.37, 0.71)).r;
	float f = texture(fine, wp / 160.0).r;
	vec3 grass = vec3(0.486, 0.651, 0.153);
	vec3 grass_dark = vec3(0.424, 0.600, 0.157);
	vec3 grass_light = vec3(0.545, 0.702, 0.188);
	// 草地：两层硬边色斑（卡通平涂，不是柔和渐变）
	vec3 c = grass;
	c = mix(c, grass_dark, smoothstep(0.56, 0.58, b1 + (f - 0.5) * 0.06));
	c = mix(c, grass_light, smoothstep(0.62, 0.64, b2 + (f - 0.5) * 0.05) * 0.8);
	vec4 m = texture(mask, uv);
	// 林地：树底下压暗，边缘随噪声起伏
	float forest = smoothstep(0.30, 0.34, m.g + (f - 0.5) * 0.12);
	c = mix(c, vec3(0.318, 0.494, 0.137), forest);
	// 巢穴黏液地：硬边的暗紫泥地，外沿一圈更深的描边
	float cv = m.b + (b2 - 0.5) * 0.18 + (f - 0.5) * 0.06;
	float creep_edge = smoothstep(0.46, 0.475, cv);
	float creep = smoothstep(0.49, 0.505, cv);
	c = mix(c, vec3(0.29, 0.25, 0.20), creep_edge);
	c = mix(c, vec3(0.42, 0.34, 0.38) * (0.92 + b1 * 0.16), creep);
	// 矿场：一片踩秃的褐土，外沿一圈深色草边，土里撒灰色碎石（不是土路那种沙黄，远看分得开）
	float qv = m.a + (b2 - 0.5) * 0.30 + (f - 0.5) * 0.12;
	float q_edge = smoothstep(0.43, 0.445, qv);
	float q_in = smoothstep(0.47, 0.485, qv);
	c = mix(c, vec3(0.30, 0.44, 0.12), q_edge * 0.9);
	vec3 earth = vec3(0.62, 0.50, 0.30) * (0.94 + b1 * 0.12);
	earth = mix(earth, vec3(0.53, 0.42, 0.25), smoothstep(0.55, 0.75, qv) * 0.5);
	float qpeb = 1.0 - smoothstep(0.07, 0.10, texture(cells, wp / 120.0 + vec2(0.31, 0.57)).r);
	earth = mix(earth, vec3(0.50, 0.49, 0.46), qpeb * 0.85);
	c = mix(c, earth, q_in);
	// 土路：距离场 0.5 为路边；外面一圈锯齿状深绿草边，里面沙色路面
	float r = m.r + (f - 0.5) * 0.10;
	float fringe = smoothstep(0.415, 0.43, r + (texture(fine, wp / 75.0).r - 0.5) * 0.12);
	c = mix(c, vec3(0.243, 0.420, 0.122), fringe);
	float road = smoothstep(0.47, 0.49, r);
	vec3 dirt = vec3(0.886, 0.725, 0.345) * (0.97 + b2 * 0.06);
	// 路的下沿（往上一点还是路、往下就出路了）压一条暗边，像王国保卫战的路肩
	float r_up = texture(mask, uv - vec2(0.0, 7.0 / world_size.y)).r;
	float lower = smoothstep(0.62, 0.52, r) * step(r, r_up + 0.02);
	dirt = mix(dirt, vec3(0.745, 0.565, 0.267), lower * 0.9);
	// 小石子
	float peb = 1.0 - smoothstep(0.08, 0.11, texture(cells, wp / 260.0).r);
	dirt = mix(dirt, vec3(0.80, 0.63, 0.32), peb * smoothstep(0.6, 0.7, r));
	c = mix(c, dirt, road);
	// 河：岸边一圈湿泥 → 白色浪花边 → 浅水 → 深水；水面上漂几道亮纹；浅滩颜色浅、看得见水底的石头
	vec4 m2 = texture(mask2, uv);
	float wv = m2.r + (f - 0.5) * 0.07 + (b2 - 0.5) * 0.05;
	float bank = smoothstep(0.405, 0.42, wv);
	float wet = smoothstep(0.455, 0.468, wv);
	c = mix(c, vec3(0.33, 0.29, 0.18), bank);
	float fd = smoothstep(0.42, 0.58, m2.g);
	vec3 water = mix(vec3(0.33, 0.64, 0.72), vec3(0.17, 0.43, 0.62), smoothstep(0.5, 0.8, wv));
	water = mix(water, vec3(0.47, 0.73, 0.73), fd);
	float rp = texture(blobs, wp / 260.0 + vec2(TIME * 0.010, TIME * 0.006)).r * 0.55 + texture(fine, wp / 210.0 - vec2(TIME * 0.008, -TIME * 0.005)).r * 0.45;
	float streak = smoothstep(0.575, 0.59, rp) * (1.0 - smoothstep(0.605, 0.62, rp));
	water = mix(water, vec3(0.62, 0.86, 0.90), streak * 0.5 * (1.0 - fd));
	// 浅滩：沙底透上来（偏黄绿），撒些卵石
	water = mix(water, vec3(0.62, 0.74, 0.62), fd * 0.45);
	float stone = 1.0 - smoothstep(0.10, 0.13, texture(cells, wp / 90.0 + vec2(0.13, 0.41)).r);
	water = mix(water, vec3(0.6, 0.58, 0.5), stone * fd * 0.7);
	float foam = 1.0 - smoothstep(0.475, 0.50, wv);
	water = mix(water, vec3(0.88, 0.96, 0.95), foam * 0.9);
	c = mix(c, water, wet);
	COLOR = vec4(c, 1.0);
}
"""

var size_px := Vector2(1280, 720)

func build(layout: Dictionary, w: float, h: float) -> void:
	size_px = Vector2(w, h)
	z_index = -2
	var mw := int(ceil(w / MASK_PX))
	var mh := int(ceil(h / MASK_PX))
	var road := PackedFloat32Array()
	road.resize(mw * mh)
	var creep := PackedFloat32Array()
	creep.resize(mw * mh)
	var quarry := PackedFloat32Array()
	quarry.resize(mw * mh)
	for p in layout.get("ore", []):
		_splat(quarry, mw, mh, p + Vector2(0, 5), QUARRY_REACH, QUARRY_SQUASH)
	for cp in layout.get("camps", []):
		for p in cp.rich:
			_splat(quarry, mw, mh, p + Vector2(0, 5), QUARRY_REACH * 1.06, QUARRY_SQUASH)
	# 土路：沿路每 6px 取一点，按点到路心的距离写距离场（取最大值 = 离最近那段路的距离）
	var noise := FastNoiseLite.new()
	noise.seed = int(layout.get("seed", 1))
	noise.frequency = 0.004
	for rd in layout.roads:
		var pts: Array = _resample(rd, 6.0)
		for i in pts.size():
			var p: Vector2 = pts[i]
			var half := ROAD_HALF * (0.9 + 0.25 * noise.get_noise_2d(p.x, p.y))
			# 主城端路面放宽一点，和城下空地自然接上
			_splat(road, mw, mh, p, half * 2.0)
	_splat(road, mw, mh, layout.base, PLAZA_R * 2.0)
	for hp in layout.hives:
		_splat(creep, mw, mh, hp, 290.0)
		_splat(road, mw, mh, hp, 150.0)
	# 河：沿中线每 6px 盖一个章（半宽处 = 0.5）；浅滩一圈
	var water := PackedFloat32Array()
	water.resize(mw * mh)
	var ford := PackedFloat32Array()
	ford.resize(mw * mh)
	var rv: Dictionary = layout.get("river", {})
	if not rv.is_empty():
		var pts: Array = rv.pts
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var n := maxi(1, int(a.distance_to(b) / 6.0))
			for k in n:
				var t := float(k) / n
				_splat(water, mw, mh, a.lerp(b, t), lerpf(rv.hw[i], rv.hw[i + 1], t) * 2.0)
	for fp in layout.get("fords", []):
		_splat(ford, mw, mh, fp, MapGen.FORD_R * 2.0)
		# 两岸各踩出一条小土路通到浅滩（纯视觉：告诉玩家这里能趟过去）
		var n := RiverArt.cross_dir(rv, fp)
		var hw := RiverArt.half_at(rv, fp)
		var along := n.orthogonal()
		for side in [-1.0, 1.0]:
			var d := hw - 4.0
			var len := 92.0
			while d < hw + len:
				var k := (d - hw) / len    # 0 = 岸边 → 1 = 小路尽头：越走越窄，轻轻拐个弯
				_splat(road, mw, mh, fp + n * side * d + along * sin(k * 2.2) * 10.0 * side, lerpf(26.0, 10.0, clampf(k, 0.0, 1.0)))
				d += 4.0
	# 林地：格子占用图（树/密林 = 1）放大到遮罩分辨率，双线性插值后就是平滑的覆盖度
	var gw: int = layout.gw
	var gh: int = layout.gh
	var occ := PackedByteArray()
	occ.resize(gw * gh)
	for i in gw * gh:
		occ[i] = 255 if layout.cells[i] == MapGen.C_TREE or layout.cells[i] == MapGen.C_WOODS else 0
	var occ_img := Image.create_from_data(gw, gh, false, Image.FORMAT_L8, occ)
	occ_img.resize(mw, mh, Image.INTERPOLATE_CUBIC)
	var occ_data := occ_img.get_data()
	var data := PackedByteArray()
	data.resize(mw * mh * 4)
	for i in mw * mh:
		data[i * 4] = int(clampf(road[i], 0.0, 1.0) * 255.0)
		data[i * 4 + 1] = occ_data[i]
		data[i * 4 + 2] = int(clampf(creep[i], 0.0, 1.0) * 255.0)
		data[i * 4 + 3] = int(clampf(quarry[i], 0.0, 1.0) * 255.0)
	var mask := ImageTexture.create_from_image(Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, data))
	var data2 := PackedByteArray()
	data2.resize(mw * mh * 4)
	for i in mw * mh:
		data2[i * 4] = int(clampf(water[i], 0.0, 1.0) * 255.0)
		data2[i * 4 + 1] = int(clampf(ford[i], 0.0, 1.0) * 255.0)
	var mask2 := ImageTexture.create_from_image(Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, data2))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("mask", mask)
	mat.set_shader_parameter("mask2", mask2)
	mat.set_shader_parameter("blobs", _noise_tex(noise.seed + 1, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 3))
	mat.set_shader_parameter("fine", _noise_tex(noise.seed + 2, FastNoiseLite.TYPE_SIMPLEX, 0.03, 2))
	var cn := _noise_tex(noise.seed + 3, FastNoiseLite.TYPE_CELLULAR, 0.03, 1)
	mat.set_shader_parameter("cells", cn)
	mat.set_shader_parameter("world_size", size_px)
	mat.set_shader_parameter("mask_px", Vector2(mw, mh))
	material = mat
	queue_redraw()

## 无缝噪声贴图（256²，平铺使用）
static func _noise_tex(seed_: int, type: int, freq: float, octaves: int) -> Texture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	if type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	return ImageTexture.create_from_image(n.get_seamless_image(256, 256))

## 距离场盖章：p 周围 reach 像素内写 1 - d/reach（reach 的一半处 = 0.5 = 边界），和已有值取大。
## squash > 1 = 纵向压扁成椭圆（斜俯视下的一片地）
static func _splat(f: PackedFloat32Array, mw: int, mh: int, p: Vector2, reach: float, squash := 1.0) -> void:
	var c := p / MASK_PX
	var r := reach / MASK_PX
	for y in range(maxi(0, int(c.y - r)), mini(mh, int(c.y + r) + 2)):
		for x in range(maxi(0, int(c.x - r)), mini(mw, int(c.x + r) + 2)):
			var d := Vector2(x + 0.5 - c.x, (y + 0.5 - c.y) * squash).length()
			var v := 1.0 - d / r
			if v > f[y * mw + x]:
				f[y * mw + x] = v

static func _resample(pts: Array, step: float) -> Array:
	var out: Array = []
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / step))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	out.append(pts[pts.size() - 1])
	return out

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size_px), Color.WHITE)
