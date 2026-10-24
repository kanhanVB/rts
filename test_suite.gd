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
	if "--only=solo" in OS.get_cmdline_user_args():
		await _a_move_probe()    # 单独探针：A 移动 + 打怪 + 继续赶路（-- --test --only=solo）
		_done()
		return
	if "--only=bell" in OS.get_cmdline_user_args():
		await _bell_tests()    # 只跑警钟 / 报警这一块（调试用：-- --test --only=bell）
		await _alert_tests()
		_done()
		return
	if "--only=new" in OS.get_cmdline_user_args():
		await _time_tests()    # 只跑暂停/倍速、结算统计、农民自保（-- --test --only=new，迭代用）
		await _stats_tests()
		await _light_rts_tests()
		await _flee_tests()
		_done()
		return
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
	# 先清一次场：轻 RTS 的近战 1v1 是独占的，前面测试残留的兵会抢先钉住这只 Goo，
	# 也可能站在路中间把人挡住（这不是 bug，是 1v1 该有的样子，所以测试场地得干净）
	for e0 in m.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e0):
			e0.queue_free()
	for u0 in m.get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u0) and u0 is Soldier:
			u0.queue_free()
	await m.get_tree().create_timer(0.3).timeout
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
	var dbg: Array = []
	for e0 in m.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e0):
			continue
		var pb = e0.get("pinned_by")
		var ptxt := str(pb)
		if pb != null and is_instance_valid(pb):
			ptxt = "%s(name=%s,%s)" % [ptxt, str(pb.name), pb.get_script().resource_path if pb.get_script() else "-"]
		dbg.append("%s@%.0f pin=%s can=%s" % [e0.etype,
			s2.position.distance_to(e0.position), ptxt, str(s2._can_pin(e0))])
	_check(not is_instance_valid(g7) or (s2.attack_target == g7),
		"A 移动途中遇敌自动开打（g7活着=%s s2目标=%s 位置=%s amove=%s manual=%s ignore=%s 敌方=[%s]）" % [
			is_instance_valid(g7), str(s2.attack_target), str(s2.position),
			str(s2._amove_dest), str(s2.is_manual()), str(s2._ignore_aggro), " | ".join(dbg)])

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
	_check(s4.position.distance_to(dest4) < 60.0,
		"A 移动打完继续走到目的地（距终点 %.0fpx 位置=%s 目标=%s amove=%s pin=%s mt=%s post=%s dead=%s）" % [
			s4.position.distance_to(dest4), str(s4.position), str(s4.attack_target),
			str(s4._amove_dest), str(s4.pin_target), str(s4.move_target),
			str(s4.has_post()), str(s4.dead)])
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
	await _tech_tests()
	await _explore_tests()
	await _bell_tests()
	await _alert_tests()
	await _time_tests()
	await _stats_tests()
	await _light_rts_tests()
	await _flee_tests()

	# 拆巢穴触发胜利
	m.hive.take_damage(99999.0)
	await m.get_tree().create_timer(0.5).timeout
	_check(m.game_state == "win", "拆巢穴触发胜利")
	_check(m.overlay_stats.text.contains("击杀"), "结算页列出本局统计")
	_done()

## ---- 时间控制：暂停 / 倍速（只动引擎缩放，测完复位，别把后面的等待拖慢）----
func _time_tests() -> void:
	_check(m.speed_mult() == 1.0 and Engine.time_scale == 1.0, "开局 1 倍速")
	m.set_speed(1)
	_check(m.speed_mult() == 2.0 and Engine.time_scale == 2.0, "加速一档 = 2 倍速（引擎 time_scale 跟着走）")
	m.cycle_speed()
	_check(m.speed_mult() == 3.0, "再一档 = 3 倍速")
	m.cycle_speed()
	_check(m.speed_i == 0 and Engine.time_scale == 1.0, "第三下转回 1 倍速（1→2→3→1）")
	m.toggle_pause()
	_check(m.paused and Engine.time_scale == 0.0, "P 暂停：引擎时间停住（time_scale = 0）")
	var t0: float = m.game_time
	# 注意：暂停时 SceneTreeTimer 也不走字，这里只能等"帧"（delta=0，帧照样在跑）
	for _i in 10:
		await m.get_tree().process_frame
	_check(absf(m.game_time - t0) < 0.01, "暂停时游戏时间不再往前（%.2f）" % m.game_time)
	m.toggle_pause()
	_check(not m.paused and Engine.time_scale == 1.0, "再按 P 继续")
	# 暂停中按加速：顺手解除暂停开跑
	m.toggle_pause()
	m.set_speed(1)
	_check(not m.paused and Engine.time_scale == 2.0, "暂停中加速：自动解除暂停并跑起来")
	m.set_speed(0)
	Engine.time_scale = 1.0
	_check(m.speed_i == 0 and not m.paused, "速度复位到 1 倍速")

## ---- 结算统计：击杀 / 阵亡 / 训练 / 峰值库存 ----
func _stats_tests() -> void:
	var k0: int = m.stats.kills
	var g := Goo.new()
	g.position = Vector2(300, 300)
	m.add_child(g)
	await m.get_tree().create_timer(0.1).timeout
	g.take_damage(99999.0)
	await m.get_tree().create_timer(0.2).timeout
	_check(int(m.stats.kills) == k0 + 1, "打死一只怪，击杀 +1")

	var l0: int = m.stats.lost
	var w := Worker.new()
	w.position = Vector2(300, 340)
	m.add_child(w)
	await m.get_tree().create_timer(0.1).timeout
	w.take_damage(99999.0)
	await m.get_tree().create_timer(0.2).timeout
	_check(int(m.stats.lost) == l0 + 1, "自家单位阵亡，阵亡 +1")

	var tr0: int = m.stats.trained
	m._point_select(m.base.position)
	m._on_worker_pressed()
	await m.get_tree().create_timer(0.4).timeout
	_check(int(m.stats.trained) == tr0 + 1, "训练出单位，训练 +1")

	m.economy.ore = 777.0
	await m.get_tree().create_timer(0.7).timeout    # 等一次 0.5 秒采样
	_check(float(m.stats.peak_ore) >= 777.0, "峰值库存记下这一局的最高矿石（%.0f）" % float(m.stats.peak_ore))
	var txt: String = m.stats_text()
	_check(txt.contains("用时") and txt.contains("击杀") and txt.contains("峰值库存"), "结算文字有用时 / 击杀 / 峰值")

## ---- 轻 RTS：兵听兵营集结点、近战 1v1 钉住、不自动补员 ----
func _light_rts_tests() -> void:
	var tree := m.get_tree()
	# 清场：别的测试留下的怪和兵会干扰"谁钉谁"
	for e in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	for u in tree.get_nodes_in_group("player_units"):
		if is_instance_valid(u):
			u.queue_free()      # 农民也清掉：下面只看兵
	await tree.create_timer(0.3).timeout

	var bk: Building = m._build_mgr.add_building("barracks", m.base.position + Vector2(-40, 250), 0)
	await tree.create_timer(0.1).timeout
	bk.queue.clear()
	var post: Vector2 = m.open_point(bk.position + Vector2(230, 0))
	bk.rally = post
	bk.rally_node = null
	m.economy.ore += 500.0
	m.economy.ingot += 200.0
	m._set_selection([bk])
	m.run_hotkey("Q")        # 兵营第一格 = 剑士
	await tree.create_timer(0.15).timeout
	m.run_hotkey("Q")
	await tree.create_timer(0.3).timeout
	var sws: Array = []
	for u in tree.get_nodes_in_group("player_units"):
		if u is Soldier and not u.is_ranged:
			sws.append(u)
	_check(sws.size() >= 2, "兵营出了 2 个剑士（%d）" % sws.size())
	var sw: Soldier = sws[0]
	_check(sw.has_post() and sw.post_home == bk, "兵出厂就领了防区（听这座兵营的集结点）")
	_check(sw.post_pos().distance_to(post) < 60.0, "站位点就在集结点上（%.0fpx）" % sw.post_pos().distance_to(post))
	_check(not sw.is_idle(), "站岗的兵不算闲置（`.` 不会一直选中它）")
	await tree.create_timer(3.2).timeout
	_check(sw.position.distance_to(post) < 70.0, "兵自己走到集结点站好（离点 %.0fpx）" % sw.position.distance_to(post))

	# 兵可以随便动：右键照常下令，兵听（手令接管，暂时离开防区）
	var p0: Vector2 = sw.position
	var dest: Vector2 = m.open_point(p0 + Vector2(130, 0))
	m._set_selection([sw])
	m._command_at(dest)
	await tree.create_timer(2.2).timeout
	_check(sw.is_manual() and sw.position.distance_to(dest) < 70.0,
		"选中兵右键地面照样下令，兵自己走过去（离目标 %.0fpx）" % sw.position.distance_to(dest))
	# S 停止 = 把手令交还回去，走回防区接着守
	m.run_hotkey("S")
	await tree.create_timer(3.6).timeout
	_check(not sw.is_manual() and sw.position.distance_to(post) < 80.0,
		"按 S 停止：交还手令，回集结点站好（离点 %.0fpx）" % sw.position.distance_to(post))

	# 怪进防区：迎上去钉住（1v1），怪停下跟他对砍
	var g := Goo.new()
	g.position = post + Vector2(90, 0)
	m.add_child(g)
	await tree.create_timer(0.3).timeout
	_check(sw.pin_target == g and g.pinned_by == sw, "怪进防区：剑士认领并钉住（怪身上记着是他）")
	var g_hp0: float = g.hp
	await tree.create_timer(1.6).timeout
	_check(sw.position.distance_to(g.position) < sw.attack_range + 40.0,
		"迎上去贴脸（%.0fpx）" % sw.position.distance_to(g.position))
	_check(g.hp < g_hp0, "钉住就开打（怪 %.0f → %.0f）" % [g_hp0, g.hp])

	# 第二只怪：同一个兵不抢（一个兵只钉一只）
	var g2 := Goo.new()
	g2.position = post + Vector2(-90, 0)
	m.add_child(g2)
	await tree.create_timer(0.5).timeout
	_check(g2.pinned_by != sw, "第二只怪不会被同一个兵抢（1v1 独占）")

	# 清怪：兵自己回位
	if is_instance_valid(g):
		g.queue_free()
	if is_instance_valid(g2):
		g2.queue_free()
	await tree.create_timer(3.0).timeout
	_check(sw.pin_target == null and sw.position.distance_to(post) < 80.0,
		"怪清完：松口回站位点（离点 %.0fpx）" % sw.position.distance_to(post))

	# 兵死了：钉子松开，而且不会自动补
	var n0: int = sws.size()
	var victim: Soldier = sws[1]
	var gk := Goo.new()
	gk.position = victim.position + Vector2(40, 0)
	m.add_child(gk)
	await tree.create_timer(0.3).timeout
	victim.take_damage(99999.0)
	await tree.create_timer(0.4).timeout
	_check(not is_instance_valid(victim), "兵死了就是死了")
	var n1 := 0
	for u in tree.get_nodes_in_group("player_units"):
		if u is Soldier:
			n1 += 1
	_check(n1 == n0 - 1, "兵死了不会自动补（%d → %d）" % [n0, n1])
	if is_instance_valid(gk):
		gk.queue_free()
	await tree.create_timer(0.4).timeout

	# 改集结点：全队跟着挪（这就是轻 RTS 的"调防"）
	var post2: Vector2 = m.open_point(post + Vector2(0, 190))
	bk.rally = post2
	await tree.create_timer(3.6).timeout
	_check(sw.position.distance_to(post2) < 80.0, "改集结点：兵跟着搬过去（离新点 %.0fpx）" % sw.position.distance_to(post2))
	bk.queue_free()
	if is_instance_valid(sw):
		sw.queue_free()
	await tree.create_timer(0.2).timeout

