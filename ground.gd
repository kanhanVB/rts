class_name Ground
extends Node2D
## 随机地图的地面：一张铺满全图的矩形 + 着色器。
## 草地深浅斑、土路（沙色路面 + 下沿暗边 + 锯齿草边 + 小石子）、林下暗地、巢穴周围的黏液地，
## 都由一张低分辨率遮罩（1 像素 = 8 世界像素）+ 无缝噪声在 GPU 上算出来，边缘是硬朗的 KR 卡通色块。
## 遮罩通道：R = 土路距离场（0.5 = 路边）/ G = 林地覆盖 / B = 巢穴黏液

const MASK_PX := 8.0
const ROAD_HALF := 25.0     # 土路半宽（世界像素）
const PLAZA_R := 118.0      # 主城脚下那片空地的半径

const SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_linear, repeat_disable;
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
		data[i * 4 + 3] = 255
	var mask := ImageTexture.create_from_image(Image.create_from_data(mw, mh, false, Image.FORMAT_RGBA8, data))
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("mask", mask)
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

## 距离场盖章：p 周围 reach 像素内写 1 - d/reach（reach 的一半处 = 0.5 = 边界），和已有值取大
static func _splat(f: PackedFloat32Array, mw: int, mh: int, p: Vector2, reach: float) -> void:
	var c := p / MASK_PX
	var r := reach / MASK_PX
	for y in range(maxi(0, int(c.y - r)), mini(mh, int(c.y + r) + 2)):
		for x in range(maxi(0, int(c.x - r)), mini(mw, int(c.x + r) + 2)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
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
