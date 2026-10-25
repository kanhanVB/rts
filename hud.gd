class_name Hud
extends CanvasLayer
## HUD：帝国时代式布局（顶栏资源/人口/波次，底栏 命令卡 | 选中信息 | 闲置按钮 | 小地图），
## 皮肤沿用王国保卫战风格：木板金边面板、羊皮纸提示、圆框头像，全部用 art/ui 贴图九宫格拉伸。
## 只负责"怎么显示"；显示什么（文字、按钮可见性）仍由 main.gd 决定，测试照旧读 main 上的同名控件。
## 素材缺失（或 --noart）时自动退回纯色 StyleBoxFlat。

const WOOD := Color(0.4, 0.26, 0.14)
const WOOD_LIGHT := Color(0.55, 0.36, 0.19)
const GOLD := Color(0.95, 0.75, 0.33)
const INK := Color(0.2, 0.12, 0.06)
const CREAM := Color(1.0, 0.95, 0.82)
const PARCH := Color(0.97, 0.9, 0.72)
const RED_TEXT := Color(1.0, 0.55, 0.45)

## 九宫格边距（原图像素：左、上、右、下）
const SLICE := {
	"ui/panel": [48, 48, 48, 48],
	"ui/parchment": [30, 14, 30, 16],
	"ui/button": [36, 24, 36, 24],
	"ui/button_hover": [36, 24, 36, 24],
	"ui/button_pressed": [36, 24, 36, 24],
	"ui/button_disabled": [36, 24, 36, 24],
	"ui/banner": [72, 12, 72, 40],
}


const VW := 1280.0
const VH := 720.0
const TOP_H := 42.0              # 顶栏：资源 / 人口 / 波次 / 时钟
const BOT_H := 164.0             # 底栏：命令卡 | 选中信息 | 闲置按钮 | 小地图（帝国时代布局）
const MINI_W := 222.0

var main: Node2D
var root: Control
var theme_res: Theme
var _res_vals := {}              # kind -> Label
var _res_boxes := {}             # kind -> 徽章节点（二级材料没货时隐藏）
var _res_sub := {}               # kind -> "(n)" 在采这种资源的农民数
var _worker_val: Label
var _pop_val: Label
var _hero_val: Label
var _clock_val: Label
var _wave_bar: ProgressBar
var _wave_box: HBoxContainer
var _call_btn: Button    # 提前叫波（N）
var _bell_btn: Button    # 警钟 / 解除警报（B）
var _speed_btn: Button   # 游戏速度（+ / -，点一下加一档；暂停时显示 ⏸）
var _pause_tag: Label    # 暂停时屏幕上方那行提示
var _help: PanelContainer
var _top: PanelContainer
var _bottom: PanelContainer
var _cmd_btns: Array = []        # 15 个命令卡按钮（5×3，对应 QWERT / ASDFG / ZXCVB）
var _cmd_at := {}                # slot -> 命令项 {id, key, title, icon, cost, tip}
var _cmd_sig := "-"
var _sel: SelPanel
var _idle_w: Button
var _idle_s: Button
var _overlay_pic: TextureRect
var minimap: Control

func _init(m: Node2D) -> void:
	main = m
	layer = 5

func top_h() -> float:
	return TOP_H

func bottom_h() -> float:
	return BOT_H

func help_visible() -> bool:
	return _help != null and _help.visible

## ================================================================ 主题
func _font() -> Font:
	var f := Art.font()
	if f is FontFile and (f as FontFile).fallbacks.is_empty():
		var sys := SystemFont.new()    # 卡通字库缺的符号（·、→ 等）交给系统字体
		sys.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans SC", "Noto Sans CJK SC", "WenQuanYi Micro Hei", "sans-serif"])
		sys.font_weight = 700
		(f as FontFile).fallbacks = [sys]
	return f

static func box(bg: Color, border: Color, bw := 3, radius := 12, pad := 10.0, shadow := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = shadow
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing = true
	return sb

## 贴图九宫格：key 的原图缩到 k 倍，边距按 SLICE 等比缩；pad = 内容额外内缩（左上右下）
static func tbox(key: String, k: float, pad := [0.0, 0.0, 0.0, 0.0], fallback: StyleBox = null) -> StyleBox:
	var t: Texture2D = Art.scaled(key, k) if Art.has(key) else null
	if t == null:
		return fallback if fallback != null else box(WOOD, GOLD)
	var m: Array = SLICE.get(key, [0, 0, 0, 0])
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = roundf(m[0] * k)
	sb.texture_margin_top = roundf(m[1] * k)
	sb.texture_margin_right = roundf(m[2] * k)
	sb.texture_margin_bottom = roundf(m[3] * k)
	sb.content_margin_left = sb.texture_margin_left + pad[0]
	sb.content_margin_top = sb.texture_margin_top + pad[1]
	sb.content_margin_right = sb.texture_margin_right + pad[2]
	sb.content_margin_bottom = sb.texture_margin_bottom + pad[3]
	return sb

func _panel_box(k := 0.4, pad := 2.0) -> StyleBox:
	return tbox("ui/panel", k, [pad, pad, pad, pad], box(WOOD, GOLD))

func _parch_box(k := 0.5, pad := [6.0, 0.0, 6.0, 0.0]) -> StyleBox:
	return tbox("ui/parchment", k, pad, box(PARCH, INK, 3, 16, 10.0, 5))

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font()
	t.default_font_size = 17
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 6)
	t.set_stylebox("panel", "PanelContainer", _panel_box())
	t.set_stylebox("panel", "TooltipPanel", tbox("ui/parchment", 0.22, [4.0, -2.0, 4.0, -2.0], box(PARCH, INK, 2, 8, 8.0, 4)))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 15)
	# 按钮：木牌金铆钉；悬停变亮，按下变深，禁用变铁灰
	var pad := [-4.0, -6.0, -4.0, -6.0]
	var bk := 0.3
	t.set_stylebox("normal", "Button", tbox("ui/button", bk, pad, box(WOOD_LIGHT, GOLD, 3, 10, 6.0, 3)))
	t.set_stylebox("hover", "Button", tbox("ui/button_hover", bk, pad, box(WOOD_LIGHT.lightened(0.15), GOLD, 3, 10, 6.0, 3)))
	var pressed := tbox("ui/button_pressed", bk, pad, box(WOOD_LIGHT.darkened(0.2), GOLD, 3, 10, 6.0, 0))
	pressed.content_margin_top += 2.0
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", tbox("ui/button_disabled", bk, pad, box(Color(0.35, 0.32, 0.3), Color(0.55, 0.5, 0.42), 3, 10, 6.0, 2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 1, 0.9))
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 6)
	t.set_font_size("font_size", "Button", 15)
	# 进度条
	var pbg := box(Color(0.15, 0.09, 0.05), INK, 2, 6, 0.0, 0)
	var pfill := box(Color(0.98, 0.72, 0.2), Color(0, 0, 0, 0), 0, 6, 0.0, 0)
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", pfill)
	return t

