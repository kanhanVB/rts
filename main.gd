extends Node2D
## 主脚本：地图、选择、指令、UI、波次、胜负，外加一套无头自测。
## 操作照帝国时代：左键点选 / 拖框 / Shift 加减选 / 双击选同类；右键 = 智能指令；命令卡热键按 5×3 位置（详见“输入”一节）。

## 地图尺寸：经典测试图 1280×720；随机图 3200×2048（约 2.5×2.8 屏）
var W := 1280.0
var H := 720.0
const MAP_W := 3200.0
const MAP_H := 2048.0

const WORKER_CAP := 16
const ENGINEER_RESPAWN := 15.0    # 英雄工程师阵亡后的复活倒计时
const UNIT_CAP := 40

# 镜头
var CAM_MIN_ZOOM := 1.0       # 缩放下限：经典图 = 视野正好铺满地图；随机图大，可以缩到 0.55 看大局
const CAM_MAX_ZOOM := 2.4     # 放大上限，贴近看单位
const CAM_EDGE := 10.0          # 鼠标贴边多少像素就开始滚屏
const CAM_SPEED := 8.0          # 每像素滚屏速度（乘 delta）

# ---- 地面装饰（固定坐标：KR 式草地深浅斑 + 基地到巢穴的土路）----
const GRASS_DARK := [Vector2(500, 620), Vector2(920, 640), Vector2(240, 170), Vector2(780, 110), Vector2(1190, 430), Vector2(60, 300)]
const GRASS_LIGHT := [Vector2(360, 380), Vector2(840, 520), Vector2(1090, 640), Vector2(560, 140), Vector2(950, 100)]
const DIRT_PATH := [Vector2(170, 580), Vector2(420, 530), Vector2(660, 440), Vector2(880, 330), Vector2(1100, 210)]
const STONES := [Vector2(300, 565), Vector2(520, 480), Vector2(760, 390), Vector2(980, 300), Vector2(600, 470), Vector2(430, 520), Vector2(900, 360), Vector2(1050, 250), Vector2(340, 500)]

## 三个子系统：经济（资源账本）/ 建造（设施 + 工地）/ 波次（防守压力）
var economy: Economy = Economy.new()
var _build_mgr: BuildManager
var _wave_mgr: WaveManager

var base: Building
var hive: Building                 # 第一个巢穴（兼容老代码/测试）；全部巢穴在 hives
var hives: Array = []
var roads: Array = []              # 每个巢穴一条行军土路（点从主城端排到巢穴端），和 hives 一一对应
var classic := false               # 经典固定图（--test / --classic）：测试断言用的老坐标
var map_seed := 0
var layout := {}                   # 随机图布局（MapGen.generate 的结果）
var ground: Ground
var decor_layer: DecorLayer
var minimap_img: Image             # 小地图底图（每格一像素：草/树/矿/路），砍树时改像素
var minimap_tex: ImageTexture
var barracks_list: Array = []
var warehouses_list: Array = []
var processors_list: Array = []   # 熔炉 / 木工台：加工链上的设施
var selected: Array = []
var inspected: Unit = null         # 点敌人只看属性，不能指挥
var respawn_timers: Array = []    # 每个阵亡工程师一个复活倒计时
var terrain: Terrain

var game_state := "play"    # play / win / lose

var _drag_start := Vector2.ZERO
var _dragging := false
var _placing_kind := ""      # ""=没在放置；"barracks"/"warehouse"=等待点地图落工地
var _build_eng: Engineer = null    # 进入放置模式时选中的工程师，完工工地直接派给他
var _fail := 0

# 镜头
var cam: Camera2D
var control_groups: Array = []    # 编队：control_groups[i] = 该队的单位数组

# UI 引用
var ui: CanvasLayer
var res_label: Label
var wave_label: Label
var overlay: ColorRect
var overlay_label: Label
var _hud_msg_label: Label
var _hud_msg_t := 0.0
var info_label: Label        # 底部信息栏：点选 = 数值，框选 = "已选中 N 个"
var panel: Control           # 产能面板（C 键开关）
var panel_label: Label
var _panel_on := true
var hud: Hud                 # 王国保卫战风格 HUD（hud.gd）
var _decor: Array = []       # 地图装饰：[{key, pos, flip}]（纯视觉）
var _markers: Array = []
var _rally_i := 0            # 新兵在兵营前排队的序号     # 右键落点圈：[{pos, t0, attack}]

func _ready() -> void:
	add_to_group("game")
	randomize()
	var args := OS.get_cmdline_user_args()
	classic = "--test" in args or "--classic" in args
	map_seed = randi() % 1000000
	for a in args:
		if a.begins_with("--seed="):
			map_seed = int(a.substr(7))
	_build_mgr = BuildManager.new()
	add_child(_build_mgr)
	_build_mgr.building_built.connect(_on_building_built)
	_wave_mgr = WaveManager.new()
	add_child(_wave_mgr)
	_build_map()
	_build_ui()
	_build_camera()
	if "--noart" in OS.get_cmdline_user_args():
		Art.enabled = false    # 对比用：退回原来的程序化色块画法
	# 贴图有高度，必须按 y 排序（靠下的挡住靠上的）；建筑/工地挂在 BuildManager 下，一起参与排序
	y_sort_enabled = true
	_build_mgr.y_sort_enabled = true
	if classic:
		_build_decor()
	if Art.has("ui/cursor") and DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(Art.tex("ui/cursor"), Input.CURSOR_ARROW, Vector2(4, 2))
	if "--test" in OS.get_cmdline_user_args():
		_wave_mgr.wave_timer = 999.0    # 测试期间不来波次，保证断言确定性
		train_scale = 0.0               # 老断言按"点了就出"写的；读条另有专门的测试
		_run_test()

## 建造系统完工回调：按 kind 归档（基建加设施种类时在这里加分支）
func _on_building_built(b: Building) -> void:
	if b.kind == "barracks":
		barracks_list.append(b)
	elif b.kind == "warehouse":
		warehouses_list.append(b)
	elif b.kind == "smelter" or b.kind == "workshop":
		processors_list.append(b)
func _build_camera() -> void:
	cam = Camera2D.new()
	cam.position = Vector2(W / 2.0, H / 2.0) if classic else base.position + Vector2(0, 60)
	cam.zoom = Vector2.ONE
	CAM_MIN_ZOOM = 1.0 if classic else 0.55
	add_child(cam)
	cam.make_current()    # 必须在 add_child 之后，否则报 "not inside tree"

## ================================ 地图 ================================
func _build_map() -> void:
	# 地形层（先建，垫在最下面）
	terrain = Terrain.new()
	add_child(terrain)
	if classic:
		_build_classic_map()
	else:
		_build_random_map()
	# 开局 3 工人自动分工：2 采矿 1 伐木，开局就有供应链在转
	for i in 3:
		var w := Worker.new()
		w.position = base.position + Vector2(60.0 + i * 30.0, 40.0)
		add_child(w)
		w.auto_assign("wood" if i == 2 else "ore")

	# 开局 1 名工程师，负责建造
	_spawn_engineer(base.position + Vector2(90.0, 40.0))

## 经典固定图（测试用）：1280×720，基地左下、巢穴右上，三片矿三片树，资源点不占格
func _build_classic_map() -> void:
	terrain.setup(W, H)
	_build_terrain()
	base = _build_mgr.add_building("base", Vector2(170, 560), 0)
	hive = _build_mgr.add_building("hive", Vector2(1110, 160), 1)
	hives = [hive]
	roads = [ArtData.ROAD if Art.has("map/map") and not ArtData.ROAD.is_empty() else DIRT_PATH]
	for c in [Vector2(430, 470), Vector2(720, 260), Vector2(960, 560)]:
		for i in 3:
			_add_res("ore", c + Vector2((i - 1) * 46.0, 0.0 if i == 1 else 36.0))
	for c in [Vector2(320, 240), Vector2(620, 570), Vector2(1010, 420)]:
		for i in 3:
			_add_res("wood", c + Vector2((i - 1) * 46.0, 0.0 if i == 1 else 36.0))

## 随机图：主城在正中，巢穴在两侧边缘，土路、树林、矿都由 MapGen 按种子生成
func _build_random_map() -> void:
	W = MAP_W
	H = MAP_H
	layout = MapGen.generate(map_seed, W, H)
	terrain.setup(W, H)
	terrain.draw_cells = false
	ground = Ground.new()
	add_child(ground)
	ground.build(layout, W, H)
	decor_layer = DecorLayer.new()
	add_child(decor_layer)
	decor_layer.items = layout.decor.duplicate()
	var gw: int = layout.gw
	var gh: int = layout.gh
	# 边缘密林：格子挡路，树按行合成节点画
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed + 7
	var rows := {}
	for i in gw * gh:
		if layout.cells[i] != MapGen.C_WOODS:
			continue
		var c := Vector2i(i % gw, i / gw)
		terrain.set_cell(c, Terrain.T.WOODS)
		if not rows.has(c.y):
			rows[c.y] = []
		rows[c.y].append({"x": (c.x + 0.5) * Terrain.CELL + rng.randf_range(-6.0, 6.0), "dy": rng.randf_range(-4.0, 4.0),
			"v": rng.randi_range(1, 3), "flip": rng.randf() < 0.5, "h": rng.randf_range(62.0, 74.0),
			"mod": Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.12))})
	for y in rows:
		var r := WoodsRow.new()
		r.position = Vector2(0, (y + 0.5) * Terrain.CELL)
		r.trees = rows[y]
		add_child(r)
	base = _build_mgr.add_building("base", layout.base, 0)
	hives = []
	for hp in layout.hives:
		hives.append(_build_mgr.add_building("hive", hp, 1))
	hive = hives[0]
	roads = layout.roads
	# 能砍的树（每棵 100 木）和矿堆（每堆 250 矿），都占格挡路
	for p in layout.trees:
		var n := _add_res("wood", p, true)
		n.amount = 100.0
		n.tree_h = rng.randf_range(58.0, 70.0)
	for p in layout.ore:
		_add_res("ore", p, true)
	_build_minimap_img()