## ---- 农民自保：怪凑近就跑，怪走远自己回去 ----
func _flee_tests() -> void:
	# 先把场上所有怪清掉，让"有没有怪"这件事由测试自己决定；
	# 兵也一起清（轻 RTS 的兵会主动钉怪，留着会把测试放出来的 Goo 抢走打死）
	for e in m.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	for s in m.get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(s) and s is Soldier:
			s.queue_free()
	await m.get_tree().create_timer(0.3).timeout
	m._check_worker_safety()

	var w := Worker.new()
	w.position = m.base.position + Vector2(240, 30)
	m.add_child(w)
	await m.get_tree().create_timer(0.2).timeout
	var ore: ResNode = w._nearest_node("ore")
	_check(ore != null, "自保测试：找到一处矿")
	w.command_gather(ore)
	_check(not w.is_fleeing(), "没怪的时候不跑")

	var g := Goo.new()
	g.position = w.position + Vector2(45, 0)
	m.add_child(g)
	await m.get_tree().create_timer(0.2).timeout
	m._check_worker_safety()
	_check(w.is_fleeing(), "怪贴到 45px：农民放下活开跑")
	# 目标是"最近的己方房子墙边"（这张图上测试中途盖过仓库/箭塔，不一定就是基地）
	var near_b: Building = null
	var nd := INF
	for b in m.get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.team == 0 and b.kind in ["base", "warehouse", "outpost", "tower"]:
			var d: float = w.position.distance_to(b.position)
			if d < nd:
				nd = d
				near_b = b
	_check(near_b != null and w.flee_to.distance_to(near_b.position) <= near_b.size * 0.5 + 40.0,
		"逃跑目标是最近的己方房子墙边（%s，%.0fpx）" % [near_b.kind if near_b else "无", nd])

	# 拉远 200px 再量"能不能跑到"：上面那栋仓库就在脚边，贴着量不出速度
	var tgt: Vector2 = w.flee_to
	var back: Vector2 = (tgt - w.position)
	back = back.normalized() if back.length() > 0.001 else Vector2(1, 0)
	w.position = tgt + back * 200.0
	w._path = PackedVector2Array()
	w._path_idx = 0
	g.position = w.position + back * 60.0    # 怪跟着挪过去：不然拉开 200px 后自动判定"已脱险"就收工了
	# 瞬移落点可能正好压在房子/树上，先让物理把它挤出来再起量（不然量的那段全在"脱困"）
	await m.get_tree().create_timer(0.35).timeout
	# 量的口径是"离怪越来越远"而不是"离房子越来越近"：逃跑的本质就是远离威胁，
	# 绕一点路躲开房子不算失败
	var gd0 := w.position.distance_to(g.position)
	await m.get_tree().create_timer(1.2).timeout
	var gd1 := w.position.distance_to(g.position)
	_check(w.is_fleeing() and gd1 > gd0 + 40.0,
		"往远离怪的方向跑（离怪 %.0f → %.0f，位置=%s）" % [gd0, gd1, str(w.position)])

	g.queue_free()
	await m.get_tree().create_timer(0.3).timeout
	m._check_worker_safety()
	_check(not w.is_fleeing(), "怪没了：自己收工往回走")
	_check(is_instance_valid(w.node_target) and w.state != Worker.State.IDLE, "回去接着干原来的活（采矿）")
	w.queue_free()

## ---- 单独探针：A 移动 → 半路遇怪 → 打完接着赶路 ----
## 全量里这条最脆（路径、卡住、时序都掺在一起），单独跑几秒就能看清卡在哪
func _a_move_probe() -> void:
	var tree := m.get_tree()
	for e in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(e):
			e.queue_free()
	for u in tree.get_nodes_in_group("player_units"):
		if is_instance_valid(u):
			u.queue_free()
	await tree.create_timer(0.4).timeout
	var s := Soldier.new()
	s.setup(false)
	s.position = Vector2(200, 150)
	m.add_child(s)
	var dest := Vector2(700, 150)
	s.command_attack_move(dest)
	var g := Goo.new()
	g.position = Vector2(350, 150)
	m.add_child(g)
	g.hp = 10.0
	for i in 14:
		await tree.create_timer(1.0).timeout
		_check(true, "t=%2ds 位置=%s 距终点=%3.0f amove=%s 目标=%s 路径=%d/%d 速度=%.0f" % [
			i + 1, str(s.position.round()), s.position.distance_to(dest),
			str(s._amove_dest != Vector2.ZERO), str(s.attack_target),
			s._path_idx, s._path.size(), s.speed])
	_check(s.position.distance_to(dest) < 60.0,
		"A 移动打完继续走到目的地（距终点 %.0fpx）" % s.position.distance_to(dest))

func _done() -> void:
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

	# 兵可以随便动：命令卡照旧给 A 移动 / S 停止 / D 驻守 / F 巡逻，另加一格「回位」
	m._set_selection([s1])
	var card: Array = m.commands().map(func(c): return c.id)
	_check(card.has("recall") and card.has("attack") and card.has("stop") and card.has("hold") and card.has("patrol"),
		"士兵命令卡：回位 + A 移动 / S 停止 / D 驻守 / F 巡逻（兵随便动）")
	# 这些命令都不走 UI 也照样能用（老接口没变）
	s1.command_attack_move(s1.position + Vector2(-140, 0))
	_check(s1._amove_dest != Vector2.ZERO, "A 移动：记下目的地")
	s1.command_move(s1.position + Vector2(-140, 0))
	await tree.create_timer(0.4).timeout
	s1.command_stop()
	var p_stop := s1.position
	await tree.create_timer(0.8).timeout
	_check(s1.position.distance_to(p_stop) < 6.0, "停止：原地站住（挪了 %.1fpx）" % s1.position.distance_to(p_stop))
	s1.position = Vector2(420, 600)
	var p1 := Vector2(420, 540)
	var p2 := Vector2(480, 540)
	m._issue_command(p1)
	m._issue_queued(p2, false)
	_check(s1.waypoints.size() == 1, "Shift+右键排了 1 个路点")
	await tree.create_timer(120.0 / s1.speed + 1.2).timeout
	_check(s1.position.distance_to(p2) < 30.0 and s1.waypoints.is_empty(), "走完第一段接着走排队的路点（离终点 %.0fpx）" % s1.position.distance_to(p2))
	s1.command_hold()
	_check(s1.hold, "驻守（底层）")
	var hold_p := s1.position
	var g := Goo.new()
	g.position = s1.position + Vector2(130, 0)
	m.add_child(g)
	g.speed = 0.0
	await tree.create_timer(1.5).timeout
	_check(s1.position.distance_to(hold_p) < 10.0, "驻守：130px 外的怪不去追（挪了 %.0fpx）" % s1.position.distance_to(hold_p))
	if is_instance_valid(g):
		g.take_damage(99999.0)
	var start := s1.position
	s1.command_patrol(start + Vector2(0, -80))
	_check(s1.patrol and not s1.hold, "巡逻开始（驻守自动取消）")
	await tree.create_timer(80.0 / s1.speed + 0.6).timeout
	_check(s1._amove_dest.distance_to(start) < 30.0, "巡逻到头自动掉头往回走")
	m._set_selection([s1])
	m._issue_command(start + Vector2(40, 0))    # 内部入口：走完整的"下新指令 → 取消巡逻"
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
			elif v == MapGen.C_WATER:
				t.set_cell(Vector2i(i % gw, i / gw), Terrain.T.DEEP)
			elif v == MapGen.C_SHALLOW:
				t.set_cell(Vector2i(i % gw, i / gw), Terrain.T.SHALLOW)
		# 岔路：主路之外多出来的几条（整条从主城排到巢穴），road_hive 一一对应
		var good: bool = lay.base == Vector2(1600, 1024) and lay.hives.size() == 2 and lay.roads.size() >= 2 and lay.road_hive.size() == lay.roads.size() and lay.ore.size() >= 6
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
		_check(good, "随机图 seed=%d：主城居中、2 巢穴 %d 条路、过河到巢穴和 %d 堆矿都走得通" % [sd, lay.roads.size(), lay.ore.size()])
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
	var ru: Ruins = _ruins_at(spot)
	_check(ru != null and ru.tier == 2 and is_equal_approx(ru.loot_mult, 0.5) and ru.team == 2 and ru.hold == "guards" and is_equal_approx(ru.left, Ruins.REOCCUPY),
		"窝塌成废墟（二档、Goo 回来占了再拆缴获减半）；守军还在 = 还是 Goo 的地盘，不倒计时（%s）" % ["没有废墟" if ru == null else ru.hold])
	for g in gs2:
		if is_instance_valid(g):
			g.take_damage(99999.0)
	bait2.queue_free()
	await m.get_tree().create_timer(0.6).timeout
	_check(rn.all(func(n): return not n.guarded()), "守军也清光：富矿没人看了")
	_check(ru != null and is_instance_valid(ru) and ru.hold != "guards", "守军清光：废墟不再算 Goo 的地盘（%s）" % [ru.hold if ru != null and is_instance_valid(ru) else "没了"])
	if ru != null and is_instance_valid(ru):
		ru.queue_free()    # 别在后面的测试里倒计时到点、Goo 回来占窝
	for n in rn:
		n.queue_free()
	for n in frozen:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT

## ---- 科技：基地 / 兵营第二排研究；排队先扣钱、取消全额退、不占人口；研究完全军生效（已有的兵也算）----
func _cmd_keys(ids_only_tech := true) -> String:
	var parts: Array = []
	for c in m.commands():
		if not ids_only_tech or Tech.is_tech(c.id):
			parts.append("%s=%s" % [c.key, c.id])
	return " ".join(parts)

