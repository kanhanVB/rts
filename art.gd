class_name Art
extends RefCounted
## 美术素材入口：按 key（如 "units/worker_idle"）取贴图、锚点，并提供"按锚点画到指定高度"的小工具。
## 素材缺了就返回 null / false，调用方自动退回原来的程序化画法——所以素材可以一批批补。

const OUTLINE := Color(0.16, 0.1, 0.05)
static var enabled := true
static var _tex := {}
static var _font: Font = null

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

static func font() -> Font:
	if _font == null:
		_font = load("res://fonts/ZCOOLKuaiLe-Regular.ttf") if ResourceLoader.exists("res://fonts/ZCOOLKuaiLe-Regular.ttf") else ThemeDB.fallback_font
	return _font

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
static func hp_bar(ci: CanvasItem, center: Vector2, w: float, ratio: float, friendly := true) -> void:
	var r := Rect2(center.x - w * 0.5, center.y, w, 5.0)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, Color(0.35, 0.08, 0.05))
	var c := Color(0.45, 0.9, 0.25) if friendly else Color(0.95, 0.3, 0.2)
	ci.draw_rect(Rect2(r.position, Vector2(w * clampf(ratio, 0.0, 1.0), 5.0)), c)
	ci.draw_rect(Rect2(r.position, Vector2(w * clampf(ratio, 0.0, 1.0), 1.6)), c.lightened(0.35))

## 脚下椭圆：投影 / 选中圈
static func ellipse(ci: CanvasItem, center: Vector2, rx: float, col: Color, filled := true, width := 2.0) -> void:
	ci.draw_set_transform(center, 0.0, Vector2(1.0, 0.42))
	if filled:
		ci.draw_circle(Vector2.ZERO, rx, col)
	else:
		ci.draw_arc(Vector2.ZERO, rx, 0, TAU, 40, col, width / 0.42 * 0.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
