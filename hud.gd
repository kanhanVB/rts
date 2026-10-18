class_name Hud
extends CanvasLayer
## 王国保卫战风格 HUD：木板金边面板、羊皮纸提示、红绸波次横幅、圆框头像，全部用 art/ui 贴图九宫格拉伸。
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
	"ui/panel": [56, 56, 56, 56],
	"ui/parchment": [44, 80, 44, 74],
	"ui/button": [40, 36, 40, 36],
	"ui/button_hover": [40, 36, 40, 36],
	"ui/button_pressed": [40, 36, 40, 36],
	"ui/button_disabled": [40, 36, 40, 36],
	"ui/banner": [140, 22, 140, 34],
}

var main: Node2D
var root: Control
var theme_res: Theme
var _res_vals := {}              # kind -> Label
var _res_boxes := {}             # kind -> 徽章节点（二级材料没货时隐藏）
var _worker_val: Label
var _hero_val: Label
var _wave_bar: ProgressBar
var _wave_box: VBoxContainer
var _help: PanelContainer
var _card: PanelContainer
var _portraits: Control
var _cmd_box: HBoxContainer
var _btn_cost := {}              # Button -> cost Dictionary
var _overlay_pic: TextureRect
var minimap: Control
var _side: VBoxContainer
var _res_panel: PanelContainer
var _btn_row: HBoxContainer

func _init(m: Node2D) -> void:
	main = m
	layer = 5

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
	_build_resource_bar()
	_build_wave_banner()
	_build_toast()
	_build_card()
	_build_side()
	_build_help()
	_build_overlay()

## 左上：资源徽章（物品图标 + 数字）+ 农民数 + 英雄状态
func _build_resource_bar() -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _panel_box(0.3, 0.0))
	pc.position = Vector2(8, 6)
	root.add_child(pc)
	_res_panel = pc
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	for k in ["ore", "wood", "ingot", "plank"]:
		var b := _badge(hb, k, Economy.KIND_NAME[k])
		_res_vals[k] = b.get_meta("val")
		_res_boxes[k] = b
	_worker_val = _badge(hb, "workers", "农民（上限 %d）" % main.WORKER_CAP).get_meta("val")
	_hero_val = _badge(hb, "engineer", "英雄工程师：唯一会盖房子的人，阵亡后在基地免费复活").get_meta("val")
	_hero_val.add_theme_font_size_override("font_size", 18)
	main.res_label = Label.new()     # 兼容：完整资源文字仍写在这里（不显示）
	main.res_label.visible = false
	root.add_child(main.res_label)

func _badge(parent: Control, key: String, tip: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.tooltip_text = tip
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(hb)
	var tr := TextureRect.new()
	tr.texture = icon(key)
	tr.custom_minimum_size = Vector2(34, 34)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tr)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 23)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 34
	hb.add_child(l)
	hb.set_meta("val", l)
	return hb

## 右上：红绸波次横幅 + 倒计时条 + 产能/帮助按钮
func _build_wave_banner() -> void:
	_wave_box = VBoxContainer.new()
	_wave_box.add_theme_constant_override("separation", 2)
	_wave_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_wave_box)
	var ribbon := PanelContainer.new()
	ribbon.add_theme_stylebox_override("panel", tbox("ui/banner", 0.62, [6.0, -2.0, 6.0, -2.0], box(Color(0.6, 0.14, 0.1), GOLD)))
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_box.add_child(ribbon)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	ribbon.add_child(hb)
	var ic := TextureRect.new()
	ic.texture = icon("wave")
	ic.custom_minimum_size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hb.add_child(ic)
	main.wave_label = Label.new()
	main.wave_label.add_theme_font_size_override("font_size", 19)
	main.wave_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.6))
	main.wave_label.add_theme_color_override("font_outline_color", Color(0.3, 0.05, 0.03))
	main.wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(main.wave_label)
	_wave_bar = ProgressBar.new()
	_wave_bar.custom_minimum_size = Vector2(220, 9)
	_wave_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_wave_bar.show_percentage = false
	_wave_bar.max_value = 1.0
	_wave_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_box.add_child(_wave_bar)
	var bb := HBoxContainer.new()      # 产能/帮助按钮挂在资源栏右边，别挡住右上角的巢穴
	bb.add_theme_constant_override("separation", 6)
	root.add_child(bb)
	_btn_row = bb
	var bp := _small_btn(bb, "产能", "产能面板（C 键）")
	bp.pressed.connect(func(): main._panel_on = not main._panel_on; main._update_panel())
	var bh := _small_btn(bb, "?", "操作说明（F1）")
	bh.pressed.connect(toggle_help)