func _tech_tests() -> void:
	var tree := m.get_tree()
	m._deselect_all()
	Tech.reset()
	var e: Economy = m.economy
	e.ore += 1000.0
	e.wood += 1000.0
	e.ingot += 300.0
	e.plank += 300.0
	m.base.queue.clear()
	m.select_base()
	_check(_cmd_keys() == "A=up_cart S=up_tools D=up_craft F=up_arrows", "基地第二排 4 个研究：%s" % _cmd_keys())
	var bk: Building = null
	for b in m.barracks_list:
		if is_instance_valid(b):
			bk = b
			break
	if bk == null:
		bk = m._build_mgr.add_building("barracks", m.base.position + Vector2(-260, 170), 0)
		await tree.create_timer(0.1).timeout
	bk.queue.clear()
	m._set_selection([bk])
	_check(_cmd_keys() == "A=up_blade S=up_mail D=up_longbow F=up_medic", "兵营第二排 4 个研究：%s" % _cmd_keys())
	var ore0 := e.ore
	_check(not m.research("up_cart") and absf(e.ore - ore0) < 0.01, "选着兵营研究不了基地的科技（不扣钱）")

	# 排队：先扣钱、按钮藏起来、不占人口、取消全额退；读条走完才生效
	m.select_base()
	m.train_scale = 1.0
	var w0 := e.wood
	var p0 := e.plank
	var pop0: int = m.queued_count()
	m.run_hotkey("A")
	_check(m.base.queue.size() == 1 and m.base.queue[0].kind == "up_cart" and absf(e.wood - (w0 - 80.0)) < 0.5 and absf(e.plank - (p0 - 20.0)) < 0.5,
		"A 研究手推车：排进基地队列，先扣 80 木 20 木板（木 %.0f→%.0f）" % [w0, e.wood])
	_check(not _cmd_keys().contains("up_cart") and _cmd_keys(false).contains("Q=worker"), "排上的研究按钮藏起来，造农民还在")
	_check(m.queued_count() == pop0 and not m.pop_blocked("up_cart"), "研究不占人口")
	_check(not m.research("up_cart") and m.base.queue.size() == 1, "同一项不能排两次")
	_check(not Tech.has("up_cart") and is_equal_approx(Worker.carry_cap(), 10.0), "读条没完不生效")
	m.cancel_train(m.base, 0)
	_check(m.base.queue.is_empty() and absf(e.wood - w0) < 0.5 and absf(e.plank - p0) < 0.5 and _cmd_keys().contains("A=up_cart"),
		"取消研究全额退，按钮回来")
	m.train_scale = 0.02    # 25 秒 → 0.5 秒
	m.run_hotkey("A")
	await tree.create_timer(0.9).timeout
	_check(Tech.has("up_cart") and m.base.queue.is_empty() and not _cmd_keys().contains("up_cart"), "读条走完：手推车研究完成，按钮不再出现")
	m.train_scale = 0.0
	_check(is_equal_approx(Worker.carry_cap(), 15.0), "手推车：每趟扛 15（%.1f）" % Worker.carry_cap())
	_check(not m.research("up_cart"), "研究过的不能再研究")
	# 采集的农民真的扛 15 才回去交
	var ore_node: ResNode = null
	for n in m.get_tree().get_nodes_in_group("res_nodes"):
		if n is ResNode and n.kind == "ore" and n.amount > 60.0 and not n.guarded() and (ore_node == null or n.position.distance_to(m.base.position) < ore_node.position.distance_to(m.base.position)):
			ore_node = n
	var gw := Worker.new()
	gw.position = m.open_point(ore_node.position + Vector2(0, 40)) if ore_node != null else m.base.position + Vector2(60, 60)
	m.add_child(gw)
	await tree.create_timer(0.1).timeout
	if ore_node != null:
		gw.command_gather(ore_node)
	var full := -1.0
	for i in 60:
		await tree.create_timer(0.2).timeout
		if gw.state == Worker.State.TO_BASE:
			full = gw.carry_amount
			break
	_check(full >= 14.5, "研究手推车后农民采满 15 才回去交（%.1f）" % full)
	gw.queue_free()

	m.run_hotkey("S")
	_check(Tech.has("up_tools") and is_equal_approx(Worker.gather_rate(), 5.2), "精工工具：采集每秒 5.2（%.2f）" % Worker.gather_rate())
	var sm: Building = m._build_mgr.add_building("smelter", m.base.position + Vector2(-320, -170), 0)    # 临时摆一座（前面的熔炉可能被拆了）
	var bt0: float = sm.batch_time()
	m.run_hotkey("D")
	_check(Tech.has("up_craft") and is_equal_approx(bt0, 5.0) and is_equal_approx(sm.batch_time(), 3.5), "熟练工匠：熔炉一批 %.1f → %.1f 秒" % [bt0, sm.batch_time()])
	sm.queue_free()
	var td0: float = m.base.tower_stats().dmg
	m.run_hotkey("F")
	_check(Tech.has("up_arrows") and is_equal_approx(m.base.tower_stats().dmg, td0 + 3.0), "破甲箭头：基地每箭 %.0f → %.0f" % [td0, m.base.tower_stats().dmg])
	var tw: Building = m._build_mgr.add_building("tower", m.base.position + Vector2(200, -200), 0)
	_check(is_equal_approx(tw.tower_stats().dmg, Building.TOWER_LV[1].dmg + 3.0) and is_equal_approx(Building.TOWER_LV[1].dmg, 9.0), "破甲箭头：箭塔每箭 12（常量表没被改）")
	tw.queue_free()
	_check(_cmd_keys() == "", "基地 4 项研究完：第二排空了")
	_check(m._selected_info_text().contains("已研究：手推车、精工工具、熟练工匠、破甲箭头"), "基地信息栏列出已研究")

	# 兵营：场上已有的兵研究完立刻变强，新出的兵也带着
	var sw := Soldier.new()
	sw.setup(false)
	sw.position = m.base.position + Vector2(-140, 190)
	m.add_child(sw)
	var ar := Soldier.new()
	ar.setup(true)
	ar.position = sw.position + Vector2(40, 0)
	m.add_child(ar)
	await tree.create_timer(0.1).timeout
	_check(is_equal_approx(sw.atk, 12.0) and is_equal_approx(sw.max_hp, 85.0) and is_equal_approx(ar.atk_range, 140.0), "研究前：剑士 12 攻 85 血，弓手射程 140")
	m._set_selection([bk])
	m.run_hotkey("A")
	_check(Tech.has("up_blade") and is_equal_approx(sw.atk, 16.0) and is_equal_approx(ar.atk, 8.0), "锻铁剑：已有剑士 12 → 16，弓手不变")
	m.run_hotkey("S")
	_check(Tech.has("up_mail") and is_equal_approx(sw.max_hp, 100.0) and is_equal_approx(sw.hp, 100.0) and is_equal_approx(sw.armor, 4.0)
		and is_equal_approx(ar.max_hp, 60.0) and is_equal_approx(ar.armor, 2.0), "锁子甲：剑士 100 血 4 甲、弓手 60 血 2 甲（满血的直接补满）")
	m.run_hotkey("D")
	_check(Tech.has("up_longbow") and is_equal_approx(ar.atk_range, 170.0) and is_equal_approx(ar.atk, 10.0) and ar.aggro_range >= 180.0,
		"长弓：弓手射程 170、每箭 10、索敌 %.0f" % ar.aggro_range)
	var ns := Soldier.new()
	ns.setup(false)
	_check(is_equal_approx(ns.atk, 16.0) and is_equal_approx(ns.max_hp, 100.0) and is_equal_approx(ns.hp, 100.0) and is_equal_approx(ns.armor, 4.0), "新出的剑士带着锻铁剑 + 锁子甲")
	ns.free()
	sw.apply_techs()
	_check(is_equal_approx(sw.atk, 16.0) and is_equal_approx(sw.max_hp, 100.0) and is_equal_approx(sw.armor, 4.0), "重算一遍不会叠两次")
	m.run_hotkey("F")
	_check(Tech.has("up_medic") and _cmd_keys() == "", "战地包扎研究完，兵营第二排空了")
	sw.take_damage(44.0)
	var hp1 := sw.hp
	await tree.create_timer(0.5).timeout
	_check(is_equal_approx(sw.hp, hp1) and hp1 < 70.0, "刚挨打不回血（%.1f）" % sw.hp)
	sw._calm_t = Tech.MEDIC_DELAY
	await tree.create_timer(0.5).timeout
	_check(sw.hp > hp1 + 0.8 and sw.hp < hp1 + 3.0, "战地包扎：脱战 4 秒后每秒回 3 血（%.1f → %.1f）" % [hp1, sw.hp])
	m._set_selection([bk])
	_check(m._selected_info_text().contains("已研究：锻铁剑、锁子甲、长弓、战地包扎"), "兵营信息栏列出已研究")

	# 收尾：科技清零，兵恢复原样（后面的测试按原数值写的）
	Tech.reset()
	for u in m.get_tree().get_nodes_in_group("player_units"):
		if u is Soldier:
			u.apply_techs()
	_check(is_equal_approx(sw.atk, 12.0) and is_equal_approx(sw.max_hp, 85.0) and is_equal_approx(sw.armor, 2.0) and is_equal_approx(ar.atk_range, 140.0), "清零后恢复原数值")
	sw.queue_free()
	ar.queue_free()
	m._deselect_all()

## ---- 地图和探索：岔路 / 河 / 桥 / 浅滩 / 宝箱遗物（随机图生成）；水车；捡宝；废墟和前哨；战争迷雾 ----
func _explore_tests() -> void:
	_explore_mapgen_tests()
	await _wheel_tests()
	await _treasure_tests()
	await _outpost_tests()
	await _fog_tests()