## ================================================================ 搭建
func build() -> void:
	theme_res = _build_theme()
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_res
	add_child(root)
	_build_top_bar()
	_build_bottom_bar()
	_build_toast()
	_build_panel()
	_build_help()
	_build_overlay()

## 顶栏（帝国式）：左边资源 + 人口，右边波次 + 时钟 + 按钮
func _build_top_bar() -> void:
	_top = PanelContainer.new()
	_top.add_theme_stylebox_override("panel", _panel_box(0.26, -7.0))
	_top.mouse_filter = Control.MOUSE_FILTER_STOP     # 点在顶栏上不穿透到地图
	_top.position = Vector2.ZERO
	_top.custom_minimum_size = Vector2(VW, TOP_H)
	_top.size = Vector2(VW, TOP_H)
	root.add_child(_top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	_top.add_child(hb)
	for k in ["ore", "wood", "ingot", "plank"]:
		var b := _badge(hb, k, Economy.KIND_NAME[k] + ("（括号里 = 在采的农民数）" if k == "ore" or k == "wood" else ""), k == "ore" or k == "wood")
		_res_vals[k] = b.get_meta("val")
		_res_boxes[k] = b
		if b.has_meta("sub"):
			_res_sub[k] = b.get_meta("sub")
	_worker_val = _badge(hb, "workers", "农民（上限 %d）" % main.WORKER_CAP).get_meta("val")
	_pop_val = _badge(hb, "pop", "人口：己方单位 + 排队中（上限 %d）" % main.UNIT_CAP).get_meta("val")
	_hero_val = _badge(hb, "engineer", "英雄工程师：唯一会盖房子的人，阵亡后在基地免费复活").get_meta("val")
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(sp)
	# 波次：图标 + 文字 + 细进度条
	_wave_box = HBoxContainer.new()
	_wave_box.add_theme_constant_override("separation", 6)
	_wave_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_wave_box)
	var ic := TextureRect.new()
	ic.texture = icon("wave")
	ic.custom_minimum_size = Vector2(22, 22)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wave_box.add_child(ic)
	var wv := VBoxContainer.new()
	wv.add_theme_constant_override("separation", 0)
	wv.alignment = BoxContainer.ALIGNMENT_CENTER
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_box.add_child(wv)
	main.wave_label = Label.new()
	main.wave_label.add_theme_font_size_override("font_size", 16)
	main.wave_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	main.wave_label.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.03))
	main.wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wv.add_child(main.wave_label)
	_wave_bar = ProgressBar.new()
	_wave_bar.custom_minimum_size = Vector2(200, 5)
	_wave_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wave_bar.show_percentage = false
	_wave_bar.max_value = 1.0
	_wave_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wv.add_child(_wave_bar)
	_call_btn = _small_btn(_wave_box, "叫波", "")
	_call_btn.pressed.connect(func(): main.call_wave_early())
	_bell_btn = _small_btn(hb, "警钟", "")
	_bell_btn.custom_minimum_size.x = 64
	_bell_btn.pressed.connect(func(): main.ring_bell())
	_clock_val = Label.new()
	_clock_val.add_theme_font_size_override("font_size", 18)
	_clock_val.tooltip_text = "游戏时间"
	_clock_val.mouse_filter = Control.MOUSE_FILTER_PASS
	_clock_val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_clock_val.custom_minimum_size.x = 56
	hb.add_child(_clock_val)
	var bp := _small_btn(hb, "产能", "产能面板：最近 15 秒的采集 / 加工速度")
	bp.pressed.connect(func(): main.toggle_panel())
	_speed_btn = _small_btn(hb, "1×", "游戏速度：点一下加一档（1× / 2× / 3×）")
	_speed_btn.custom_minimum_size.x = 46
	_speed_btn.pressed.connect(func(): main.cycle_speed())
	var bh := _small_btn(hb, "?", "操作说明（F1）")
	bh.pressed.connect(toggle_help)
	main.res_label = Label.new()     # 兼容：完整资源文字仍写在这里（不显示）
	main.res_label.visible = false
	root.add_child(main.res_label)
	# 暂停提示：屏幕上方一行大字（默认隐藏）
	_pause_tag = Label.new()
	_pause_tag.text = "已暂停　·　按 P 继续"
	_pause_tag.add_theme_font_size_override("font_size", 26)
	_pause_tag.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	_pause_tag.add_theme_constant_override("outline_size", 9)
	_pause_tag.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.04))
	_pause_tag.visible = false
	_pause_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pause_tag)

func _badge(parent: Control, key: String, tip: String, with_sub := false) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.tooltip_text = tip
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(hb)
	var tr := TextureRect.new()
	tr.texture = icon(key)
	tr.custom_minimum_size = Vector2(28, 28)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tr)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 19)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 30
	hb.add_child(l)
	hb.set_meta("val", l)
	if with_sub:
		var s := Label.new()
		s.add_theme_font_size_override("font_size", 14)
		s.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
		s.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb.add_child(s)
		hb.set_meta("sub", s)
	return hb

func _small_btn(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34 if text.length() < 2 else 56, 28)
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(b)
	return b