## 小地图底图：每格一个像素
func _build_minimap_img() -> void:
	var gw: int = layout.gw
	var gh: int = layout.gh
	minimap_img = Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	for i in gw * gh:
		minimap_img.set_pixel(i % gw, i / gw, MINI_COLORS[layout.cells[i]])
	for rd in roads:
		for p in rd:
			minimap_img.set_pixel(clampi(int(p.x / Terrain.CELL), 0, gw - 1), clampi(int(p.y / Terrain.CELL), 0, gh - 1), MINI_ROAD)
	minimap_tex = ImageTexture.create_from_image(minimap_img)

const MINI_COLORS := [Color(0.49, 0.65, 0.16), Color(0.2, 0.42, 0.12), Color(0.12, 0.3, 0.08), Color(0.95, 0.78, 0.25)]
const MINI_ROAD := Color(0.88, 0.72, 0.35)

## 树砍光 / 矿采空：小地图上那格变回草地
func on_cell_cleared(c: Vector2i) -> void:
	if minimap_img != null and c.x >= 0 and c.y >= 0 and c.x < minimap_img.get_width() and c.y < minimap_img.get_height():
		minimap_img.set_pixel(c.x, c.y, MINI_COLORS[0])
		minimap_tex.update(minimap_img)

func add_stump(pos: Vector2) -> void:
	if decor_layer != null:
		decor_layer.add_item("decor/stump", pos, randf() < 0.5)

## 某个巢穴的行军路线
func road_for(h: Node2D) -> Array:
	var i := hives.find(h)
	return roads[i] if i >= 0 and i < roads.size() else road()

## 点到树林/矿里（不能站人）→ 最近的空地。经典图看手绘地图的树林，随机图看地形格子
func open_point(p: Vector2) -> Vector2:
	if classic:
		return Art.open_point(p)
	return terrain.open_point(p)

## 这里能不能盖房：脚下一圈（半径约 r）有树/矿/密林就不行
func area_blocked(p: Vector2, r: float) -> bool:
	if classic:
		return Art.forest_at(p) or Art.forest_at(p + Vector2(0, 26))
	for dy in [-r, 0.0, r]:
		for dx in [-r, 0.0, r]:
			if terrain.solid_at(p + Vector2(dx, dy)):
				return true
	return false

func _add_res(kind: String, pos: Vector2, solid := false) -> ResNode:
	var n := ResNode.new()
	n.kind = kind
	n.position = pos
	n.solid = solid
	add_child(n)
	return n

## 铺设地形：当前是纯平原（森林/河/悬崖暂时撤掉，等方向定完再铺）
## 寻路、移速/射程修正都长在 Terrain 上，重新 paint 就能用回来
func _build_terrain() -> void:
	pass

func _spawn_engineer(pos: Vector2) -> Engineer:
	var e := Engineer.new()
	e.position = pos
	add_child(e)
	e.died.connect(_on_engineer_died)
	return e

## ================================ 每帧 ================================
func _process(delta: float) -> void:
	selected = selected.filter(func(u): return is_instance_valid(u))
	barracks_list = barracks_list.filter(func(b): return is_instance_valid(b))
	warehouses_list = warehouses_list.filter(func(b): return is_instance_valid(b))
	if inspected != null and not is_instance_valid(inspected):
		inspected = null
	# 鼠标在 HUD 上松开时 _unhandled_input 收不到抬起事件：这里兜底收尾拖框
	if _dragging and DisplayServer.get_name() != "headless" and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_drag(get_viewport().get_mouse_position())
	if game_state == "play":
		game_time += delta
		_wave_mgr.update(delta)
		_update_respawn(delta)
		_check_end()
	_update_labels()
	_update_panel()
	_update_camera(delta)
	hud.refresh()
	if _hud_msg_t > 0.0:
		_hud_msg_t -= delta
		_hud_msg_label.visible = _hud_msg_t > 0.0
	queue_redraw()

## 镜头：鼠标贴边滚屏 + 滚轮缩放（缩放以屏幕中心为锚）
func _update_camera(delta: float) -> void:
	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var dir := Vector2.ZERO
	if m.x < CAM_EDGE:
		dir.x -= 1.0
	elif m.x > vp.x - CAM_EDGE:
		dir.x += 1.0
	if m.y < CAM_EDGE:
		dir.y -= 1.0
	elif m.y > vp.y - CAM_EDGE:
		dir.y += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if not get_window().has_focus() or DisplayServer.get_name() == "headless":
		dir = Vector2.ZERO
	if dir != Vector2.ZERO:
		cam.position += dir.normalized() * CAM_SPEED * 60.0 * delta / cam.zoom.x
	_clamp_camera()

## 镜头限制在地图内；上下多留出顶栏/底栏的高度（地图边沿能露到 HUD 外面）
func _clamp_camera() -> void:
	var vp := get_viewport_rect().size
	var half := vp / cam.zoom / 2.0
	var top := -hud_top_h() / cam.zoom.y
	var bottom := H + hud_bottom_h() / cam.zoom.y
	# 视野比地图还大时（缩小过头），镜头锁死在地图中心，避免 clamp 上下限颠倒
	if half.x * 2.0 >= W:
		cam.position.x = W / 2.0
	else:
		cam.position.x = clampf(cam.position.x, half.x, W - half.x)
	if half.y * 2.0 >= bottom - top:
		cam.position.y = (top + bottom) / 2.0
	else:
		cam.position.y = clampf(cam.position.y, top + half.y, bottom - half.y)

func hud_bottom_h() -> float:
	return hud.bottom_h() if hud != null and hud.has_method("bottom_h") else 0.0

func hud_top_h() -> float:
	return hud.top_h() if hud != null and hud.has_method("top_h") else 0.0

## 工程师免费复活：死了就排队，到点在基地重生
func _on_engineer_died(u) -> void:
	if u is Engineer and is_instance_valid(u):
		u._drop_site()    # 死在施工中也得把工地放出来，复活后自动接手
	respawn_timers.append(ENGINEER_RESPAWN)
	_hud_msg("英雄工程师阵亡！%d 秒后在基地复活" % int(ENGINEER_RESPAWN))

func _update_respawn(delta: float) -> void:
	if respawn_timers.is_empty():
		return
	for i in respawn_timers.size():
		respawn_timers[i] -= delta
	while respawn_timers.size() > 0 and respawn_timers.min() <= 0.0:
		respawn_timers.erase(respawn_timers.min())
		if is_instance_valid(base):
			_spawn_engineer(base.position + Vector2(90.0, 40.0))
			_hud_msg("工程师已复活")

func _check_end() -> void:
	if not is_instance_valid(base):
		_end("lose", "基地被拆了")
	elif not hives.any(func(h): return is_instance_valid(h)):
		_end("win", "巢穴被拆了！" if hives.size() <= 1 else "所有巢穴都被拆了！")

func _end(result: String, msg: String) -> void:
	if game_state != "play":
		return
	game_state = result
	overlay.visible = true
	overlay_label.text = ("胜利！ " if result == "win" else "失败… ") + msg

## ================================ HUD 提示 ================================
## 所有"为什么不行"都在屏幕上说清楚，绝不静默失败
func _hud_msg(text: String) -> void:
	_hud_msg_label.text = text
	_hud_msg_t = 3.0
	_hud_msg_label.visible = true

## ================================ 输入（帝国时代式） ================================
## 左键：点选 / 拖框；Shift+左键 加减选；双击或 Ctrl+左键 = 选屏幕内同类
## 右键：智能指令（移动 / 采集 / 攻击 / 交货）；选中基地/兵营右键 = 集结点；Shift+右键 = 排路点
## 命令卡热键按 5×3 网格：QWERT / ASDFG / ZXCVB，和底栏按钮位置一一对应
## H 基地 · . 闲置农民 · , 闲置军队 · 空格 = 镜头回到选中 · Del 删除 · Esc 取消/取消选中
## Ctrl+数字 编队 · 数字 选队（连按两下跳过去）· Shift+数字 把该队加进当前选择 · 中键拖动平移
const GRID_KEYS := ["Q", "W", "E", "R", "T", "A", "S", "D", "F", "G", "Z", "X", "C", "V", "B"]
var _target_mode := ""            # "attack" / "patrol"：按了热键，等左/右键点目的地
## 兼容老代码 / 机器人脚本：A 移动待命 = 目标模式是 attack
var _a_move_next: bool:
	get:
		return _target_mode == "attack"
	set(v):
		_target_mode = "attack" if v else ""
