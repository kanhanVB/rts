class_name Hud
extends CanvasLayer
## 王国保卫战风格 HUD：木板 + 金边面板、粗描边字、3D 渲染的资源/单位图标。
## 只负责"怎么显示"；显示什么（文字、按钮可见性）仍由 main.gd 决定，测试照旧读 main 上的同名控件。

const WOOD := Color(0.4, 0.26, 0.14)
const WOOD_LIGHT := Color(0.55, 0.36, 0.19)
const GOLD := Color(0.95, 0.75, 0.33)
const INK := Color(0.2, 0.12, 0.06)
const CREAM := Color(1.0, 0.95, 0.82)
const PARCH := Color(0.97, 0.9, 0.72)

static var _icons := {}          # key -> ViewportTexture（全局共享，只渲一次）
static var _icon_host: Node = null

var main: Node2D
var root: Control
var theme_res: Theme
var _res_vals := {}              # kind -> Label
var _res_boxes := {}             # kind -> 徽章节点（二级材料没货时隐藏）
var _worker_val: Label
var _hero_val: Label
var _wave_bar: ProgressBar
var _wave_box: PanelContainer
var _help: PanelContainer
var _card: PanelContainer
var _portraits: Control
var _cmd_box: HBoxContainer
var _btn_cost := {}              # Button -> cost Dictionary
var _drag_layer: Control
var minimap: Control
var _side: VBoxContainer

func _init(m: Node2D) -> void:
	main = m
	layer = 5

## ================================================================ 主题
func _font(weight: int) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans SC", "Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei", "sans-serif"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
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

func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = _font(700)
	t.default_font_size = 16
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 5)
	t.set_stylebox("panel", "PanelContainer", box(WOOD, GOLD))
	t.set_stylebox("panel", "TooltipPanel", box(PARCH, INK, 2, 8, 8.0, 4))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 14)
	# 按钮：亮木块 + 金边，按下下沉
	var bn := box(WOOD_LIGHT, GOLD, 3, 10, 6.0, 3)
	var bh := box(WOOD_LIGHT.lightened(0.15), Color(1.0, 0.88, 0.5), 3, 10, 6.0, 3)
	var bp := box(WOOD_LIGHT.darkened(0.2), GOLD, 3, 10, 6.0, 0)
	bp.content_margin_top = 8.0
	var bd := box(Color(0.35, 0.32, 0.3), Color(0.55, 0.5, 0.42), 3, 10, 6.0, 2)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color(1, 1, 0.9))
	t.set_color("font_pressed_color", "Button", CREAM)
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 5)
	t.set_font_size("font_size", "Button", 14)
	# 进度条
	var pbg := box(Color(0.15, 0.09, 0.05), INK, 2, 6, 0.0, 0)
	var pfill := box(Color(0.92, 0.36, 0.22), Color(0, 0, 0, 0), 0, 6, 0.0, 0)
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
	if _icon_host == null or not is_instance_valid(_icon_host):
		_icons.clear()
	_icon_host = Node.new()
	add_child(_icon_host)

	_drag_layer = DragLayer.new()
	_drag_layer.main = main
	_drag_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drag_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_drag_layer)

	_build_resource_bar()
	_build_wave_banner()
	_build_toast()
	_build_card()
	_build_side()
	_build_help()
	_build_overlay()

## 左上：资源徽章（3D 图标 + 数字）+ 农民数 + 英雄状态
func _build_resource_bar() -> void:
	var pc := PanelContainer.new()
	pc.position = Vector2(10, 8)
	root.add_child(pc)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	for k in ["ore", "wood", "ingot", "plank"]:
		var b := _badge(hb, k, Economy.KIND_NAME[k])
		_res_vals[k] = b.get_meta("val")
		_res_boxes[k] = b
	hb.add_child(VSeparator.new())
	_worker_val = _badge(hb, "worker", "农民（上限 %d）" % main.WORKER_CAP).get_meta("val")
	_hero_val = _badge(hb, "engineer", "英雄工程师：唯一会盖房子的人，阵亡后在基地免费复活").get_meta("val")
	_hero_val.add_theme_font_size_override("font_size", 15)
	main.res_label = Label.new()     # 兼容：完整资源文字仍写在这里（不显示）
	main.res_label.visible = false
	root.add_child(main.res_label)

