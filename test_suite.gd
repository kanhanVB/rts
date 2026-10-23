class_name GameTests
extends RefCounted
## 从 main.gd 拆出来的自测套件（原样搬家，逻辑零改动）。
## 用法：Godot --headless --path rts-demo -- --test
## m = 主场景脚本（main.gd），测试通过它访问游戏状态和真实入口（点选/指令/按钮）。

var m: Node2D

func _init(main: Node2D) -> void:
	m = main

func run() -> void:
	print("[TEST] 开始")
	await m.get_tree().create_timer(1.0).timeout
	_check(is_instance_valid(m.base) and m.base.kind == "base", "基地存在")
	_check(is_instance_valid(m.hive) and m.hive.kind == "hive", "巢穴存在")
	_check(m._player_workers().size() == 3, "开局 3 农民自动上岗")
	_check(m._player_engineers().size() == 1, "开局 1 工程师")

	# 点基地 → 显示数值 + 造农民
	m._point_select(Vector2(170, 560))
	_check(m.selected.size() == 1 and m.selected[0] is Building and m.selected[0].kind == "base", "点选基地")
	await m.get_tree().create_timer(0.1).timeout
	_check(m.info_label.text.contains("基地") and m.info_label.text.contains("血量"), "点建筑显示数值")
	m._on_worker_pressed()
	_check(m._player_workers().size() == 4, "基地造出农民")

	# 工人采一趟矿并入库
	var w: Worker = m._player_workers()[0]
	var n := w._nearest_node("ore")
	_check(n != null, "找到矿点")
	w.command_gather(n)
	var ore0: float = m.economy.ore
	await m.get_tree().create_timer(16.0).timeout
	_check(m.economy.ore > ore0, "工人采矿入库（%.0f -> %.0f）" % [ore0, m.economy.ore])

	# 剑士应能击杀 Goo
	var s := Soldier.new()
	s.setup(false)
	s.position = Vector2(600, 400)
	m.add_child(s)
	var g := Goo.new()
	g.position = Vector2(660, 400)
	m.add_child(g)
	await m.get_tree().create_timer(8.0).timeout
	_check(not is_instance_valid(g), "剑士击杀 Goo")
	_check(is_instance_valid(s), "剑士存活")

	# Goo 啃基地（把工人和工程师都瞬移到远处角落，确保没有单位干扰索敌）
	var corner := 0
	for u in m.get_tree().get_nodes_in_group("player_units"):
		if u is Worker or u is Engineer:
			corner += 1
			u.position = Vector2(640.0 + corner * 60.0, 60.0)
			u.command_move(u.position)
	var g2 := Goo.new()
	g2.position = m.base.position + Vector2(70, 0)
	m.add_child(g2)
	await m.get_tree().create_timer(5.0).timeout
	_check(is_instance_valid(m.base) and m.base.hp < m.base.max_hp, "Goo 啃基地掉血（%.0f/%.0f）" % [m.base.hp, m.base.max_hp])
	if is_instance_valid(g2):
		g2.take_damage(99999.0)    # 清场，防止它干扰后面的工程师测试

	# Goo 会啃工地（把工地标记为已认领，防止远处的工程师跑来接手干扰断言）
	var site_probe := ConstructionSite.new()
	site_probe.position = m.base.position + Vector2(130, 0)
	site_probe.assigned = s
	m.add_child(site_probe)
	var g4 := Goo.new()
	g4.position = site_probe.position + Vector2(60, 0)
	m.add_child(g4)
	await m.get_tree().create_timer(5.0).timeout
	_check(is_instance_valid(site_probe) and site_probe.hp < site_probe.max_hp, "Goo 啃工地掉血（%.0f/%.0f）" % [site_probe.hp, site_probe.max_hp])
	if is_instance_valid(site_probe):
		site_probe.take_damage(99999.0)
	if is_instance_valid(g4):
		g4.take_damage(99999.0)
	await m.get_tree().create_timer(0.3).timeout    # queue_free 是帧末出组，等一拍再数工地

	# 兵营全流程：选中工程师下令建兵营 -> 完工 -> 点兵营出兵
	m.economy.ore = 500.0
	m.economy.wood = 500.0
	var eng0: Engineer = m._player_engineers()[0]
	m._point_select(eng0.position)
	_check(m.selected.size() == 1 and m.selected[0] is Engineer, "选中英雄工程师")
	m._on_barracks_pressed()
	_check(m._placing_kind == "barracks", "选中工程师后进入放置模式")
	m._build_mgr.try_place("barracks", Vector2(520, 400), m._build_eng)
	_check(m.get_tree().get_nodes_in_group("sites").size() == 1, "地图上放置工地")
	var site2 = m.get_tree().get_nodes_in_group("sites")[0]
	_check(site2.assigned == m._build_eng, "工地直接派给下令的工程师")
	await m.get_tree().create_timer(16.0).timeout
	_check(m.barracks_list.size() == 1 and is_instance_valid(m.barracks_list[0]), "工程师建好兵营")
	m._point_select(Vector2(520, 400))
	_check(m.selected.size() == 1 and m.selected[0] is Building and m.selected[0].kind == "barracks", "点选兵营")
	await m.get_tree().create_timer(0.1).timeout
	_check(m.info_label.text.contains("兵营") and m.info_label.text.contains("血量"), "点兵营显示数值")
	var n_units := m.get_tree().get_nodes_in_group("player_units").size()
	m.economy.ore = 500.0
	m.economy.ingot = 100.0    # 剑士要铁锭（加工链产出）
	m._on_sword_pressed()
	_check(m.get_tree().get_nodes_in_group("player_units").size() == n_units + 1, "兵营出剑士")

	# ---- 基建：仓库 = 就近收货点 ----
	m.economy.wood = 500.0
	var eng_wh: Engineer = m._player_engineers()[0]
	m._point_select(eng_wh.position)
	m._on_warehouse_pressed()
	_check(m._placing_kind == "warehouse", "点建仓库进入放置模式")
	m._build_mgr.try_place("warehouse", Vector2(400, 600), eng_wh)
	await m.get_tree().create_timer(16.0).timeout
	_check(m.warehouses_list.size() == 1 and is_instance_valid(m.warehouses_list[0]), "工程师建好仓库")
	var wh: Building = m.warehouses_list[0]
	var w2: Worker = m._player_workers()[0]
	var w2_old := w2.position
	w2.position = wh.position + Vector2(40, 0)
	_check(w2._depot() == wh, "仓库旁的农民把收货点认成仓库")
	w2.position = m.base.position + Vector2(40, 0)
	_check(w2._depot() == m.base, "离仓库远的农民仍认基地")
	w2.position = w2_old

	# ---- 加工链：熔炉（矿石 -> 铁锭）= 流水线：料场 → 工人守炉读条 → 成品扛回仓库才入账 ----
	m.economy.ore = 500.0
	m.economy.wood = 500.0
	var eng_sm: Engineer = m._player_engineers()[0]
	m._point_select(eng_sm.position)
	m._on_smelter_pressed()
	_check(m._placing_kind == "smelter", "点建熔炉进入放置模式")
	m._build_mgr.try_place("smelter", Vector2(300, 480), eng_sm)
	await m.get_tree().create_timer(16.0).timeout
	_check(m.processors_list.size() == 1 and is_instance_valid(m.processors_list[0]), "工程师建好熔炉")
	var sm: Building = m.processors_list[0]
	_check(sm.is_processor() and sm.recipe().in == "ore" and sm.recipe().out == "ingot", "熔炉是加工线：矿石 → 铁锭")
	sm.self_fetch = false    # 先只测送货：工人不许自己去仓库扛
	var w3 := Worker.new()
	w3.position = sm.position + Vector2(50, 0)
	m.add_child(w3)
	w3.carry_kind = "ore"
	# 关键：熔炉不自动抢货。没人点名，原料原样入库，否则木材全变木板就造不出农民了
	_check(w3._depot().kind != "smelter", "不点名的情况下加工厂不抢货")
	w3.set_deliver_to(sm)
	_check(w3._depot() == sm, "右键指定后农民才把矿送去熔炉")
	w3.carry_kind = "wood"
	# 熔炉只吃矿石：就算点名了熔炉，木材也不会被吞掉
	_check(w3._output_kind(sm) == "wood", "熔炉不吃木材，伐木的照样存原料")
	w3.carry_kind = "ore"
	_check(w3._output_kind(sm) == "", "对口的矿石卸进熔炉料场")
	m.economy.ingot = 0.0
	w3.carry_amount = 10.0
	w3.state = Worker.State.TO_BASE
	w3._path = w3._find_path(sm.position)
	w3._path_idx = 0
	await m.get_tree().create_timer(4.0).timeout
	_check(sm.stock_in >= 10.0, "送来的矿石堆进熔炉料场（%.0f）" % sm.stock_in)
	_check(m.economy.ingot == 0.0 and not sm.batch_on and sm.stock_out == 0.0, "没工人守炉：一块铁锭都不出")
	_check(sm.line_status == "no_op", "熔炉状态 = 没人干活（%s）" % sm.line_status)
	# 招工：闲农民右键熔炉 = 进厂干活；最多 2 个；采矿送料的不会被拉进厂
	var op1 := Worker.new()
	op1.position = sm.position + Vector2(-70, 70)
	m.add_child(op1)
	var op2 := Worker.new()
	op2.position = sm.position + Vector2(70, 70)
	m.add_child(op2)
	var op3 := Worker.new()
	op3.position = sm.position + Vector2(0, 100)
	m.add_child(op3)
	await m.get_tree().create_timer(0.1).timeout
	m.selected = [op1, op2, op3]
	m._issue_command(sm.position)
	_check(op1.work_at == sm and op2.work_at == sm and sm.op_count() == 2, "闲农民右键熔炉 = 进厂当工人（%d/2）" % sm.op_count())
	_check(op3.work_at == null and op3.state != Worker.State.OPERATE, "熔炉最多 2 个工人，第 3 个不收")
	_check(w3.work_at == null and w3.deliver_to == sm, "采矿送料的农民照旧送料，不进厂")
	m.selected.clear()
	sm.stock_in = 30.0
	await m.get_tree().create_timer(4.0).timeout
	_check(sm.batch_on or sm.stock_out > 0.0, "工人到岗后开炉读条（进度 %.0f%%，成品 %.0f）" % [sm.batch * 100.0, sm.stock_out])
	var standing: Array = sm.operators.filter(func(o): return o.op_phase == "work")
	_check(not standing.is_empty() and standing[0]._can_yield(), "守线的工人给路过的队友让路（工位在门口，不让会顶死）")
	await m.get_tree().create_timer(14.0).timeout
	_check(sm.made_total >= 10.0, "熔炉一炉一炉出铁锭（累计 %.0f）" % sm.made_total)
	_check(m.economy.ingot >= 10.0, "工人把铁锭扛回仓库才入账（%.0f）" % m.economy.ingot)
	# 自取：料场空了，工人自己去仓库扛矿；仓库留底 30；能关
	w3.set_deliver_to(null)
	w3.auto_assign("ore")    # 不再送料，改回自动交货
	sm.stock_in = 0.0
	sm.self_fetch = true
	m.economy.ore = 200.0
	var f0: float = sm.fetched_total
	await m.get_tree().create_timer(10.0).timeout
	_check(sm.fetched_total > f0, "料场空了工人自己去仓库扛矿（扛了 %.0f）" % (sm.fetched_total - f0))
	m.economy.ore = 20.0
	_check(not sm.can_fetch() and sm.fetch_amount() == 0.0, "仓库矿石不到留底 30 时不自取")
	m.economy.ore = 200.0
	# 选中熔炉：命令卡 招工 / 放人 / 自取
	m._set_selection([sm])
	await m.get_tree().create_timer(0.1).timeout
	var ids: Array = m.commands().map(func(c): return c.id)
	_check(ids.has("hire") and ids.has("fire") and ids.has("fetch_off"), "熔炉命令卡：招工 / 放人 / 自取（%s）" % ",".join(ids))
	_check(m.info_label.text.contains("炼铁") and m.info_label.text.contains("自取"), "点熔炉显示加工线信息")
	m.run_command("fetch_off")
	_check(not sm.self_fetch and not sm.can_fetch(), "自取按钮能关：关了就不动仓库的矿")
	m.run_command("fetch_on")
	var last_op: Worker = sm.operators.back()
	m.run_command("fire")
	_check(sm.op_count() == 1 and last_op.work_at == null and last_op.state != Worker.State.OPERATE, "放人：最后来的工人离岗（剩 %d）" % sm.op_count())
	_check(is_instance_valid(last_op.node_target) and last_op.node_target.kind == "ore", "放走的工人回去采矿")
	m.run_command("hire")
	_check(sm.op_count() == 2 and op3.work_at == sm, "招工：先叫最近的闲农民（%d/2）" % sm.op_count())
	m._deselect_all()
	# 工位就在门口、人挡着房子：选农民右键点到守线工人身上 = 点他的熔炉
	var fired: Worker = m.fire_operator(sm)
	var keep: Worker = sm.operators[0]
	keep.position = sm.work_spot(keep)
	var wpick := Worker.new()
	wpick.position = sm.position + Vector2(-90, 100)
	m.add_child(wpick)
	await m.get_tree().process_frame
	m.selected = [wpick]
	m._command_at(keep.position + Vector2(0, -8))
	_check(wpick.work_at == sm and wpick.state == Worker.State.OPERATE, "右键点到门口守线的工人身上 = 进他的熔炉干活")
	m.selected = []
	wpick.command_stop()
	wpick.queue_free()
	# 基地集结点设在熔炉上：新农民出来直接进厂（人满了就在门口等）
	m.set_rally(m.base, sm.position)
	_check(m.base.rally_node == sm, "基地集结点能设到熔炉上")
	await m.get_tree().process_frame
	var nops: int = sm.op_count()
	m.on_trained(m.base, "worker")
	var rook: Worker = sm.operators.back()
	_check(sm.op_count() == nops + 1 and rook != keep and rook.state == Worker.State.OPERATE, "集结点在熔炉：新农民出来直接进厂（%d/2）" % sm.op_count())
	m.base.rally_node = null
	m.base.rally = Vector2.INF
	rook.command_stop()
	rook.queue_free()
	fired.cancel_orders()
	fired.command_operate(sm)
	# 自取只把料场补到 FETCH_FILL：多了是把仓库的矿压在门口（开局造不了农民/兵）
	var sin0: float = sm.stock_in
	sm.stock_in = Building.FETCH_FILL
	_check(sm.fetch_amount() == 0.0, "自取只补到 %d（料场有 %d 就不再从仓库扛）" % [int(Building.FETCH_FILL), int(Building.FETCH_FILL)])
	sm.stock_in = sin0
	# 闲着手里攥着半车成品（守线工人被叫走时扛着的）：右键仓库就去交，别一直不入账
	var wp := Worker.new()
	wp.position = wh.position + Vector2(110, 0)
	m.add_child(wp)
	await m.get_tree().process_frame
	wp.carry_kind = "ingot"
	wp.carry_amount = 5.0
	wp.set_deliver_to(wh)
	await m.get_tree().create_timer(4.0).timeout
	_check(wp.carry_amount < 0.5, "闲着手里有半车铁锭，右键仓库就去交（手上还剩 %.0f）" % wp.carry_amount)
	wp.queue_free()

	# ---- 帝国式操作：右键指定交货点、右键资源点派活、换工种先交货 ----
	var plank_before: float = m.economy.plank
	var wood_before: float = m.economy.wood
	var ws := Worker.new()
	ws.position = wh.position + Vector2(30, 0)
	m.add_child(ws)
	ws.carry_kind = "wood"
	ws.carry_amount = 10.0
	ws.state = Worker.State.TO_BASE
	ws._path = ws._find_path(wh.position)
	ws._path_idx = 0
	await m.get_tree().create_timer(4.0).timeout
	_check(m.economy.wood >= wood_before + 10.0 and m.economy.plank == plank_before,
		"自动交货的木材原样入库，没被加工掉（+%d木）" % int(m.economy.wood - wood_before))
	# 采矿的农民右键熔炉 = 改送矿到熔炉料场（走真实的右键指令入口）
	w3.auto_assign("ore")
	m.selected = [w3]
	m._issue_command(sm.position)
	_check(w3.deliver_to == sm and w3.work_at == null, "采矿的农民右键熔炉 = 指派交货点（送料）")
	# 改回去也只要右键仓库，不需要按钮
	m._issue_command(wh.position)
	_check(w3.deliver_to == wh, "右键仓库就改送仓库（原料入库）")
	w3.set_deliver_to(null)
	_check(w3.deliver_to == null, "清空指派后回到自动")
	# 框选多个农民右键同一个资源点 = 一起去（帝国式批量派活）
	var wg := Worker.new()
	wg.position = m.base.position + Vector2(60, 0)
	m.add_child(wg)
	var ore_node: ResNode = w3._nearest_node("ore")
	m.selected = [w3, wg]
	m._issue_command(ore_node.position)
	_check(w3.node_target == ore_node and wg.node_target == ore_node,
		"框选多个农民右键同一个矿点 = 一起去采矿")
	# 换工种：扛着木材被派去挖矿，得先把木材交回仓库，不能把木材记成矿石
	var wood_before2: float = m.economy.wood
	w3.carry_kind = "wood"
	w3.carry_amount = 10.0
	m.selected = [w3]
	m._issue_command(ore_node.position)
	_check(w3.state == Worker.State.TO_BASE, "扛着木材改去挖矿 → 先回仓交货")
	await m.get_tree().create_timer(5.0).timeout
	_check(m.economy.wood >= wood_before2 + 10.0, "旧货按原样入库（+%d木）" % int(m.economy.wood - wood_before2))
	_check(w3.carry_kind == "ore" and w3.carry_amount < 10.0, "到岗后改认矿石，账目没串")
	m.selected.clear()
	# 熔炉被打爆：工人自动离岗，不会对着废墟发呆
	var op_a: Worker = sm.operators[0]
	sm.take_damage(sm.hp + 1.0)
	await m.get_tree().create_timer(0.3).timeout
	_check(op_a.work_at == null and op_a.state != Worker.State.OPERATE, "熔炉被拆，工人自动离岗")
	w3.queue_free()
	wg.queue_free()
	ws.queue_free()
	for o in [op1, op2, op3]:
		if is_instance_valid(o):
			o.queue_free()

	# 工程师的自卫攻击
	var eng: Engineer = m._player_engineers()[0]
	var g3 := Goo.new()
	g3.position = eng.position + Vector2(40, 0)
	m.add_child(g3)
	await m.get_tree().create_timer(12.0).timeout
	_check(not is_instance_valid(g3), "工程师击杀 Goo")
	_check(is_instance_valid(eng), "工程师存活")

	# 工程师阵亡后自动复活
	eng.take_damage(9999.0)
	await m.get_tree().create_timer(1.0).timeout
	_check(m._player_engineers().size() == 0, "工程师阵亡后不在场")
	await m.get_tree().create_timer(16.0).timeout
	_check(m._player_engineers().size() == 1, "工程师 15 秒后自动复活")

	# 右键指挥工程师移动（move_order 优先，到点前不接活）
	var eng2: Engineer = m._player_engineers()[0]
	var dest := Vector2(500, 600)
	eng2.command_move(dest)
	_check(eng2.move_order, "工程师接到移动指令")
	await m.get_tree().create_timer(9.0).timeout
	_check(is_instance_valid(eng2) and eng2.position.distance_to(dest) < 15.0,
		"工程师走到位（距目标 %.0fpx）" % eng2.position.distance_to(dest))

	# 群体移动：同一目标点会环形散开，挤不进去的就地停下（不原地抽搐）
	var crowd: Array = []
	var ci := 0
	for u in m.get_tree().get_nodes_in_group("player_units"):
		if u is Worker or u is Engineer:
			u.position = Vector2(560.0 + ci * 24.0, 240.0)
			u.command_move(u.position)
			crowd.append(u)
			ci += 1
	var dest2 := Vector2(640, 200)    # 河北岸可达点，避免跨河/深水干扰群体移动断言
	for u in crowd:
		u.command_move(dest2)
	await m.get_tree().create_timer(6.0).timeout
	var worst := 0.0
	for u in crowd:
		if is_instance_valid(u):
			worst = maxf(worst, u.position.distance_to(dest2))
	_check(worst < 60.0, "群体移动都到位（最远 %.0fpx）" % worst)

	# 下方信息栏：点选 = 数值面板，框选 = 头像模式
	var sinfo := Soldier.new()
	sinfo.setup(false)
	sinfo.position = Vector2(400, 400)
	m.add_child(sinfo)
	m._point_select(Vector2(400, 400))
	_check(m.selected.size() == 1, "点选到剑士")
	await m.get_tree().create_timer(0.1).timeout    # 等 _process 跑一拍再读信息栏
	_check(m.info_label.visible and m.info_label.text.contains("剑士") and m.info_label.text.contains("护甲 2")
		and m.info_label.text.contains("攻击 12") and m.info_label.text.contains("移速 95") and m.info_label.text.contains("射程 30"),
		"信息栏显示单位数值（血量/护甲/攻击/移速/射程）")
	m._box_select(Rect2(380, 340, 320, 180))    # 兵营出过的剑士打过架会漂位，框大一点
	await m.get_tree().create_timer(0.1).timeout
	_check(m.selected.size() >= 2, "框选到多个单位")
	_check(m.info_label.text.contains("已选中"), "框选后切到头像/计数模式")
	sinfo.take_damage(99999.0)

	# 点敌人 = 查看属性（不能指挥）
	var g5 := Goo.new()
	g5.position = Vector2(700, 620)    # 别贴着仓库，否则点选会先命中建筑
	m.add_child(g5)
	m._point_select(Vector2(700, 620))
	_check(m.selected.is_empty() and m.inspected == g5, "点敌人进入查看模式")
	await m.get_tree().create_timer(0.1).timeout
	_check(m.info_label.text.contains("Goo") and m.info_label.text.contains("攻击 7"),
		"信息栏显示敌人数值")
	g5.take_damage(99999.0)
	await m.get_tree().create_timer(0.3).timeout

	# 镜头缩放后点选仍准确：用 canvas transform 正变换造一个屏幕点，再逆变换回来验证
	m.cam.zoom = Vector2(1.5, 1.5)
	m.cam.position = Vector2(300, 300)
	var world_anchor := Vector2(600, 400)
	var screen_pt: Vector2 = m.cam.get_canvas_transform() * world_anchor    # 世界 → 屏幕
	var world_back: Vector2 = m._to_world(screen_pt)                         # 屏幕 → 世界（往返）
	_check(world_back.distance_to(world_anchor) < 0.5,
		"缩放后坐标转换往返一致（误差 %.1fpx）" % world_back.distance_to(world_anchor))
	m.cam.zoom = Vector2.ONE
	m.cam.position = Vector2(m.W / 2.0, m.H / 2.0)

	# 攻击指令有距离门槛：太远自动转成移动
	var eng3: Engineer = m._player_engineers()[0]
	eng3.position = Vector2(200, 200)
	eng3.command_move(eng3.position)
	var g6 := Goo.new()
	g6.position = Vector2(500, 200)    # 离工程师 300px，超出他的 70px 指挥圈
	m.add_child(g6)
	m._point_select(Vector2(200, 200))
	m._issue_command(g6.position)
	_check(eng3.move_order and eng3.attack_target == null, "远处敌人只下达移动指令")
	g6.take_damage(99999.0)

	# 镜头缩放：范围钳制在 [0.6, 1.6]
	var z0: float = m.cam.zoom.x
	m._zoom_camera(10.0)
	_check(m.cam.zoom.x <= m.CAM_MAX_ZOOM + 0.01, "镜头缩放有上限（%.2f）" % m.cam.zoom.x)
	m._zoom_camera(0.001)
	_check(m.cam.zoom.x >= m.CAM_MIN_ZOOM - 0.01, "镜头缩放有下限（%.2f）" % m.cam.zoom.x)
	m.cam.zoom = Vector2(z0, z0)

	# 编队：存队 + 召回
	var eng4: Engineer = m._player_engineers()[0]
	eng4.position = Vector2(300, 500)
	eng4.command_move(eng4.position)
	m._point_select(Vector2(300, 500))
	m._save_control_group(0)
	_check(m.control_groups.size() >= 1 and m.control_groups[0].size() == 1, "Ctrl+数字 存编队")
	m._clear_inspect()
	for ss in m.selected:
		ss.selected = false
	m.selected.clear()
	m._recall_control_group(0)
	_check(m.selected.size() == 1 and m.selected[0] == eng4, "数字键召回编队")

	# A 移动：剑士接到攻击移动指令，走到半路遇敌会自动索敌开打
	var s2 := Soldier.new()
	s2.setup(false)
	s2.position = Vector2(200, 300)
	m.add_child(s2)
	var dest3 := Vector2(600, 300)
	s2.command_attack_move(dest3)
	_check(s2._amove_dest == dest3, "剑士接到 A 移动指令")
	var g7 := Goo.new()
	g7.position = Vector2(420, 300)    # 正好挡在 A 移动路线上
	m.add_child(g7)
	await m.get_tree().create_timer(3.0).timeout
	# 剑士应已锁定敌人（attack_target 非空）或仍在 A 移动目的地推进中
	_check(not is_instance_valid(g7) or (s2.attack_target == g7),
		"A 移动途中遇敌自动开打")

	# 战斗贴脸互殴不被分离力顶开（双方站定输出，不来回抖）
	var s3 := Soldier.new()
	s3.setup(false)
	s3.position = Vector2(640, 500)
	m.add_child(s3)
	var g8 := Goo.new()
	g8.position = Vector2(660, 500)
	m.add_child(g8)
	s3.command_attack(g8)
	g8.attack_target = s3
	var sp3 := s3.position
	await m.get_tree().create_timer(1.5).timeout
	if is_instance_valid(s3):
		_check(s3.position.distance_to(sp3) < 12.0, "战斗贴脸单位不被分离力顶开（偏移 %.0fpx）" % s3.position.distance_to(sp3))
	s3.take_damage(99999.0)
	if is_instance_valid(g8):
		g8.take_damage(99999.0)

	s2.take_damage(99999.0)
	if is_instance_valid(g7):
		g7.take_damage(99999.0)

	# ---- 回归测试：本轮优化修掉的行为 bug ----
	# A 移动打完一仗要接着赶路（以前打完原地站死）
	var s4 := Soldier.new()
	s4.setup(false)
	s4.position = Vector2(200, 150)
	m.add_child(s4)
	var dest4 := Vector2(700, 150)
	s4.command_attack_move(dest4)
	var g9 := Goo.new()
	g9.position = Vector2(350, 150)
	m.add_child(g9)
	g9.hp = 10.0
	await m.get_tree().create_timer(10.0).timeout
	_check(not is_instance_valid(g9), "A 移动途中的 Goo 被打掉")
	_check(s4.position.distance_to(dest4) < 60.0, "A 移动打完继续走到目的地（距终点 %.0fpx）" % s4.position.distance_to(dest4))
	s4.take_damage(99999.0)

	# 普通右键移动不被沿路敌人勾走（撤退要撤得下来）
	var s5 := Soldier.new()
	s5.setup(false)
	s5.position = Vector2(200, 200)    # 走 y=200 这条线：避开前面测试盖的兵营和矿点、树，免得绕路导致误判
	m.add_child(s5)
	var g10 := Goo.new()
	g10.position = Vector2(450, 240)
	m.add_child(g10)
	s5.command_move(Vector2(700, 200))
	await m.get_tree().create_timer(3.0).timeout
	_check(s5.position.x > 470.0, "普通移动无视沿路敌人继续走（x=%.0f）" % s5.position.x)
	s5.take_damage(99999.0)
	if is_instance_valid(g10):
		g10.take_damage(99999.0)

	# 工程师自卫必须贴脸才能锤到（以前缩进错位，70px 外隔空就锤中）
	var eng5: Engineer = m._player_engineers()[0]
	eng5.position = Vector2(400, 600)
	eng5.command_move(eng5.position)
	await m.get_tree().process_frame
	var g11 := Goo.new()
	g11.position = eng5.position + Vector2(60, 0)
	m.add_child(g11)
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	_check(is_instance_valid(g11) and g11.hp >= g11.max_hp, "工程师 60px 外不会隔空锤中")
	await m.get_tree().create_timer(2.0).timeout
	_check(not is_instance_valid(g11) or g11.hp < g11.max_hp, "工程师贴上去后能锤到")
	if is_instance_valid(g11):
		g11.take_damage(99999.0)

	# 多人同采一处：总采集量不超过储量
	var rn := ResNode.new()
	rn.kind = "ore"
	rn.amount = 2.0
	rn.position = Vector2(820, 120)
	m.add_child(rn)
	var wa := Worker.new()
	var wb := Worker.new()
	for wx in [wa, wb]:
		wx.position = rn.position + Vector2(8, 0)
		m.add_child(wx)
		wx.node_target = rn
		wx.carry_kind = "ore"
		wx.state = Worker.State.GATHERING
	await m.get_tree().create_timer(1.0).timeout
	var got := wa.carry_amount + wb.carry_amount
	_check(got <= 2.001 and got > 1.9, "同采一处不超采（储量 2，实采 %.3f）" % got)
	wa.take_damage(99999.0)
	wb.take_damage(99999.0)

	# ---- 产能面板：流水能算出速率，瓶颈说得出来 ----
	m.economy._log.clear()
	m.economy.add("ore", 10.0)
	_check(m.economy.rate("ore") > 0.0, "账本流水能算出矿石速率（%.2f/秒）" % m.economy.rate("ore"))
	_check(m.economy.rate("plank") == 0.0, "没入过账的资源速率为 0")
	m._update_panel()
	_check(m.panel_label.text.contains("产能"), "产能面板显示标题")
	_check(m.panel_label.text.contains("矿石"), "产能面板列出矿石")
	_check(m._bottleneck().length() > 0, "瓶颈提示有话说（%s）" % m._bottleneck())

	# ---- 连续下两个建造指令：第一个不能被"认领着却不干活"卡死 ----
	# 放在最后跑：会往场上加两个仓库 + 等 34 秒，别干扰前面的战斗断言
	m.economy.ore = 500.0
	m.economy.wood = 500.0
	var eng_c: Engineer = m._player_engineers()[0]
	m._point_select(eng_c.position)
	m._on_warehouse_pressed()
	m._build_mgr.try_place("warehouse", Vector2(300, 345), eng_c)    # 别压着 (274,276) 那棵树
	await m.get_tree().create_timer(0.2).timeout
	m._point_select(eng_c.position)
	m._on_warehouse_pressed()
	m._build_mgr.try_place("warehouse", Vector2(700, 360), eng_c)    # 别压着 (674,296) 那块矿
	var sites_now := m.get_tree().get_nodes_in_group("sites")
	_check(sites_now.size() == 2, "两个工地都放到了地图上")
	var claimed := 0
	for st in sites_now:
		if st.assigned != null:
			claimed += 1
	_check(claimed == 1, "工程师只认领一个，另一个保持无主（不会被占着不干）")
	var wh_before: int = m.warehouses_list.size()
	await m.get_tree().create_timer(34.0).timeout
	_check(m.warehouses_list.size() == wh_before + 2, "连续两个建造指令都能完工（%d -> %d）" % [wh_before, m.warehouses_list.size()])

	# ---- 放置规则：不能压矿/树、不能叠工地 ----
	var ore_n = null
	for rn2 in m.get_tree().get_nodes_in_group("res_nodes"):
		if rn2.kind == "ore":
			ore_n = rn2
			break
	if ore_n != null:
		_check(m._build_mgr.placement_error(ore_n.position + Vector2(20, 0)) != "", "工地不能压在矿上")
	var probe := ConstructionSite.new()
	probe.position = Vector2(820, 520)
	probe.assigned = m._player_engineers()[0]
	m.add_child(probe)
	_check(m._build_mgr.placement_error(Vector2(850, 520)) != "", "工地不能叠在别的工地上")
	probe.queue_free()

	# ---- 城堡箭塔：Goo 进射程会挨箭 ----
	var gt := Goo.new()
	gt.position = m.base.position + Vector2(140, -60)
	m.add_child(gt)
	gt.command_move(gt.position)
	await m.get_tree().create_timer(1.5).timeout
	_check(not is_instance_valid(gt) or gt.hp < gt.max_hp, "城堡箭塔射击射程内的 Goo")
	if is_instance_valid(gt):
		gt.take_damage(99999.0)

	# ---- 波次 Goo 沿土路行军：路边远处的建筑不会被拐过去啃 ----
	var gl := Goo.new()
	gl.position = m.road()[m.road().size() - 1] + Vector2(-40, 60)
	m.add_child(gl)
	gl.start_lane(m.road())
	var max_off := 0.0
	for i in 20:
		await m.get_tree().create_timer(0.25).timeout
		if not is_instance_valid(gl):
			break
		var rd: Array = m.road()
		var off := INF
		for j in rd.size() - 1:
			off = minf(off, Geometry2D.get_closest_point_to_segment(gl.position, rd[j], rd[j + 1]).distance_to(gl.position))
		max_off = maxf(max_off, off)
	_check(is_instance_valid(gl) and gl.lane and max_off < 90.0, "波次 Goo 沿土路行军（最远偏离 %.0fpx）" % max_off)
	if is_instance_valid(gl):
		gl.take_damage(99999.0)

	await _td_tests()

	# ---- 回归：第二轮查 bug 修过的问题 ----
	# 工程师同一帧挨两下致死，只能复活一个
	var eng_list: Array = m._player_engineers()
	if not eng_list.is_empty():
		var timers0: int = m.respawn_timers.size()
		eng_list[0].take_damage(99999.0)
		eng_list[0].take_damage(99999.0)
		_check(m.respawn_timers.size() == timers0 + 1, "同帧两次致死只排一次复活（%d -> %d）" % [timers0, m.respawn_timers.size()])
	# 农民要去的矿被采空：换新矿点要重新寻路，不能先跑到旧点
	var rw: Worker = null
	for u in m._player_workers():
		rw = u
		break
	var ores: Array = m.get_tree().get_nodes_in_group("res_nodes").filter(func(n): return n.kind == "ore" and not n.is_queued_for_deletion())
	if rw != null and ores.size() >= 2:
		ores.sort_custom(func(a, b): return a.position.distance_to(rw.position) > b.position.distance_to(rw.position))
		var far_ore: ResNode = ores[0]
		rw.carry_amount = 0.0    # 空手、自动交货，排除"先回去交别的货"的分支
		rw.carry_kind = "ore"
		rw.deliver_to = null
		rw.command_gather(far_ore)
		await m.get_tree().create_timer(0.3).timeout
		far_ore.queue_free()
		await m.get_tree().create_timer(0.1).timeout
		var last: Vector2 = rw._path[rw._path.size() - 1] if rw._path.size() > 0 else rw.node_target.position
		_check(is_instance_valid(rw.node_target) and last.distance_to(rw.node_target.position) < 40.0,
			"矿点被采空换矿后重新寻路（状态 %d，路径终点离新矿 %.0fpx）" % [rw.state, last.distance_to(rw.node_target.position) if is_instance_valid(rw.node_target) else -1.0])
	# 选中基地右键地面：建筑不会走路，跳过（以前报 command_move 不存在）
	m._point_select(m.base.position)
	m._issue_command(m.base.position + Vector2(160, 0))
	_check(m.selected.size() == 1 and m.selected[0] == m.base, "选中基地右键地面不出错")
	# 远处右键巢穴：剑士走过去要真的打，不能站在脚下发呆
	var hs := Soldier.new()
	hs.setup(false)
	hs.position = m.hive.position + Vector2(-300, 170)
	m.add_child(hs)
	await m.get_tree().create_timer(0.1).timeout
	m.selected = [hs]
	m._issue_command(m.hive.position)
	var hive_hp0: float = m.hive.hp
	await m.get_tree().create_timer(7.0).timeout
	_check(is_instance_valid(m.hive) and m.hive.hp < hive_hp0, "远处右键巢穴，剑士走过去开打（%.0f -> %.0f）" % [hive_hp0, m.hive.hp])
	if is_instance_valid(hs):
		hs.queue_free()    # 别在后面的测试里把巢穴拆了

	await _aoe_tests()
	await _camp_tests()

	# 拆巢穴触发胜利
	m.hive.take_damage(99999.0)
	await m.get_tree().create_timer(0.5).timeout
	_check(m.game_state == "win", "拆巢穴触发胜利")

	if m._fail == 0:
		print("TEST PASS")
		m.get_tree().quit(0)
	else:
		print("TEST FAIL（%d 项未过）" % m._fail)
		m.get_tree().quit(1)