## 底栏（帝国式）：左 命令卡 5×3 | 中 选中信息 + 生产队列 | 闲置按钮 | 右 小地图
func _build_bottom_bar() -> void:
	_bottom = PanelContainer.new()
	_bottom.add_theme_stylebox_override("panel", _panel_box(0.3, -6.0))
	_bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	_bottom.position = Vector2(0, VH - BOT_H)
	_bottom.custom_minimum_size = Vector2(VW, BOT_H)
	_bottom.size = Vector2(VW, BOT_H)
	root.add_child(_bottom)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	_bottom.add_child(hb)
	# 命令卡
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(grid)
	for slot in 15:
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.32)
		b.pressed.connect(func():
			if _cmd_at.has(slot):
				main.run_command(_cmd_at[slot].id))
		b.draw.connect(_draw_cmd.bind(slot))
		grid.add_child(b)
		_cmd_btns.append(b)
	hb.add_child(VSeparator.new())
	# 选中信息
	_sel = SelPanel.new()
	_sel.hud = self
	_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sel.clip_contents = true
	hb.add_child(_sel)
	var info := Label.new()
	info.add_theme_font_override("font", Art.body_font())
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_constant_override("outline_size", 5)
	info.add_theme_constant_override("line_spacing", 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sel.add_child(info)
	main.info_label = info
	hb.add_child(VSeparator.new())
	# 闲置农民 / 闲置军队
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override("separation", 6)
	iv.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(iv)
	_idle_w = _idle_btn(iv, "workers", "闲置农民：轮流选中没活干的农民")
	_idle_w.pressed.connect(func(): main.select_next_idle(true))
	_idle_s = _idle_btn(iv, "sword", "闲置军队：轮流选中没命令的士兵")
	_idle_s.pressed.connect(func(): main.select_next_idle(false))
	# 小地图
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", _panel_box(0.2, -7.0))
	mp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(mp)
	minimap = Minimap.new()
	minimap.main = main
	minimap.custom_minimum_size = Vector2(MINI_W, roundf(MINI_W * main.H / main.W))
	mp.add_child(minimap)

func _idle_btn(parent: Control, key: String, tip: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(46, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.set_meta("n", 0)
	b.draw.connect(func():
		var t := icon(key)
		if t != null:
			var ts := t.get_size()
			var s := minf(30.0 / ts.x, 30.0 / ts.y)
			var sz := ts * s
			b.draw_texture_rect(t, Rect2(Vector2(23, 21) - sz * 0.5, sz), false, Color(1, 1, 1, 1.0 if int(b.get_meta("n")) > 0 else 0.45))
		Art.text(b, Vector2(34, 42), str(b.get_meta("n")), 14, Hud.GOLD if int(b.get_meta("n")) > 0 else Color(0.7, 0.66, 0.6)))
	parent.add_child(b)
	return b

## 命令卡按钮：图标（或符号）+ 底部名字 + 左上角热键字母
func _draw_cmd(slot: int) -> void:
	var b: Button = _cmd_btns[slot]
	if not _cmd_at.has(slot):
		return
	var c: Dictionary = _cmd_at[slot]
	var id: String = c.id
	if id in ["attack", "stop", "hold", "patrol", "retreat", "delete", "bell", "all_clear"]:
		_glyph(b, id, Vector2(28, 17))
	else:
		var t := icon(c.icon)
		if t != null:
			var ts := t.get_size()
			var s := minf(36.0 / ts.x, 27.0 / ts.y)
			var sz := ts * s
			b.draw_texture_rect(t, Rect2(Vector2(28, 17) - sz * 0.5, sz), false)
	if Tech.is_tech(id):
		tech_overlay(b, id, Rect2(10, 3, 36, 28))
	var ok: bool = c.cost.is_empty() or main.economy.can_afford(c.cost)
	Art.text(b, Vector2(28, 40), c.title, 11, Hud.CREAM if ok else Hud.RED_TEXT)
	Art.text(b, Vector2(5, 12), c.key if c.key.length() == 1 else "", 11, Hud.GOLD, false)

## 科技图标的叠加标记：右上角金色向上箭头（= 研究升级）；锁子甲叠一面小钢盾，战地包扎画白底红十字
func tech_overlay(ci: CanvasItem, id: String, r: Rect2) -> void:
	var ink := Hud.INK
	var k := clampf(r.size.y / 28.0, 0.8, 1.2)
	var c := r.get_center()
	match str(Tech.DEFS[id].glyph):
		"medic":
			ci.draw_circle(c, 12.5 * k, ink)
			ci.draw_circle(c, 11.0 * k, Color(0.97, 0.94, 0.86))
			var red := Color(0.84, 0.16, 0.12)
			ci.draw_rect(Rect2(c - Vector2(7.5, 2.6) * k, Vector2(15.0, 5.2) * k), red)
			ci.draw_rect(Rect2(c - Vector2(2.6, 7.5) * k, Vector2(5.2, 15.0) * k), red)
		"shield":
			var sc := c + Vector2(8.0, 4.0) * k
			var pts := PackedVector2Array()
			for v in [Vector2(-6, -7), Vector2(6, -7), Vector2(6, 0), Vector2(0, 7.5), Vector2(-6, 0)]:
				pts.append(sc + v * k)
			ci.draw_colored_polygon(pts, Color(0.74, 0.78, 0.84))
			pts.append(pts[0])
			ci.draw_polyline(pts, ink, 1.6)
			ci.draw_line(sc + Vector2(0, -5.5) * k, sc + Vector2(0, 5.5) * k, Hud.GOLD, 1.6)
	var a := Vector2(r.end.x + 1.0, r.position.y + 4.0)
	var tri := PackedVector2Array([a + Vector2(0, -4.5) * k, a + Vector2(4.5, 0.5) * k, a + Vector2(-4.5, 0.5) * k])
	var stem := Rect2(a + Vector2(-1.8, 0.5) * k, Vector2(3.6, 4.0) * k)
	ci.draw_rect(stem.grow(1.2), ink)
	ci.draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(0, -1.6), tri[1] + Vector2(1.6, 0.9), tri[2] + Vector2(-1.6, 0.9)]), ink)
	ci.draw_colored_polygon(tri, Hud.GOLD)
	ci.draw_rect(stem, Hud.GOLD)

