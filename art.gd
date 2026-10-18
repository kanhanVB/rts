class_name Art
extends RefCounted
## 美术素材入口：按 key（如 "units/worker_idle"）取贴图、锚点，并提供"按锚点画到指定高度"的小工具。
## 素材缺了就返回 null / false，调用方自动退回原来的程序化画法——所以素材可以一批批补。

const OUTLINE := Color(0.16, 0.1, 0.05)
static var enabled := true
static var _tex := {}
static var _font: Font = null
static var _body_font: Font = null

static func has(key: String) -> bool:
	return enabled and ArtData.SPRITES.has(key) and tex(key) != null

static func tex(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var path := "res://art/%s.png" % key
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[key] = t
	return t

static func info(key: String) -> Dictionary:
	return ArtData.SPRITES.get(key, {})

## 运行时缩小一份（UI 九宫格要的小号边框）
static func scaled(key: String, k: float) -> Texture2D:
	var ck := "%s@%.3f" % [key, k]
	if _tex.has(ck):
		return _tex[ck]
	var t := tex(key)
	if t == null:
		return null
	var img := t.get_image()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	var out := ImageTexture.create_from_image(img)
	_tex[ck] = out
	return out

## 地图上画着树林的地方（来自 tools/prepare_art.py 的分析）：不能盖房，右键点进去会落到最近的空地上
static func forest_at(p: Vector2) -> bool:
	if not has("map/map") or ArtData.FOREST.is_empty():
		return false
	var c: float = ArtData.FOREST_CELL
	var gy := int(p.y / c)
	if p.y < 0.0 or gy >= ArtData.FOREST.size():
		return true
	var row: String = ArtData.FOREST[gy]
	var gx := int(p.x / c)
	if p.x < 0.0 or gx >= row.length():
		return true
	return row[gx] == "1"

## 离 p 最近的非树林点（p 本身能走就原样返回）
static func open_point(p: Vector2) -> Vector2:
	if not forest_at(p):
		return p
	var c: float = ArtData.FOREST_CELL
	for r in range(1, 40):
		var n := 8 * r
		var best := Vector2.INF
		for i in n:
			var q := p + Vector2.from_angle(TAU * i / n) * (r * c * 0.75)
			if not forest_at(q) and (best == Vector2.INF or q.distance_to(p) < best.distance_to(p)):
				best = q
		if best != Vector2.INF:
			return best
	return p

## 标题字：仓耳周珂正大榜书（王国保卫战：起源 中文版那种粗毛笔榜书），只裁了代码里用到的字；
## 缺的字/符号落到思源柔黑 Heavy（GB2312 全集）。重新裁字：tools/subset_fonts.py
const FONT_PATH := "res://fonts/TsangerZhoukeZhengdabangshu.ttf"
const FONT_FALLBACK_PATH := "res://fonts/ResourceHanRoundedCN-Heavy.ttf"

static func font() -> Font:
	if _font == null:
		var fb: Font = load(FONT_FALLBACK_PATH) if ResourceLoader.exists(FONT_FALLBACK_PATH) else null
		var f: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else fb
		if f != null and fb != null and f != fb:
			f.fallbacks = [fb]
		_font = f if f != null else ThemeDB.fallback_font
	return _font

## 正文字：长说明/数值面板用圆黑（起源 中文版里的说明文字也是黑体，不用毛笔字）
static func body_font() -> Font:
	if _body_font == null:
		_body_font = load(FONT_FALLBACK_PATH) if ResourceLoader.exists(FONT_FALLBACK_PATH) else font()
	return _body_font

## 以锚点（单位=脚底，建筑=底边中心）对准 pos，按显示高度 height 画出来。
## flip=朝左；squash=挤压拉伸；rot=绕锚点旋转
static func draw(ci: CanvasItem, key: String, pos: Vector2, height: float, flip := false,
		mod := Color.WHITE, rot := 0.0, squash := Vector2.ONE) -> float:
	var t := tex(key)
	if t == null:
		return 0.0
	var d := info(key)
	var k := height / float(d.h)
	ci.draw_set_transform(pos, rot, Vector2(k * squash.x * (-1.0 if flip else 1.0), k * squash.y))
	ci.draw_texture(t, Vector2(-d.ax, -d.ay), mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return float(d.w) * k

## 同上，但按显示宽度定尺寸（建筑 / 资源）。返回画出来的高度
static func draw_w(ci: CanvasItem, key: String, pos: Vector2, width: float, mod := Color.WHITE, flip := false) -> float:
	var d := info(key)
	if d.is_empty():
		return 0.0
	var h := width * float(d.h) / float(d.w)
	draw(ci, key, pos, h, flip, mod)
	return h

## 描边字（世界里的小标签）
static func text(ci: CanvasItem, pos: Vector2, s: String, size := 13, col := Color(1.0, 0.95, 0.8), center := true) -> void:
	var f := font()
	var x := pos.x
	if center:
		x -= f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * 0.5
	ci.draw_string_outline(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, OUTLINE)
	ci.draw_string(f, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

## KR 式血条：深色底 + 亮色条
static func hp_bar(ci: CanvasItem, center: Vector2, w: float, ratio: float, friendly := true, th := 3.0) -> void:
	# 简约血条：细条 + 半透明深底，不描边、不加高光
	var r := Rect2(center.x - w * 0.5, center.y, w, th)
	ci.draw_rect(r.grow(1.0), HP_BG)
	ci.draw_rect(Rect2(r.position, Vector2(w * clampf(ratio, 0.0, 1.0), th)), hp_color(ratio, friendly))

const HP_BG := Color(0.1, 0.08, 0.06, 0.55)

## 血条颜色：友军 绿 → 黄（半血）→ 红（残血），敌人一律暗红；都压低饱和，和画风一致
static func hp_color(ratio: float, friendly := true) -> Color:
	if not friendly:
		return Color(0.82, 0.34, 0.27)
	if ratio > 0.5:
		return Color(0.58, 0.78, 0.38)
	if ratio > 0.25:
		return Color(0.88, 0.72, 0.32)
	return Color(0.82, 0.34, 0.27)

## 脚下椭圆：投影 / 选中圈
static func ellipse(ci: CanvasItem, center: Vector2, rx: float, col: Color, filled := true, width := 2.0) -> void:
	ci.draw_set_transform(center, 0.0, Vector2(1.0, 0.42))
	if filled:
		ci.draw_circle(Vector2.ZERO, rx, col)
	else:
		ci.draw_arc(Vector2.ZERO, rx, 0, TAU, 40, col, width / 0.42 * 0.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