func _explore_mapgen_tests() -> void:
	var n_forks := 0
	var n_camp_tr := 0
	for sd in [3, 7, 11, 19]:
		var lay: Dictionary = MapGen.generate(sd, 3200.0, 2048.0)
		var gw: int = lay.gw
		var cells: PackedByteArray = lay.cells
		var t := Terrain.new()
		t.setup(3200.0, 2048.0)
		for i in cells.size():
			var v: int = cells[i]
			var cc := Vector2i(i % gw, i / gw)
			if v == MapGen.C_TREE or v == MapGen.C_WOODS or v == MapGen.C_ORE or v == MapGen.C_RICH:
				t.set_cell(cc, Terrain.T.WOODS)
			elif v == MapGen.C_WATER:
				t.set_cell(cc, Terrain.T.DEEP)
			elif v == MapGen.C_SHALLOW:
				t.set_cell(cc, Terrain.T.SHALLOW)
		var st: Vector2 = lay.base + Vector2(0, 60)
		# 岔路：每条都从主城走到自己那个巢穴；岔出去那段离主路够远（不是一条加宽的路）
		var roads_ok: bool = lay.roads.size() <= lay.hives.size() + 2
		for ri in lay.roads.size():
			var rd: Array = lay.roads[ri]
			var hp: Vector2 = lay.hives[lay.road_hive[ri]]
			if rd[0].distance_to(lay.base) > 80.0 or rd[rd.size() - 1].distance_to(hp) > 80.0:
				roads_ok = false
			if ri >= lay.hives.size():
				var main_rd: Array = lay.roads[lay.road_hive[ri]]
				var far := 0.0
				for q in rd:
					var dmin := INF
					for q2 in main_rd:
						dmin = minf(dmin, q.distance_to(q2))
					far = maxf(far, dmin)
				if far < 180.0:
					roads_ok = false
		n_forks += lay.roads.size() - lay.hives.size()
		_check(roads_ok, "随机图 seed=%d：%d 条路都从主城通到自己的巢穴，岔路和主路分得开" % [sd, lay.roads.size()])
		# 河：横穿土路，过路的地方架桥（1~3 座，桥面走得通）；浅滩是浅水，从那里趟过去比绕桥近得多
		var rv: Dictionary = lay.river
		var river_ok: bool = not rv.is_empty() and rv.pts.size() >= 20 and rv.hw.size() == rv.pts.size()
		var br_ok: bool = lay.bridges.size() >= 1 and lay.bridges.size() <= 3
		for br in lay.bridges:
			var mid: Vector2 = (br.a + br.b) * 0.5
			if not t.walkable(int(mid.x / 32.0), int(mid.y / 32.0)):
				br_ok = false
		var ford_ok: bool = lay.fords.size() >= 1 and river_ok
		var ford_note := ""
		for fp in lay.fords:
			if not ford_ok:
				break
			var fc := Vector2i(int(fp.x / 32.0), int(fp.y / 32.0))
			if cells[fc.y * gw + fc.x] != MapGen.C_SHALLOW:
				ford_ok = false
				break
			var i := RiverArt._nearest(rv, fp)
			var tan: Vector2 = rv.pts[mini(i + 1, rv.pts.size() - 1)] - rv.pts[maxi(i - 1, 0)]
			var nrm := tan.orthogonal().normalized()
			var off: float = float(rv.hw[i]) + 60.0
			var a: Vector2 = fp + nrm * off
			var b: Vector2 = fp - nrm * off
			var path: PackedVector2Array = t.find_path(a, b)
			var plen := 0.0
			var prev := a
			for q in path:
				plen += prev.distance_to(q)
				prev = q
			ford_note += " %.0f/%.0f" % [plen, a.distance_to(b)]
			if path.is_empty() or plen > a.distance_to(b) * 2.5:
				ford_ok = false
		_check(river_ok and br_ok and ford_ok, "随机图 seed=%d：一条河、%d 座桥走得通、%d 处浅滩趟得过去（路长/直线%s）" % [sd, lay.bridges.size(), lay.fords.size(), ford_note])
		# 水车位：至少一处；磨坊落在岸上、轮心泡进水里（套 build_mgr 的规则），走得到
		var mill_ok: bool = lay.mills.size() >= 1
		for mp in lay.mills:
			var wet := maxf(RiverArt.depth_in(rv, Building.wheel_hub(mp, true)), RiverArt.depth_in(rv, Building.wheel_hub(mp, false)))
			if RiverArt.depth_in(rv, mp) > -BuildManager.WHEEL_BANK or wet < BuildManager.WHEEL_DEEP:
				mill_ok = false
			var mpath: PackedVector2Array = t.find_path(st, mp)
			if mpath.is_empty() or mpath[mpath.size() - 1].distance_to(mp) > 60.0:
				mill_ok = false
		_check(mill_ok, "随机图 seed=%d：河边留了 %d 处水车位，磨坊在岸上、轮子泡在水里，走得到" % [sd, lay.mills.size()])
		# 宝箱遗物：至少 4 箱 1 件，都走得到、不压土路；遗物不重样
		var tr_ok: bool = lay.chests.size() >= 4 and lay.relics.size() >= 1
		var ids := {}
		for d in lay.chests + lay.relics:
			var p: Vector2 = d.pos
			if t.find_path(st, p).is_empty() or MapGen._near_road(lay.roads, p, 40.0):
				tr_ok = false
			if d.get("camp", false):
				n_camp_tr += 1
		for d in lay.relics:
			if ids.has(d.id) or not Relic.DEFS.has(d.id):
				tr_ok = false
			ids[d.id] = true
		for d in lay.chests:
			if d.loot.is_empty():
				tr_ok = false
		_check(tr_ok, "随机图 seed=%d：%d 个宝箱 %d 件遗物，都走得到、不压土路、遗物不重样" % [sd, lay.chests.size(), lay.relics.size()])
		if sd == 3:
			var again: Dictionary = MapGen.generate(sd, 3200.0, 2048.0)
			_check(again.river.pts == rv.pts and again.fords == lay.fords and again.chests.size() == lay.chests.size()
				and again.relics.map(func(r): return r.id) == lay.relics.map(func(r): return r.id) and again.roads.size() == lay.roads.size(),
				"同一个 seed 同一条河、同一套岔路和宝贝")
		t.free()
	_check(n_forks >= 1, "随机图会分叉：4 张图共 %d 条岔路" % n_forks)
	_check(n_camp_tr >= 4, "据点窝边藏着宝箱 / 遗物（4 张图共 %d 件）" % n_camp_tr)

## 别的人和房子先冻住（自动采集、交货、箭塔放箭会混进账里）
func _freeze_own() -> Array:
	var frozen: Array = []
	for grp in ["player_units", "buildings"]:
		for n in m.get_tree().get_nodes_in_group(grp):
			if is_instance_valid(n) and n.process_mode != Node.PROCESS_MODE_DISABLED and not (n is Building and n.team != 0):
				n.process_mode = Node.PROCESS_MODE_DISABLED
				frozen.append(n)
	return frozen

func _unfreeze(frozen: Array) -> void:
	for n in frozen:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT

func _ruins_at(p: Vector2) -> Ruins:
	for b in m.get_tree().get_nodes_in_group("buildings"):
		if b is Ruins and is_instance_valid(b) and not b.is_queued_for_deletion() and b.position.distance_to(p) < 4.0:
			return b
	return null

func _site_at(p: Vector2) -> ConstructionSite:
	for s in m.get_tree().get_nodes_in_group("sites"):
		if is_instance_valid(s) and not s.is_queued_for_deletion() and s.position.distance_to(p) < 2.0:
			return s
	return null

## 这个点放房子，除了水以外的条件都满足（离边界、建筑、工地、矿树、土路都够远）
func _dry_ok(q: Vector2, kind: String) -> bool:
	if q.x < 60.0 or q.x > m.W - 60.0 or q.y < 110.0 or q.y > m.H - 100.0:
		return false
	for b in m.get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and q.distance_to(b.position) < b.size + 50.0 + (Camp.NO_BUILD_R if b.kind == "camp" else 0.0):
			return false
	for s in m.get_tree().get_nodes_in_group("sites"):
		if is_instance_valid(s) and q.distance_to(s.position) < s.size + 40.0:
			return false
	for n in m.get_tree().get_nodes_in_group("res_nodes"):
		if is_instance_valid(n) and q.distance_to(n.position) < 64.0:
			return false
	var half: float = Building.size_of(kind) * 0.5
	for rd in m.roads:
		for i in rd.size() - 1:
			if Geometry2D.get_closest_point_to_segment(q, rd[i], rd[i + 1]).distance_to(q) < half + 36.0:
				return false
	return true

## center 周围 rmin~rmax 一圈找块空地（离建筑、工地、矿树、宝箱都远点），找不到 = INF
func _open_spot(center: Vector2, rmin: float, rmax: float) -> Vector2:
	for ri in 4:
		var r := lerpf(rmin, rmax, ri / 3.0)
		for k in 16:
			var p := center + Vector2.from_angle(TAU * k / 16.0 + ri * 0.4) * r
			if p.x < 60.0 or p.x > m.W - 60.0 or p.y < 110.0 or p.y > m.H - 100.0 or m.area_blocked(p, 30.0):
				continue
			var ok := true
			for grp in ["buildings", "sites", "res_nodes", "treasures", "player_units"]:
				for n in m.get_tree().get_nodes_in_group(grp):
					if not is_instance_valid(n):
						continue
					var need := 50.0
					if n is Building or n is ConstructionSite:
						need = n.size * 0.6 + 40.0
					elif grp == "player_units":
						need = 36.0
					if n.position.distance_to(p) < need:
						ok = false
			if ok and not m.terrain.find_path(m.base.position + Vector2(0, 80), p).is_empty():
				return p
	return Vector2.INF

## 离己方单位 / 建筑 / 工地 / 矿 / 怪都最远的一块空地；剑士弓手离得比 soldier_r 远（摆据点、废墟用）
func _far_spot(soldier_r := 0.0) -> Vector2:
	var spot := Vector2.ZERO
	var best := -1.0
	for y in range(150, int(m.H) - 130, 30):
		for x in range(170, int(m.W) - 170, 30):
			var p := Vector2(x, y)
			if m.area_blocked(p, 40.0):
				continue
			var dmin := INF
			var near_soldier := false
			for grp in ["player_units", "buildings", "sites", "enemies", "res_nodes", "treasures"]:
				for n in m.get_tree().get_nodes_in_group(grp):
					if not is_instance_valid(n) or n.is_queued_for_deletion():
						continue
					var d: float = n.position.distance_to(p)
					if n is Soldier and d < soldier_r:
						near_soldier = true
					if grp == "enemies":
						d += 60.0
					elif grp == "res_nodes":
						d += 100.0
					dmin = minf(dmin, d)
			if not near_soldier and dmin > best:
				best = dmin
				spot = p
	return spot