## 通用指令的矢量符号（没有专门贴图）
func _glyph(ci: CanvasItem, id: String, c: Vector2) -> void:
	var ink := Hud.INK
	match id:
		"attack":    # 交叉双剑
			for s in [-1.0, 1.0]:
				var a := c + Vector2(-9.0 * s, -10.0)
				var e := c + Vector2(9.0 * s, 9.0)
				ci.draw_line(a, e, ink, 5.0)
				ci.draw_line(a, e, Color(0.92, 0.92, 0.95), 2.5)
				var g := a.lerp(e, 0.72)
				var n := Vector2(s, 1.0).normalized().orthogonal() * 5.0
				ci.draw_line(g - n, g + n, ink, 4.0)
				ci.draw_line(g - n, g + n, Hud.GOLD, 2.0)
		"stop":      # 红色八角
			var pts := PackedVector2Array()
			for i in 8:
				pts.append(c + Vector2.from_angle(TAU * (i + 0.5) / 8.0) * 11.0)
			ci.draw_colored_polygon(pts, Color(0.8, 0.18, 0.12))
			pts.append(pts[0])
			ci.draw_polyline(pts, ink, 2.0)
			ci.draw_rect(Rect2(c - Vector2(6, 1.5), Vector2(12, 3)), Color(1, 0.95, 0.85))
		"hold":      # 盾
			var pts := PackedVector2Array([c + Vector2(-10, -11), c + Vector2(10, -11), c + Vector2(10, 0), c + Vector2(0, 12), c + Vector2(-10, 0)])
			ci.draw_colored_polygon(pts, Color(0.3, 0.5, 0.9))
			pts.append(pts[0])
			ci.draw_polyline(pts, ink, 2.0)
			ci.draw_line(c + Vector2(0, -9), c + Vector2(0, 9), Hud.GOLD, 2.0)
		"patrol":    # 来回箭头
			for s in [-1.0, 1.0]:
				var y: float = c.y + 5.0 * s
				var a := Vector2(c.x - 11.0 * s, y)
				var e := Vector2(c.x + 11.0 * s, y)
				ci.draw_line(a, e, ink, 4.5)
				ci.draw_line(a, e, Color(1.0, 0.85, 0.35), 2.0)
				ci.draw_colored_polygon(PackedVector2Array([e + Vector2(3.0 * s, 0), e + Vector2(-4.0 * s, -4), e + Vector2(-4.0 * s, 4)]), Color(1.0, 0.85, 0.35))
		"retreat":   # 后撤：一支朝后（左下）的箭头，右上两道速度线
			var a := c + Vector2(10, -10)
			var e := c + Vector2(-6, 6)
			ci.draw_line(a, e, ink, 5.5)
			ci.draw_line(a, e, Color(0.55, 0.85, 0.95), 2.6)
			var d := (e - a).normalized()
			var n := d.orthogonal()
			var head := PackedVector2Array([e + d * 8.0, e + n * 6.0, e - n * 6.0])
			ci.draw_colored_polygon(head, Color(0.7, 0.9, 0.97))
			head.append(head[0])
			ci.draw_polyline(head, ink, 2.0)
			for s in [0.0, 1.0]:
				var o := c + Vector2(12.0 - s * 6.0, -14.0 + s * 6.0)
				ci.draw_line(o + Vector2(-6, -6) * 0.35, o + Vector2(3, -3), Color(0.7, 0.9, 0.97, 0.75), 2.0)
		"delete":    # 红叉
			for s in [-1.0, 1.0]:
				ci.draw_line(c + Vector2(-8, -8 * s), c + Vector2(8, 8 * s), ink, 6.0)
				ci.draw_line(c + Vector2(-8, -8 * s), c + Vector2(8, 8 * s), Color(0.95, 0.3, 0.2), 3.0)
		"bell":      # 金钟 + 两边的声纹
			bell_glyph(ci, c + Vector2(0, 1), 0.82, 0.0)
			for sx in [-1.0, 1.0]:
				for i in 2:
					var r := 4.0 + i * 3.5
					var a0 := (0.0 if sx > 0.0 else PI) - 0.7
					ci.draw_arc(c + Vector2(sx * 11.0, -2.0), r, a0, a0 + 1.4, 6, ink, 2.6)
					ci.draw_arc(c + Vector2(sx * 11.0, -2.0), r, a0, a0 + 1.4, 6, Color(1.0, 0.9, 0.55), 1.2)
		"all_clear": # 金钟 + 绿勾
			bell_glyph(ci, c + Vector2(-3, 1), 0.82, 0.0)
			var ck := PackedVector2Array([c + Vector2(4, 4), c + Vector2(8, 9), c + Vector2(15, -2)])
			ci.draw_polyline(ck, ink, 5.5)
			ci.draw_polyline(ck, Color(0.45, 0.85, 0.35), 2.8)

## 钟（警钟按钮 / 基地顶上）：c = 钟身中心，k = 缩放，rot = 摆角（绕顶上的挂环摆）
static func bell_glyph(ci: CanvasItem, c: Vector2, k := 1.0, rot := 0.0) -> void:
	var ink := INK
	ci.draw_set_transform(c + Vector2(0, -12.0) * k, rot, Vector2(k, k))
	var body := PackedVector2Array([Vector2(-3, 1.5), Vector2(3, 1.5), Vector2(6.5, 4), Vector2(8, 10), Vector2(9, 16),
		Vector2(12.5, 20.5), Vector2(-12.5, 20.5), Vector2(-9, 16), Vector2(-8, 10), Vector2(-6.5, 4)])
	ci.draw_circle(Vector2(0, 23.0), 3.8, ink)                       # 钟舌
	ci.draw_circle(Vector2(0, 23.0), 2.5, Color(0.6, 0.42, 0.2))
	ci.draw_colored_polygon(body, Color(0.95, 0.75, 0.33))
	var ol := body.duplicate()
	ol.append(body[0])
	ci.draw_polyline(ol, ink, 2.0)
	ci.draw_line(Vector2(-10.0, 17.0), Vector2(10.0, 17.0), Color(0.72, 0.5, 0.2), 1.5)    # 腰线
	ci.draw_line(Vector2(-4.0, 5.5), Vector2(-5.5, 14.0), Color(1.0, 0.95, 0.78), 1.6)     # 高光
	ci.draw_arc(Vector2(0, -0.8), 2.6, 0.0, TAU, 12, ink, 2.0)                             # 挂环
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 命令卡内容跟着选中对象换（只在变了时重建提示文字）
func _sync_commands() -> void:
	var cmds: Array = main.commands()
	var sig := ""
	# 签名必须带上标题和说明：箭塔 / 二级箭塔的 tip 里写着"每箭 %d"，
	# 那个数是现查科技加成的。只按 id@slot 判变化的话，研究完「破甲箭头」
	# 按钮还在，签名没变 → 悬停提示永远停在旧数字（写着 9，实际打 12）
	for c in cmds:
		sig += "%s@%d:%s|%s;" % [c.id, c.slot, c.title, c.tip]
	if sig != _cmd_sig:
		_cmd_sig = sig
		_cmd_at.clear()
		for c in cmds:
			_cmd_at[int(c.slot)] = c
		for slot in 15:
			var b: Button = _cmd_btns[slot]
			if _cmd_at.has(slot):
				var c: Dictionary = _cmd_at[slot]
				var cost_txt: String = "" if c.cost.is_empty() else "\n花费：" + main.economy.cost_text(c.cost)
				b.disabled = false
				b.modulate = Color.WHITE
				b.tooltip_text = "%s（%s）%s\n%s" % [c.title, c.key, cost_txt, c.tip]
			else:
				b.disabled = true
				b.modulate = Color(1, 1, 1, 0.32)
				b.tooltip_text = ""
	for b in _cmd_btns:
		b.queue_redraw()

## 底栏上方中间：提示条（羊皮纸）
func _build_toast() -> void:
	var l := Label.new()
	l.add_theme_stylebox_override("normal", _parch_box(0.26, [14.0, -4.0, 14.0, -4.0]))
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_constant_override("outline_size", 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	root.add_child(l)
	main._hud_msg_label = l

## 右侧、底栏上方：产能面板（顶栏"产能"按钮开关）
func _build_panel() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_box(0.3, 2.0))
	p.self_modulate = Color(1, 1, 1, 0.93)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	main.panel = p
	var l := Label.new()
	l.add_theme_font_override("font", Art.body_font())
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_constant_override("line_spacing", 1)
	l.add_theme_constant_override("outline_size", 5)
	p.add_child(l)
	main.panel_label = l