func _small_btn(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44 if text.length() < 2 else 64, 32)
	parent.add_child(b)
	return b

## 屏幕中上：提示条（羊皮纸）
func _build_toast() -> void:
	var l := Label.new()
	l.add_theme_stylebox_override("normal", _parch_box(0.26, [14.0, -4.0, 14.0, -4.0]))
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", INK)
	l.add_theme_constant_override("outline_size", 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.visible = false
	root.add_child(l)
	main._hud_msg_label = l

## 底部中央：指令卡 = 头像 | 数值 | 指令按钮
func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _panel_box(0.36, 0.0))
	root.add_child(_card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_card.add_child(hb)
	_portraits = Portraits.new()
	_portraits.hud = self
	hb.add_child(_portraits)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 16)
	info.add_theme_constant_override("outline_size", 5)
	info.custom_minimum_size = Vector2(250, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	main.info_label = info
	_cmd_box = HBoxContainer.new()
	_cmd_box.add_theme_constant_override("separation", 5)
	hb.add_child(_cmd_box)
	main.btn_worker = _cmd(_cmd_box, "worker", "农民", Economy.COST_WORKER, main._on_worker_pressed, "采矿、伐木、搬运。右键矿/树派去采集")
	main.btn_warehouse = _cmd(_cmd_box, "warehouse", "仓库", Economy.COST_WAREHOUSE, main._on_warehouse_pressed, "就近交货点，缩短农民跑路")
	main.btn_smelter = _cmd(_cmd_box, "smelter", "熔炉", Economy.COST_SMELTER, main._on_smelter_pressed, "矿石 → 铁锭（剑士要用）。农民右键熔炉送矿")
	main.btn_workshop = _cmd(_cmd_box, "workshop", "木工台", Economy.COST_WORKSHOP, main._on_workshop_pressed, "木材 → 木板（弓手要用）。农民右键木工台送木")
	main.btn_barracks = _cmd(_cmd_box, "barracks", "兵营", Economy.COST_BARRACKS, main._on_barracks_pressed, "训练剑士和弓手")
	main.btn_sword = _cmd(_cmd_box, "sword", "剑士", Economy.COST_SWORD, main._on_sword_pressed, "近战前排，护甲高")
	main.btn_archer = _cmd(_cmd_box, "archer", "弓手", Economy.COST_ARCHER, main._on_archer_pressed, "远程输出，躲在剑士后面")
	for b in [main.btn_worker, main.btn_warehouse, main.btn_smelter, main.btn_workshop,
			main.btn_barracks, main.btn_sword, main.btn_archer]:
		b.visible = false

func _cmd(parent: Control, key: String, title: String, cost: Dictionary, cb: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = "%s\n%s" % [title, main.economy.cost_text(cost)]
	b.icon = icon(key)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.custom_minimum_size = Vector2(80, 104)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s（%s）\n%s" % [title, main.economy.cost_text(cost), tip]
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_constant_override("line_spacing", -3)
	b.add_theme_constant_override("outline_size", 5)
	b.pressed.connect(cb)
	parent.add_child(b)
	_btn_cost[b] = cost
	return b

## 右下：产能面板 + 小地图
func _build_side() -> void:
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 6)
	root.add_child(_side)
	var p := PanelContainer.new()
	var psb := _panel_box(0.3, 2.0)
	p.add_theme_stylebox_override("panel", psb)
	p.self_modulate = Color(1, 1, 1, 0.93)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(p)
	main.panel = p
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_constant_override("line_spacing", 1)
	l.add_theme_constant_override("outline_size", 5)
	p.add_child(l)
	main.panel_label = l
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", _panel_box(0.22, -6.0))
	_side.add_child(mp)
	minimap = Minimap.new()
	minimap.main = main
	minimap.custom_minimum_size = Vector2(228, 128)
	mp.add_child(minimap)

func _build_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", _parch_box(0.55, [14.0, -6.0, 14.0, -8.0]))
	_help.visible = false
	root.add_child(_help)
	var l := Label.new()
	l.add_theme_color_override("font_color", INK)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_font_size_override("font_size", 17)
	l.text = """操作说明
左键：点选单位/建筑 · 拖动：框选己方单位
右键：空地 = 移动 · 矿/树 = 农民去采 · 敌人 = 攻击
右键己方仓库/熔炉/木工台 = 农民改送那里
A + 右键：攻击移动（路上遇敌就打）
Ctrl+数字：编队 · 数字：召回编队
滚轮：缩放 · 鼠标贴边 / 方向键：移动镜头 · 小地图：点击跳转
点基地 = 造农民 · 点兵营 = 出兵 · 点工程师 = 盖设施
C：产能面板 · F1：本说明"""
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
	var restart := Button.new()
	restart.text = "再来一局"
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
	_worker_val.text = "%d/%d" % [main._player_workers().size(), main.WORKER_CAP]
	if not main.respawn_timers.is_empty():
		_hero_val.text = "复活 %ds" % int(maxf(main.respawn_timers[0], 0.0))
		_hero_val.add_theme_color_override("font_color", RED_TEXT)
	elif main._player_engineers().is_empty():
		_hero_val.text = "失踪"
		_hero_val.add_theme_color_override("font_color", RED_TEXT)
	else:
		_hero_val.text = "上阵"
		_hero_val.remove_theme_color_override("font_color")
	# 波次条：离下一波越近越满
	var wm: WaveManager = main._wave_mgr
	_wave_box.visible = main.game_state == "play"
	var span: float = WaveManager.FIRST_WAVE_AT if wm.wave == 0 else WaveManager.WAVE_INTERVAL
	_wave_bar.visible = wm.wave < WaveManager.MAX_WAVES
	_wave_bar.value = 1.0 - clampf(wm.wave_timer / span, 0.0, 1.0)
	_fit(_wave_box, Vector2(1280 - _wave_box.size.x - 8, 6))
	_fit(_res_panel, Vector2.ZERO)
	_fit(_btn_row, _res_panel.position + Vector2(_res_panel.size.x + 6.0, (_res_panel.size.y - 32.0) * 0.5))
	# 提示条居中
	var t: Label = main._hud_msg_label
	if t.visible:
		_fit(t, Vector2((1280 - t.size.x) * 0.5, 80))
	# 指令卡：有选中才出现
	var list: Array = main._display_list()
	_card.visible = not list.is_empty() and main.game_state == "play"
	if _card.visible:
		var any_btn := false
		for b in _btn_cost:
			if b.visible:
				any_btn = true
				var ok: bool = e.can_afford(_btn_cost[b])
				b.add_theme_color_override("font_color", CREAM if ok else RED_TEXT)
				b.add_theme_color_override("font_hover_color", Color(1, 1, 0.9) if ok else Color(1.0, 0.65, 0.55))
				b.self_modulate = Color.WHITE if ok else Color(0.8, 0.75, 0.72)
		_cmd_box.visible = any_btn
		main.info_label.custom_minimum_size.x = 240 if any_btn else 400
		_portraits.queue_redraw()
		_portraits.update_size(list.size())
		_fit(_card, Vector2.ZERO)
		_card.position = Vector2((1280 - _card.size.x) * 0.5 - 70.0, 720 - _card.size.y - 6)
	# 右下栏
	_fit(_side, Vector2(1280 - _side.size.x - 8, 720 - _side.size.y - 6))
	_fit(_help, Vector2((1280 - _help.size.x) * 0.5, 120))
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
	"sword": "units/swordsman_idle", "archer": "units/archer_idle",
	"warehouse": "buildings/warehouse", "smelter": "buildings/smelter", "workshop": "buildings/workshop",
	"barracks": "buildings/barracks", "base": "buildings/base", "hive": "buildings/hive", "wave": "ui/icon_wave",
}