var _mid_drag := false
var _drag_shift := false
var _drag_ctrl := false
var _drag_double := false
var _last_group := -1
var _last_group_t := 0
var _idle_i := 0
var game_time := 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_drag = event.pressed    # 中键按住拖动 = 平移镜头
			return
	if event is InputEventMouseMotion and _mid_drag:
		cam.position -= event.relative / cam.zoom.x
		_clamp_camera()
		return
	if game_state != "play":
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _placing_kind != "":
					# 0=成功落工地 / 2=买不起 → 结束放置模式；1=位置不合适 → 可以再点
					var r := _build_mgr.try_place(_placing_kind, _to_world(event.position), _build_eng)
					if r != 1:
						_placing_kind = ""
					queue_redraw()
				elif _target_mode != "" and _has_units_selected():
					# 按了 A / F 再左键 = 往那里 A 移动 / 巡逻
					_command_at(_to_world(event.position), event.shift_pressed)
				else:
					_target_mode = ""
					_drag_start = _to_world(event.position)
					_dragging = true
					_drag_shift = event.shift_pressed
					_drag_ctrl = event.ctrl_pressed or event.meta_pressed
					_drag_double = event.double_click
					queue_redraw()
			elif _dragging:
				_finish_drag(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _placing_kind != "":
				_hud_msg("已取消放置" + _place_name(_placing_kind))
				_placing_kind = ""
				queue_redraw()
			elif _has_units_selected():
				_command_at(_to_world(event.position), event.shift_pressed)
			else:
				var b := _selected_building()
				if b != null and b.trains():
					set_rally(b, _pick_at(_to_world(event.position), true))
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event)

## 松开左键：拖得够远 = 框选，否则点选（Shift 加减选、双击/Ctrl 选同类）
func _finish_drag(screen: Vector2) -> void:
	_dragging = false
	var rect := Rect2(_drag_start, _to_world(screen) - _drag_start).abs()
	if rect.size.length() > 10.0 / cam.zoom.x:    # 拖框阈值也按缩放换算
		_box_select(rect, _drag_shift)
	else:
		var p := _pick_at(_to_world(screen))
		if _drag_double or _drag_ctrl:
			_select_same_type(p)
		elif _drag_shift:
			_toggle_select(p)
		else:
			_point_select(p)
	queue_redraw()

func _on_key(event: InputEventKey) -> void:
	var k := event.keycode
	if k == KEY_ESCAPE:
		# Esc：先取消放置 / 目标模式，再关帮助，最后取消选中
		if _placing_kind != "":
			_hud_msg("已取消放置" + _place_name(_placing_kind))
			_placing_kind = ""
			queue_redraw()
		elif _target_mode != "":
			_hud_msg("已取消" + ("A 移动" if _target_mode == "attack" else "巡逻"))
			_target_mode = ""
		elif hud.help_visible():
			hud.toggle_help()
		else:
			_deselect_all()
	elif k == KEY_F1:
		hud.toggle_help()
	elif k == KEY_F2:
		toggle_panel()
	elif k == KEY_DELETE:
		_delete_selected()
	elif k == KEY_H:
		select_base()
	elif k == KEY_N:
		call_wave_early()
	elif k == KEY_PERIOD:
		select_next_idle(true)
	elif k == KEY_COMMA:
		select_next_idle(false)
	elif k == KEY_SPACE:
		_center_on_selection()
	elif k >= KEY_1 and k <= KEY_9:
		# 编队：Ctrl+数字 存队，数字 选队（连按两下镜头跳过去），Shift+数字 并进当前选择
		var idx := int(k) - int(KEY_1)
		if event.ctrl_pressed or event.meta_pressed:
			_save_control_group(idx)
		elif event.shift_pressed:
			_recall_control_group(idx, true)
		else:
			var now := Time.get_ticks_msec()
			_recall_control_group(idx)
			if _last_group == idx and now - _last_group_t < 450:
				_center_on_selection()
			_last_group = idx
			_last_group_t = now
	elif not run_hotkey(OS.get_keycode_string(k)) and k == KEY_C:
		toggle_panel()

func toggle_panel() -> void:
	_panel_on = not _panel_on
	_update_panel()

func _has_units_selected() -> bool:
	return selected.any(func(u): return u is Unit and is_instance_valid(u))

func _sel_units() -> Array:
	return selected.filter(func(u): return u is Unit and is_instance_valid(u))

## 左/右键在世界里点了一下：按当前模式下指令
func _command_at(world: Vector2, shift := false) -> void:
	var pos := _pick_at(world, true)
	# 选着农民点到门口守线的工人：算点他的加工厂（工位就在门口，人正好挡着房子，
	# 以前点人身上 = 走到那人脚下，招工/送料全落空）
	if _thing_at(pos) == null and _friendly_depot_at(pos) == null and not _selected_workers().is_empty():
		var ob := _operator_building_at(world, pos)
		if ob != null:
			pos = ob.position
	var t := _thing_at(pos)
	var mode := _target_mode
	var attack: bool = mode != "" or ((t is Unit or t is Building) and t.team == 1)
	if mode == "patrol":
		_issue_patrol(pos)
	elif shift and t == null:
		_issue_queued(pos, mode == "attack")
	else:
		_issue_command(pos)
	_target_mode = ""
	_markers.append({"pos": pos, "t0": Time.get_ticks_msec(), "attack": attack})

## Shift+右键：路点排到队尾（闲着的马上出发）
func _issue_queued(pos: Vector2, attack: bool) -> void:
	pos = open_point(pos)
	var i := 0
	for u in _sel_units():
		u.queue_move(_spread_pos(i, pos), attack and (u is Soldier or u is Engineer))
		i += 1

## F 巡逻：士兵在当前位置和目标点之间来回 A 移动；工程师就 A 移动过去，农民走过去
func _issue_patrol(pos: Vector2) -> void:
	pos = open_point(pos)
	var i := 0
	for u in _sel_units():
		u.cancel_orders()
		var p := _spread_pos(i, pos)
		if u is Soldier:
			u.command_patrol(p)
		elif u is Engineer:
			u.command_attack_move(p)
		else:
			u.command_move(p)
		i += 1

func _deselect_all() -> void:
	_clear_inspect()
	for s in selected:
		if is_instance_valid(s):
			s.selected = false
	selected.clear()

## 换一批选中
func _set_selection(list: Array) -> void:
	_deselect_all()
	for u in list:
		if is_instance_valid(u) and not selected.has(u):
			u.selected = true
			selected.append(u)

