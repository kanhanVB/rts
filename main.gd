extends Node2D
## 主脚本：地图、选择、指令、UI、波次、胜负，外加一套无头自测。
## 操作：左键点选 / 拖框群选；右键 = 移动 / 采集 / 攻击（看点的什么）。

const W := 1280
const H := 720

const WORKER_CAP := 12
const ENGINEER_RESPAWN := 15.0    # 英雄工程师阵亡后的复活倒计时
const UNIT_CAP := 40

# 镜头
const CAM_MIN_ZOOM := 1.0     # 缩放下限 = 视野正好铺满地图，杜绝看到地图外的灰底
const CAM_MAX_ZOOM := 2.0     # 放大上限，贴近看单位
const CAM_EDGE := 40.0          # 鼠标贴边多少像素就开始滚屏
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
var hive: Building
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
var _a_move_next := false         # 按了 A 后，下一次右键 = 攻击移动

# UI 引用
var ui: CanvasLayer
var res_label: Label
var wave_label: Label
var btn_worker: Button
var btn_warehouse: Button
var btn_smelter: Button
var btn_workshop: Button
var btn_barracks: Button
var btn_sword: Button
var btn_archer: Button
var overlay: ColorRect
var overlay_label: Label
var _hud_msg_label: Label
var _hud_msg_t := 0.0
var info_label: Label        # 底部信息栏：点选 = 数值，框选 = "已选中 N 个"
var panel: ColorRect         # 产能面板（C 键开关）
var panel_label: Label
var _panel_on := true
var portraits: Node2D        # 挂在 CanvasLayer 上画选中单位的头像

func _ready() -> void:
	add_to_group("game")
	randomize()
	_build_mgr = BuildManager.new()
	add_child(_build_mgr)
	_build_mgr.building_built.connect(_on_building_built)
	_wave_mgr = WaveManager.new()
	add_child(_wave_mgr)
	_build_map()
	_build_ui()
	_build_camera()
	if "--test" in OS.get_cmdline_user_args():
		_wave_mgr.wave_timer = 999.0    # 测试期间不来波次，保证断言确定性
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
	cam.position = Vector2(W / 2.0, H / 2.0)
	cam.zoom = Vector2.ONE
	add_child(cam)
	cam.make_current()    # 必须在 add_child 之后，否则报 "not inside tree"

## ================================ 地图 ================================
func _build_map() -> void:
	# 地形层（先建，垫在最下面）
	terrain = Terrain.new()
	add_child(terrain)
	_build_terrain()

	base = _build_mgr.add_building("base", Vector2(170, 560), 0)
	hive = _build_mgr.add_building("hive", Vector2(1110, 160), 1)

	for c in [Vector2(430, 470), Vector2(720, 260), Vector2(960, 560)]:
		for i in 3:
			_add_res("ore", c + Vector2((i - 1) * 46.0, 0.0 if i == 1 else 36.0))
	for c in [Vector2(320, 240), Vector2(620, 570), Vector2(1010, 420)]:
		for i in 3:
			_add_res("wood", c + Vector2((i - 1) * 46.0, 0.0 if i == 1 else 36.0))

	# 开局 3 工人自动分工：2 采矿 1 伐木，开局就有供应链在转
	for i in 3:
		var w := Worker.new()
		w.position = base.position + Vector2(60.0 + i * 30.0, 40.0)
		add_child(w)
		w.auto_assign("wood" if i == 2 else "ore")

	# 开局 1 名工程师，负责建造
	_spawn_engineer(base.position + Vector2(90.0, 40.0))

func _add_res(kind: String, pos: Vector2) -> void:
	var n := ResNode.new()
	n.kind = kind
	n.position = pos
	add_child(n)

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
	if game_state == "play":
		_wave_mgr.update(delta)
		_update_respawn(delta)
		_check_end()
	_update_buttons()
	_update_labels()
	_update_panel()
	portraits.queue_redraw()
	_update_camera(delta)
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
	if dir != Vector2.ZERO:
		cam.position += dir.normalized() * CAM_SPEED * 60.0 * delta / cam.zoom.x
	var half := vp / cam.zoom / 2.0
	# 视野比地图还大时（缩小过头），镜头锁死在地图中心，避免 clamp 上下限颠倒
	if half.x * 2.0 >= W:
		cam.position.x = W / 2.0
	else:
		cam.position.x = clampf(cam.position.x, half.x, W - half.x)
	if half.y * 2.0 >= H:
		cam.position.y = H / 2.0
	else:
		cam.position.y = clampf(cam.position.y, half.y, H - half.y)

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
	elif not is_instance_valid(hive):
		_end("win", "巢穴被拆了！")

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