## ---- 塔防：箭塔 / 三种怪 / 波次配表 / 提前叫波 ----
func _td_tests() -> void:
	# 品种数值：窜窜快又脆、岩壳慢又厚带甲
	var st := {}
	for t in ["goo", "runner", "brute"]:
		var e := Goo.make(t)
		m.add_child(e)
		st[t] = {"hp": e.max_hp, "spd": e.speed, "armor": e.armor, "siege": e.siege, "key": e._art_key()}
		e.queue_free()
	_check(st.runner.spd > st.goo.spd * 1.6 and st.runner.hp < st.goo.hp, "窜窜比 Goo 快得多、血更少（速度 %.0f vs %.0f）" % [st.runner.spd, st.goo.spd])
	_check(st.brute.hp >= st.goo.hp * 4.0 and st.brute.armor > 0.0 and st.brute.siege > 1.0 and st.brute.spd < st.goo.spd,
		"岩壳又慢又厚、带甲、拆房加成（血 %.0f 甲 %.0f）" % [st.brute.hp, st.brute.armor])
	_check(st.runner.key == "runner" and st.brute.key == "brute", "三种怪各用各的贴图")
	var ab := Goo.make("brute")
	ab.position = Vector2(-300, -300)
	m.add_child(ab)
	var ahp: float = ab.hp
	ab.take_damage(9.0)
	var d9: float = ahp - ab.hp
	ab.take_damage(2.0)
	_check(is_equal_approx(d9, 5.0) and is_equal_approx(ahp - ab.hp, 6.0), "岩壳护甲 4：9 点伤害只吃 5、小伤害保底 1")
	ab.queue_free()

	# 工程师命令卡有箭塔；箭塔不许压土路（不传品种的老接口不受影响）
	var engs: Array = m._player_engineers()
	if not engs.is_empty():
		m._set_selection([engs[0]])
		var tc: Array = m.commands().filter(func(c): return c.id == "tower")
		_check(tc.size() == 1 and tc[0].key == "T", "工程师命令卡 T = 箭塔")
	var road_ok := false
	for rp in m.road():
		if m._build_mgr.placement_error(rp) == "":
			road_ok = m._build_mgr.placement_error(rp, "tower").contains("土路")
			break
	_check(road_ok, "箭塔不能盖在土路上（要盖在路边）")

	# 找一块空地测箭塔：塔前（或塔后）60px 一段横着 230px 的土路，路边够不着别的房子/工地/人，射程里没别的怪
	var spot = null
	var side := 60.0
	for y in range(120, int(m.H) - 120, 40):
		for x in range(200, int(m.W) - 200, 40):
			for sd in [60.0, -60.0]:
				if spot != null:
					break
				var p := Vector2(x, y)
				if m._build_mgr.placement_error(p, "tower") != "":
					continue
				var la: Vector2 = p + Vector2(-100, sd)
				var lb: Vector2 = p + Vector2(130, sd)
				var ok: bool = la.y > 70.0 and la.y < m.H - 50.0
				for k in 8:
					if m.area_blocked(la.lerp(lb, k / 7.0), 22.0):
						ok = false
				for grp in ["buildings", "sites", "player_units", "enemies", "res_nodes"]:
					for n in m.get_tree().get_nodes_in_group(grp):
						if not ok or not is_instance_valid(n):
							continue
						var dl: float = Geometry2D.get_closest_point_to_segment(n.position, la, lb).distance_to(n.position)
						if grp == "buildings" and n.team != 0:
							ok = dl > n.size + 10.0    # 巢穴脚下的路点会被 start_lane 剔掉，路就断了
						elif grp == "buildings" or grp == "sites":
							ok = dl > Goo.LANE_AGGRO + n.size * 0.5 + 8.0
						elif grp == "player_units":
							ok = dl > 120.0
						elif grp == "res_nodes":
							ok = dl > 50.0 and n.position.distance_to(p) > 56.0    # 矿/树挡路，路过时别被挤开
						else:
							ok = n.position.distance_to(p) > 300.0
				if ok:
					spot = p
					side = sd
	_check(spot != null, "找到测箭塔的空地 %s" % [spot])
	if spot == null:
		return
	var tw: Building = m._build_mgr.add_building("tower", spot, 0)
	var lane_pts := [spot + Vector2(130, side), spot + Vector2(-100, side)]    # 土路数据是基地端在前，怪反着走

	# 普通 Goo 从塔下走过：不啃塔，只挨射，被射死记到塔的击杀上
	var gp := Goo.make("goo")
	gp.position = lane_pts[1]
	m.add_child(gp)
	gp.max_hp = 36.0    # 4 箭死：2.5 秒时还活着，走到路尽头前一定死
	gp.hp = 36.0
	gp.hunt_r = 0.0     # 别被路过的农民勾走（这里只测它理不理塔）
	gp.start_lane(lane_pts)
	await m.get_tree().create_timer(2.5).timeout
	_check(is_instance_valid(gp) and gp.hp < gp.max_hp, "箭塔射路过的 Goo")
	_check(is_instance_valid(gp) and gp.position.x - lane_pts[1].x > 80.0 and is_equal_approx(tw.hp, tw.max_hp),
		"普通 Goo 打不着塔：从塔下走过（走了 %.0fpx，塔血 %.0f/%.0f）" % [gp.position.x - lane_pts[1].x if is_instance_valid(gp) else -1.0, tw.hp, tw.max_hp])
	for i in 20:
		if not is_instance_valid(gp) or gp.dead:
			break
		await m.get_tree().create_timer(0.25).timeout
	_check((not is_instance_valid(gp) or gp.dead) and tw.kills >= 1, "箭塔射死 Goo 记击杀（%d）" % tw.kills)

	# 岩壳在路上隔老远盯上箭塔，过去拆（拆房伤害 ×2.5）
	var bp := Goo.make("brute")
	bp.position = lane_pts[1]
	m.add_child(bp)
	bp.hunt_r = 0.0
	bp.start_lane(lane_pts)
	var thp0: float = tw.hp
	await m.get_tree().create_timer(6.0).timeout
	_check(tw.hp <= thp0 - 14.0 * 2.0, "岩壳离开土路去拆箭塔（塔血 %.0f -> %.0f）" % [thp0, tw.hp])
	if is_instance_valid(bp):
		bp.take_damage(99999.0)

	# 窜窜在路上不理路边的房子，一路冲
	var wh: Building = m._build_mgr.add_building("warehouse", spot + Vector2(90, side - signf(side) * 90.0), 0)    # 路边 90px
	var rp2 := Goo.make("runner")
	rp2.position = lane_pts[1]
	m.add_child(rp2)
	rp2.max_hp = 300.0
	rp2.hp = 300.0
	rp2.start_lane(lane_pts)
	await m.get_tree().create_timer(1.5).timeout
	_check(is_instance_valid(rp2) and rp2.position.x - lane_pts[1].x > 120.0 and is_equal_approx(wh.hp, wh.max_hp),
		"窜窜不理路边房子，一路冲（1.5 秒跑了 %.0fpx）" % (rp2.position.x - lane_pts[1].x if is_instance_valid(rp2) else -1.0))
	if is_instance_valid(rp2):
		rp2.take_damage(99999.0)
	wh.take_damage(99999.0)

	# 升级：要木板 + 铁锭；二级两名弓手、射程更远、加血；满级不能再升
	m._point_select(tw.position + Vector2(0, -20))
	_check(m.selected.size() == 1 and m.selected[0] == tw and m.commands().any(func(c): return c.id == "upgrade"), "选中箭塔，命令卡有升级")
	m.economy.plank = 0.0
	m.economy.ingot = 0.0
	_check(not m.upgrade_tower(tw) and tw.level == 1, "没木板铁锭升不了级")
	m.economy.plank = float(Economy.COST_TOWER_UP.plank)
	m.economy.ingot = float(Economy.COST_TOWER_UP.ingot)
	var mhp0: float = tw.max_hp
	_check(m.upgrade_tower(tw) and tw.level == 2 and m.economy.plank < 0.5 and m.economy.ingot < 0.5, "升二级扣木板 + 铁锭")
	var s2: Dictionary = tw.tower_stats()
	_check(int(s2.archers) == 2 and s2.range > Building.TOWER_LV[1].range and s2.dmg > Building.TOWER_LV[1].dmg and tw.max_hp > mhp0,
		"二级箭塔：2 弓手、射程 %d、每箭 %d、血 %.0f" % [int(s2.range), int(s2.dmg), tw.max_hp])
	_check(not tw.can_upgrade() and not m.commands().any(func(c): return c.id == "upgrade"), "满级不能再升")
	tw.take_damage(99999.0)

	# 波次：十波配表、文字、提前叫波奖励、一只只放（用一个不接主循环的波次管理器，不影响主局）
	_check(WaveManager.WAVES.size() == WaveManager.MAX_WAVES and WaveManager.wave_text(4) == "Goo×4 岩壳×1 窜窜×3",
		"波次配表（第 4 波：%s）" % WaveManager.wave_text(4))
	var wm := WaveManager.new()
	m.add_child(wm)
	wm.remove_from_group("wave_mgr")
	wm.wave_timer = 20.0
	var ore0: float = m.economy.ore
	var n := wm.call_early()
	_check(n == 12 and is_equal_approx(m.economy.ore - ore0, 12.0) and wm.wave == 1 and wm.spawning() and is_equal_approx(wm.wave_timer, WaveManager.WAVE_INTERVAL),
		"提前 20 秒叫波：奖励 12 矿 12 木，第 1 波开始放怪")
	var before: Array = m.get_tree().get_nodes_in_group("enemies").duplicate()
	wm.update(0.01)
	var mid_cnt: int = wm._queue.size()
	wm.update(0.3)
	var mid_cnt2: int = wm._queue.size()
	wm.update(0.4)
	var fresh: Array = m.get_tree().get_nodes_in_group("enemies").filter(func(e): return not before.has(e))
	_check(mid_cnt == 1 and mid_cnt2 == 1 and not wm.spawning() and fresh.size() == 2 and fresh.all(func(e): return e.lane),
		"一波怪隔 0.6 秒一只只出、沿土路走（%d 只）" % fresh.size())
	wm.wave = 5
	var big: Goo = wm._spawn("brute")
	_check(big != null and is_equal_approx(big.max_hp, Goo.TYPES.brute.hp * 1.24), "后面的波血量加成（第 5 波 ×1.24）")
	if big != null:
		fresh.append(big)
	for e in fresh:
		if is_instance_valid(e):
			e.take_damage(99999.0)
	wm.queue_free()
	_check(m._wave_mgr.wave == 0 and not m._wave_mgr.spawning(), "主局波次没被测试动过")