func icon(key: String) -> Texture2D:
	var k: String = ICON_KEY.get(key, key)
	return Art.tex(k) if Art.has(k) else null

## ================================================================ 子控件
## 选中头像：金圈圆框 + 头像；单选一个大的，多选排成两行小的，都带血条
class Portraits extends Control:
	var hud: Hud
	var _n := 0

	func update_size(n: int) -> void:
		if n == _n:
			return
		_n = n
		if n <= 1:
			custom_minimum_size = Vector2(104, 108)
		else:
			custom_minimum_size = Vector2(48.0 * mini(n, 8) + 4.0, 56.0 if n <= 8 else 110.0)

	func _draw() -> void:
		var list: Array = hud.main._display_list()
		if list.is_empty():
			return
		if list.size() == 1:
			_one(list[0], Rect2(4, 0, 96, 96), 7.0)
			return
		var shown := mini(list.size(), 16)
		for i in shown:
			var col := i % 8
			var row := i / 8
			if i == 15 and list.size() > 16:
				Art.text(self, Vector2(col * 48.0 + 24.0, row * 54.0 + 30.0), "+%d" % (list.size() - 15), 20, Hud.CREAM)
				break
			_one(list[i], Rect2(col * 48.0 + 3.0, row * 54.0 + 1.0, 44, 44), 5.0)

	## 头像内容：农民/英雄/敌人用专门的圆头像图标，兵种裁立绘上半身，建筑整张缩进去
	func _face(u) -> Array:
		if u is Building:
			return ["buildings/" + u.kind, false]
		var k: String = u._art_key()
		match k:
			"worker": return ["ui/icon_worker", false]
			"engineer": return ["ui/icon_hero", false]
			"goo": return ["units/goo_idle", false]
			_: return ["units/%s_idle" % k, true]

	func _one(u, r: Rect2, bar_h: float) -> void:
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
				draw_texture_rect(t, Rect2(c - sz * 0.5, sz), false)
		else:
			draw_circle(c, rad * 0.4, Color(0.3, 0.55, 1.0) if not enemy else Color(0.85, 0.25, 0.2))
		if Art.has("ui/portrait_frame"):
			draw_texture_rect(Art.tex("ui/portrait_frame"), r, false, Color(1, 0.75, 0.7) if enemy else Color.WHITE)
		else:
			draw_arc(c, rad - 2.0, 0, TAU, 40, Hud.GOLD, 3.0)
		var hb := Rect2(r.position.x + 4.0, r.end.y + 3.0, r.size.x - 8.0, bar_h)
		draw_rect(hb, Hud.INK)
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		var bc := Color(0.4, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.25) if ratio > 0.25 else Color(0.95, 0.3, 0.2))
		draw_rect(Rect2(hb.position + Vector2(1, 1), Vector2((hb.size.x - 2.0) * ratio, hb.size.y - 2.0)), bc)