## ================================ 输入 ================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_camera(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_camera(1.0 / 1.15)
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
				else:
					_drag_start = _to_world(event.position)
					_dragging = true
					queue_redraw()
			elif _dragging:
				_dragging = false
				var rect := Rect2(_drag_start, _to_world(event.position) - _drag_start).abs()
				if rect.size.length() > 10.0 / cam.zoom.x:    # 拖框阈值也按缩放换算
					_box_select(rect)
				else:
					_point_select(_to_world(event.position))
				queue_redraw()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _placing_kind != "":
				_hud_msg("已取消放置" + _place_name(_placing_kind))
				_placing_kind = ""
				queue_redraw()
			else:
				_issue_command(_to_world(event.position))
	elif event is InputEventMouseMotion and _dragging:
		queue_redraw()
	elif event is InputEventKey and event.pressed:
		# A 键 = 攻击移动（下次右键就是 A 移动）
		if event.keycode == KEY_A and not event.echo:
			_a_move_next = true
			_hud_msg("A 移动：右键目的地，路上遇到敌人就开打")
		elif event.keycode == KEY_C and not event.echo:
			_panel_on = not _panel_on
			_update_panel()
		# 编队：Ctrl+数字 存队，数字键 召回
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx := int(event.keycode) - int(KEY_1)
			if event.ctrl_pressed or event.meta_pressed:
				_save_control_group(idx)
			else:
				_recall_control_group(idx)

## 屏幕坐标 → 世界坐标（考虑镜头缩放和位移）
func _to_world(screen: Vector2) -> Vector2:
	return cam.get_canvas_transform().affine_inverse() * screen

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
	_clear_inspect()
	for s in selected:
		s.selected = false
	selected.clear()
	var best: Unit = null
	var best_d := 18.0
	for u in get_tree().get_nodes_in_group("player_units"):
		var d := pos.distance_to(u.position)
		if d < best_d:
			best_d = d
			best = u
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

func _box_select(rect: Rect2) -> void:
	_clear_inspect()
	for s in selected:
		s.selected = false
	selected.clear()
	for u in get_tree().get_nodes_in_group("player_units"):
		if rect.has_point(u.position):
			u.selected = true
			selected.append(u)

## 右键：看点的什么，给选中单位下发对应指令
func _issue_command(pos: Vector2) -> void:
	if selected.is_empty():
		return
	var target := _thing_at(pos)
	var depot := _friendly_depot_at(pos)     # 选农民右键己方收货建筑 = 指派交货点
	var move_idx := 0    # 纯移动的单位排队领环形散点，别全挤向同一个坐标
	for u in selected:
		if target is ResNode and u is Worker:
			u.command_gather(target)
		elif depot != null and u is Worker:
			u.set_deliver_to(depot)
		elif target is ResNode:
			# 士兵/工程师点资源点 = 走过去，不是攻击指令
			u.command_move(_spread_pos(move_idx, pos))
			move_idx += 1
		elif target != null and target.team == 1 and (u is Soldier or u is Engineer):
			# 攻击指令有距离门槛：超出射程责任圈就转成移动，别追杀到天涯海角
			var cmd_range := 70.0 if u is Engineer else 250.0
			if u.position.distance_to(target.position) <= cmd_range:
				u.command_attack(target)
			else:
				u.command_move(_spread_pos(move_idx, pos))
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
	if depot != null:
		var nw := _selected_workers().size()
		if nw > 0:
			_hud_msg("%d 个农民改送%s：%s" % [nw, depot.display_name, _depot_result(depot)])

## 送进这个建筑变成什么账（给玩家看，别让人盲猜）
func _depot_result(b: Building) -> String:
	match b.kind:
		"smelter":
			return "矿石炼成铁锭（木材照样存原料）"
		"workshop":
			return "木材做成木板（矿石照样存原料）"
		"warehouse":
			return "原样入库，攒着造农民"
	return "原样入库"

## ---------- 编队：Ctrl+数字 存，数字 召回 ----------
func _save_control_group(idx: int) -> void:
	control_groups.resize(max(control_groups.size(), idx + 1))
	control_groups[idx] = selected.filter(func(u): return is_instance_valid(u)).duplicate()
	_hud_msg("编队 %d 已存（%d 个单位）" % [idx + 1, control_groups[idx].size()])