## 点中的己方单位（点选/加减选共用的命中规则）
func _unit_at(pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d := 18.0
	for u in get_tree().get_nodes_in_group("player_units"):
		var d := pos.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
	return best

## Shift+左键：把点中的单位加进 / 移出当前选择（和建筑混选时只留单位，帝国式）
func _toggle_select(pos: Vector2) -> void:
	var u := _unit_at(pos)
	if u == null:
		return
	_clear_inspect()
	for s in selected.duplicate():
		if s is Building:
			s.selected = false
			selected.erase(s)
	if selected.has(u):
		u.selected = false
		selected.erase(u)
	else:
		u.selected = true
		selected.append(u)

## 单位类型（双击选同类用）：worker / swordsman / archer / engineer；建筑 = b_兵种
static func type_key(n: Node) -> String:
	if n is Unit:
		return n._art_key()
	if n is Building:
		return "b_" + n.kind
	return ""

## 屏幕内（顶栏和底栏之间）的世界矩形
func view_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var a := _to_world(Vector2(0, hud_top_h()))
	var b := _to_world(Vector2(vp.x, vp.y - hud_bottom_h()))
	return Rect2(a, b - a)

## 双击 / Ctrl+左键：选中屏幕上所有同类单位（点在建筑上 = 同类建筑）
func _select_same_type(pos: Vector2) -> void:
	var u: Node2D = _unit_at(pos)
	if u == null:
		for b in get_tree().get_nodes_in_group("buildings"):
			if b.team == 0 and pos.distance_to(b.position) < b.size * 0.6:
				u = b
				break
	if u == null:
		_point_select(pos)
		return
	select_type(type_key(u), view_rect())

func select_type(key: String, rect := Rect2()) -> void:
	var list: Array = []
	var group := "buildings" if key.begins_with("b_") else "player_units"
	for n in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(n) or n.team != 0 or type_key(n) != key:
			continue
		if rect.has_area() and not rect.has_point(n.position):
			continue
		list.append(n)
	_set_selection(list)

## H：选中基地并把镜头拉过去
func select_base() -> void:
	if not is_instance_valid(base):
		return
	_set_selection([base])
	center_on(base.position)

## . 闲置农民 / , 闲置军队：轮流选中下一个并跳镜头
func idle_units(workers: bool) -> Array:
	var r: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if workers and u is Worker and u.is_idle():
			r.append(u)
		elif not workers and u is Soldier and u.is_idle():
			r.append(u)
	r.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	return r

func select_next_idle(workers: bool) -> void:
	var list := idle_units(workers)
	if list.is_empty():
		_hud_msg("没有闲着的" + ("农民" if workers else "士兵"))
		return
	_idle_i = (_idle_i + 1) % list.size()
	_set_selection([list[_idle_i]])
	center_on(list[_idle_i].position)

## 镜头对准某点（底栏挡住的部分不算，点落在可视区正中）
func center_on(p: Vector2) -> void:
	cam.position = p + Vector2(0, (hud_bottom_h() - hud_top_h()) * 0.5 / cam.zoom.y)
	_clamp_camera()

func _center_on_selection() -> void:
	var list := selected.filter(func(u): return is_instance_valid(u))
	if list.is_empty():
		return
	var c := Vector2.ZERO
	for u in list:
		c += u.position
	center_on(c / list.size())

## Del：删除选中的己方单位/建筑（英雄工程师和基地不能删）；排队的训练全额退
func _delete_selected() -> void:
	var n := 0
	for u in selected.duplicate():
		if not is_instance_valid(u) or u.team != 0:
			continue
		if u is Engineer or (u is Building and u.kind == "base"):
			continue
		if u is Building:
			while not u.queue.is_empty():
				cancel_train(u, u.queue.size() - 1)
			u.take_damage(u.hp + 1.0)
		else:
			u.kill()
		n += 1
	if n > 0:
		_hud_msg("已删除 %d 个" % n)
	elif not selected.is_empty():
		_hud_msg("英雄工程师和基地不能删除")

## ---------- 命令卡（底栏 5×3 按钮 + 热键共用一张表）----------
## 每项：{id, slot(0-14 → 热键 GRID_KEYS[slot]), key, title, icon, cost, tip}
func commands() -> Array:
	if game_state != "play":
		return []
	var out: Array = []
	var bs: Array = selected.filter(func(u): return u is Building and is_instance_valid(u) and u.team == 0)
	if not bs.is_empty() and not _has_units_selected():
		var b: Building = bs[0]
		match b.kind:
			"base":
				out.append(_cmd_entry("worker", 0, "农民", "worker", Economy.COST_WORKER, "采矿、伐木、搬运（训练 %d 秒）" % int(TRAIN.worker.time)))
			"barracks":
				out.append(_cmd_entry("sword", 0, "剑士", "sword", Economy.COST_SWORD, "近战前排，护甲高（训练 %d 秒）" % int(TRAIN.sword.time)))
				out.append(_cmd_entry("archer", 1, "弓手", "archer", Economy.COST_ARCHER, "远程输出，躲在剑士后面（训练 %d 秒）" % int(TRAIN.archer.time)))
		if b.is_processor():
			var r: Dictionary = b.recipe()
			var raw: String = Economy.KIND_NAME[r.in]
			out.append(_cmd_entry("hire", 0, "招工", "workers", {},
				"叫最近的闲农民来%s（最多 %d 人）。一个人要守线又要搬货，干一阵停一阵；两个人轮班才连续出货" % [r.verb, Building.OP_MAX]))
			out.append(_cmd_entry("fire", 1, "放人", "worker", {}, "让最后来的工人离岗，回去采%s" % raw))
			if b.self_fetch:
				out.append(_cmd_entry("fetch_off", 2, "自取:开", r.in, {},
					"现在：料场见底时工人自己去仓库扛%s（仓库至少留 %d）。点一下关掉，只用送货农民送来的料" % [raw, int(Building.FETCH_RESERVE)]))
			else:
				out.append(_cmd_entry("fetch_on", 2, "自取:关", r.in, {},
					"现在：只用送货农民送来的料，仓库的%s一点不动。点一下打开（仓库留底 %d）" % [raw, int(Building.FETCH_RESERVE)]))
		if b.can_upgrade():
			var t2: Dictionary = Building.TOWER_LV[2]
			out.append(_cmd_entry("upgrade", 0, "升级", "tower2", Economy.COST_TOWER_UP,
				"升二级箭塔：2 名弓手、射程 %d、每箭 %d（护甲高的岩壳也扛不住），血 +%d" % [int(t2.range), int(t2.dmg), int(Building.TOWER_UP_HP)]))
		if b.kind != "base":
			out.append(_cmd_entry("delete", 14, "删除", "delete", {}, "拆掉这座建筑（不退资源）", "Del"))
		return out
	var us := _sel_units()
	if us.is_empty():
		return out
	var all_workers := us.all(func(u): return u is Worker)
	if us.size() == 1 and us[0] is Engineer:
		out.append(_cmd_entry("warehouse", 0, "仓库", "warehouse", Economy.COST_WAREHOUSE, "就近交货点，缩短农民跑路"))
		out.append(_cmd_entry("smelter", 1, "熔炉", "smelter", Economy.COST_SMELTER, "矿石 → 铁锭（剑士要用）。要农民进厂守炉：一炉 5 矿烧 5 秒"))
		out.append(_cmd_entry("workshop", 2, "木工台", "workshop", Economy.COST_WORKSHOP, "木材 → 木板（弓手要用）。要农民进厂锯板：一批 5 木锯 4 秒"))
		out.append(_cmd_entry("barracks", 3, "兵营", "barracks", Economy.COST_BARRACKS, "训练剑士和弓手"))
		var t1: Dictionary = Building.TOWER_LV[1]
		out.append(_cmd_entry("tower", 4, "箭塔", "tower", Economy.COST_TOWER,
			"盖在土路边：塔上弓手自动射路过的怪（射程 %d、每箭 %d），先打跑在最前面的。普通 Goo 和窜窜打不着塔，岩壳会来拆" % [int(t1.range), int(t1.dmg)]))
		out.append(_cmd_entry("attack", 5, "攻击移动", "attack", {}, "走到目的地，路上遇敌就打"))
		out.append(_cmd_entry("stop", 6, "停止", "stop", {}, "扔下手上的事，原地站着"))
		return out
	if all_workers:
		out.append(_cmd_entry("mine", 0, "采矿", "ore", {}, "去最近的矿堆采矿"))
		out.append(_cmd_entry("chop", 1, "伐木", "wood", {}, "去最近的树林伐木"))
		out.append(_cmd_entry("auto_deliver", 2, "自动交货", "base", {}, "货送最近的基地/仓库（取消指定的熔炉/木工台）"))
		out.append(_cmd_entry("stop", 6, "停止", "stop", {}, "扔下手上的事，原地站着"))
	else:
		out.append(_cmd_entry("attack", 5, "攻击移动", "attack", {}, "走到目的地，路上遇敌就打"))
		out.append(_cmd_entry("stop", 6, "停止", "stop", {}, "扔下手上的事，原地站着"))
		out.append(_cmd_entry("hold", 7, "驻守", "hold", {}, "原地不动：敌人进射程就打，不追"))
		out.append(_cmd_entry("patrol", 8, "巡逻", "patrol", {}, "在这里和目标点之间来回走，遇敌就打"))
	if not us.any(func(u): return u is Engineer):
		out.append(_cmd_entry("delete", 14, "删除", "delete", {}, "删除选中的单位", "Del"))
	return out

func _cmd_entry(id: String, slot: int, title: String, icon_key: String, cost: Dictionary, tip: String, key := "") -> Dictionary:
	return {"id": id, "slot": slot, "key": key if key != "" else GRID_KEYS[slot], "title": title,
		"icon": icon_key, "cost": cost, "tip": tip}

## 热键 → 命令卡上同位置的按钮
func run_hotkey(letter: String) -> bool:
	for c in commands():
		if c.key == letter:
			run_command(c.id)
			return true
	return false

func run_command(id: String) -> void:
	if game_state != "play":
		return
	match id:
		"worker":
			_on_worker_pressed()
		"sword":
			_on_sword_pressed()
		"archer":
			_on_archer_pressed()
		"warehouse", "smelter", "workshop", "barracks", "tower":
			_start_placing(id)
		"upgrade":
			_upgrade_selected_tower()
		"call_wave":
			call_wave_early()
		"attack":
			_target_mode = "attack"
			_hud_msg("A 移动：点目的地（左右键都行），路上遇到敌人就开打 · Esc 取消")
		"patrol":
			_target_mode = "patrol"
			_hud_msg("巡逻：点另一头（左右键都行），在两点之间来回 · Esc 取消")
		"stop":
			for u in _sel_units():
				u.command_stop()
		"hold":
			for u in _sel_units():
				if u is Soldier:
					u.command_hold()
				else:
					u.command_stop()
			_hud_msg("原地驻守：只打进射程的敌人，不追")
		"mine", "chop":
			var kind := "ore" if id == "mine" else "wood"
			var n := 0
			for w in _selected_workers():
				w.cancel_orders()
				var node: ResNode = w._nearest_node(kind)
				if node != null:
					w.command_gather(node)
					n += 1
			if n == 0:
				_hud_msg("附近找不到能采的" + ("矿" if kind == "ore" else "树"))
		"auto_deliver":
			for w in _selected_workers():
				w.set_deliver_to(null)
			_hud_msg("交货改回自动：送最近的基地/仓库")
		"hire", "fire", "fetch_on", "fetch_off":
			var b := _selected_building()
			if b == null or not b.is_processor():
				return
			if id == "hire":
				hire_operator(b)
			elif id == "fire":
				fire_operator(b)
			else:
				b.self_fetch = id == "fetch_on"
				var raw: String = Economy.KIND_NAME[b.recipe().in]
				_hud_msg("%s自取已%s" % [b.display_name, ("打开：料不够时工人去仓库扛%s（留底 %d）" % [raw, int(Building.FETCH_RESERVE)]) if b.self_fetch else "关掉：只用送货农民送来的料"])
		"delete":
			_delete_selected()

## 屏幕坐标 → 世界坐标（考虑镜头缩放和位移）
func _to_world(screen: Vector2) -> Vector2:
	return cam.get_canvas_transform().affine_inverse() * screen

## 点中贴图：单位/建筑的贴图比碰撞圈高得多，点在头顶、屋顶上也要算点中。
## 命中就返回它的逻辑坐标（交给原来的点选/指令逻辑），否则原样返回
func _pick_at(world: Vector2, include_res := false) -> Vector2:
	if not Art.enabled:
		return world
	var best = null
	var best_y := -INF
	var tree := get_tree()
	for u in tree.get_nodes_in_group("units"):
		var h: float = Unit.ART_H.get(u._art_key(), 0.0)
		if h <= 0.0:
			continue
		var d: Vector2 = world - u.position
		if absf(d.x) < u.radius * 1.4 and d.y > -h + u.radius * 0.4 and d.y < u.radius * 0.9 and u.position.y > best_y:
			best = u
			best_y = u.position.y
	for g in (["buildings", "sites", "res_nodes"] if include_res else ["buildings"]):
		for b in tree.get_nodes_in_group(g):
			var d: Vector2 = world - b.position
			var hit := false
			if b is ResNode:
				hit = absf(d.x) < 22.0 and d.y > -56.0 and d.y < 14.0
			else:
				var top: float = b.size * (2.2 if b.kind == "tower" else 1.5)    # 箭塔又高又瘦
				hit = absf(d.x) < b.size * 0.8 and d.y > -top and d.y < b.size * 0.45
			if hit and b.position.y > best_y:
				best = b
				best_y = b.position.y
	return best.position if best != null else world

func _zoom_camera(factor: float) -> void:

	var vp := get_viewport_rect().size
	var m := get_viewport().get_mouse_position()
	var world := cam.get_global_mouse_position()
	cam.zoom *= factor
	cam.zoom.x = clampf(cam.zoom.x, CAM_MIN_ZOOM, CAM_MAX_ZOOM)
	cam.zoom.y = cam.zoom.x
	# 缩放后把鼠标指向的世界点拉回原位（朝鼠标缩放）
	cam.position += world - cam.get_global_mouse_position()

func _clear_inspect() -> void:
	if inspected != null and is_instance_valid(inspected):
		inspected.selected = false
	inspected = null

## 信息栏/头像用的展示列表：查看敌人时就是它自己，否则是选中的己方
func _display_list() -> Array:
	if inspected != null and is_instance_valid(inspected):
		return [inspected]
	return selected.filter(func(u): return is_instance_valid(u))

func _point_select(pos: Vector2) -> void:
	_deselect_all()
	var best := _unit_at(pos)
	if best:
		best.selected = true
		selected.append(best)
		return
	# 没点到单位 → 试试点玩家建筑（基地/兵营，出农民出兵用）
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team != 0:
			continue
		if pos.distance_to(b.position) < b.size * 0.6:
			b.selected = true
			selected.append(b)
			return
	# 也不是建筑 → 看是不是点了敌人（只读属性，不能下指令）
	for e in get_tree().get_nodes_in_group("enemies"):
		if pos.distance_to(e.position) < 18.0:
			inspected = e
			e.selected = true
			return

## 框选：只框单位；Shift 拖框 = 加进当前选择（建筑先剔掉，帝国式）
func _box_select(rect: Rect2, add := false) -> void:
	if add:
		_clear_inspect()
		for s in selected.duplicate():
			if s is Building:
				s.selected = false
				selected.erase(s)
	else:
		_deselect_all()
	for u in get_tree().get_nodes_in_group("player_units"):
		if rect.has_point(u.position) and not selected.has(u):
			u.selected = true
			selected.append(u)

## 右键：看点的什么，给选中单位下发对应指令
func _issue_command(pos: Vector2) -> void:
	if selected.is_empty():
		return
	var target := _thing_at(pos)
	if target == null:
		pos = open_point(pos)    # 点进树林里 = 走到林子边上
	var depot := _friendly_depot_at(pos)     # 选农民右键己方收货建筑 = 指派交货点
	# 右键加工厂：正在采对口原料的 = 改送料（送货工）；其余的（闲着/采别的/别处的工人）= 进厂干活
	var proc: Building = depot if depot != null and depot.is_processor() else null
	var n_op := 0
	var n_feed := 0
	var n_full := 0
	var move_idx := 0    # 纯移动的单位排队领环形散点，别全挤向同一个坐标
	for u in selected:
		if not (u is Unit) or not is_instance_valid(u):
			continue    # 选中的是建筑（基地/兵营）：建筑不会走路，跳过
		u.cancel_orders()    # 新指令覆盖排队路点 / 巡逻 / 原地坚守
		if target is ResNode and u is Worker:
			u.command_gather(target)
		elif proc != null and u is Worker and not u.feeds(proc.recipe().in):
			if u.command_operate(proc):
				n_op += 1
			else:
				n_full += 1    # 人满了：走到门口等着，别傻站原地
				u.command_move(_spread_pos(move_idx, proc.position + Vector2(0, proc.size * 1.1)))
				move_idx += 1
		elif depot != null and u is Worker:
			u.set_deliver_to(depot)
			n_feed += 1
		elif target is ResNode:
			# 士兵/工程师点资源点 = 走过去，不是攻击指令
			u.command_move(_spread_pos(move_idx, pos))
			move_idx += 1
		elif target != null and target.team == 1 and (u is Soldier or u is Engineer):
			# 攻击指令有距离门槛：远处的怪转成 A 移动（路上遇敌就打），别追杀到天涯海角。
			# 以前转成普通移动：走到巢穴脚下就站着不打，一路挨打也不还手。
			# 建筑不会跑，点名多远都直接打
			var cmd_range := 70.0 if u is Engineer else 250.0
			if target is Building or u.position.distance_to(target.position) <= cmd_range:
				u.command_attack(target)
			else:
				u.command_attack_move(_spread_pos(move_idx, pos))
				move_idx += 1
		elif _a_move_next and (u is Soldier or u is Engineer):
			# A 移动：走到目的地，路上自动索敌（战斗单位专属）
			u.command_attack_move(_spread_pos(move_idx, pos))
			move_idx += 1
		else:
			u.command_move(_spread_pos(move_idx, pos))
			move_idx += 1
	if _a_move_next:
		_a_move_next = false
	# 指派必须看得见反馈：说清楚这批货进去以后变成什么
	if proc != null:
		var parts: Array = []
		if n_op > 0:
			parts.append("%d 个农民进%s干活（工人 %d/%d）" % [n_op, proc.display_name, proc.op_count(), Building.OP_MAX])
		if n_full > 0:
			parts.append("%s人满了（%d/%d），%d 个没排上" % [proc.display_name, Building.OP_MAX, Building.OP_MAX, n_full])
		if n_feed > 0:
			parts.append("%d 个农民改送%s到%s料场" % [n_feed, Economy.KIND_NAME[proc.recipe().in], proc.display_name])
		if not parts.is_empty():
			_hud_msg("；".join(parts))
	elif depot != null:
		var nw := _selected_workers().size()
		if nw > 0:
			_hud_msg("%d 个农民改送%s：%s" % [nw, depot.display_name, _depot_result(depot)])

## 送进这个建筑变成什么账（给玩家看，别让人盲猜）
func _depot_result(b: Building) -> String:
	match b.kind:
		"smelter":
			return "矿石卸进料场，等工人炼成铁锭（木材照样存原料）"
		"workshop":
			return "木材卸进料场，等工人锯成木板（矿石照样存原料）"
		"warehouse":
			return "原样入库，攒着造农民"
	return "原样入库"

## ---------- 加工线：招工 / 放人 ----------
## 招工：先挑最近的闲农民，没有闲的就从采集的里调最近的（加工线上的工人不动）
func hire_operator(b: Building) -> Worker:
	if not b.has_room():
		_hud_msg("%s人满了（%d/%d）" % [b.display_name, Building.OP_MAX, Building.OP_MAX])
		return null
	var best: Worker = null
	var best_d := INF
	for w in _player_workers():
		if w.state == Worker.State.OPERATE:
			continue
		# 站着没事的 > 走在路上的闲人（玩家刚派走的，别抢）> 采集中的；给这条线送料的最后动
		var d: float = w.position.distance_to(b.position)
		if w.state != Worker.State.IDLE:
			d += 5000.0
		elif w.moving:
			d += 1500.0
		if w.deliver_to == b:
			d += 2000.0
		if d < best_d:
			best_d = d
			best = w
	if best == null:
		_hud_msg("没有能调的农民了：先在基地多造几个")
		return null
	best.cancel_orders()
	best.command_operate(b)
	_hud_msg("%s招到 1 个工人（%d/%d）" % [b.display_name, b.op_count(), Building.OP_MAX])
	return best

## 放人：最后来的工人离岗，回去采这条线要的原料（正好给自己送料）
func fire_operator(b: Building) -> Worker:
	if b.op_count() == 0:
		_hud_msg("%s没有工人" % b.display_name)
		return null
	var w: Worker = b.operators.back()
	w.cancel_orders()
	w.command_stop()
	w.auto_assign(b.recipe().in)
	_hud_msg("%s放走 1 个工人，回去采%s（剩 %d/%d）" % [b.display_name, Economy.KIND_NAME[b.recipe().in], b.op_count(), Building.OP_MAX])
	return w

## ---------- 箭塔升级 / 提前叫波 ----------
func _upgrade_selected_tower() -> void:
	var list: Array = selected.filter(func(b): return b is Building and is_instance_valid(b) and b.can_upgrade())
	if list.is_empty():
		_hud_msg("先选中一座一级箭塔")
		return
	for b in list:    # 框了好几座就挨个升，钱不够为止
		if not upgrade_tower(b):
			break

func upgrade_tower(b: Building) -> bool:
	if b == null or not b.can_upgrade():
		return false
	if not economy.can_afford(Economy.COST_TOWER_UP):
		_hud_msg(economy.short_msg(Economy.COST_TOWER_UP) + "（木板靠木工台、铁锭靠熔炉）")
		return false
	economy.spend(Economy.COST_TOWER_UP)
	b.upgrade()
	_hud_msg("箭塔升到二级：2 名弓手，射程 %d、每箭 %d" % [int(Building.TOWER_LV[2].range), int(Building.TOWER_LV[2].dmg)])
	return true

## N / 波次旁的按钮：倒计时没走完就放下一波，剩几秒给多少矿和木
func call_wave_early() -> void:
	if game_state != "play":
		return
	if not _wave_mgr.can_call_early():
		_hud_msg("最后一波已经出了" if _wave_mgr.wave >= WaveManager.MAX_WAVES else "下一波马上就到")
		return
	var n := _wave_mgr.call_early()
	_hud_msg("提前叫来第 %d 波（%s）：奖励 %d 矿 + %d 木" % [_wave_mgr.wave, WaveManager.wave_text(_wave_mgr.wave), n, n])

## ---------- 编队：Ctrl+数字 存，数字 召回 ----------
func _save_control_group(idx: int) -> void:
	control_groups.resize(max(control_groups.size(), idx + 1))
	control_groups[idx] = selected.filter(func(u): return is_instance_valid(u)).duplicate()
	_hud_msg("编队 %d 已存（%d 个单位）" % [idx + 1, control_groups[idx].size()])

func _recall_control_group(idx: int, add := false) -> void:
	if not add:
		_deselect_all()
	else:
		_clear_inspect()
	if idx >= control_groups.size() or control_groups[idx] == null:
		return
	var grp: Array = control_groups[idx]
	var alive: Array = []
	for u in grp:
		if is_instance_valid(u):
			alive.append(u)
			if not selected.has(u):
				u.selected = true
				selected.append(u)
	control_groups[idx] = alive

## 第 i 个移动单位的目标点：中心 + 环形散开（每圈 8 个，圈距 26px）
func _spread_pos(i: int, pos: Vector2) -> Vector2:
	if i == 0:
		return pos
	var ring := 1
	var k := i
	while k >= ring * 8:
		k -= ring * 8
		ring += 1
	var ang := TAU * float(k) / float(ring * 8) + ring * 0.35
	return pos + Vector2(cos(ang), sin(ang)) * (ring * 26.0)

func _thing_at(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d := 20.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var d := pos.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	if best:
		return best
	best = null
	best_d = 26.0
	for n in get_tree().get_nodes_in_group("res_nodes"):
		var d := pos.distance_to(n.position)
		if d < best_d:
			best_d = d
			best = n
	if best:
		return best
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.team == 1 and pos.distance_to(b.position) < b.size:
			return b
	return null

## 鼠标下是不是守线工人（art 模式下 pos = 点中的那个人的脚底；方块模式看离鼠标多近）
func _operator_building_at(world: Vector2, pos: Vector2) -> Building:
	for w in _player_workers():
		if w.state != Worker.State.OPERATE or not is_instance_valid(w.work_at):
			continue
		if w.position.distance_to(pos) < 1.0 or w.position.distance_to(world) < w.radius * 1.3:
			return w.work_at
	return null

## 右键扫到的己方"收货点"：基地 / 仓库 / 熔炉 / 木工台。
## 兵营不算——那是出兵的地方，不是货场。
const DEPOT_KINDS := ["base", "warehouse", "smelter", "workshop"]
func _friendly_depot_at(pos: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in get_tree().get_nodes_in_group("buildings"):
		if not is_instance_valid(b) or b.team != 0 or b.kind not in DEPOT_KINDS:
			continue
		var d := pos.distance_to(b.position)
		if d < b.size * 0.75 and d < best_d:
			best_d = d
			best = b
	return best

## ================================ 经济 ================================
## 资源出入账统一走 economy（基建加资源种类时只在 Economy 里加）
func add_resource(kind: String, amount: float) -> void:
	economy.add(kind, amount)

func _can_afford(cost: Dictionary) -> bool:
	return economy.can_afford(cost)

func _spend(cost: Dictionary) -> void:
	economy.spend(cost)

func _player_workers() -> Array:
	var r: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Worker:
			r.append(u)
	return r

## 当前选中的农民（"去采矿/去伐木/改自动交货"三个按钮只认他们）
func _selected_workers() -> Array:
	var r: Array = []
	for u in selected:
		if u is Worker and is_instance_valid(u):
			r.append(u)
	return r

func _player_engineers() -> Array:
	var r: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Engineer:
			r.append(u)
	return r

## ================================ UI ================================
func _build_ui() -> void:
	hud = Hud.new(self)
	add_child(hud)
	ui = hud
	hud.build()    # 建好后 res_label / wave_label / info_label / panel / overlay 等都已挂到 main 上

## ================================ 生产 ================================
## 点中的玩家建筑（基地出农民 / 兵营出兵）
## 多选同种建筑（帝国式）：排进队列最短的那个
func _selected_building() -> Building:
	var best: Building = null
	for s in selected:
		if not (s is Building) or not is_instance_valid(s):
			return null
		if best != null and s.kind != best.kind:
			return null
		if best == null or s.queue.size() < best.queue.size():
			best = s
	return best

## 训练表：成本 / 读条秒数 / 在哪造
const TRAIN := {
	"worker": {"cost": Economy.COST_WORKER, "time": 6.0, "at": "base", "name": "农民"},
	"sword": {"cost": Economy.COST_SWORD, "time": 8.0, "at": "barracks", "name": "剑士"},
	"archer": {"cost": Economy.COST_ARCHER, "time": 8.0, "at": "barracks", "name": "弓手"},
}
var train_scale := 1.0    # 读条时间倍率；自测（--test）设 0 = 立刻出，老断言照旧

func train_name(kind: String) -> String:
	return TRAIN[kind].name if TRAIN.has(kind) else kind

## 排队中的单位数（kind 为空 = 全部）
func queued_count(kind := "") -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.team == 0:
			for q in b.queue:
				if kind == "" or q.kind == kind:
					n += 1
	return n

## 出兵时人口满了没有（农民有单独上限）
func pop_blocked(kind: String) -> bool:
	if get_tree().get_nodes_in_group("player_units").size() >= UNIT_CAP:
		return true
	return kind == "worker" and _player_workers().size() >= WORKER_CAP

## 点基地 → 造农民（排进基地的生产队列）
func _on_worker_pressed() -> void:
	if game_state != "play":
		return
	var home := _selected_building()
	if home == null or home.kind != "base":
		_hud_msg("先点基地才能造农民")
		return
	if _player_workers().size() + queued_count("worker") >= WORKER_CAP:
		_hud_msg("农民已到上限（%d），够用就好" % WORKER_CAP)
		return
	_enqueue(home, "worker")

## 排队：检查人口 / 队列 / 钱 → 先扣钱再排（帝国式，取消全额退）
func _enqueue(b: Building, kind: String) -> bool:
	if get_tree().get_nodes_in_group("player_units").size() + queued_count() >= UNIT_CAP:
		_hud_msg("全军已到上限（%d）" % UNIT_CAP)
		return false
	if b.queue.size() >= Building.QUEUE_MAX:
		_hud_msg("%s的队列满了（最多排 %d 个）" % [b.display_name, Building.QUEUE_MAX])
		return false
	var cost: Dictionary = TRAIN[kind].cost
	if not _can_afford(cost):
		_hud_msg(economy.short_msg(cost))
		return false
	_spend(cost)
	var t: float = TRAIN[kind].time * train_scale
	if t <= 0.0:
		on_trained(b, kind)
	else:
		b.queue.append({"kind": kind, "left": t, "total": t, "cost": cost})
	return true

## 取消队列里第 i 个：全额退钱
func cancel_train(b: Building, i: int) -> void:
	if not is_instance_valid(b) or i < 0 or i >= b.queue.size():
		return
	var q: Dictionary = b.queue[i]
	for k in q.cost:
		economy.add(k, float(q.cost[k]))
	b.queue.remove_at(i)
	if i == 0:
		b.waiting_pop = false
	_hud_msg("已取消%s，退回 %s" % [train_name(q.kind), economy.cost_text(q.cost)])

## 读条完成：在建筑门口出人，按集结点走（没设集结点：农民自动上岗，兵在门口列队）
func on_trained(b: Building, kind: String) -> void:
	if kind == "worker":
		var w := Worker.new()
		w.position = b.position + Vector2(60, 40)
		add_child(w)
		if is_instance_valid(b.rally_node) and b.rally_node is ResNode:
			w.command_gather(b.rally_node)
			return
		# 集结点设在熔炉/木工台上：出来直接进厂干活（人满了就在门口等）
		if is_instance_valid(b.rally_node) and b.rally_node is Building and b.rally_node.is_processor():
			if w.command_operate(b.rally_node):
				return
		if b.rally != Vector2.INF:
			w.command_move(open_point(b.rally))
			return
		# 新农民自动上岗：哪种资源干活的人少就去哪（玩家随时可以右键改派）
		var n_ore := 0
		var n_wood := 0
		for o in _player_workers():
			if o != w and is_instance_valid(o.node_target):
				if o.node_target.kind == "ore":
					n_ore += 1
				else:
					n_wood += 1
		w.auto_assign("wood" if n_wood < n_ore else "ore")
		return
	var s := Soldier.new()
	s.setup(kind == "archer")
	s.position = b.position + Vector2(0, 60)
	add_child(s)
	_rally_i += 1
	var at := b.rally if b.rally != Vector2.INF else b.position + Vector2(0, 86)
	s.command_move(open_point(_spread_pos(_rally_i % 24, at)))

## 设集结点：选中基地/兵营右键地面（点在矿/树上 = 新农民直接去采）
func set_rally(b: Building, pos: Vector2) -> void:
	var t := _thing_at(pos)
	var proc := _friendly_depot_at(pos)
	if t == null and proc != null and proc.is_processor() and b.kind == "base":
		b.rally_node = proc
		b.rally = proc.position + Vector2(0, proc.size * 1.1)
		_hud_msg("集结点已设到%s：新农民出来直接进厂干活（人满了在门口等）" % proc.display_name)
		return
	b.rally_node = t if t is ResNode else null
	b.rally = t.position if t is ResNode else open_point(pos)
	_hud_msg("集结点已设到%s" % ("这片%s" % ("矿" if t.kind == "ore" else "树林") if t is ResNode else "这里"))

## 点英雄工程师 → 建兵营（帝国式：建造是工程师的活）
## 两种设施共用一个放置入口：工程师选中 → 检查成本 → 进入放置模式
func _start_placing(kind: String) -> void:
	if game_state != "play":
		return
	if selected.size() != 1 or not (selected[0] is Engineer) or not is_instance_valid(selected[0]):
		_hud_msg("先选中英雄工程师——全帝国只有他会盖房子")
		return
	_build_eng = selected[0]
	var cost: Dictionary = BuildManager.COST_TABLE.get(kind, {})
	if not _can_afford(cost):
		_hud_msg(economy.short_msg(cost) + " · 框选农民右键点树，多派几个伐木")
		return
	_placing_kind = kind
	_hud_msg("点击地图放置%s（右键取消）· 工程师会亲自过去施工" % _place_name(kind))

func _on_warehouse_pressed() -> void:
	_start_placing("warehouse")

func _on_smelter_pressed() -> void:
	_start_placing("smelter")

func _on_workshop_pressed() -> void:
	_start_placing("workshop")

func _on_barracks_pressed() -> void:
	_start_placing("barracks")

func _place_name(kind: String) -> String:
	match kind:
		"warehouse":
			return "仓库"
		"smelter":
			return "熔炉"
		"workshop":
			return "木工台"
		"barracks":
			return "兵营"
		"tower":
			return "箭塔"
	return "设施"

func _on_sword_pressed() -> void:
	_train_soldier(false)

func _on_archer_pressed() -> void:
	_train_soldier(true)

## 点兵营 → 出兵（排进兵营的生产队列）
func _train_soldier(ranged: bool) -> void:
	if game_state != "play":
		return
	var b := _selected_building()
	if b == null or b.kind != "barracks":
		if barracks_list.is_empty():
			_hud_msg("先建兵营才能出兵")
			return
		b = barracks_list[0]
	_enqueue(b, "archer" if ranged else "sword")

## ================================ 选中信息栏 ================================
## 点选 1 个 = 头像 + 数值面板；框选多个 = 头像排排站 + 数量统计
func _selected_info_text() -> String:
	var list := _display_list()
	if list.is_empty():
		return ""
	if list.size() == 1:
		var t = list[0]
		if t is Building:
			var extra := ""
			if t.has_tower():
				var st: Dictionary = t.tower_stats()
				extra = " · 箭塔 %.0f 伤害 / %.1f 秒 · 射程 %.0f" % [st.dmg, st.cd, st.range]
			var txt := "%s   血量 %.0f/%.0f · 建筑%s" % [t.display_name, t.hp, t.max_hp, extra]
			if t.kind == "tower":
				var st: Dictionary = t.tower_stats()
				txt = "%s   血量 %.0f/%.0f · 弓手 %d · 每箭 %.0f（%.1f 秒/箭）· 射程 %.0f\n先打跑在最前面的 · 击杀 %d" % [
					t.display_name, t.hp, t.max_hp, int(st.archers), st.dmg, st.cd, st.range, t.kills]
				txt += " · Q 升级（%s）" % economy.cost_text(Economy.COST_TOWER_UP) if t.can_upgrade() else " · 已满级"
			if t.trains():
				txt += "\n集结点已设（右键改）" if t.rally != Vector2.INF else "\n右键地面/矿/树 = 集结点"
				if t.waiting_pop:
					txt += " · 人口满了，等空位"
			if t.is_processor():
				var r: Dictionary = t.recipe()
				txt = "%s   血量 %.0f/%.0f · %s：%d %s → %d %s / %.0f 秒\n%s · 自取%s" % [t.display_name, t.hp, t.max_hp, r.verb,
					r.n, Economy.KIND_NAME[r.in], r.n, Economy.KIND_NAME[r.out], r.time, t.status_text(), "开" if t.self_fetch else "关"]
			return txt
		var u: Unit = t
		var atk_txt := "—" if u.atk <= 0.0 else "%.0f（%.1f秒/下）" % [u.atk, u.atk_cd]
		var rng_txt := "—"
		if u.atk > 0.0:
			rng_txt = "%.0f（近战）" % u.atk_range if u.atk_range <= 35.0 else "%.0f（远程）" % u.atk_range
		var line := "%s   血量 %.0f/%.0f · 护甲 %.0f · 攻击 %s\n移速 %.0f · 射程 %s" % [
			u.display_name, u.hp, u.max_hp, u.armor, atk_txt, u.speed, rng_txt]
		if u is Goo:
			line += "\n" + u.type_tip()
		if u is Worker and u.team == 0:
			var w: Worker = u
			var dest := "就近仓库/基地"
			if is_instance_valid(w.deliver_to):
				dest = w.deliver_to.display_name
			var job := w.job_text()
			line += (" · " + job) if job != "" else " · 交货→%s" % dest
			if w.carry_amount > 0.5:
				line += " · 扛着 %d %s" % [int(w.carry_amount),
					Economy.KIND_NAME.get(w.carry_kind, w.carry_kind)]
		return line
	var counts := {}
	for u in list:
		counts[u.display_name] = int(counts.get(u.display_name, 0)) + 1
	var parts: Array = []
	for k in counts:
		parts.append("%s×%d" % [k, counts[k]])
	return "已选中 %d 个：%s" % [list.size(), "  ".join(parts)]

func _update_labels() -> void:
	var txt := _selected_info_text()
	info_label.visible = txt != ""
	info_label.text = txt
	var eng_txt := "英雄·工程 上阵"
	if not respawn_timers.is_empty():
		eng_txt = "英雄·工程 复活 %ds" % int(maxf(respawn_timers[0], 0.0))
	elif _player_engineers().is_empty():
		eng_txt = "英雄·工程 失踪"
	var res_txt := "矿 %d    木 %d" % [int(economy.ore), int(economy.wood)]
	# 二级材料有货才显示，平时不占地方
	if economy.ingot > 0.0:
		res_txt += "    铁 %d" % int(economy.ingot)
	if economy.plank > 0.0:
		res_txt += "    板 %d" % int(economy.plank)
	res_label.text = "%s    农民 %d/%d    %s" % [res_txt, _player_workers().size(), WORKER_CAP, eng_txt]
	if game_state != "play":
		wave_label.text = ""
	elif _wave_mgr.wave == 0:
		wave_label.text = "敌情：第一波还有 %d 秒 · %s" % [int(_wave_mgr.wave_timer), WaveManager.wave_text(1)]
	elif _wave_mgr.wave >= WaveManager.MAX_WAVES:
		wave_label.text = "最后一波已出，清完即胜"
	else:
		wave_label.text = "第 %d/%d 波 · 下一波 %d 秒：%s" % [_wave_mgr.wave, WaveManager.MAX_WAVES, int(_wave_mgr.wave_timer), WaveManager.wave_text(_wave_mgr.wave + 1)]

## ================================ 产能面板 ================================
func _update_panel() -> void:
	panel.visible = _panel_on and game_state == "play"
	panel_label.visible = panel.visible
	if not panel.visible:
		return
	var lines := "产能（近 %d 秒 · C 键隐藏）" % int(Economy.RATE_WINDOW)
	for k in ["ore", "wood", "ingot", "plank"]:
		var r := economy.rate(k)
		var v := "—" if r < 0.02 else "%.1f/秒" % r
		lines += "\n%s    %s" % [Economy.KIND_NAME[k], v]
	lines += "\n" + _bottleneck()
	panel_label.text = lines

## 瓶颈提示：说人话，指出卡在哪一环
func _bottleneck() -> String:
	if game_state != "play":
		return ""
	var ore_r := economy.rate("ore")
	var wood_r := economy.rate("wood")
	if ore_r < 0.02 and wood_r < 0.02:
		return "没人交货，派人去采矿/伐木"
	var w := _player_workers().size()
	# 攒不出农民是最要命的卡点，比其他提示优先
	if economy.wood < Economy.COST_WORKER["wood"] and w < WORKER_CAP:
		return "木材不足，造不了农民（要%d木）" % int(Economy.COST_WORKER["wood"])
	var has_smelter := _has_processor("smelter")
	var has_workshop := _has_processor("workshop")
	# 加工线卡在哪一环：没工人 / 缺料 / 成品堆满
	for b in processors_list:
		if not is_instance_valid(b):
			continue
		var raw: String = Economy.KIND_NAME[b.recipe().in]
		match b.line_status:
			"no_op":
				return "%s没人干活：选中它按 Q 招工（或选农民右键它）" % b.display_name
			"no_in":
				if b.self_fetch and economy.amount(b.recipe().in) < Building.FETCH_RESERVE + 1.0:
					return "%s缺料：仓库%s不到 %d（留底），多派人采" % [b.display_name, raw, int(Building.FETCH_RESERVE)]
				return "%s缺料：派采%s的农民右键它送料，或打开自取" % [b.display_name, raw]
			"full":
				if b.op_count() < Building.OP_MAX:
					return "%s成品堆满了：再招 1 个工人专门搬货" % b.display_name
				return "%s成品堆满了：仓库太远搬不过来，在旁边盖个仓库" % b.display_name
	if w < 4 and ore_r + wood_r < 1.2:
		return "农民 %d/%d，人少产得慢" % [w, WORKER_CAP]
	if not has_smelter:
		return "还没熔炉：出不了剑士（要铁锭）"
	if not has_workshop:
		return "还没木工台：出不了弓手（要木板）"
	return "各条产线都在转"

func _has_processor(kind: String) -> bool:
	for b in processors_list:
		if is_instance_valid(b) and b.kind == kind:
			return true
	return false

## ================================ 绘制 ================================
## 地图装饰：固定随机种子撒灌木/花丛/石头，避开土路、建筑、资源点和边缘树林
## 敌人行军路线 = 地图上画的土路（有手绘地图时从图里分析出来），否则用老的折线
func road() -> Array:
	if not roads.is_empty():
		return roads[0]
	if Art.has("map/map") and not ArtData.ROAD.is_empty():
		return ArtData.ROAD
	return DIRT_PATH

func _build_decor() -> void:
	_decor.clear()
	var keys := ["decor/bush_1", "decor/bush_2", "decor/flowers", "decor/flowers", "decor/rock_1"]    # 木栅栏去掉了：没碰撞，看着像能挡路其实不能，容易误会
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	var tries := 0
	while _decor.size() < 34 and tries < 2000:
		tries += 1
		var p := Vector2(rng.randf_range(140, W - 140), rng.randf_range(90, H - 100))
		var ok := not Art.forest_at(p)
		var rd := road()
		for i in rd.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, rd[i], rd[i + 1]).distance_to(p) < 52.0:
				ok = false
				break
		for n in get_tree().get_nodes_in_group("res_nodes"):
			if n.position.distance_to(p) < 46.0:
				ok = false
		for b in get_tree().get_nodes_in_group("buildings"):
			if b.position.distance_to(p) < b.size + 30.0:
				ok = false
		for d in _decor:
			if d.pos.distance_to(p) < 60.0:
				ok = false
		if ok:
			_decor.append({"key": keys[rng.randi() % keys.size()], "pos": p, "flip": rng.randf() < 0.5})
	_decor.sort_custom(func(a, b): return a.pos.y < b.pos.y)

const DECOR_H := {"decor/bush_1": 26.0, "decor/bush_2": 26.0, "decor/flowers": 16.0, "decor/rock_1": 16.0}

func _draw() -> void:
	# ---- 地面：随机图由 Ground 节点（着色器）画；经典图有手绘地图就整张铺上，否则用原来的色块草地 ----
	if not classic:
		pass
	elif Art.has("map/map"):
		draw_texture_rect(Art.tex("map/map"), Rect2(0, 0, W, H), false)
		for d in _decor:
			if Art.has(d.key):
				Art.draw(self, d.key, d.pos, DECOR_H.get(d.key, 20.0), d.flip)
	else:
		draw_rect(Rect2(0, 0, W, H), Color(0.46, 0.69, 0.34))
		for p in GRASS_DARK:
			draw_circle(p, 58.0, Color(0.41, 0.63, 0.29))
		for p in GRASS_LIGHT:
			draw_circle(p, 48.0, Color(0.52, 0.75, 0.38))
		var path := PackedVector2Array(DIRT_PATH)
		draw_polyline(path, Color(0.42, 0.33, 0.22), 54.0)
		draw_polyline(path, Color(0.56, 0.45, 0.3), 46.0)
		for p in STONES:
			draw_circle(p, 4.0, Color(0.52, 0.44, 0.34))

	# ---- 右键落点圈：移动 = 绿，攻击 = 红，缩小淡出 ----
	var now := Time.get_ticks_msec()
	_markers = _markers.filter(func(m): return now - m.t0 < 500)
	for m in _markers:
		var k: float = (now - m.t0) / 500.0
		var c: Color = Color(1.0, 0.35, 0.25) if m.attack else Color(0.55, 1.0, 0.35)
		c.a = 1.0 - k
		Art.ellipse(self, m.pos, 16.0 * (1.2 - k * 0.6), c, false, 3.0)
		Art.ellipse(self, m.pos, 6.0 * (1.2 - k * 0.6), c, false, 2.0)

	# ---- 选中的箭塔 / 基地：射程圈 ----
	for s in selected:
		if s is Building and is_instance_valid(s) and s.has_tower():
			_range_ring(s.position, s.tower_stats().range)
	# ---- 集结点 / 排队路点 / 巡逻线（只画选中的；路点只画一个代表，多选时别画成一团乱麻） ----
	var drew_wp := false
	for s in selected:
		if not is_instance_valid(s):
			continue
		if s is Building:
			if s.team == 0 and s.trains() and s.rally != Vector2.INF:
				_dashed(s.position, s.rally, Color(1.0, 1.0, 1.0, 0.7))
				_draw_flag(s.rally)
		elif s is Unit:
			if not s.waypoints.is_empty() and not drew_wp:
				drew_wp = true
				var pts: Array = s.order_points()
				var prev: Vector2 = s.position
				for q in pts:
					_dashed(prev, q, Color(0.55, 1.0, 0.35, 0.75))
					Art.ellipse(self, q, 5.0, Color(0.55, 1.0, 0.35, 0.8), false, 2.0)
					prev = q
			if s is Soldier and s.patrol:
				_dashed(s._patrol_a, s._patrol_b, Color(1.0, 0.85, 0.35, 0.75))
				Art.ellipse(self, s._patrol_a, 6.0, Color(1.0, 0.85, 0.35, 0.8), false, 2.0)
				Art.ellipse(self, s._patrol_b, 6.0, Color(1.0, 0.85, 0.35, 0.8), false, 2.0)

	# ---- 拖框 ----
	if _dragging:
		var rect := Rect2(_drag_start, get_global_mouse_position() - _drag_start).abs()
		draw_rect(rect, Color(0.6, 1.0, 0.5, 0.1))
		draw_rect(rect, Color(0.75, 1.0, 0.6, 0.85), false, 2.0 / cam.zoom.x)
	# ---- 放置设施的幽灵预览：半透明建筑贴图，能放 = 绿，不能放 = 红 ----
	if _placing_kind != "":
		var p := get_global_mouse_position()
		var ok := _placement_ok(_placing_kind, p)
		var tint := Color(0.6, 1.0, 0.6, 0.6) if ok else Color(1.0, 0.45, 0.4, 0.6)
		if _placing_kind == "tower":
			_range_ring(p, Building.TOWER_LV[1].range, ok)    # 放塔时就看得见能罩住哪段路
		if Art.has("buildings/" + _placing_kind):
			var sz: float = Building.size_of(_placing_kind)    # 和盖好后一样大
			Art.ellipse(self, p + Vector2(0, sz * 0.38), sz * 0.95, Color(tint, 0.35))
			Art.draw_w(self, "buildings/" + _placing_kind, p + Vector2(0, sz * 0.42), Building.art_w(_placing_kind, sz), tint)
		else:
			var half: float = 30.0 * Building.SIZE_SCALE    # 工地半宽
			var r := Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
			draw_rect(r, Color(0.15, 0.6, 0.55, 0.5))
			draw_rect(r, Color(1, 1, 1, 0.6), false, 1.0)

## 射程圈（选中箭塔 / 放塔预览）：淡色实心 + 描边，画在地上、单位下面
func _range_ring(c: Vector2, r: float, ok := true) -> void:
	var col := Color(0.55, 0.85, 1.0) if ok else Color(1.0, 0.45, 0.4)
	draw_circle(c, r, Color(col, 0.08))
	draw_arc(c, r, 0, TAU, 72, Color(col, 0.65), 2.0 / cam.zoom.x)

## 虚线（集结点、路点）：每段 14px，线宽不随缩放变粗
func _dashed(a: Vector2, b: Vector2, c: Color) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var dir := (b - a) / d
	var w := 2.0 / cam.zoom.x
	var t := 0.0
	while t < d:
		draw_line(a + dir * t, a + dir * minf(t + 14.0, d), c, w)
		t += 24.0

## 集结点小旗：旗杆 + 蓝色三角旗
func _draw_flag(p: Vector2) -> void:
	Art.ellipse(self, p, 7.0, Color(0, 0, 0, 0.3))
	draw_line(p, p + Vector2(0, -26), Color(0.35, 0.25, 0.15), 2.0)
	draw_colored_polygon(PackedVector2Array([p + Vector2(1, -26), p + Vector2(16, -21), p + Vector2(1, -16)]), Color(0.25, 0.5, 0.95))

## 放置预览用：和 BuildManager.try_place 同一套规则（只判断，不提示）
func _placement_ok(kind: String, pos: Vector2) -> bool:
	return _build_mgr.placement_error(pos, kind) == "" and economy.can_afford(BuildManager.COST_TABLE.get(kind, {}))

## ================================ 自测 ================================
## 套件本体已拆到 test_suite.gd。入口和用法不变：
## Godot --headless --path rts-demo -- --test
## 这里用 preload 而不是裸类名 GameTests：headless 首跑未刷新全局类缓存时会认不出 class_name。
const TestSuite := preload("res://test_suite.gd")

func _run_test() -> void:
	await TestSuite.new(self).run()