## 小地图：整张地图缩略图 + 建筑/单位/资源点 + 当前视野框，点击/拖动跳转镜头
class Minimap extends Control:
	var main: Node2D
	var _held := false

	func _k() -> float:
		return size.x / float(main.W)

	func _draw() -> void:
		var k := _k()
		if Art.has("map/map"):
			draw_texture_rect(Art.tex("map/map"), Rect2(Vector2.ZERO, size), false)
		else:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.42, 0.66, 0.3))
			var pts := PackedVector2Array()
			for p in main.DIRT_PATH:
				pts.append(p * k)
			draw_polyline(pts, Color(0.78, 0.63, 0.42), 46.0 * k)
		var tree := main.get_tree()
		for n in tree.get_nodes_in_group("res_nodes"):
			draw_circle(n.position * k, 2.2, Color(0.75, 0.75, 0.85) if n.kind == "ore" else Color(0.1, 0.3, 0.1))
		for b in tree.get_nodes_in_group("buildings"):
			var s: float = maxf(b.size * k * 1.1, 5.0)
			var c := Color(0.3, 0.55, 1.0) if b.team == 0 else Color(0.85, 0.25, 0.2)
			draw_rect(Rect2(b.position * k - Vector2(s, s) * 0.5, Vector2(s, s)), c)
			draw_rect(Rect2(b.position * k - Vector2(s, s) * 0.5, Vector2(s, s)), Hud.INK, false, 1.0)
		for s in tree.get_nodes_in_group("sites"):
			draw_rect(Rect2(s.position * k - Vector2(3, 3), Vector2(6, 6)), Color(0.6, 0.75, 1.0, 0.7))
		for u in tree.get_nodes_in_group("units"):
			draw_circle(u.position * k, 2.0, Color(0.55, 0.85, 1.0) if u.team == 0 else Color(1.0, 0.35, 0.25))
		# 视野框
		var cam: Camera2D = main.cam
		if cam != null:
			var half: Vector2 = Vector2(1280, 720) / cam.zoom * 0.5
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
			main._issue_command(event.position / _k())    # 小地图右键 = 对那里下指令
			accept_event()
		elif event is InputEventMouseMotion and _held:
			_jump(event.position)
			accept_event()

	func _jump(p: Vector2) -> void:
		main.cam.position = p / _k()