func _recall_control_group(idx: int) -> void:
	_clear_inspect()
	for s in selected:
		s.selected = false
	selected.clear()
	if idx >= control_groups.size():
		return
	var grp: Array = control_groups[idx]
	var alive: Array = []
	for u in grp:
		if is_instance_valid(u):
			u.selected = true
			selected.append(u)
			alive.append(u)
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
	ui = CanvasLayer.new()
	add_child(ui)

	# 深木色横条垫底，标签放上面才看得清（KR 的 UI 就是深板 + 奶油字）
	var top_strip := ColorRect.new()
	top_strip.color = Color(0.13, 0.1, 0.07, 0.6)
	top_strip.position = Vector2.ZERO
	top_strip.size = Vector2(W, 64)
	top_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(top_strip)

	var bottom_strip := ColorRect.new()
	bottom_strip.color = Color(0.13, 0.1, 0.07, 0.6)
	bottom_strip.position = Vector2(0, H - 72)
	bottom_strip.size = Vector2(W, 72)
	bottom_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom_strip)

	res_label = Label.new()
	res_label.position = Vector2(16, 10)
	res_label.add_theme_font_size_override("font_size", 18)
	res_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	ui.add_child(res_label)

	wave_label = Label.new()
	wave_label.position = Vector2(W - 320, 10)
	wave_label.add_theme_font_size_override("font_size", 18)
	wave_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	ui.add_child(wave_label)

	var tip := Label.new()
	tip.text = "左键点选 / 拖框群选 · 点基地=造农民、点兵营=出兵、点工程师=建设施（仓库/熔炉/木工台/兵营） · 右键：空地=移动，矿/树=农民去采，己方仓库/熔炉/木工台=农民改送那里，敌人=攻击 · C 键=产能面板"
	tip.position = Vector2(16, 42)
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	ui.add_child(tip)

	_hud_msg_label = Label.new()
	_hud_msg_label.position = Vector2(W / 2 - 260, 72)
	_hud_msg_label.size = Vector2(520, 30)
	_hud_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_msg_label.add_theme_font_size_override("font_size", 19)
	_hud_msg_label.add_theme_color_override("font_color", Color(0.95, 0.8, 0.3))
	_hud_msg_label.visible = false
	ui.add_child(_hud_msg_label)

	var bar := HBoxContainer.new()
	bar.position = Vector2(16, H - 64)
	bar.add_theme_constant_override("separation", 8)
	ui.add_child(bar)

	btn_worker = _mk_btn(bar, "造农民 30木", _on_worker_pressed)
	btn_warehouse = _mk_btn(bar, "建仓库 60木", _on_warehouse_pressed)
	btn_smelter = _mk_btn(bar, "建熔炉 40矿40木", _on_smelter_pressed)
	btn_workshop = _mk_btn(bar, "木工台 20矿60木", _on_workshop_pressed)
	btn_barracks = _mk_btn(bar, "建兵营 80矿60木", _on_barracks_pressed)
	btn_sword = _mk_btn(bar, "剑士 40矿20木", _on_sword_pressed)
	btn_archer = _mk_btn(bar, "弓手 30矿40木", _on_archer_pressed)
	for b in [btn_worker, btn_warehouse, btn_smelter,
			btn_workshop, btn_barracks, btn_sword, btn_archer]:
		b.visible = false    # 按钮跟着选中对象出现（点基地/兵营/工程师）

	# ---- 底部信息栏：点选单位 = 头像 + 数值；框选 = 头像排排站 ----
	info_label = Label.new()
	info_label.position = Vector2(608, H - 50)
	info_label.add_theme_font_size_override("font_size", 15)
	info_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	ui.add_child(info_label)

	portraits = Node2D.new()
	ui.add_child(portraits)
	portraits.draw.connect(_draw_portraits)

	# ---- 产能面板（C 键开关）：基建看得见瓶颈才有得调 ----
	panel = ColorRect.new()
	panel.color = Color(0.13, 0.1, 0.07, 0.74)
	panel.position = Vector2(W - 258, H - 210)
	panel.size = Vector2(248, 148)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)
	panel_label = Label.new()
	panel_label.position = panel.position + Vector2(14, 10)
	panel_label.add_theme_font_size_override("font_size", 14)
	panel_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.8))
	ui.add_child(panel_label)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	ui.add_child(overlay)

	overlay_label = Label.new()
	overlay_label.position = Vector2(W / 2 - 260, H / 2 - 60)
	overlay_label.add_theme_font_size_override("font_size", 42)
	overlay.add_child(overlay_label)

	var restart := Button.new()
	restart.text = "再来一局"
	restart.position = Vector2(W / 2 - 60, H / 2 + 40)
	restart.pressed.connect(func(): get_tree().reload_current_scene())
	overlay.add_child(restart)