## ---- 水车：贴着河岸盖、轮子朝水；带动附近两条加工线一批 ×0.7 ----
func _wheel_tests() -> void:
	var tree := m.get_tree()
	var bm: BuildManager = m._build_mgr
	var e: Economy = m.economy
	m._deselect_all()
	var engs: Array = m._player_engineers()
	if not engs.is_empty():
		m._set_selection([engs[0]])
		var keys := _cmd_keys(false)
		e.wood += 200.0
		e.plank += 50.0
		m.run_hotkey("D")
		var pk: String = m._placing_kind
		m._placing_kind = ""
		m._build_eng = null
		_check(keys.contains("D=waterwheel") and keys.contains("F=outpost") and pk == "waterwheel", "工程师命令卡：D 水车、F 前哨，D 进放置（%s）" % keys)
		m._deselect_all()
	# 经典图没有河：找块空地，临时摆一条竖着的河（中线 + 半宽当画出来的水面，格子刷成深水）
	var c := Vector2.INF
	for gy in range(4, 19):
		for gx in range(5, 36):
			var p := Vector2(gx * 32 + 16, gy * 32 + 16)
			if not (_dry_ok(p + Vector2(-100, 0), "waterwheel") and _dry_ok(p + Vector2(-56, 0), "waterwheel") and _dry_ok(p + Vector2(56, 0), "waterwheel")
					and _dry_ok(p + Vector2(-10, 0), "waterwheel") and _dry_ok(p, "warehouse")):
				continue
			var busy := false
			for grp in ["buildings", "sites", "res_nodes", "treasures", "player_units", "enemies"]:
				for n in tree.get_nodes_in_group(grp):
					if is_instance_valid(n) and absf(n.position.x - p.x) < 100.0 and absf(n.position.y - p.y) < 210.0:
						busy = true
			for b in m.processors_list:
				if is_instance_valid(b) and b.position.distance_to(p) < 300.0:
					busy = true
			if not busy:
				c = p
				break
		if c != Vector2.INF:
			break
	_check(c != Vector2.INF, "经典图找到摆临时河的空地 %s" % c)
	if c == Vector2.INF:
		return
	var frozen := _freeze_own()
	var pts: Array = []
	var hws: Array = []
	for i in 17:
		pts.append(c + Vector2(0, -160 + i * 20))
		hws.append(36.0)
	RiverArt.river = {"pts": pts, "hw": hws}
	var ter: Terrain = m.terrain
	var painted: Array = []
	var cx := int(c.x / 32.0)
	var cy := int(c.y / 32.0)
	for gy in range(cy - 5, cy + 6):
		for gx in range(cx - 1, cx + 2):
			if ter.in_bounds(gx, gy):
				painted.append([Vector2i(gx, gy), ter.cell_type(Vector2i(gx, gy))])
				ter.set_cell(Vector2i(gx, gy), Terrain.T.DEEP)
	var west := c + Vector2(-56, 0)
	var east := c + Vector2(56, 0)
	var e_far: String = bm.placement_error(c + Vector2(-100, 0), "waterwheel")
	var e_wet: String = bm.placement_error(c + Vector2(-10, 0), "waterwheel")
	var e_w: String = bm.placement_error(west, "waterwheel")
	var e_e: String = bm.placement_error(east, "waterwheel")
	_check(e_far.contains("贴着河") and e_wet.contains("岸上") and e_w == "" and e_e == "",
		"水车：离河远了不行、压进水里不行、两岸贴着河都能盖（%s / %s / %s / %s）" % [e_far, e_wet, e_w, e_e])
	_check(not Building.wheel_flip_at(west) and Building.wheel_flip_at(east) and RiverArt.water_depth(Building.wheel_hub(west, false)) >= BuildManager.WHEEL_DEEP,
		"轮子朝着河：西岸朝右、东岸镜像朝左，轮心泡在水里")
	var e_wh: String = bm.placement_error(c, "warehouse")
	var e_wh2: String = bm.placement_error(west, "warehouse")
	_check(e_wh.contains("河") and e_wh2.contains("河"), "别的房子不许压河（%s / %s）" % [e_wh, e_wh2])
	# 没有河的几何数据（经典图）：按深水格判断
	RiverArt.river = {}
	var g_ok: String = bm.placement_error(west, "waterwheel")
	var g_far: String = bm.placement_error(c + Vector2(-100, 0), "waterwheel")
	var g_flip := Building.wheel_flip_at(east)
	RiverArt.river = {"pts": pts, "hw": hws}
	_check(g_ok == "" and g_far.contains("贴着河") and g_flip, "没有河的画面数据时按深水格判断（%s / %s）" % [g_ok, g_far])
	# 盖起来：扣钱 → 工地 → 完工记进水车列表
	e.wood += 300.0
	e.plank += 100.0
	var wood0 := e.wood
	var plank0 := e.plank
	var r0: int = bm.try_place("waterwheel", west, null)
	var site := _site_at(west)
	_check(r0 == 0 and site != null and absf(e.wood - (wood0 - 50.0)) < 0.5 and absf(e.plank - (plank0 - 20.0)) < 0.5, "放水车：扣 50 木 20 木板，落下工地")
	var wh: Building = null
	if site != null:
		bm.complete_site(site)
		await tree.process_frame
		for b in m.wheels:
			if is_instance_valid(b) and b.position == west:
				wh = b
	_check(wh != null and wh.kind == "waterwheel" and not wh.wheel_flip, "水车盖好：记进水车列表，轮子朝河")
	if wh != null:
		var p1: Building = bm.add_building("smelter", c + Vector2(-150, -60), 0)
		var p2: Building = bm.add_building("workshop", c + Vector2(-170, 60), 0)
		var p3: Building = bm.add_building("smelter", c + Vector2(150, 80), 0)
		for b in [p1, p2, p3]:
			b.process_mode = Node.PROCESS_MODE_DISABLED
			bm.building_built.emit(b)
		_check(p1.powered() and p2.powered() and not p3.powered() and wh.powering.size() == Building.WHEEL_MAX and p3.position.distance_to(wh.position) < Building.WHEEL_R,
			"一架水车只带最近的两条线，第三座在范围里也带不动")
		_check(is_equal_approx(p1.batch_time() / p3.batch_time(), Building.WHEEL_MULT), "被带动的熔炉一批快 30%%（%.1f → %.1f 秒）" % [p3.batch_time(), p1.batch_time()])
		m._set_selection([wh])
		var ti: String = m._selected_info_text()
		m._set_selection([p1])
		var tp: String = m._selected_info_text()
		m._deselect_all()
		_check(ti.contains("带动 2/2") and tp.contains("水车带动"), "信息栏：水车带了几条线、加工线写着被水车带动（%s）" % ti.get_slice("\n", 0))
		p1.queue_free()
		await tree.create_timer(0.7).timeout
		_check(p3.powered() and p2.powered(), "拆掉一座，空出来的名额给下一座")
		wh.take_damage(99999.0)
		await tree.create_timer(0.7).timeout
		_check(not p2.powered() and not p3.powered() and not m.wheels.has(wh), "水车被拆：加工线恢复原速")
		p2.queue_free()
		p3.queue_free()
	for pc in painted:
		ter.set_cell(pc[0], pc[1])
	RiverArt.river = {}
	_unfreeze(frozen)
	await tree.process_frame

## ---- 宝箱 / 遗物：选农民右键 → 走过去扛起来 → 扛回收货点才到手；死了掉在原地 ----
func _treasure_tests() -> void:
	var tree := m.get_tree()
	var e: Economy = m.economy
	Relic.reset()
	m._deselect_all()
	var frozen := _freeze_own()
	var w := Worker.new()
	w.position = m.open_point(m.base.position + Vector2(100, -100))
	m.add_child(w)
	await tree.create_timer(0.1).timeout
	var cp := _open_spot(m.base.position, 170.0, 300.0)
	_check(cp != Vector2.INF, "基地附近找得到放宝箱的空地 %s" % cp)
	if cp == Vector2.INF:
		w.queue_free()
		_unfreeze(frozen)
		return
	var ch: Treasure = m.spawn_treasure({"kind": "chest", "loot": {"ore": 50, "wood": 30}}, cp)
	await tree.process_frame
	_check(m._thing_at(ch.position) == ch and m._treasure_at(ch.position + Vector2(0, -12)) == ch, "宝箱点得中")
	m._point_select(ch.position + Vector2(0, -8))
	var it: String = m._selected_info_text()
	await tree.create_timer(0.1).timeout
	_check(m.inspected == ch and ch.selected and it.contains("宝箱") and it.contains("50 矿石"), "点宝箱：信息栏写着开出来什么（%s）" % it.get_slice("\n", 0))
	m._deselect_all()
	ch.selected = false
	var ore0 := e.ore
	var wood0 := e.wood
	m._set_selection([w])
	m._issue_command(ch.position)
	_check(w.state == Worker.State.FETCH and w.fetch_target == ch and w.job_text().contains("去捡宝箱"), "选农民右键宝箱：走过去捡（%s）" % w.job_text())
	var picked := false
	for i in 100:
		await tree.create_timer(0.1).timeout
		if not w.treasure.is_empty():
			picked = true
			break
	var gone := not is_instance_valid(ch) or ch.is_queued_for_deletion()    # 计时器可能和捡起同一帧：还没真删
	_check(picked and gone and w.state == Worker.State.TO_BASE and w.job_text().contains("扛着宝箱"),
		"走到跟前弯腰扛起来，往回走（%s · 状态 %d · 箱子%s）" % [w.job_text(), w.state, "没了" if gone else "还在"])
	var claimed := false
	for i in 140:
		await tree.create_timer(0.1).timeout
		if w.treasure.is_empty():
			claimed = true
			break
	_check(claimed and is_equal_approx(e.ore - ore0, 50.0) and is_equal_approx(e.wood - wood0, 30.0) and w.state == Worker.State.IDLE,
		"扛回收货点开箱：+50 矿 +30 木，农民原地待命（+%.0f / +%.0f）" % [e.ore - ore0, e.wood - wood0])
	m._deselect_all()
	# 遗物：丰饶号角，扛回去采集快 20%；扛着的时候派去捡别的 = 先把手上这件送回去
	var gr0 := Worker.gather_rate()
	var rp := _open_spot(m.base.position, 170.0, 300.0)
	var rl: Treasure = m.spawn_treasure({"kind": "relic", "relic": "relic_horn"}, rp if rp != Vector2.INF else cp)
	await tree.process_frame
	_check(w.command_fetch(rl), "派农民去扛遗物")
	picked = false
	for i in 100:
		await tree.create_timer(0.1).timeout
		if not w.treasure.is_empty():
			picked = true
			break
	var extra: Treasure = m.spawn_treasure({"kind": "chest", "loot": {"ore": 10}}, w.position + Vector2(50, 0))
	_check(picked and w.job_text().contains("遗物") and not w.command_fetch(extra) and w.treasure.get("relic", "") == "relic_horn" and w.state == Worker.State.TO_BASE,
		"扛着遗物再派去捡宝箱：一次只扛一件，先送回去（%s）" % w.job_text())
	claimed = false
	for i in 140:
		await tree.create_timer(0.1).timeout
		if w.treasure.is_empty():
			claimed = true
			break
	_check(claimed and Relic.has("relic_horn") and is_equal_approx(Worker.gather_rate() / gr0, Relic.HORN_MULT),
		"丰饶号角到手：采集快 20%%（%.2f → %.2f）" % [gr0, Worker.gather_rate()])
	# 扛着宝贝的农民死了：东西掉在原地
	extra.queue_free()
	w.treasure = {"kind": "chest", "loot": {"ore": 11}, "relic": ""}
	var dp := w.position
	w.take_damage(99999.0)
	await tree.process_frame
	var drop: Treasure = null
	for t in tree.get_nodes_in_group("treasures"):
		if is_instance_valid(t) and not t.is_queued_for_deletion() and t.position.distance_to(dp) < 40.0 and t.kind == "chest" and int(t.loot.get("ore", 0)) == 11:
			drop = t
	_check(drop != null, "扛着宝箱的农民死了：箱子掉在原地，再派人来捡")
	if drop != null:
		drop.queue_free()
	# 其余几件遗物：直接记账看效果
	var bmax0: float = m.base.max_hp
	var bfrac: float = m.base.hp / m.base.max_hp
	m.claim_treasure({"kind": "relic", "relic": "relic_heart"}, m.base.position)
	_check(is_equal_approx(m.base.max_hp, bmax0 * Relic.HEART_MULT) and is_equal_approx(m.base.hp / m.base.max_hp, bfrac),
		"磐石之心：基地血量上限 %.0f → %.0f，按比例回血" % [bmax0, m.base.max_hp])
	var nb: Building = m._build_mgr.add_building("warehouse", Vector2(-400, -400), 0)
	var ref := Building.new()
	ref.setup("warehouse")
	_check(is_equal_approx(nb.max_hp, ref.max_hp * Relic.HEART_MULT) and is_equal_approx(nb.hp, nb.max_hp), "磐石之心：之后盖的房子也结实 25%")
	ref.free()
	nb.queue_free()
	m.claim_treasure({"kind": "relic", "relic": "relic_heart"}, m.base.position)
	_check(is_equal_approx(m.base.max_hp, bmax0 * Relic.HEART_MULT), "同一件遗物不会叠两次")
	var rg0: float = m.base.tower_stats().range
	m.claim_treasure({"kind": "relic", "relic": "relic_eye"}, m.base.position)
	_check(is_equal_approx(m.base.tower_stats().range, rg0 + Relic.EYE_RANGE) and is_equal_approx(Building.TOWER_LV[1].range, 190.0), "鹰眼石：基地射程 %.0f → %.0f（常量表没被改）" % [rg0, m.base.tower_stats().range])
	var sm: Building = m._build_mgr.add_building("smelter", Vector2(-400, -400), 0)
	var bt0: float = sm.batch_time()
	m.claim_treasure({"kind": "relic", "relic": "relic_gear"}, m.base.position)
	_check(is_equal_approx(sm.batch_time(), bt0 * Relic.GEAR_MULT), "古老齿轮：熔炉一批 %.1f → %.1f 秒" % [bt0, sm.batch_time()])
	sm.queue_free()
	var w2 := Worker.new()
	w2.position = m.open_point(m.base.position + Vector2(100, -60))
	m.add_child(w2)
	await tree.process_frame
	var sf0: float = w2._terrain_speed_factor()
	var eng: Engineer = m._player_engineers()[0] if not m._player_engineers().is_empty() else null
	var ef0: float = eng._terrain_speed_factor() if eng != null else 1.0
	m.claim_treasure({"kind": "relic", "relic": "relic_boots"}, m.base.position)
	_check(is_equal_approx(w2._terrain_speed_factor() / sf0, Relic.BOOTS_MULT) and (eng == null or is_equal_approx(eng._terrain_speed_factor() / ef0, Relic.BOOTS_MULT)),
		"疾风靴：农民、工程师移速 ×1.15")
	w2.queue_free()
	m.select_base()
	var bt: String = m._selected_info_text()
	_check(bt.contains("遗物：古老齿轮、鹰眼石、丰饶号角、疾风靴、磐石之心"), "基地信息栏列出到手的遗物（%s）" % bt.get_slice("\n", bt.get_slice_count("\n") - 1))
	m._deselect_all()
	# 收尾：遗物清掉，磐石之心加的血还回去（后面的测试按原数值写的）
	Relic.reset()
	for b in tree.get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.team == 0:
			b.max_hp /= Relic.HEART_MULT
			b.hp /= Relic.HEART_MULT
	_check(is_equal_approx(m.base.max_hp, bmax0) and is_equal_approx(Worker.gather_rate() / gr0, 1.0), "遗物清零后恢复原数值")
	_unfreeze(frozen)