func _badge(parent: Control, key: String, tip: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 2)
	hb.tooltip_text = tip
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(hb)
	var tr := TextureRect.new()
	tr.texture = icon(key)
	tr.custom_minimum_size = Vector2(38, 38)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(tr)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 21)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 34
	hb.add_child(l)
	hb.set_meta("val", l)
	return hb

## 右上：波次横幅 + 倒计时条 + 帮助/产能开关
func _build_wave_banner() -> void:
	_wave_box = PanelContainer.new()
	_wave_box.add_theme_stylebox_override("panel", box(Color(0.5, 0.14, 0.1), GOLD))
	root.add_child(_wave_box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_wave_box.add_child(vb)
	main.wave_label = Label.new()
	main.wave_label.add_theme_font_size_override("font_size", 18)
	main.wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(main.wave_label)
	_wave_bar = ProgressBar.new()
	_wave_bar.custom_minimum_size = Vector2(250, 10)
	_wave_bar.show_percentage = false
	_wave_bar.max_value = 1.0
	vb.add_child(_wave_bar)
	var hb := HBoxContainer.new()
	hb.position = Vector2(1280 - 128, 74)
	hb.add_theme_constant_override("separation", 6)
	root.add_child(hb)
	var bp := _small_btn(hb, "产能", "产能面板（C 键）")
	bp.pressed.connect(func(): main._panel_on = not main._panel_on; main._update_panel())
	var bh := _small_btn(hb, "?", "操作说明（F1）")
	bh.pressed.connect(toggle_help)

func _small_btn(parent: Control, text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 34)
	parent.add_child(b)
	return b

## 屏幕中上：提示条（羊皮纸）
func _build_toast() -> void:
	var l := Label.new()
	l.add_theme_stylebox_override("normal", box(PARCH, INK, 3, 16, 10.0, 5))
	l.add_theme_font_size_override("font_size", 18)
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
	root.add_child(_card)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_card.add_child(hb)
	_portraits = Portraits.new()
	_portraits.hud = self
	hb.add_child(_portraits)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 15)
	info.custom_minimum_size = Vector2(250, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	main.info_label = info
	_cmd_box = HBoxContainer.new()
	_cmd_box.add_theme_constant_override("separation", 6)
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
	b.custom_minimum_size = Vector2(76, 100)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s（%s）\n%s" % [title, main.economy.cost_text(cost), tip]
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_constant_override("line_spacing", -2)
	b.pressed.connect(cb)
	parent.add_child(b)
	_btn_cost[b] = cost
	return b

## 右下：产能面板 + 小地图
func _build_side() -> void:
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 8)
	root.add_child(_side)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Color(WOOD, 0.88), GOLD, 3, 10, 10.0, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.add_child(p)
	main.panel = p
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_constant_override("line_spacing", 1)
	p.add_child(l)
	main.panel_label = l
	var mp := PanelContainer.new()
	mp.add_theme_stylebox_override("panel", box(WOOD, GOLD, 3, 8, 4.0, 4))
	_side.add_child(mp)
	minimap = Minimap.new()
	minimap.main = main
	minimap.custom_minimum_size = Vector2(224, 126)
	mp.add_child(minimap)

func _build_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", box(PARCH, INK, 3, 14, 16.0, 8))
	_help.visible = false
	root.add_child(_help)
	var l := Label.new()
	l.add_theme_color_override("font_color", INK)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_font_size_override("font_size", 15)
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