func _mk_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## ================================ 生产 ================================
## 点中的玩家建筑（基地出农民 / 兵营出兵）
func _selected_building() -> Building:
	if selected.size() == 1 and selected[0] is Building and is_instance_valid(selected[0]):
		return selected[0]
	return null

## 点基地 → 造农民
func _on_worker_pressed() -> void:
	if game_state != "play":
		return
	var home := _selected_building()
	if home == null or home.kind != "base":
		_hud_msg("先点基地才能造农民")
		return
	if _player_workers().size() >= WORKER_CAP:
		_hud_msg("农民已到上限（%d），够用就好" % WORKER_CAP)
		return
	if get_tree().get_nodes_in_group("player_units").size() >= UNIT_CAP:
		_hud_msg("全军已到上限（%d）" % UNIT_CAP)
		return
	if not _can_afford(Economy.COST_WORKER):
		_hud_msg(economy.short_msg(Economy.COST_WORKER))
		return
	_spend(Economy.COST_WORKER)
	var w := Worker.new()
	w.position = home.position + Vector2(60, 40)
	add_child(w)

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
	return "设施"

func _on_sword_pressed() -> void:
	_train_soldier(false)

func _on_archer_pressed() -> void:
	_train_soldier(true)

## 点兵营 → 出兵
func _train_soldier(ranged: bool) -> void:
	if game_state != "play":
		return
	var b := _selected_building()
	if b == null or b.kind != "barracks":
		if barracks_list.is_empty():
			_hud_msg("先建兵营才能出兵")
			return
		b = barracks_list[0]
	var cost: Dictionary = Economy.COST_ARCHER if ranged else Economy.COST_SWORD
	if not _can_afford(cost):
		_hud_msg(economy.short_msg(cost))
		return
	if get_tree().get_nodes_in_group("player_units").size() >= UNIT_CAP:
		_hud_msg("全军已到上限（%d）" % UNIT_CAP)
		return
	_spend(cost)
	var s := Soldier.new()
	s.setup(ranged)
	s.position = b.position + Vector2(0, 60)
	add_child(s)

## 按钮跟随选中对象出现：点基地出农民、点兵营出兵、点工程师建房子
func _update_buttons() -> void:
	var playing := game_state == "play"
	var b := _selected_building()
	btn_worker.visible = playing and b != null and b.kind == "base"
	btn_sword.visible = playing and b != null and b.kind == "barracks"
	btn_archer.visible = btn_sword.visible
	var eng_sel := playing and selected.size() == 1 and selected[0] is Engineer
	btn_warehouse.visible = eng_sel
	btn_smelter.visible = eng_sel
	btn_workshop.visible = eng_sel
	btn_barracks.visible = eng_sel
	btn_worker.disabled = not playing
	btn_warehouse.disabled = not playing
	btn_smelter.disabled = not playing
	btn_workshop.disabled = not playing
	btn_barracks.disabled = not playing
	btn_sword.disabled = not playing
	btn_archer.disabled = not playing

## ================================ 选中信息栏 ================================
## 点选 1 个 = 头像 + 数值面板；框选多个 = 头像排排站 + 数量统计
func _selected_info_text() -> String:
	var list := _display_list()
	if list.is_empty():
		return ""
	if list.size() == 1:
		var t = list[0]
		if t is Building:
			return "%s   血量 %.0f/%.0f · 建筑" % [t.display_name, t.hp, t.max_hp]
		var u: Unit = t
		var atk_txt := "—" if u.atk <= 0.0 else "%.0f（%.1f秒/下）" % [u.atk, u.atk_cd]
		var rng_txt := "—"
		if u.atk > 0.0:
			rng_txt = "%.0f（近战）" % u.atk_range if u.atk_range <= 35.0 else "%.0f（远程）" % u.atk_range
		var line := "%s   血量 %.0f/%.0f · 护甲 %.0f · 攻击 %s · 移速 %.0f · 射程 %s" % [
			u.display_name, u.hp, u.max_hp, u.armor, atk_txt, u.speed, rng_txt]
		if u is Worker and u.team == 0:
			var w: Worker = u
			var dest := "就近仓库/基地"
			if is_instance_valid(w.deliver_to):
				dest = w.deliver_to.display_name
			line += " · 交货→%s" % dest
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
	var list := _display_list()
	var txt := _selected_info_text()
	info_label.visible = txt != ""
	info_label.text = txt
	if list.size() == 1:
		info_label.position = Vector2(668, H - 50)   # 单选：头像右边一行数值
	else:
		info_label.position = Vector2(608, H - 70)   # 多选：数量统计放头像排上方
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
		wave_label.text = "敌情：第一波还有 %d 秒" % int(_wave_mgr.wave_timer)
	elif _wave_mgr.wave >= WaveManager.MAX_WAVES:
		wave_label.text = "最后一波已出，清完即胜"
	else:
		wave_label.text = "第 %d/%d 波 · 下一波 %d 秒" % [_wave_mgr.wave, WaveManager.MAX_WAVES, int(_wave_mgr.wave_timer)]

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
	# 加工厂不再自动抢货：没人点名就一直闲着，所以提示要教玩家怎么点名
	if has_smelter and economy.rate("ingot") < 0.02:
		return "熔炉闲着：选农民右键熔炉才送矿去炼"
	if has_workshop and economy.rate("plank") < 0.02:
		return "木工台闲着：选农民右键木工台才送木材加工"
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