## ---- 帝国时代式操作：生产队列 / 选择 / 热键 / 删除 / 闲置 / 占格 / 随机图 ----
func _aoe_tests() -> void:
	var tree := m.get_tree()
	m._deselect_all()
	# 生产队列：先扣钱再排队，取消全额退；集结点
	m.train_scale = 1.0
	m.economy.wood += 200.0
	m.select_base()
	var wood0: float = m.economy.wood
	var nw0: int = m._player_workers().size()
	m.run_hotkey("Q")
	m.run_hotkey("Q")
	_check(m.base.queue.size() == 2 and absf(m.economy.wood - (wood0 - 60.0)) < 0.5,
		"Q 排两个农民进基地队列，先扣钱（队列 %d，木 %.0f→%.0f）" % [m.base.queue.size(), wood0, m.economy.wood])
	m.cancel_train(m.base, 1)
	_check(m.base.queue.size() == 1 and absf(m.economy.wood - (wood0 - 30.0)) < 0.5, "取消队列里的第 2 个，全额退钱")
	var rally: Vector2 = m.base.position + Vector2(170, -30)
	m.set_rally(m.base, rally)
	await tree.create_timer(1.0).timeout
	_check(m._player_workers().size() == nw0, "读条没完不出人")
	await tree.create_timer(float(m.TRAIN.worker.time)).timeout
	var fresh: Worker = null
	for w in m._player_workers():
		if w.move_target.distance_to(m.open_point(rally)) < 30.0:
			fresh = w
	_check(m._player_workers().size() == nw0 + 1 and fresh != null, "读条完出 1 个农民，走向集结点")
	m.base.rally = Vector2.INF
	m.base.rally_node = null
	m.train_scale = 0.0

	# 选择：Shift+左键加选/减选、选同类、Esc 取消选中
	var s1 := Soldier.new()
	s1.setup(false)
	s1.position = Vector2(420, 640)
	m.add_child(s1)
	var s2 := Soldier.new()
	s2.setup(false)
	s2.position = Vector2(470, 640)
	m.add_child(s2)
	await tree.create_timer(0.1).timeout
	m._set_selection([s1])
	m._toggle_select(s2.position)
	_check(m.selected.size() == 2 and m.selected.has(s2), "Shift+左键加选")
	m._toggle_select(s2.position)
	_check(m.selected.size() == 1 and m.selected[0] == s1, "Shift+左键再点一次 = 移出选择")
	m.select_type("swordsman")
	_check(m.selected.size() >= 2 and m.selected.all(func(u): return u is Soldier and not u.is_ranged), "选同类：全部剑士（%d 个）" % m.selected.size())
	m._placing_kind = ""
	m._target_mode = ""
	if m.hud.help_visible():
		m.hud.toggle_help()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	m._on_key(esc)
	_check(m.selected.is_empty(), "Esc 取消选中")

	# 命令卡热键：A 攻击移动 / S 停止 / D 驻守 / F 巡逻；Shift+右键排路点
	m._set_selection([s1])
	m.run_hotkey("A")
	_check(m._target_mode == "attack", "A = 进入攻击移动模式")
	m._on_key(esc)
	_check(m._target_mode == "" and m.selected.size() == 1, "Esc 取消 A 模式，选中还在")
	s1.command_move(s1.position + Vector2(-140, 0))
	await tree.create_timer(0.4).timeout
	m.run_hotkey("S")
	var p_stop := s1.position
	await tree.create_timer(0.8).timeout
	_check(s1.position.distance_to(p_stop) < 6.0, "S 停止：原地站住（挪了 %.1fpx）" % s1.position.distance_to(p_stop))
	s1.position = Vector2(420, 600)
	var p1 := Vector2(420, 540)
	var p2 := Vector2(480, 540)
	m._issue_command(p1)
	m._issue_queued(p2, false)
	_check(s1.waypoints.size() == 1, "Shift+右键排了 1 个路点")
	await tree.create_timer(120.0 / s1.speed + 1.2).timeout
	_check(s1.position.distance_to(p2) < 30.0 and s1.waypoints.is_empty(), "走完第一段接着走排队的路点（离终点 %.0fpx）" % s1.position.distance_to(p2))
	m.run_hotkey("D")
	_check(s1.hold, "D = 原地驻守")
	var hold_p := s1.position
	var g := Goo.new()
	g.position = s1.position + Vector2(130, 0)
	m.add_child(g)
	g.speed = 0.0
	await tree.create_timer(1.5).timeout
	_check(s1.position.distance_to(hold_p) < 10.0, "驻守：130px 外的怪不去追（挪了 %.0fpx）" % s1.position.distance_to(hold_p))
	if is_instance_valid(g):
		g.take_damage(99999.0)
	m.run_hotkey("F")
	_check(m._target_mode == "patrol", "F = 进入巡逻模式")
	var start := s1.position
	m._issue_patrol(start + Vector2(0, -80))
	m._target_mode = ""
	_check(s1.patrol and not s1.hold, "巡逻开始（驻守自动取消）")
	await tree.create_timer(80.0 / s1.speed + 0.6).timeout
	_check(s1._amove_dest.distance_to(start) < 30.0, "巡逻到头自动掉头往回走")
	m._issue_command(start + Vector2(40, 0))
	_check(not s1.patrol, "下新指令取消巡逻")

	# Del：删选中的单位，基地删不掉
	m._set_selection([s2, m.base])
	m._delete_selected()
	await tree.process_frame
	_check(not is_instance_valid(s2) and is_instance_valid(m.base), "Del 删掉选中的士兵，基地不能删")

	# 闲置农民：. 键选中，W 派去伐木
	var iw := Worker.new()
	iw.position = m.base.position + Vector2(90, 70)
	m.add_child(iw)
	await tree.create_timer(0.3).timeout
	_check(m.idle_units(true).has(iw), "没活干的农民算闲置")
	m.select_next_idle(true)
	_check(m.selected.size() == 1 and m.selected[0] is Worker and m.selected[0].is_idle(), ". 键选中闲置农民")
	m._set_selection([iw])
	m.run_hotkey("W")
	_check(is_instance_valid(iw.node_target) and iw.node_target.kind == "wood", "W = 去伐木")
	m._deselect_all()

	# 建筑占格：基地格子挡路，寻路绕着走
	_check(m.terrain.solid_at(m.base.position), "基地占住脚下的格子")
	var pa: Vector2 = m.base.position + Vector2(-80, 0)
	var pb: Vector2 = m.base.position + Vector2(80, 0)
	var path: PackedVector2Array = m.terrain.find_path(pa, pb)
	var ok := not path.is_empty()
	var prev := pa
	for q in path:
		if not m.terrain.line_walkable(prev, q):
			ok = false
		prev = q
	_check(ok, "寻路绕开基地（%d 个拐点）" % path.size())

	# 随机图：主城居中、2 个巢穴、主城到巢穴和每堆矿都走得通
	for sd in range(1, 6):
		var lay: Dictionary = MapGen.generate(sd, 3200.0, 2048.0)
		var t := Terrain.new()
		t.setup(3200.0, 2048.0)
		var gw: int = lay.gw
		var cells: PackedByteArray = lay.cells
		for i in cells.size():
			var v: int = cells[i]
			if v == MapGen.C_TREE or v == MapGen.C_WOODS or v == MapGen.C_ORE or v == MapGen.C_RICH:
				t.set_cell(Vector2i(i % gw, i / gw), Terrain.T.WOODS)
		var good: bool = lay.base == Vector2(1600, 1024) and lay.hives.size() == 2 and lay.roads.size() == 2 and lay.ore.size() >= 6
		var st: Vector2 = lay.base + Vector2(0, 60)
		for hp in lay.hives:
			if t.find_path(st, hp).is_empty():
				good = false
		for op in lay.ore:
			if t.find_path(st, op).is_empty():
				good = false
		# Goo 据点：2~3 个，各守 6 堆富矿；离主城不远不近、不挨土路，警戒圈里没有树/普通矿，窝和富矿都走得到
		var camp_ok: bool = lay.camps.size() >= 2
		var n_rich := 0
		for cp in lay.camps:
			var cpos: Vector2 = cp.pos
			var dd: float = cpos.distance_to(lay.base)
			if cp.rich.size() != 6 or dd < MapGen.CAMP_MIN_D or dd > MapGen.CAMP_MAX_D or MapGen._near_road(lay.roads, cpos, 250.0):
				camp_ok = false
			if t.find_path(st, cpos).is_empty():
				camp_ok = false
			for rp in cp.rich:
				n_rich += 1
				if t.find_path(st, rp).is_empty() or rp.distance_to(cpos) > Goo.GUARD_AGGRO:
					camp_ok = false
			for i in cells.size():
				var v: int = cells[i]
				if (v == MapGen.C_TREE or v == MapGen.C_ORE) and (Vector2(i % gw + 0.5, i / gw + 0.5) * MapGen.CELL).distance_to(cpos) < MapGen.CAMP_CLEAR_R:
					camp_ok = false
		t.free()
		_check(good, "随机图 seed=%d：主城居中、2 巢穴、到巢穴和 %d 堆矿都走得通" % [sd, lay.ore.size()])
		_check(camp_ok, "随机图 seed=%d：%d 个 Goo 据点各守 6 堆富矿（共 %d，都在警戒圈里），不挨土路、窝边没树没普通矿、都走得到" % [sd, lay.camps.size(), n_rich])