func _build_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", _parch_box(0.55, [24.0, 22.0, 24.0, 46.0]))
	_help.visible = false
	_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_help)
	# 只留骨架。每个命令卡按钮本来就有悬停说明（_cmd_entry 的 tip），F1 里再抄一遍没必要。
	# 两栏 20 多行也还是"打开就想关掉"——这里只回答三个问题：从哪开始、手怎么动、兵怎么指挥。
	var l := Label.new()
	l.add_theme_color_override("font_color", INK)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_font_override("font", Art.body_font())
	l.add_theme_font_size_override("font_size", 16)
	l.text = """怎么开始
  选中基地，点「农民」
  农民右键矿堆 / 树林，自己往返搬
  选中工程师，点「熔炉」「木工台」「兵营」
  选中兵营，点「剑士」「弓手」
  怪沿土路来，十波打完就赢
  拆掉所有巢穴也算赢——但巢穴挨打会往外吐守军，带够兵再去
  房子被打坏了工程师会自己去修（右键一座受损的自家建筑 = 点名）

怎么操作
  左键点选 · 拖动框选 · Shift 加选
  右键：走过去 / 采集 / 打谁 / 交货
  选中基地或兵营，右键地面 = 集结点
  命令都点底栏按钮，鼠标悬停有说明

兵怎么打
  平时守在兵营周围，怪来了自己上去拦，不用管
  打崩了按 W 撤退，兵退到后方待命（不会自己回来）"""
	_help.add_child(l)

func toggle_help() -> void:
	_help.visible = not _help.visible

## 结算：半透明黑幕 + 胜利/失败徽章 + 羊皮纸卷轴
func _build_overlay() -> void:
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.55)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.visible = false
	root.add_child(ov)
	main.overlay = ov
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	col.add_theme_constant_override("separation", -18)
	ov.add_child(col)
	_overlay_pic = TextureRect.new()
	_overlay_pic.custom_minimum_size = Vector2(300, 200)
	_overlay_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_overlay_pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_overlay_pic)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _parch_box(0.6, [24.0, -4.0, 24.0, -6.0]))
	col.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", Color(0.98, 0.82, 0.3))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 460
	vb.add_child(l)
	main.overlay_label = l
	# 结算统计：用时 / 击杀 / 阵亡 / 训练 / 峰值库存 / 科技 / 遗物
	var st := Label.new()
	st.add_theme_font_size_override("font_size", 18)
	st.add_theme_color_override("font_color", Color(0.36, 0.26, 0.16))
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size.x = 460
	vb.add_child(st)
	main.overlay_stats = st
	var restart := Button.new()
	restart.text = "再来一局（R）"
	restart.add_theme_font_size_override("font_size", 22)
	restart.custom_minimum_size = Vector2(190, 54)
	restart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart.pressed.connect(func(): main.get_tree().reload_current_scene())
	vb.add_child(restart)

## ================================================================ 每帧
func refresh() -> void:
	var e: Economy = main.economy
	for k in _res_vals:
		_res_vals[k].text = str(int(e.amount(k)))
	_res_boxes["ingot"].visible = e.ingot > 0.0 or main._has_processor("smelter")
	_res_boxes["plank"].visible = e.plank > 0.0 or main._has_processor("workshop")
	# 每种资源有几个农民在干（帝国式顶栏括号数）
	var on := {"ore": 0, "wood": 0}
	var workers: Array = main._player_workers()
	for w in workers:
		var k := ""
		if w.state == Worker.State.SHELTER:
			continue
		if w.state == Worker.State.TO_BASE:
			k = w.carry_kind
		elif w.state != Worker.State.IDLE and is_instance_valid(w.node_target):
			k = w.node_target.kind
		if on.has(k):
			on[k] += 1
	for k in _res_sub:
		_res_sub[k].text = "(%d)" % on[k]
	_worker_val.text = "%d/%d" % [main.worker_count(), main.WORKER_CAP]
	var pop: int = main.unit_count() + main.queued_count()
	_pop_val.text = "%d/%d" % [pop, main.UNIT_CAP]
	if pop >= main.UNIT_CAP:
		_pop_val.add_theme_color_override("font_color", RED_TEXT)
	else:
		_pop_val.remove_theme_color_override("font_color")
	if not main.respawn_timers.is_empty():
		_hero_val.text = "复活 %ds" % int(maxf(main.respawn_timers[0], 0.0))
		_hero_val.add_theme_color_override("font_color", RED_TEXT)
	elif main._player_engineers().is_empty():
		_hero_val.text = "失踪"
		_hero_val.add_theme_color_override("font_color", RED_TEXT)
	else:
		_hero_val.text = "上阵"
		_hero_val.remove_theme_color_override("font_color")
	var secs := int(main.game_time)
	_clock_val.text = "%02d:%02d" % [secs / 60, secs % 60]
	# 时间控制：暂停时按钮变 ⏸，2× / 3× 时变黄提醒"现在是快进的"
	if main.paused:
		_speed_btn.text = "暂停"
		_speed_btn.add_theme_color_override("font_color", RED_TEXT)
	elif int(main.speed_i) > 0:
		_speed_btn.text = "%d×" % int(main.SPEEDS[main.speed_i])
		_speed_btn.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	else:
		_speed_btn.text = "1×"
		_speed_btn.remove_theme_color_override("font_color")
	_pause_tag.visible = main.paused
	if main.paused:
		_fit(_pause_tag, Vector2((VW - _pause_tag.size.x) * 0.5, TOP_H + 22.0))
	# 波次条：离下一波越近越满
	var wm: WaveManager = main._wave_mgr
	_wave_box.visible = main.game_state == "play"
	var span: float = WaveManager.FIRST_WAVE_AT if wm.wave == 0 else WaveManager.WAVE_INTERVAL
	_wave_bar.visible = wm.wave < WaveManager.MAX_WAVES
	_wave_bar.value = 1.0 - clampf(wm.wave_timer / span, 0.0, 1.0)
	_call_btn.visible = wm.can_call_early()
	_bell_btn.visible = main.game_state == "play"
	if main.alarm_on:
		_bell_btn.text = "解除警报"
		_bell_btn.add_theme_color_override("font_color", RED_TEXT)
		_bell_btn.tooltip_text = "警报解除（B）：躲着的 %d 个农民出来，回去接着干原来的活" % main.worker_count_hidden()
	else:
		_bell_btn.text = "警钟"
		_bell_btn.remove_theme_color_override("font_color")
		_bell_btn.tooltip_text = main.bell_tip()
	if _call_btn.visible:
		_call_btn.tooltip_text = "提前叫第 %d 波（N）：%s\n现在叫奖励 %d 矿 + %d 木（越早叫奖励越多）" % [
			wm.wave + 1, WaveManager.wave_text(wm.wave + 1), wm.early_bonus(), wm.early_bonus()]
	# 底栏
	_sync_commands()
	_sel.layout()
	_sel.queue_redraw()
	_idle_w.set_meta("n", main.idle_units(true).size())
	_idle_s.set_meta("n", main.idle_units(false).size())
	_idle_w.queue_redraw()
	_idle_s.queue_redraw()
	# 提示条：底栏上方居中
	var t: Label = main._hud_msg_label
	if t.visible:
		_fit(t, Vector2((VW - t.size.x) * 0.5, VH - BOT_H - t.size.y - 10.0))
	# 产能面板：右侧、底栏上方
	if main.panel.visible:
		_fit(main.panel, Vector2(VW - main.panel.size.x - 8.0, VH - BOT_H - main.panel.size.y - 6.0))
	_fit(_help, Vector2((VW - _help.size.x) * 0.5, TOP_H + 10.0))
	if main.overlay.visible and _overlay_pic.texture == null:
		_overlay_pic.texture = icon("ui/icon_victory" if main.game_state == "win" else "ui/icon_defeat")
		_overlay_pic.visible = _overlay_pic.texture != null
	minimap.queue_redraw()