## ---- 废墟 / 前哨：拆了窝没人看着就倒计时，Goo 回来重新占；兵守着 / 前哨工地停表；盖好前哨 = 永久占下 ----
func _outpost_tests() -> void:
	var tree := m.get_tree()
	var bm: BuildManager = m._build_mgr
	var e: Economy = m.economy
	m._deselect_all()
	var frozen := _freeze_own()
	var spot := _far_spot(Ruins.HOLD_R + 40.0)
	var c: Camp = m.add_camp(spot, 1)
	await tree.create_timer(0.3).timeout
	var gs: Array = c.alive_guards().duplicate()
	for g in gs:
		g.take_damage(99999.0)
	await tree.process_frame
	var ore0 := e.ore
	c.take_damage(99999.0)
	var d0 := e.ore - ore0
	await tree.create_timer(0.7).timeout
	var r := _ruins_at(spot)
	_check(gs.size() == 3 and is_equal_approx(d0, 80.0) and r != null and r.tier == 1 and is_equal_approx(r.loot_mult, 0.5),
		"一档据点：守军清光再拆窝缴获 %.0f 矿，留下一片废墟" % d0)
	if r == null:
		_unfreeze(frozen)
		return
	_check(r.hold == "" and r.left < Ruins.REOCCUPY and r.left > Ruins.REOCCUPY - 1.5, "废墟没人看着：开始倒计时（还剩 %.1f 秒）" % r.left)
	m._point_select(spot)
	var rt: String = m._selected_info_text()
	_check(m.inspected == r and rt.contains("没人看着") and rt.contains("前哨"), "点废墟：显示倒计时和怎么守住（%s）" % rt.get_slice("\n", 0))
	m._deselect_all()
	# 兵站在旁边：停表
	var sd := Soldier.new()
	sd.setup(false)
	sd.position = m.open_point(spot + Vector2(-150, 40))
	m.add_child(sd)
	sd.process_mode = Node.PROCESS_MODE_DISABLED
	await tree.create_timer(0.7).timeout
	var l1 := r.left
	await tree.create_timer(0.5).timeout
	_check(r.hold == "soldiers" and is_equal_approx(r.left, l1) and r.status_text().contains("有兵守着"), "有兵站在废墟旁：倒计时停住（%s）" % r.hold)
	sd.queue_free()
	await tree.create_timer(0.7).timeout
	_check(r.hold == "" and r.left < l1, "兵走了接着倒计时")
	r.left = Ruins.WARN_AT + 0.2
	await tree.create_timer(0.6).timeout
	_check(r._warned and m._hud_msg_label.text.contains("回来占窝"), "还剩 %d 秒：横幅提醒派兵或盖前哨" % int(Ruins.WARN_AT))
	# 到点：Goo 回来重新占
	r.left = 0.2
	await tree.create_timer(0.6).timeout
	var c2: Camp = null
	for cc in m.camps:
		if is_instance_valid(cc) and not cc.is_queued_for_deletion() and cc.position.distance_to(spot) < 4.0:
			c2 = cc
	_check(not is_instance_valid(r) and c2 != null and c2.tier == 1 and c2.alive_guards().size() == 3 and c2.spotted and is_equal_approx(c2.loot_mult, 0.5),
		"没人看着到点：Goo 回来重新占窝，守军刷满")
	if c2 == null:
		_unfreeze(frozen)
		return
	var lt: Dictionary = c2.loot()
	_check(int(lt.get("ore", 0)) == 40 and int(lt.get("wood", 0)) == 30, "回来占的窝再拆只缴获一半（%s）" % e.cost_text(lt))
	for g in c2.alive_guards():
		g.take_damage(99999.0)
	await tree.process_frame
	var ore1 := e.ore
	c2.take_damage(99999.0)
	var d1 := e.ore - ore1
	await tree.create_timer(0.6).timeout
	var r2 := _ruins_at(spot)
	_check(is_equal_approx(d1, 40.0) and r2 != null and is_equal_approx(r2.loot_mult, 0.25), "再拆一次缴获 %.0f 矿；再让 Goo 回来就只剩四分之一" % d1)
	if r2 == null:
		_unfreeze(frozen)
		return
	# 前哨：只能盖在废墟旁
	var e_far: String = bm.placement_error(m.base.position + Vector2(120, -120), "outpost")
	_check(e_far.contains("废墟"), "前哨只能盖在据点废墟旁（%s）" % e_far)
	var op_pos := Vector2.INF
	for k in 16:
		var p: Vector2 = spot + Vector2.from_angle(TAU * k / 16.0) * 150.0
		if bm.placement_error(p, "outpost") == "":
			op_pos = p
			break
	_check(op_pos != Vector2.INF, "废墟旁找得到盖前哨的地方 %s" % op_pos)
	if op_pos == Vector2.INF:
		r2.queue_free()
		_unfreeze(frozen)
		return
	e.wood += 200.0
	e.ore += 200.0
	var wood0 := e.wood
	var ore2 := e.ore
	var res: int = bm.try_place("outpost", op_pos, null)
	var site := _site_at(op_pos)
	_check(res == 0 and site != null and is_equal_approx(e.wood, wood0 - 80.0) and is_equal_approx(e.ore, ore2 - 60.0) and is_equal_approx(site.build_time, 10.0),
		"放前哨：扣 80 木 60 矿，工地敲 10 秒")
	await tree.create_timer(0.7).timeout
	var other: Vector2 = spot - (op_pos - spot).normalized() * 60.0
	_check(r2.hold == "site" and bm.placement_error(other, "outpost").contains("已经在盖"), "前哨施工中：废墟停表，一片废墟只盖一座（%s）" % r2.hold)
	var op: Building = null
	if site != null:
		bm.complete_site(site)
		await tree.process_frame
		await tree.process_frame
		for b in tree.get_nodes_in_group("buildings"):
			if is_instance_valid(b) and b.kind == "outpost" and b.position == op_pos:
				op = b
	_check(op != null and not is_instance_valid(r2), "前哨盖好：废墟清掉，Goo 再也回不来")
	if op != null:
		_check(op.has_tower() and op.trains() and is_equal_approx(op.tower_stats().range, Building.OUTPOST_TOWER.range), "前哨：塔上一名弓手（射程 %d）、能造农民" % int(Building.OUTPOST_TOWER.range))
		m._set_selection([op])
		var keys := _cmd_keys(false)
		var ot: String = m._selected_info_text()
		m._deselect_all()
		_check(keys.contains("Q=worker") and ot.contains("交货"), "选中前哨：命令卡能造农民，信息栏写着能交货（%s）" % keys)
		var wk := Worker.new()
		wk.position = m.open_point(op_pos + Vector2(0, 70))
		m.add_child(wk)
		await tree.process_frame
		_check(wk._store() == op and wk._depot() == op and m._friendly_depot_at(op_pos) == op, "前哨是收货点：旁边的农民就近交货")
		wk.queue_free()
		op.queue_free()
	_unfreeze(frozen)
	await tree.process_frame

## ---- 战争迷雾：没去过 = 黑；去过没人看着 = 灰（宝箱、敌方房子照样看得见，怪看不见）；没探过的地方不许盖房 ----
func _fog_tests() -> void:
	var tree := m.get_tree()
	var f := Fog.new()
	m.add_child(f)
	f.setup(m.W, m.H)
	_check(f.gw == int(ceil(m.W / Fog.CELL)) and f.gh == int(ceil(m.H / Fog.CELL)) and f.mini_tex != null and f.mini_tex.get_width() == f.gw
		and is_equal_approx(Fog.sight_of(m.base), Fog.SIGHT.base), "迷雾 32px 一格铺满地图，小地图那层每格一像素")
	_check(not f.explored_at(m.base.position) and not f.visible_at(m.base.position), "刚铺上：哪儿都没去过")
	f.reveal(Vector2(640, 360), 100.0)
	_check(f.explored_at(Vector2(640, 360)) and not f.explored_at(Vector2(640, 520)) and not f.visible_at(Vector2(640, 360)), "开局揭开的地方算去过，但不算看得见")
	f.refresh()
	_check(f.visible_at(m.base.position) and f.explored_at(m.base.position), "己方房子周围看得见，也算去过")
	# 找一块谁都看不见的地方
	var hide := Vector2.INF
	var best := 0.0
	for y in range(130, int(m.H) - 100, 32):
		for x in range(80, int(m.W) - 80, 32):
			var p := Vector2(x, y)
			var marg := INF
			for grp in ["player_units", "buildings", "sites"]:
				for n in tree.get_nodes_in_group(grp):
					if not is_instance_valid(n) or (grp == "buildings" and n.team != 0):
						continue
					marg = minf(marg, n.position.distance_to(p) - (Fog.SIGHT.site if grp == "sites" else Fog.sight_of(n)))
			if marg > best:
				best = marg
				hide = p
	_check(best > 48.0, "经典图上有块谁都看不见的地方 %s（离视野边 %.0f）" % [hide, best])
	if best > 48.0:
		var g := Goo.make("goo")
		g.position = hide
		m.add_child(g)
		g.process_mode = Node.PROCESS_MODE_DISABLED
		var tr: Treasure = m.spawn_treasure({"kind": "chest", "loot": {"ore": 5}}, hide + Vector2(24, 0))
		f.refresh()
		_check(not g.visible and not tr.visible and m._thing_at(g.position) != g and m._treasure_at(tr.position) == null, "没人看着的地方：怪和宝箱藏在雾里，点不中")
		f.reveal(hide, 120.0)
		f.refresh()
		_check(not g.visible and tr.visible, "去过、现在没人看着：宝箱照样看得见，怪看不见")
		var hp0: Vector2 = g.position
		g.position = m.base.position + Vector2(60, 40)
		f.refresh()
		var seen := g.visible
		g.position = hp0
		f.refresh()
		_check(seen and not g.visible, "怪走进己方视野就露出来，走开又藏起来")
		var unexp := Vector2.INF
		for y in range(130, int(m.H) - 100, 32):
			for x in range(80, int(m.W) - 80, 32):
				if not f.explored_at(Vector2(x, y)):
					unexp = Vector2(x, y)
		m.fog = f
		var pe: String = m._build_mgr.placement_error(unexp, "warehouse") if unexp != Vector2.INF else ""
		var pe2: String = m._build_mgr.placement_error(m.base.position + Vector2(0, -150), "warehouse")
		var fv: bool = m.fog_visible(m.base.position) and not m.fog_explored(unexp)
		m.fog = null
		_check(pe.contains("探") and not pe2.contains("探") and fv, "没探过的地方不许盖房（%s），探过的照常判断" % pe)
		f.set_enabled(false)
		_check(g.visible and tr.visible and f.visible_at(hide) and m.hive.visible, "关掉迷雾：全都看得见")
		g.queue_free()
		tr.queue_free()
	f.set_enabled(false)
	f.queue_free()
	await tree.process_frame