## ---- Goo 据点（野怪小窝）：守军警戒 / 全窝一起上 / 拴绳回窝 / 回血 / 补兵 / 缴获 / 富矿 / 不许贴脸盖房 ----
func _camp_tests() -> void:
	# 己方单位、建筑先冻住：农民采矿路过、箭塔放冷箭都会把守军勾走，测不准
	var frozen: Array = []
	for grp in ["player_units", "buildings"]:
		for n in m.get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n) and n.process_mode != Node.PROCESS_MODE_DISABLED and not (n is Building and n.team != 0):
				n.process_mode = Node.PROCESS_MODE_DISABLED
				frozen.append(n)
	# 经典图小：挑离己方单位/建筑/工地/矿最远的一块空地（巢穴和别的怪也离远点）
	var spot := Vector2.ZERO
	var best := -1.0
	for y in range(150, int(m.H) - 130, 30):
		for x in range(170, int(m.W) - 170, 30):
			var p := Vector2(x, y)
			if m.area_blocked(p, 40.0):
				continue
			var dmin := INF
			for grp in ["player_units", "buildings", "sites", "enemies", "res_nodes"]:
				for n in m.get_tree().get_nodes_in_group(grp):
					if not is_instance_valid(n):
						continue
					var d: float = n.position.distance_to(p)
					if grp == "enemies":
						d += 60.0
					elif grp == "res_nodes":
						d += 100.0    # 资源点别太近就行（己方单位都冻住了，不会有人来采）
					dmin = minf(dmin, d)
			if dmin > best:
				best = dmin
				spot = p
	_check(best > Goo.GUARD_AGGRO + 30.0, "找到摆据点的空地 %s（离己方最近 %.0f，在警戒圈外）" % [spot, best])
	var away: Vector2 = (spot - m.base.position).normalized()
	var rich_pts := [spot + away * 110.0, spot + away * 110.0 + away.orthogonal() * 44.0]
	var c: Camp = m.add_camp(spot, 2, rich_pts)
	await m.get_tree().create_timer(0.4).timeout
	var gs: Array = c.alive_guards().duplicate()
	var types: Array = gs.map(func(g): return g.etype)
	_check(gs.size() == 4 and types.count("goo") == 3 and types.count("brute") == 1
		and gs.all(func(g): return g.is_guard() and not g.lane and g.position.distance_to(spot) < 90.0),
		"据点刷出守军：Goo×3 岩壳×1 站在窝边（%s）" % [types])
	var rn: Array = m.get_tree().get_nodes_in_group("res_nodes").filter(func(n): return n.rich and n.guard_at == spot)
	_check(rn.size() == 2 and rn.all(func(n): return is_equal_approx(n.amount, ResNode.RICH_AMOUNT) and n.guarded()), "富矿每堆 %d、据点看着" % int(ResNode.RICH_AMOUNT))
	_check(m._build_mgr.placement_error(spot - away * 200.0, "warehouse").contains("据点"), "据点没拆不许在旁边盖房")
	_check(not m._wave_mgr.wave_enemies().any(func(e): return e.is_guard()), "十波打完的胜利判定不算据点守军")
	# 自动找矿：远处派活跳过有人看着的富矿；人已经在富矿边上（玩家派过去的）照采
	var w0: Worker = m._player_workers()[0]
	var far_from: Vector2 = rn[0].position + away * 300.0
	var nn: ResNode = w0._nearest_node("ore", far_from)
	var nn2: ResNode = w0._nearest_node("ore", rn[0].position + Vector2(4, 0))
	_check((nn == null or not nn.rich) and nn2 != null and nn2.rich, "自动找矿跳过有守军的富矿，人在矿边上照采（远处挑了 %s）" % ["没有" if nn == null else ("富矿" if nn.rich else "普通矿")])
	# 警戒圈外的人不理；没架打的守军待在岗位边
	var bait := Worker.new()
	bait.position = m.open_point(spot - away * 260.0)
	m.add_child(bait)
	bait.max_hp = 99999.0
	bait.hp = 99999.0
	await m.get_tree().create_timer(0.6).timeout
	_check(gs.all(func(g): return is_instance_valid(g) and g.attack_target == null and g._cached_target == null and g.position.distance_to(g.home) < 30.0),
		"警戒圈（%d）外的人守军不理，都站在岗位边" % int(Goo.GUARD_AGGRO))
	_check(c.spotted, "人走近据点：横幅提示发现据点")
	# 打一只 → 全窝一起上
	gs[1].take_damage(1.0, bait)
	_check(gs.all(func(g): return g.attack_target == bait), "打一只守军，全窝一起扑上来")
	await m.get_tree().create_timer(0.8).timeout
	_check(gs.all(func(g): return g.position.distance_to(bait.position) < g.home.distance_to(bait.position) - 20.0), "守军追出岗位去咬人")
	# 追出拴绳：掉头回窝，回窝路上挨打也不理
	var g0: Goo = gs[0]
	g0.position = g0.home - away * (Goo.GUARD_LEASH + 30.0)
	await m.get_tree().process_frame
	await m.get_tree().process_frame
	var ret0: bool = g0.returning and g0.attack_target == null
	g0.take_damage(1.0, bait)
	_check(ret0 and g0.returning and g0.attack_target == null, "追出拴绳（%d）就回窝，回窝路上挨打不理" % int(Goo.GUARD_LEASH))
	g0.position = g0.home + Vector2(30, 0)
	g0._path = PackedVector2Array()    # 瞬移回来的，从拴绳外算的那条回窝路作废
	await m.get_tree().create_timer(0.8).timeout
	_check(not g0.returning, "回到岗位就恢复警戒（离岗位 %.0fpx）" % g0.position.distance_to(g0.home))
	# 人没了：全员走回岗位、回血
	bait.queue_free()
	for g in gs:
		g.hp = g.max_hp * 0.3
	var back := false
	for i in 40:
		await m.get_tree().create_timer(0.25).timeout
		back = gs.all(func(g): return is_instance_valid(g) and not is_instance_valid(g.attack_target) and g.position.distance_to(g.home) < 50.0)
		if back:
			break
	_check(back, "没人可咬了守军走回岗位（离岗位 %s）" % [gs.map(func(g): return int(g.position.distance_to(g.home)) if is_instance_valid(g) else -1)])
	await m.get_tree().create_timer(0.5).timeout
	_check(gs.all(func(g): return g.hp > g.max_hp * 0.32), "守军没架打时慢慢回血（%.0f%%）" % (gs[0].hp / gs[0].max_hp * 100.0))
	# 补兵：死一只，隔一阵窝里钻出同种的一只
	gs[3].take_damage(99999.0)
	await m.get_tree().process_frame
	var miss: int = c.alive_guards().size()
	var rl: float = c.reinforce_left()
	c._reinforce_t = 0.05
	await m.get_tree().create_timer(0.3).timeout
	var gs2: Array = c.alive_guards()
	_check(miss == 3 and rl > 0.0 and gs2.size() == 4 and gs2.map(func(g): return g.etype).count("brute") == 1, "守军死了窝里会补（缺 1 只、%.0f 秒后补岩壳）" % rl)
	# 点据点：只看属性
	m._point_select(spot)
	await m.get_tree().create_timer(0.1).timeout
	_check(m.inspected == c and m.info_label.text.contains("Goo 据点") and m.info_label.text.contains("守军 4/4"), "点据点显示守军和缴获")
	m._deselect_all()
	# 窝挨打也喊守军；拆了缴获入账，旁边能盖房；守军还在 = 富矿还有人看着
	var bait2 := Worker.new()
	bait2.position = m.open_point(spot - away * 240.0)
	m.add_child(bait2)
	bait2.max_hp = 99999.0
	bait2.hp = 99999.0
	await m.get_tree().process_frame
	c.take_damage(1.0, bait2)
	_check(gs2.all(func(g): return g.attack_target == bait2), "窝挨打守军也扑上来")
	var ore0: float = m.economy.ore
	var wood0: float = m.economy.wood
	c.take_damage(99999.0, bait2)
	var d_ore: float = m.economy.ore - ore0    # 当场比（等一会儿农民交货会混进来）
	var d_wood: float = m.economy.wood - wood0
	await m.get_tree().create_timer(0.6).timeout
	_check(not is_instance_valid(c) and is_equal_approx(d_ore, 150.0) and is_equal_approx(d_wood, 100.0),
		"拆据点缴获 150 矿 100 木（+%.0f / +%.0f）" % [d_ore, d_wood])
	_check(not m._build_mgr.placement_error(spot - away * 200.0, "warehouse").contains("据点"), "据点拆了旁边就能盖房")
	_check(rn.all(func(n): return n.guarded()), "窝拆了守军还活着：富矿还有人看着")
	for g in gs2:
		if is_instance_valid(g):
			g.take_damage(99999.0)
	bait2.queue_free()
	await m.get_tree().create_timer(0.6).timeout
	_check(rn.all(func(n): return not n.guarded()), "守军也清光：富矿没人看了")
	for n in rn:
		n.queue_free()
	for n in frozen:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  - " + msg)
	else:
		m._fail += 1
		print("  FAIL- " + msg)