func _fit(c: Control, pos: Vector2) -> void:
	c.size = c.get_combined_minimum_size()
	if pos != Vector2.ZERO:
		c.position = pos

## ================================================================ 图标
## 逻辑 key → 美术贴图。素材缺失时返回 null（按钮只显示文字）
const ICON_KEY := {
	"ore": "items/ore", "wood": "items/wood", "ingot": "items/ingot", "plank": "items/plank",
	"worker": "units/worker_idle", "engineer": "ui/icon_hero", "workers": "ui/icon_worker",
	"sword": "units/swordsman_idle", "archer": "units/archer_idle", "pop": "units/swordsman_idle",
	"warehouse": "buildings/warehouse", "smelter": "buildings/smelter", "workshop": "buildings/workshop",
	"barracks": "buildings/barracks", "base": "buildings/base", "hive": "buildings/hive", "wave": "ui/icon_wave",
	"tower": "buildings/tower", "tower2": "buildings/tower2",
	"waterwheel": "buildings/waterwheel", "outpost": "buildings/outpost",
}

func icon(key: String) -> Texture2D:
	if Tech.is_tech(key):
		key = Tech.DEFS[key].icon    # 科技借用单位/建筑贴图（战地包扎没有，只画红十字）
		if key == "":
			return null
	var k: String = ICON_KEY.get(key, key)
	return Art.tex(k) if Art.has(k) else null