## 结算：半透明黑幕 + 羊皮纸卷轴
func _build_overlay() -> void:
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.55)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.visible = false
	root.add_child(ov)
	main.overlay = ov
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", box(PARCH, INK, 4, 18, 28.0, 12))
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	ov.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	pc.add_child(vb)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 40)
	l.add_theme_color_override("font_color", Color(0.98, 0.82, 0.3))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	main.overlay_label = l
	var restart := Button.new()
	restart.text = "再来一局"
	restart.add_theme_font_size_override("font_size", 20)
	restart.custom_minimum_size = Vector2(180, 52)
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
		_hero_val.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	elif main._player_engineers().is_empty():
		_hero_val.text = "失踪"
		_hero_val.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
	else:
		_hero_val.text = "上阵"
		_hero_val.remove_theme_color_override("font_color")
	# 波次条：离下一波越近越满
	var wm: WaveManager = main._wave_mgr
	_wave_box.visible = main.game_state == "play"
	var span: float = WaveManager.FIRST_WAVE_AT if wm.wave == 0 else WaveManager.WAVE_INTERVAL
	_wave_bar.visible = wm.wave < WaveManager.MAX_WAVES
	_wave_bar.value = 1.0 - clampf(wm.wave_timer / span, 0.0, 1.0)
	_fit(_wave_box, Vector2(1280 - _wave_box.size.x - 10, 8))
	# 提示条居中
	var t: Label = main._hud_msg_label
	if t.visible:
		_fit(t, Vector2((1280 - t.size.x) * 0.5, 84))
	# 指令卡：有选中才出现
	var list: Array = main._display_list()
	_card.visible = not list.is_empty() and main.game_state == "play"
	if _card.visible:
		var any_btn := false
		for b in _btn_cost:
			if b.visible:
				any_btn = true
				var ok: bool = e.can_afford(_btn_cost[b])
				b.add_theme_color_override("font_color", CREAM if ok else Color(1.0, 0.55, 0.45))
				b.add_theme_color_override("font_hover_color", Color(1, 1, 0.9) if ok else Color(1.0, 0.65, 0.55))
				b.self_modulate = Color.WHITE if ok else Color(0.85, 0.8, 0.78)
		_cmd_box.visible = any_btn
		main.info_label.custom_minimum_size.x = 250 if any_btn else 420
		_portraits.queue_redraw()
		_portraits.update_size(list.size())
		_fit(_card, Vector2.ZERO)
		_card.position = Vector2((1280 - _card.size.x) * 0.5 - 60.0, 720 - _card.size.y - 8)
	# 右下栏
	_fit(_side, Vector2(1280 - _side.size.x - 10, 720 - _side.size.y - 8))
	_fit(_help, Vector2((1280 - _help.size.x) * 0.5, 130))
	_drag_layer.queue_redraw()
	minimap.queue_redraw()

func _fit(c: Control, pos: Vector2) -> void:
	c.size = c.get_combined_minimum_size()
	if pos != Vector2.ZERO:
		c.position = pos

## ================================================================ 3D 图标
## 每种 key 开一个独立 3D 小世界的 SubViewport，只渲一帧，之后当贴图到处复用
func icon(key: String) -> Texture2D:
	if _icons.has(key):
		return _icons[key]
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_icon_host.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var model := Models.icon_model(key)
	vp.add_child(model)
	var bb := _aabb(model, Transform3D.IDENTITY)
	var center := bb.get_center()
	var radius := maxf(bb.size.length() * 0.5, 0.05)
	var cam := Camera3D.new()
	cam.fov = 30.0
	var dir := Vector3(1.0, 0.75, 1.0).normalized()
	if key in ["worker", "engineer", "sword", "archer", "goo"]:
		dir = Vector3(1.0, 0.35, 0.55).normalized()    # 人物：偏正面，看得见脸
		center.y += bb.size.y * 0.06
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.92
	cam.position = center + dir * dist
	vp.add_child(cam)
	cam.look_at_from_position(cam.position, center, Vector3.UP)
	cam.near = 0.01
	cam.far = dist * 3.0
	var tex := vp.get_texture()
	_icons[key] = tex
	return tex

func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var my := xf
	if n is Node3D:
		my = xf * (n as Node3D).transform
	if n is MeshInstance3D and n.mesh != null:
		out = my * n.mesh.get_aabb()
		first = false
	for c in n.get_children():
		var sub := _aabb(c, my)
		if sub.size == Vector3.ZERO:
			continue
		out = sub if first else out.merge(sub)
		first = false
	return out