## ---- 警钟：敲钟农民就近进屋躲（满了换一处）、躲进会射箭的房子每人每轮多射一箭、怪打不着选不中；再敲解除，各回各的活 ----
func _new_worker(p: Vector2) -> Worker:
	var w := Worker.new()
	w.position = m.open_point(p)
	m.add_child(w)
	return w

## 最多等 secs 秒，cond 一成立就返回 true
func _wait_for(cond: Callable, secs: float) -> bool:
	var tree := m.get_tree()
	var t := 0.0
	while t < secs:
		if cond.call():
			return true
		await tree.create_timer(0.2).timeout
		t += 0.2
	return cond.call()

func _bell_tests() -> void:
	var tree := m.get_tree()
	var bm: BuildManager = m._build_mgr
	var e: Economy = m.economy
	if m.alarm_on:
		m.all_clear()
	m._deselect_all()
	# 干净的场子：原有的农民各有各的差事（会搅乱位子和账），先清掉；基地附近的怪也清掉（别混进放箭的账）
	for w in m._player_workers():
		w._leave_work()
		w.queue_free()
	for en in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(en) and not en.is_guard() and en.position.distance_to(m.base.position) < 1000.0:
			en.queue_free()
	await tree.process_frame
	var bp: Vector2 = m.base.position
	var spot := _open_spot(bp + Vector2(330, -150), 0.0, 80.0)
	if spot == Vector2.INF:
		spot = _open_spot(bp, 260.0, 460.0)
	var sp2 := _open_spot(bp + Vector2(-10, -190), 0.0, 80.0)
	_check(spot != Vector2.INF and sp2 != Vector2.INF, "找到摆箭塔 / 熔炉的空地")
	if spot == Vector2.INF or sp2 == Vector2.INF:
		return
	var tw: Building = bm.add_building("tower", spot, 0)
	var sm: Building = bm.add_building("smelter", sp2, 0)
	bm.building_built.emit(sm)
	await tree.process_frame
	tw.level = 2
	var cap2 := tw.shelter_cap()
	tw.level = 1
	_check(tw.shelter_cap() == 3 and cap2 == 4 and m.base.shelter_cap() == 10 and sm.shelter_cap() == 0 and not m.hive.can_shelter(),
		"能躲的人数：箭塔 3（二级 4）、基地 10；熔炉、巢穴躲不了")

	# 箭塔边 5 个闲人（最后一个正往别处走）、基地门口一个扛着矿回来的、一个去采矿的、一个熔炉的工人
	var by_tw: Array = []
	for i in 5:
		by_tw.append(_new_worker(spot + Vector2(-40.0 + 20.0 * i, 46.0)))
	var wc := _new_worker(bp + Vector2(20, m.base.size * 0.5 + 22.0))
	var wg := _new_worker(bp + Vector2(-60, 70))
	var wo := _new_worker(sp2 + Vector2(40, 50))
	await tree.process_frame
	var ng: ResNode = wg._nearest_node("ore")
	if ng == null:
		ng = wg._nearest_node("wood")
	wg.command_gather(ng)
	var op_ok := wo.command_operate(sm)
	wc.carry_kind = "ore"
	wc.carry_amount = 8.0
	wc._back_to_base()
	var mv: Vector2 = m.open_point(spot + Vector2(-180, 110))
	by_tw[4].command_move(mv)
	m._set_selection(by_tw)
	m._save_control_group(7)
	var all8: Array = by_tw.duplicate()
	all8.append_array([wc, wg, wo])
	var ore0 := e.ore
	m.ring_bell()
	var to_tw: Array = by_tw.filter(func(w): return w.shelter_at == tw)
	var away: Array = by_tw.filter(func(w): return is_instance_valid(w.shelter_at) and w.shelter_at != tw)
	_check(m.alarm_on and Building.alarm_on and m.sfx.last == "bell" and m._hud_msg_label.text.contains("敲响警钟"),
		"敲警钟：钟响、横幅提示（%s）" % m._hud_msg_label.text)
	_check(all8.all(func(w): return w.state == Worker.State.SHELTER), "敲钟后农民全都放下手上的活去躲")
	_check(to_tw.size() == 3 and away.size() == 2 and tw.shelter_free() == 0,
		"箭塔边 5 个农民：3 个占了箭塔的位子、2 个改去别处（%d / %d）" % [to_tw.size(), away.size()])
	_check(op_ok and wo.work_at == null and not sm.operators.has(wo) and wo._resume.get("work_at") == sm, "熔炉的工人让出工位，记着回来接着干")
	_check(ng != null and wg._resume.get("node") == ng and by_tw[4]._resume.has("move") and wc._resume.get("kind") == "ore",
		"采矿的记着矿点、走路的记着要去哪、交货的记着采什么")
	_check(wo.job_text().contains("躲"), "信息栏写着去哪躲（%s）" % wo.job_text())

	var in_all: bool = await _wait_for(func(): return all8.all(func(w): return w.is_garrisoned()), 16.0)
	_check(in_all, "农民全都进屋躲好（%d/%d）" % [all8.filter(func(w): return w.is_garrisoned()).size(), all8.size()])
	_check(tw.sheltered.size() == 3 and to_tw.all(func(w): return w.shelter_in == tw), "箭塔里躲着占了位子的那 3 个")
	_check(all8.all(func(w): return not w.visible and w.process_mode == Node.PROCESS_MODE_DISABLED and not w.is_in_group("player_units") and not w.is_in_group("units")),
		"躲着的农民：藏起来、不动、不在单位组里")
	_check(e.ore - ore0 >= 7.99 and is_zero_approx(wc.carry_amount) and is_instance_valid(wc.shelter_in) and wc.shelter_in.kind != "tower",
		"扛着货躲进收货的房子：顺手交掉（矿 +%.0f）" % (e.ore - ore0))
	_check(m.selected.is_empty(), "躲进屋的农民从选择里拿掉")
	m._recall_control_group(7)
	_check(m.selected.is_empty() and m.control_groups[7].size() == 5, "编队召回：躲着的选不上，编队里还记着")
	var hw: Worker = to_tw[0] if not to_tw.is_empty() else wc
	_check(m._unit_at(hw.position) == null, "点躲着的位置点不到人")
	m._box_select(Rect2(spot - Vector2(80, 80), Vector2(160, 160)))
	_check(not m.selected.any(func(u): return u is Worker and u.is_garrisoned()), "框选也框不到躲着的人")
	m._deselect_all()
	# 怪打不着躲着的人；追着的怪丢掉目标
	var g := Goo.make("goo")
	g.position = m.open_point(spot + Vector2(100, 40))
	m.add_child(g)
	g.process_mode = Node.PROCESS_MODE_DISABLED
	var hp_w: float = hw.hp
	var n_al: int = m.alerts.size()
	hw.take_damage(30.0, g)
	g.attack_target = hw
	var got = g._acquire_target()
	_check(is_equal_approx(hw.hp, hp_w) and m.alerts.size() == n_al and got != hw and g.attack_target == null,
		"躲着的人怪打不着：伤害不吃、不报警，追着的怪丢掉这个目标")
	# 躲进会射箭的房子：每人跟着第一名弓手每轮多射一支
	g.max_hp = 9999.0
	g.hp = 9999.0
	var st: Dictionary = tw.tower_stats()
	var per: float = maxf(st.dmg - g.armor, 1.0)
	tw._arch_cd = [0.0, 0.0]
	var hp1: float = g.hp
	var tgt = tw._tower_target(st.range)
	tw._tower(0.01)
	_check(tgt == g and is_equal_approx(hp1 - g.hp, per * (int(st.archers) + 3)),
		"箭塔里躲着 3 个：一轮 %d + 3 支箭（%.0f 伤害）" % [int(st.archers), hp1 - g.hp])
	var nb: int = m.base.sheltered.size()
	g.position = m.open_point(bp + Vector2(110, 60))
	var stb: Dictionary = m.base.tower_stats()
	var perb: float = maxf(stb.dmg - g.armor, 1.0)
	m.base._arch_cd = [0.0, 0.5]
	var hp2: float = g.hp
	var tgb = m.base._tower_target(stb.range)
	m.base._tower(0.01)
	_check(nb >= 1 and tgb == g and is_equal_approx(hp2 - g.hp, perb * (1 + nb)), "基地里躲着 %d 个：一轮 1 + %d 支箭" % [nb, nb])
	g.queue_free()
	# 人口照算；顶栏按钮、提示栏、信息栏、命令卡
	m.hud.refresh()
	_check(m._player_workers().is_empty() and m.worker_count_hidden() == 8 and m.worker_count() == 8 and m.hud._worker_val.text.begins_with("8/"),
		"躲着的人口照算：顶栏农民 %s" % m.hud._worker_val.text)
	_check(m.hud._bell_btn.text == "解除警报" and m._bottleneck().contains("警钟响着"), "顶栏按钮变成「解除警报」、提示栏说警钟响着")
	m._set_selection([tw])
	var ti: String = m._selected_info_text()
	_check(ti.contains("警钟：躲着 3/3 个农民") and ti.contains("多射一支箭"), "点箭塔：躲着 3/3 个、每人多射一箭（%s）" % ti.get_slice("\n", ti.count("\n")))
	m._set_selection([m.base])
	var bi: String = m._selected_info_text()
	var bc: Array = m.commands().filter(func(c): return c.slot == 14)
	_check(bi.contains("警钟：躲着 %d/10" % nb) and bc.size() == 1 and bc[0].id == "all_clear" and bc[0].key == "B",
		"点基地：信息栏写躲了几个，命令卡 B = 解除")

	# 命令卡「解除」：屋里的出来，各回各的活
	m.run_hotkey("B")
	_check(not m.alarm_on and not Building.alarm_on and m.sfx.last == "clear" and m._hud_msg_label.text.contains("警报解除"),
		"命令卡「解除」：警报解除（%s）" % m._hud_msg_label.text)
	_check(all8.all(func(w): return not w.is_garrisoned() and w.visible and w.is_in_group("player_units") and w.process_mode == Node.PROCESS_MODE_INHERIT and w.state != Worker.State.SHELTER),
		"屋里的农民全出来了")
	_check(tw.sheltered.is_empty() and m.base.sheltered.is_empty() and tw.shelter_free() == 3, "房子都空了")
	_check(wo.state == Worker.State.OPERATE and wo.work_at == sm and sm.operators.has(wo), "熔炉的工人回去守线")
	_check(wg.node_target == ng and (wg.state == Worker.State.TO_NODE or wg.state == Worker.State.GATHERING), "采矿的回原来那处矿")
	_check(is_instance_valid(wc.node_target) and wc.node_target.kind == "ore" and wc.state == Worker.State.TO_NODE, "交完货的接着去采矿")
	_check(by_tw[4].move_target.distance_to(mv) < 2.0 and by_tw.slice(0, 4).all(func(w): return w.state == Worker.State.IDLE),
		"走路的接着往原来要去的地方走、闲着的出来站着")
	m._recall_control_group(7)
	_check(m.selected.size() == 5, "出来以后编队召回又选得上（%d）" % m.selected.size())
	m._set_selection([m.base])
	var bc2: Array = m.commands().filter(func(c): return c.slot == 14)
	m._deselect_all()
	m.hud.refresh()
	_check(m.hud._bell_btn.text == "警钟" and bc2.size() == 1 and bc2[0].id == "bell", "顶栏按钮、命令卡变回「警钟」")

	# 再敲：躲着的箭塔塌了，里面的人跑出来去别处躲
	m.ring_bell()
	var full_tw: bool = await _wait_for(func(): return tw.sheltered.size() == 3, 10.0)
	var ej: Array = tw.sheltered.duplicate()
	tw.take_damage(99999.0)
	_check(full_tw and ej.size() == 3 and ej.all(func(w): return not w.is_garrisoned() and w.visible and w.state == Worker.State.SHELTER and is_instance_valid(w.shelter_at) and w.shelter_at != tw),
		"躲着的箭塔塌了：里面的人跑出来，警钟还响着就去别处躲")
	var re_in: bool = await _wait_for(func(): return ej.all(func(w): return w.is_garrisoned()), 14.0)
	_check(re_in and ej.all(func(w): return is_instance_valid(w.shelter_in) and w.shelter_in.kind != "tower"), "换了一处躲好")

	# 警钟响着时造出来的农民：第一份差事记下，先进屋躲
	m.base.rally = Vector2.INF
	m.base.rally_node = null
	e.ore += 200.0
	e.wood += 200.0
	var known: Array = m._player_workers()
	for w in tree.get_nodes_in_group("garrisoned"):
		known.append(w)
	m._set_selection([m.base])
	m._on_worker_pressed()
	var nw: Array = m._player_workers().filter(func(w): return not known.has(w))
	_check(nw.size() == 1 and nw[0].state == Worker.State.SHELTER and nw[0]._resume.has("node") and is_instance_valid(nw[0].shelter_at),
		"警钟响着时造出的农民：差事记下，先进屋躲着")
	m._deselect_all()

	# 警钟响着时选农民右键仓库 = 指定躲那儿；另外下令 = 不躲了
	var whp := _open_spot(bp + Vector2(280, 70), 0.0, 120.0)
	if whp == Vector2.INF:
		whp = _open_spot(bp, 220.0, 460.0)
	var wh: Building = bm.add_building("warehouse", whp, 0)
	bm.building_built.emit(wh)
	var wm1 := _new_worker(bp + Vector2(70, -90))
	var wm2 := _new_worker(bp + Vector2(100, -90))
	await tree.process_frame
	var bf0: int = m.base.shelter_free()
	m._set_selection([wm1, wm2])
	m._issue_command(wh.position)
	_check(wh.shelter_cap() == 8 and wm1.shelter_at == wh and wm2.shelter_at == wh and wh.shelter_free() == 6 and m.base.shelter_free() == bf0
		and m._hud_msg_label.text.contains("2 个农民去%s躲（2/8）" % wh.display_name),
		"警钟响着时右键仓库：指定躲进这座（%s）" % m._hud_msg_label.text)
	wm2.command_move(wm2.position + Vector2(-60, 0))
	_check(wm2.state == Worker.State.IDLE and wm2.shelter_at == null and wh.shelter_free() == 7, "警钟响着时另外下令：不躲了，听玩家的（位子让出来）")
	m._deselect_all()

	# B 键：解除（路上的掉头）/ 再敲 / 再解除；M 键静音
	var kb := InputEventKey.new()
	kb.keycode = KEY_B
	kb.pressed = true
	m._on_key(kb)
	_check(not m.alarm_on and wm1.state != Worker.State.SHELTER and wm1.shelter_at == null and wh.shelter_free() == 8, "按 B 解除：路上的掉头不躲了")
	_check(tree.get_nodes_in_group("garrisoned").is_empty() and not m._player_workers().any(func(w): return w.state == Worker.State.SHELTER), "解除后没人还躲着")
	m._on_key(kb)
	var on2: bool = m.alarm_on
	m._on_key(kb)
	_check(on2 and not m.alarm_on, "再按 B 又敲响、再按解除")
	kb.keycode = KEY_M
	m._on_key(kb)
	var mute_ok: bool = Sfx.muted and m._hud_msg_label.text.contains("音效：关")
	m.sfx.play("bell")
	var last_ok: bool = m.sfx.last == "bell"
	m._on_key(kb)
	_check(mute_ok and last_ok and not Sfx.muted, "M 静音、再按打开")
	var lens: Array = []
	for k in ["bell", "clear", "alert"]:
		var s := Sfx.stream(k)
		lens.append(s.get_length() if s != null else 0.0)
	_check(lens[0] > 2.0 and lens[1] > 1.0 and lens[2] > 0.5, "音效文件都在：警钟 %.1f 秒、解除 %.1f 秒、报警 %.1f 秒" % lens)

	for w in all8 + nw + [wm1, wm2]:
		if is_instance_valid(w):
			w._leave_work()
			w.queue_free()
	for b in [sm, wh]:
		if is_instance_valid(b):
			b.queue_free()
	await tree.process_frame