## ================================================================ 子控件
## 底栏中间的选中信息（帝国式）：
## 单选 = 大头像 + 数值；己方基地/兵营下面再加一排生产队列（点图标取消）
## 多选 = 一行统计 + 小头像网格（点 = 只选它，Shift+点 = 移出，Ctrl+点 = 只留同类）
class SelPanel extends Control:
	var hud: Hud
	const ICON := 38.0
	const STEP := Vector2(43, 46)
	const Q_Y := 82.0

	func _main() -> Node2D:
		return hud.main

	func _list() -> Array:
		return _main()._display_list()

	func _queue_b() -> Building:
		var l := _list()
		if l.size() == 1 and l[0] is Building and l[0].team == 0 and l[0].trains():
			return l[0]
		return null

	## 单选己方熔炉/木工台：下面一排画加工线（料场 → 读条 → 成品 · 工人位）
	func _proc_b() -> Building:
		var l := _list()
		if l.size() == 1 and l[0] is Building and l[0].is_processor():
			return l[0]
		return null

	## 信息文字的位置：单选在头像右边，多选在顶上一行
	func layout() -> void:
		var info: Label = _main().info_label
		var l := _list()
		if l.size() <= 1:
			info.position = Vector2(112, 4)
			var row := _queue_b() != null or _proc_b() != null
			var h := (Q_Y - 6.0) if row else size.y - 8.0
			info.size = Vector2(maxf(size.x - 116.0, 40.0), h)
			info.vertical_alignment = VERTICAL_ALIGNMENT_TOP if row else VERTICAL_ALIGNMENT_CENTER
			info.clip_text = false
		else:
			info.position = Vector2(6, 0)
			info.size = Vector2(maxf(size.x - 12.0, 40.0), 26)    # 行高约 22px：框太矮 clip 会一行都不画
			info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			info.clip_text = true

	func _cols() -> int:
		return maxi(1, int((size.x - 8.0) / STEP.x))

	func _rows() -> int:
		return maxi(1, int((size.y - 28.0 + 4.0) / STEP.y))

	func _multi_rect(i: int) -> Rect2:
		var c := _cols()
		return Rect2(6.0 + (i % c) * STEP.x, 28.0 + (i / c) * STEP.y, ICON, ICON)

	func _queue_rect(i: int) -> Rect2:
		if i == 0:
			return Rect2(112, Q_Y, 46, 46)
		return Rect2(164.0 + (i - 1) * 40.0, Q_Y + 10.0, 36, 36)

	func _draw() -> void:
		var l := _list()
		if l.is_empty():
			if _main().game_state == "play":
				Art.text(self, Vector2(size.x * 0.5, size.y * 0.5 + 6.0), "左键点选 · 拖动框选 · 双击选同类 · F1 看全部操作", 15, Color(0.9, 0.85, 0.72))
			return
		if l.size() == 1:
			one(l[0], Rect2(8, 6, 92, 92), 7.0)
			var b := _queue_b()
			if b != null:
				_draw_queue(b)
			var pb := _proc_b()
			if pb != null:
				_draw_proc(pb)
			return
		var cap := _cols() * _rows()
		var shown := mini(l.size(), cap)
		for i in shown:
			var r := _multi_rect(i)
			if i == cap - 1 and l.size() > cap:
				Art.text(self, r.get_center() + Vector2(0, 7), "+%d" % (l.size() - cap + 1), 17, Hud.CREAM)
				break
			one(l[i], r, 4.0)

	## 生产队列：排头大格带读条和剩余秒数，后面小格；空位描边
	func _draw_queue(b: Building) -> void:
		for i in Building.QUEUE_MAX:
			var r := _queue_rect(i)
			draw_rect(r, Color(0, 0, 0, 0.28))
			draw_rect(r, Color(Hud.GOLD, 0.55), false, 1.5)
			if i >= b.queue.size():
				continue
			var q: Dictionary = b.queue[i]
			var t: Texture2D = hud.icon(q.kind)
			if t != null:
				var ts := t.get_size()
				var s := minf((r.size.x - 6.0) / ts.x, (r.size.y - 6.0) / ts.y)
				var sz := ts * s
				draw_texture_rect(t, Rect2(r.get_center() - sz * 0.5, sz), false)
			if Tech.is_tech(q.kind):
				hud.tech_overlay(self, q.kind, r.grow(-7.0))
			if i == 0:
				var k := 1.0 - clampf(float(q.left) / maxf(float(q.total), 0.001), 0.0, 1.0)
				var pb := Rect2(r.position.x, r.end.y - 5.0, r.size.x, 5.0)
				draw_rect(pb, Color(0.1, 0.06, 0.03))
				draw_rect(Rect2(pb.position, Vector2(pb.size.x * k, pb.size.y)), Color(0.98, 0.72, 0.2))
				Art.text(self, Vector2(r.end.x + 4.0, r.position.y + 12.0), "%ds" % ceili(float(q.left)), 13, Hud.RED_TEXT if b.waiting_pop else Hud.CREAM, false)
		var hint_x := _queue_rect(Building.QUEUE_MAX - 1).end.x + 12.0
		if hint_x < size.x - 60.0 and not b.queue.is_empty():
			Art.text(self, Vector2(hint_x, Q_Y + 32.0), "点图标取消（全额退）", 12, Color(0.85, 0.8, 0.68), false)

	## 加工线一排的格子：0 料场 / 1 成品 / 2.. 工人位
	func _proc_rect(i: int) -> Rect2:
		if i == 0:
			return Rect2(112, Q_Y, 46, 46)
		if i == 1:
			return Rect2(262, Q_Y, 46, 46)
		return Rect2(326.0 + (i - 2) * 44.0, Q_Y + 4.0, 40, 40)

	func _item(key: String, r: Rect2, mod := Color.WHITE) -> void:
		var t: Texture2D = hud.icon(key)
		if t == null:
			return
		var ts := t.get_size()
		var s := minf((r.size.x - 10.0) / ts.x, (r.size.y - 10.0) / ts.y)
		var sz := ts * s
		draw_texture_rect(t, Rect2(r.get_center() - sz * 0.5 - Vector2(0, 4), sz), false, mod)

	func _draw_proc(b: Building) -> void:
		var r: Dictionary = b.recipe()
		var slots := [[r.in, b.stock_in, Building.IN_CAP], [r.out, b.stock_out, Building.OUT_CAP]]
		for i in 2:
			var rc := _proc_rect(i)
			draw_rect(rc, Color(0, 0, 0, 0.28))
			draw_rect(rc, Color(Hud.GOLD, 0.55), false, 1.5)
			var n: float = slots[i][1]
			_item(slots[i][0], rc, Color.WHITE if n >= 1.0 else Color(1, 1, 1, 0.35))
			Art.text(self, Vector2(rc.get_center().x, rc.end.y - 3.0), "%d/%d" % [int(n), int(slots[i][2])], 12,
				Hud.RED_TEXT if (i == 0 and n < r.n) or (i == 1 and n + r.n > slots[i][2]) else Hud.CREAM)
		# 中间：一炉的读条（箭头底 + 进度）
		var a := _proc_rect(0).end.x + 8.0
		var e := _proc_rect(1).position.x - 8.0
		var y := Q_Y + 23.0
		var bar := Rect2(a, y - 5.0, e - a - 10.0, 10.0)
		draw_rect(bar, Color(0.1, 0.06, 0.03))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * b.batch, bar.size.y)),
			Color(0.98, 0.72, 0.2) if b.line_status == "work" else Color(0.62, 0.56, 0.46))
		draw_colored_polygon(PackedVector2Array([Vector2(e - 10.0, y - 9.0), Vector2(e, y), Vector2(e - 10.0, y + 9.0)]), Color(0.1, 0.06, 0.03))
		Art.text(self, Vector2((a + e) * 0.5, y - 9.0), "%d → %d · %s秒" % [r.n, r.n, Building.fmt_secs(b.batch_time())], 12, Hud.CREAM)
		Art.text(self, Vector2((a + e) * 0.5, y + 21.0), b.status_text(), 12,
			Hud.RED_TEXT if b.line_status in ["no_op", "no_in", "full"] else Color(0.85, 0.8, 0.68))
		# 工人位：有人画头像，空位画虚框 +
		for i in Building.OP_MAX:
			var rc := _proc_rect(2 + i)
			draw_rect(rc, Color(0, 0, 0, 0.28))
			draw_rect(rc, Color(Hud.GOLD, 0.55), false, 1.5)
			if i < b.operators.size() and is_instance_valid(b.operators[i]):
				var w = b.operators[i]
				_item("workers", rc.grow(4.0), Color.WHITE if w.op_phase == "work" else Color(1, 1, 1, 0.5))
				Art.text(self, Vector2(rc.get_center().x, rc.end.y - 2.0), "干活" if w.op_phase == "work" else "搬运", 11, Hud.CREAM)
			else:
				Art.text(self, rc.get_center() + Vector2(0, 7.0), "+", 22, Color(0.85, 0.8, 0.68, 0.7))
		var hx := _proc_rect(2 + Building.OP_MAX).position.x + 4.0
		if hx < size.x - 60.0:
			Art.text(self, Vector2(hx, Q_Y + 28.0), "点 + 招工 · 点工人选中他", 12, Color(0.85, 0.8, 0.68), false)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		var m := _main()
		var l := _list()
		var pb := _proc_b()
		if pb != null:
			for i in Building.OP_MAX:
				if _proc_rect(2 + i).has_point(event.position):
					if i < pb.operators.size() and is_instance_valid(pb.operators[i]):
						m._set_selection([pb.operators[i]])
					else:
						m.hire_operator(pb)
					accept_event()
					return
			return
		var b := _queue_b()
		if b != null:
			for i in b.queue.size():
				if _queue_rect(i).has_point(event.position):
					m.cancel_train(b, i)
					accept_event()
					return
			return
		if l.size() < 2 or m.inspected != null:
			return
		var cap := mini(l.size(), _cols() * _rows())
		for i in cap:
			if not _multi_rect(i).has_point(event.position):
				continue
			var u = l[i]
			if event.shift_pressed:
				u.selected = false
				m.selected.erase(u)
			elif event.ctrl_pressed:
				var key: String = m.type_key(u)
				m._set_selection(l.filter(func(x): return is_instance_valid(x) and m.type_key(x) == key))
			else:
				m._set_selection([u])
			accept_event()
			return

	## 头像内容：农民/英雄/敌人用专门的圆头像图标，兵种裁立绘上半身，建筑整张缩进去
	func _face(u) -> Array:
		if u is Treasure:
			return ["props/relic_gem", false, u.color().lightened(0.15)] if u.kind == "relic" else ["props/chest", false]
		if u is Building:
			if u.kind == "camp":
				return ["buildings/hive", false]
			return ["buildings/" + (u.kind + ("2" if u.level >= 2 else "") if u.kind == "tower" else u.kind), false]
		var k: String = u._art_key()
		match k:
			"worker": return ["ui/icon_worker", false]
			"engineer": return ["ui/icon_hero", false]
			"goo", "runner", "brute": return ["units/%s_idle" % k, false]
			_: return ["units/%s_idle" % k, true]

	## 金圈圆框头像 + 下方血条
	func one(u, r: Rect2, bar_h: float) -> void:
		var enemy: bool = u.team != 0
		var c := r.get_center()
		var rad := r.size.x * 0.5
		draw_circle(c, rad * 0.86, Color(0.95, 0.87, 0.68) if not enemy else Color(0.93, 0.68, 0.6))
		var f: Array = _face(u)
		var key: String = f[0]
		if Art.has(key):
			var t := Art.tex(key)
			var ts := t.get_size()
			var inner := r.grow(-rad * 0.2)
			if f[1]:
				# 上半身：取原图上 58%，宽度居中裁成正方形
				var src_h := ts.y * 0.58
				var src := Rect2((ts.x - src_h) * 0.5, 0, src_h, src_h)
				draw_texture_rect_region(t, inner, src)
			else:
				var s := minf(inner.size.x / ts.x, inner.size.y / ts.y)
				var sz := ts * s
				draw_texture_rect(t, Rect2(c - sz * 0.5, sz), false, f[2] if f.size() > 2 else Color.WHITE)
		else:
			draw_circle(c, rad * 0.4, Color(0.3, 0.55, 1.0) if not enemy else Color(0.85, 0.25, 0.2))
		if Art.has("ui/portrait_frame"):
			draw_texture_rect(Art.tex("ui/portrait_frame"), r, false, Color(1, 0.75, 0.7) if enemy else Color.WHITE)
		else:
			draw_arc(c, rad - 2.0, 0, TAU, 40, Hud.GOLD, 3.0)
		if u is Treasure or u is Ruins:
			return    # 宝箱 / 废墟没有血条
		var hb := Rect2(r.position.x + 3.0, r.end.y + 2.0, r.size.x - 6.0, bar_h)
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		draw_rect(hb, Art.HP_BG)
		draw_rect(Rect2(hb.position + Vector2(1, 1), Vector2((hb.size.x - 2.0) * ratio, maxf(hb.size.y - 2.0, 1.0))), Art.hp_color(ratio, not enemy))