## 选中头像：和场上同款的 KR 小人半身像（肩膀 + 大头 + 帽子）+ 血条
func _draw_portraits() -> void:
	var list := _display_list()
	if list.is_empty():
		return
	var y := H - 34.0
	var shown := mini(list.size(), 9)
	for i in shown:
		var u = list[i]
		var cx := 616.0 + i * 46.0
		portraits.draw_circle(Vector2(cx, y), 21.0, Color(0.2, 0.14, 0.1))      # 深色底圈
		# 建筑：小房子头像（墙 + 屋顶 + 门）
		if u is Building:
			var roof_c: Color = Building.COLORS.get(u.kind, Color.GRAY)
			portraits.draw_rect(Rect2(cx - 10, y - 2, 20, 16), Color(0.92, 0.84, 0.66))
			portraits.draw_rect(Rect2(cx - 10, y - 2, 20, 16), Color(0.2, 0.14, 0.1), false, 2.0)
			portraits.draw_colored_polygon(PackedVector2Array([
				Vector2(cx - 13, y - 2), Vector2(cx + 13, y - 2), Vector2(cx, y - 16)
			]), roof_c)
			portraits.draw_polyline(PackedVector2Array([
				Vector2(cx - 13, y - 2), Vector2(cx, y - 16), Vector2(cx + 13, y - 2), Vector2(cx - 13, y - 2)
			]), Color(0.2, 0.14, 0.1), 2.0)
			portraits.draw_rect(Rect2(cx - 3, y + 6, 6, 8), Color(0.5, 0.36, 0.2))
			_portrait_hp(u, cx, y)
			continue
		# Goo 是黏液怪，画同款无脸黏液堆头像
		if u is Goo:
			portraits.draw_circle(Vector2(cx, y + 2), 10.5, Color(0.2, 0.14, 0.1))
			portraits.draw_circle(Vector2(cx - 3, y - 3), 5.5, Color(0.2, 0.14, 0.1))
			portraits.draw_circle(Vector2(cx, y + 2), 9.0, u.body_color)
			portraits.draw_circle(Vector2(cx - 3, y - 3), 4.0, u.body_color)
			portraits.draw_circle(Vector2(cx - 4, y - 4), 2.2, Color(0.72, 0.93, 0.55))
			_portrait_hp(u, cx, y)
			continue
		portraits.draw_circle(Vector2(cx, y), 19.0, Color(0.88, 0.8, 0.62))       # 米色底
		# 认兵种：躯干色 + 帽子
		var torso: Color = u.body_color
		var hat := "none"
		if u is Worker:
			torso = Color(0.7, 0.6, 0.38)
			hat = "straw"
		elif u is Engineer:
			torso = Color(0.82, 0.46, 0.2)
			hat = "hardhat"
		elif u is Soldier:
			if u.is_ranged:
				torso = Color(0.5, 0.56, 0.6)
				hat = "hood"
			else:
				torso = Color(0.44, 0.52, 0.62)
				hat = "helm"
		# 肩膀（躯干）
		portraits.draw_rect(Rect2(cx - 9, y + 5, 18, 14), Color(0.2, 0.14, 0.1))
		portraits.draw_rect(Rect2(cx - 7.5, y + 6.5, 15, 11), torso)
		# 大头
		var head := Vector2(cx, y - 4)
		portraits.draw_circle(head, 8.0, Color(0.2, 0.14, 0.1))
		portraits.draw_circle(head, 6.8, Unit.SKIN)
		# 帽子（和场上同款，脸保持干净不画五官）
		match hat:
			"straw":
				portraits.draw_set_transform(head + Vector2(0, -2.5), 0.0, Vector2(1.8, 0.5))
				portraits.draw_circle(Vector2.ZERO, 7.0, Color(0.78, 0.66, 0.36))
				portraits.draw_arc(Vector2.ZERO, 7.0, 0, TAU, 32, Unit.OUTLINE, 1.4)
				portraits.draw_set_transform(head + Vector2(0, -3.5), 0.0, Vector2(1.0, 0.8))
				portraits.draw_circle(Vector2.ZERO, 3.8, Color(0.84, 0.73, 0.44))
				portraits.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"helm":
				portraits.draw_set_transform(head + Vector2(0, -1.5), 0.0, Vector2(1.05, 0.9))
				portraits.draw_circle(Vector2.ZERO, 6.2, Color(0.6, 0.63, 0.68))
				portraits.draw_arc(Vector2.ZERO, 6.2, 0, TAU, 24, Unit.OUTLINE, 1.6)
				portraits.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"hardhat":
				portraits.draw_set_transform(head + Vector2(0, -2.0), 0.0, Vector2(1.15, 0.85))
				portraits.draw_circle(Vector2.ZERO, 5.8, Color(0.85, 0.68, 0.25))
				portraits.draw_arc(Vector2.ZERO, 5.8, 0, TAU, 24, Unit.OUTLINE, 1.6)
				portraits.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				portraits.draw_rect(Rect2(cx - 8.5, head.y - 3.2, 17.0, 2.0), Color(0.85, 0.68, 0.25))
			"hood":
				portraits.draw_circle(head, 7.4, Color(0.34, 0.44, 0.5))
				portraits.draw_circle(head + Vector2(1.0, 1.5), 5.0, Unit.SKIN)
		_portrait_hp(u, cx, y)
	if list.size() > 9:
		portraits.draw_string(ThemeDB.fallback_font, Vector2(616.0 + 9 * 46.0, y + 6),
			"+%d" % (list.size() - 9), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.96, 0.92, 0.8))