## ---- 挨打报警：基地 / 前哨 / 农民被怪打 → 小地图那儿闪红圈 + 号角；同一片接着挨打只续不吹；兵挨打、没来源的伤害不报 ----
func _alert_tests() -> void:
	var tree := m.get_tree()
	var bm: BuildManager = m._build_mgr
	var bp: Vector2 = m.base.position
	m.alerts.clear()
	m._alert_sfx_t = -999.0
	var n0: int = int(m.sfx.played.get("alert", 0))
	var g := Goo.make("goo")
	g.position = Vector2(-600, -600)    # 场外冻住：只当"谁打的"
	m.add_child(g)
	g.process_mode = Node.PROCESS_MODE_DISABLED
	var hp0: float = m.base.hp
	m.base.take_damage(1.0, g)
	_check(m.alerts.size() == 1 and m.alerts[0].what == "base" and int(m.sfx.played.get("alert", 0)) == n0 + 1 and m.sfx.last == "alert",
		"基地挨怪打：报警 + 号角")
	var act: Array = m.active_alerts()
	_check(act.size() == 1 and act[0].pos.distance_to(bp) < 1.0 and m.alert_text(act[0].what) == "基地遭到攻击！", "小地图在基地那儿闪：基地遭到攻击！")
	await tree.create_timer(0.3).timeout
	m.base.take_damage(1.0, g)
	_check(m.alerts.size() == 1 and int(m.sfx.played.get("alert", 0)) == n0 + 1 and float(m.alerts[0].last) > float(m.alerts[0].t0),
		"同一处接着挨打：只续红圈，不再吹号")
	var fp := _open_spot(bp, m.ALERT_R + 80.0, m.ALERT_R + 320.0)
	var wf := _new_worker(fp if fp != Vector2.INF else bp + Vector2(m.ALERT_R + 100.0, -100.0))
	wf.process_mode = Node.PROCESS_MODE_DISABLED
	wf.take_damage(1.0, g)
	_check(m.alerts.size() == 2 and m.alerts[1].what == "worker" and int(m.sfx.played.get("alert", 0)) == n0 + 1,
		"远处农民挨咬：另一处报警，但离上一声号角不到 %d 秒不吹" % int(m.ALERT_SFX_GAP))
	# 消停了：ALERT_HOLD 秒没再挨打，这处清掉
	for a in m.alerts:
		a.last = float(a.last) - m.ALERT_HOLD - 1.0
	_check(m.active_alerts().is_empty() and m.alerts.is_empty(), "%d 秒没再挨打：红圈消掉" % int(m.ALERT_HOLD))
	# 没来源的伤害、兵挨打、自己人误伤：不报
	var sd := Soldier.new()
	sd.setup(false)
	sd.position = m.open_point(bp + Vector2(0, 120))
	m.add_child(sd)
	sd.process_mode = Node.PROCESS_MODE_DISABLED
	m.base.take_damage(1.0)
	sd.take_damage(1.0, g)
	wf.take_damage(1.0, sd)
	_check(m.alerts.is_empty(), "没来源的伤害、兵挨打、自己人碰的：不报警")
	# 前哨挨打：报「前哨遭到攻击」，离上一声号角够久了再吹
	var opp := _open_spot(bp, 300.0, 520.0)
	var op: Building = bm.add_building("outpost", opp if opp != Vector2.INF else bp + Vector2(400, 0), 0)
	await tree.process_frame
	m._alert_sfx_t = m.game_time - m.ALERT_SFX_GAP - 0.1
	op.take_damage(1.0, g)
	_check(m.alerts.size() == 1 and m.alerts[0].what == "outpost" and m.alert_text("outpost") == "前哨遭到攻击！" and int(m.sfx.played.get("alert", 0)) == n0 + 2,
		"前哨挨打：报警 + 号角（前哨遭到攻击！）")
	op.queue_free()
	sd.queue_free()
	wf.queue_free()
	g.queue_free()
	m.base.hp = hp0
	# 真打：野地里落单的农民被 Goo 咬
	m.alerts.clear()
	var lone := _far_spot(250.0)
	var wl := _new_worker(lone)
	var gb := Goo.make("goo")
	gb.position = m.open_point(lone + Vector2(40, 0))
	m.add_child(gb)
	var bit: bool = await _wait_for(func(): return m.alerts.any(func(a): return a.what == "worker"), 6.0)
	_check(bit and wl.hp < wl.max_hp and m.alerts.any(func(a): return a.pos.distance_to(wl.position) < 120.0), "野地里的农民被 Goo 咬：在那儿报警")
	if is_instance_valid(gb):
		gb.queue_free()
	if is_instance_valid(wl):
		wl.queue_free()
	m.alerts.clear()
	await tree.process_frame

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  - " + msg)
	else:
		m._fail += 1
		print("  FAIL- " + msg)