## 小地图：整张地图缩略图 + 建筑/单位/资源点 + 当前视野框，点击/拖动跳转镜头
class Minimap extends Control:
	var main: Node2D
	var _held := false

	func _k() -> float:
		return size.x / float(main.W)

	func _draw() -> void:
		var k := _k()
		if main.minimap_tex != null:
			draw_texture_rect(main.minimap_tex, Rect2(Vector2.ZERO, size), false)
		elif Art.has("map/map"):
			draw_texture_rect(Art.tex("map/map"), Rect2(Vector2.ZERO, size), false)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.42, 0.66, 0.3))
			var pts := PackedVector2Array()
			for p in main.DIRT_PATH:
				pts.append(p * k)
			draw_polyline(pts, Color(0.78, 0.63, 0.42), 46.0 * k)
		var tree := main.get_tree()
		if main.minimap_tex == null:    # 随机图的树/矿已经画在底图上了
			for n in tree.get_nodes_in_group("res_nodes"):
				draw_circle(n.position * k, 2.2, Color(0.75, 0.75, 0.85) if n.kind == "ore" else Color(0.1, 0.3, 0.1))
		# 战争迷雾：没去过的地方压黑、去过的蒙灰（怪只画看得见的，敌方房子只画去过的）
		var fog = main.get("fog")
		if fog != null and fog.enabled and fog.mini_tex != null:
			draw_texture_rect(fog.mini_tex, Rect2(Vector2.ZERO, size), false)
		for t in tree.get_nodes_in_group("treasures"):
			if t.visible:
				draw_circle(t.position * k, 2.6, Hud.INK)
				draw_circle(t.position * k, 1.8, t.color())
		for b in tree.get_nodes_in_group("buildings"):
			if not b.visible:
				continue
			var s: float = maxf(b.size * k * 1.1, 5.0)
			if b is Ruins:
				draw_circle(b.position * k, maxf(s * 0.5, 3.0), Hud.INK)
				draw_circle(b.position * k, maxf(s * 0.5, 3.0) - 1.0, Color(0.62, 0.6, 0.58))
				continue
			if b.kind == "camp":
				# Goo 据点：橙色圆点（巢穴是红方块），旁边的金色格子就是它守着的富矿
				draw_circle(b.position * k, maxf(s * 0.6, 3.5), Hud.INK)
				draw_circle(b.position * k, maxf(s * 0.6, 3.5) - 1.0, Color(1.0, 0.55, 0.15))
				continue
			var c := Color(0.3, 0.55, 1.0) if b.team == 0 else Color(0.85, 0.25, 0.2)
			draw_rect(Rect2(b.position * k - Vector2(s, s) * 0.5, Vector2(s, s)), c)
			draw_rect(Rect2(b.position * k - Vector2(s, s) * 0.5, Vector2(s, s)), Hud.INK, false, 1.0)
		for s in tree.get_nodes_in_group("sites"):
			draw_rect(Rect2(s.position * k - Vector2(3, 3), Vector2(6, 6)), Color(0.6, 0.75, 1.0, 0.7))
		for u in tree.get_nodes_in_group("units"):
			if u.visible:
				draw_circle(u.position * k, 2.0, Color(0.55, 0.85, 1.0) if u.team == 0 else Color(1.0, 0.35, 0.25))
		# 挨打报警：那儿一圈圈往外扩的红圈（一闪一闪），最新那条在底下写一行字
		var now: float = main.game_time
		var newest: Dictionary = {}
		for a in main.active_alerts():
			var age: float = now - float(a.t0)
			var p: Vector2 = a.pos * k
			for j in 2:
				var ph := fmod(age * 1.2 + j * 0.5, 1.0)
				draw_arc(p, 3.0 + ph * 13.0, 0.0, TAU, 20, Color(1.0, 0.25, 0.15, 1.0 - ph), 2.0)
			if fmod(age, 0.5) < 0.3:
				draw_circle(p, 3.6, Hud.INK)
				draw_circle(p, 2.6, Color(1.0, 0.3, 0.2))
			if newest.is_empty() or float(a.last) > float(newest.last):
				newest = a
		if not newest.is_empty() and now - float(newest.t0) < 4.0:
			Art.text(self, Vector2(size.x * 0.5, size.y - 5.0), main.alert_text(newest.what), 13, Color(1.0, 0.55, 0.42))
		# 视野框
		var cam: Camera2D = main.cam
		if cam != null:
			var half: Vector2 = get_viewport_rect().size / cam.zoom * 0.5
			var r := Rect2((cam.get_screen_center_position() - half) * k, half * 2.0 * k)
			r = r.intersection(Rect2(Vector2.ZERO, size))
			draw_rect(r, Color(1, 1, 1, 0.9), false, 1.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_held = event.pressed
			if _held:
				_jump(event.position)
			accept_event()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if main.game_state == "play":
				main._issue_command(event.position / _k())    # 小地图右键 = 对那里下指令
			accept_event()
		elif event is InputEventMouseMotion and _held:
			_jump(event.position)
			accept_event()

	## 按住拖动时手滑出小地图、在别处松开：那个"松开"事件不会送到这里（控件没抓住鼠标），
	## _held 就一直挂着，之后鼠标随便移回小地图上方（不用按）镜头就跟着乱跳。
	## 这里每帧对一下真实按键状态把它清掉——和 main 里拖框那个兜底是同一类问题
	func _process(_delta: float) -> void:
		if _held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_held = false

	func _jump(p: Vector2) -> void:
		main.center_on(p / _k())