func _portrait_hp(u, cx: float, y: float) -> void:
	portraits.draw_rect(Rect2(cx - 15.0, y + 24.0, 30.0, 3.0), Color(0, 0, 0, 0.5))
	portraits.draw_rect(Rect2(cx - 15.0, y + 24.0, 30.0 * clampf(u.hp / u.max_hp, 0.0, 1.0), 3.0), Color(0.3, 0.9, 0.3))

## ================================ 绘制 ================================
func _draw() -> void:
	# ---- 地面（Main 最先画，垫在所有节点底下）----
	draw_rect(Rect2(0, 0, W, H), Color(0.46, 0.69, 0.34))
	for p in GRASS_DARK:
		draw_circle(p, 58.0, Color(0.41, 0.63, 0.29))
	for p in GRASS_LIGHT:
		draw_circle(p, 48.0, Color(0.52, 0.75, 0.38))
	# 土路：基地 -> 巢穴，先粗深边再细浅心
	var path := PackedVector2Array(DIRT_PATH)
	draw_polyline(path, Color(0.42, 0.33, 0.22), 54.0)
	draw_polyline(path, Color(0.56, 0.45, 0.3), 46.0)
	for p in STONES:
		draw_circle(p, 4.0, Color(0.52, 0.44, 0.34))

	# ---- 拖框 ----
	if _dragging:
		var rect := Rect2(_drag_start, get_global_mouse_position() - _drag_start).abs()
		draw_rect(rect, Color(1, 1, 1, 0.08))
		draw_rect(rect, Color(1, 1, 1, 0.7), false, 1.5)
	# ---- 放置设施的幽灵预览 ----
	if _placing_kind != "":
		var p := get_global_mouse_position()
		var half: float = 30.0    # 工地半宽
		var r := Rect2(p - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
		draw_rect(r, Color(0.15, 0.6, 0.55, 0.5))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 1.0)

## ================================ 自测 ================================
## 套件本体已拆到 test_suite.gd。入口和用法不变：
## Godot --headless --path rts-demo -- --test
## 这里用 preload 而不是裸类名 GameTests：headless 首跑未刷新全局类缓存时会认不出 class_name。
const TestSuite := preload("res://test_suite.gd")

func _run_test() -> void:
	await TestSuite.new(self).run()