## ================================================================ 子控件
## 选中头像：单选一个大头像，多选排成两行小头像，都带血条
class Portraits extends Control:
	var hud: Hud
	var _n := 0

	func update_size(n: int) -> void:
		if n == _n:
			return
		_n = n
		if n <= 1:
			custom_minimum_size = Vector2(100, 100)
		else:
			custom_minimum_size = Vector2(46.0 * mini(n, 8) + 6.0, 54.0 if n <= 8 else 104.0)

	func _draw() -> void:
		var list: Array = hud.main._display_list()
		if list.is_empty():
			return
		if list.size() == 1:
			_one(list[0], Rect2(6, 2, 88, 88), 7.0)
			return
		var shown := mini(list.size(), 16)
		for i in shown:
			var col := i % 8
			var row := i / 8
			if i == 15 and list.size() > 16:
				draw_string(get_theme_default_font(), Vector2(col * 46.0 + 8.0, row * 50.0 + 32.0),
					"+%d" % (list.size() - 15), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Hud.CREAM)
				break
			_one(list[i], Rect2(col * 46.0 + 3.0, row * 50.0 + 2.0, 42, 42), 4.0)

	func _one(u, r: Rect2, bar_h: float) -> void:
		var enemy: bool = u.team != 0
		var frame := Hud.box(Color(0.93, 0.85, 0.66) if not enemy else Color(0.92, 0.7, 0.62), Hud.GOLD if not enemy else Color(0.85, 0.3, 0.2), 3, 10, 0.0, 0)
		draw_style_box(frame, r)
		var tex: Texture2D = hud.icon(Models.key_of(u))
		draw_texture_rect(tex, r.grow(-3.0), false)
		var hb := Rect2(r.position.x, r.end.y + 2.0, r.size.x, bar_h)
		draw_rect(hb, Hud.INK)
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		var c := Color(0.4, 0.9, 0.3) if ratio > 0.5 else (Color(0.95, 0.8, 0.25) if ratio > 0.25 else Color(0.95, 0.3, 0.2))
		draw_rect(Rect2(hb.position + Vector2(1, 1), Vector2((hb.size.x - 2.0) * ratio, hb.size.y - 2.0)), c)

## 屏幕空间拖框（3D 模式下框选按屏幕矩形算）
class DragLayer extends Control:
	var main: Node2D

	func _draw() -> void:
		if not main._dragging or main.view == null:
			return
		var a: Vector2 = main._drag_start_screen
		var b: Vector2 = get_viewport().get_mouse_position()
		var r := Rect2(a, b - a).abs()
		if r.size.length() < 6.0:
			return
		draw_rect(r, Color(0.6, 1.0, 0.5, 0.12))
		draw_rect(r, Color(0.75, 1.0, 0.6, 0.9), false, 2.0)

## 小地图：地形示意 + 建筑/单位/资源点 + 当前视野框，点击/拖动跳转镜头
class Minimap extends Control:
	var main: Node2D
	var _held := false

	func _k() -> float:
		return size.x / float(main.W)

	func _draw() -> void:
		var k := _k()
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.42, 0.66, 0.3))
		var pts := PackedVector2Array()
		for p in main.DIRT_PATH:
			pts.append(p * k)
		draw_polyline(pts, Color(0.78, 0.63, 0.42), 46.0 * k)
		var tree := main.get_tree()
		for n in tree.get_nodes_in_group("res_nodes"):
			draw_circle(n.position * k, 2.2, Color(0.62, 0.62, 0.7) if n.kind == "ore" else Color(0.15, 0.4, 0.15))
		for b in tree.get_nodes_in_group("buildings"):
			var s: float = maxf(b.size * k * 1.1, 5.0)
			var c := Color(0.3, 0.55, 1.0) if b.team == 0 else Color(0.85, 0.25, 0.2)
			draw_rect(Rect2(b.position * k - Vector2(s, s) * 0.5, Vector2(s, s)), c)
			draw_rect(Rect2(b.position * k - Vector2(s, s) * 0.5, Vector2(s, s)), Hud.INK, false, 1.0)
		for s in tree.get_nodes_in_group("sites"):
			draw_rect(Rect2(s.position * k - Vector2(3, 3), Vector2(6, 6)), Color(0.6, 0.75, 1.0, 0.7))
		for u in tree.get_nodes_in_group("units"):
			draw_circle(u.position * k, 1.8, Color(0.55, 0.85, 1.0) if u.team == 0 else Color(1.0, 0.35, 0.25))
		# 视野框：把屏幕四角投到地面
		if main.view != null:
			var v: View3D = main.view
			var vs := Vector2(1280, 720)
			var poly := PackedVector2Array()
			for c in [Vector2.ZERO, Vector2(vs.x, 0), vs, Vector2(0, vs.y), Vector2.ZERO]:
				var g: Vector2 = v.ground_at(c) * k
				poly.append(Vector2(clampf(g.x, 0, size.x), clampf(g.y, 0, size.y)))
			draw_polyline(poly, Color(1, 1, 1, 0.9), 1.5)

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
