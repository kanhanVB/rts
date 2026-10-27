class_name BuildManager
extends Node2D
## 建造系统：设施放置（扣款 → 工地）+ 施工完工 → 真建筑 + 工地被拆。
## 基建方向要加设施种类（仓库/熔炉/木工台）时，只改 COST_TABLE 和
## _place_label 两处，main 那边通过 building_built 信号按 kind 归类。

## 设施成本表：kind -> 成本字典
const COST_TABLE := {
	"barracks": Economy.COST_BARRACKS,
	"warehouse": Economy.COST_WAREHOUSE,
	"smelter": Economy.COST_SMELTER,
	"workshop": Economy.COST_WORKSHOP,
	"tower": Economy.COST_TOWER,
	"waterwheel": Economy.COST_WATERWHEEL,
	"outpost": Economy.COST_OUTPOST,
	# 断道不是建筑：花一点木材和工期，完工不落地变成房子，而是把那段土路挖开
	"cut": {"wood": 30},
}
const BRIDGE_CLEAR := 100.0    # 水车离桥至少这么远（别把桥头堵了）
const FORD_CLEAR := 130.0      # 离浅滩中心至少这么远（浅滩是另一条过河的路）

signal building_built(building: Building)

func _ready() -> void:
	add_to_group("build_mgr")

func _game() -> Node2D:
	return get_tree().get_first_node_in_group("game")

func _hud(text: String) -> void:
	var g := _game()
	if g:
		g._hud_msg(text)

func add_building(kind: String, pos: Vector2, team_: int) -> Building:
	var b := Building.new()
	b.setup(kind)
	b.team = team_
	b.position = pos
	# 巢穴：每局每窝抽一个脾气（见 Building.PERSONAS）。两窝以前一样，"先打哪个"没有答案；
	# 现在得看地图挑——这是全图唯一"目标优先级"来源，所以必须在生成时就定下来
	if kind == "hive" and team_ == 1:
		b.roll_persona_now()    # 抽脾气 + 厚皮的血上限当场乘上去
	if team_ == 0 and Relic.has("relic_heart"):
		b.max_hp *= Relic.HEART_MULT    # 磐石之心：之后盖的房子也结实
		b.hp = b.max_hp
	add_child(b)
	return b

## 放设施：0=成功落工地  1=可重试的失败（位置不合适）  2=买不起，该取消放置
## 放置校验（放置预览和真正落地共用）：返回 "" = 能放，否则是给玩家看的原因
func placement_error(pos: Vector2, kind := "") -> String:
	var g := _game()
	var w: float = g.W if g != null else 1280.0
	var h: float = g.H if g != null else 720.0
	if pos.x < 40.0 or pos.x > w - 40.0 or pos.y < 90.0 or pos.y > h - 80.0:
		return "放不下：离边界太近，往中间点"
	if g != null and g.has_method("fog_explored") and not g.fog_explored(pos):
		return "放不下：那里还没探过——先派人去看看"
	# 断道反过来：必须压在土路上（别的设施都得躲着路走）。查完直接返回，
	# 后面那一串"离建筑远一点 / 别堵路"的规则对它全都不适用
	if kind == "cut":
		if g == null or not g.has_method("sever_error"):
			return ""
		return g.sever_error(pos)
	# 前哨只认 Goo 据点的废墟：拆了窝、在旁边扎下来，这片地盘就永远是你的
	if kind == "outpost":
		var ruin: Node2D = null
		for r in get_tree().get_nodes_in_group("buildings"):
			if r is Ruins and not r.is_queued_for_deletion() and pos.distance_to(r.position) < Ruins.OUTPOST_R:
				ruin = r
				break
		if ruin == null:
			return "放不下：前哨只能盖在 Goo 据点的废墟旁边（先拆窝）"
		for s in get_tree().get_nodes_in_group("sites"):
			if is_instance_valid(s) and s.kind == "outpost" and s.position.distance_to(ruin.position) < Ruins.OUTPOST_R:
				return "放不下：这片废墟已经在盖前哨了"
	# 据点先查：在禁建圈里怎么挪都没用，直接告诉玩家先拆窝
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b.kind == "camp" and b.team != 0 and pos.distance_to(b.position) < Camp.NO_BUILD_R:
			return "放不下：离 Goo 据点太近——先带兵把窝拆了"
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and pos.distance_to(b.position) < b.size + 40.0:
			return "放不下：离建筑太近，挪远一点"
	for s in get_tree().get_nodes_in_group("sites"):
		if is_instance_valid(s) and pos.distance_to(s.position) < s.size + 30.0:
			return "放不下：和别的工地挤在一起了"
	for n in get_tree().get_nodes_in_group("res_nodes"):
		if is_instance_valid(n) and pos.distance_to(n.position) < 52.0:
			return "放不下：压到矿/树了，挪开一点"
	var water := _water_error(pos, kind, g)
	if water != "":
		return water
	if kind != "waterwheel" and g != null and g.area_blocked(pos, 26.0):
		return "放不下：那里是树林"
	# 不许堵路：Goo 沿土路行军，房子压在路上会把整队怪卡住（箭塔要盖在路边）
	if g != null and kind != "":
		var half: float = Building.size_of(kind) * 0.5
		var pad := 34.0 if kind == "tower" else 24.0    # 箭塔紧挨着路：留够怪的车道偏移 + 体宽，路过的怪别蹭塔脚
		for rd in g.roads:
			for i in rd.size() - 1:
				if Geometry2D.get_closest_point_to_segment(pos, rd[i], rd[i + 1]).distance_to(pos) < half + pad:
					return "放不下：别堵土路，盖在路边" + ("（箭塔射程够得着）" if kind == "tower" else "")
	return ""

## 河：别的房子不许压水、不许堵浅滩；水车反过来——房子落在岸上，轮子那一侧得是深水
func _water_error(pos: Vector2, kind: String, g: Node2D) -> String:
	var t := Terrain.current
	if g == null or t == null:
		return ""
	var lay: Dictionary = g.get("layout") if g.get("layout") != null else {}
	for fp in lay.get("fords", []):
		if pos.distance_to(fp) < (FORD_CLEAR if kind == "waterwheel" else MapGen.FORD_R + Building.size_of(kind) * 0.5 + 30.0):
			return "放不下：别堵浅滩——那是另一条过河的路"
	if kind != "waterwheel":
		for dy in [-26.0, 0.0, 26.0]:
			for dx in [-26.0, 0.0, 26.0]:
				var ty := t.type_at(pos + Vector2(dx, dy))
				if ty == Terrain.T.DEEP:
					return "放不下：那是河（河边可以盖水车）"
				if ty == Terrain.T.SHALLOW:
					return "放不下：别堵浅滩——那是另一条过河的路"
		return ""
	for br in lay.get("bridges", []):
		if Geometry2D.get_closest_point_to_segment(pos, br.a, br.b).distance_to(pos) < BRIDGE_CLEAR:
			return "放不下：离桥太近，别把桥头堵了"
	var flip := Building.wheel_flip_at(pos)
	if not RiverArt.river.is_empty():
		# 按画出来的水面：磨坊落在岸上，轮心泡进水里
		if RiverArt.water_depth(pos) > -WHEEL_BANK:
			return "放不下：磨坊得落在岸上，往岸边挪一点"
		if RiverArt.water_depth(Building.wheel_hub(pos, flip)) < WHEEL_DEEP:
			return "放不下：水车要贴着河盖，轮子得泡在水里"
	else:
		var ty0 := t.type_at(pos)
		if ty0 == Terrain.T.DEEP or ty0 == Terrain.T.SHALLOW:
			return "放不下：磨坊得落在岸上，往岸边挪一点"
		if absi(Building.wheel_water(pos)) < WHEEL_WET:
			return "放不下：水车要贴着河盖，轮子得泡在水里"
	# 磨坊那一侧（背着水）别压树和矿
	var back := 1.0 if flip else -1.0
	for dy in [-24.0, 0.0, 24.0]:
		for dx in [0.0, 24.0]:
			var ty := t.type_at(pos + Vector2(dx * back, dy))
			if ty == Terrain.T.TREE or ty == Terrain.T.WOODS or ty == Terrain.T.ORE:
				return "放不下：那里是树林"
	return ""
const WHEEL_WET := 4       # 没有河的几何数据时（经典图测试）：轮子那一侧 9 个采样点至少几个是深水格
const WHEEL_BANK := 6.0    # 磨坊中心至少离水面这么远（在岸上）
const WHEEL_DEEP := 6.0    # 轮心至少泡进水面这么深

func try_place(kind: String, pos: Vector2, eng: Node2D) -> int:
	var why := placement_error(pos, kind)
	if why != "":
		_hud(why)
		return 1
	var cost: Dictionary = COST_TABLE.get(kind, {})
	var g := _game()
	if g == null:
		return 2
	if not g.economy.can_afford(cost):
		_hud(g.economy.short_msg(cost))
		return 2
	g.economy.spend(cost)
	var site := ConstructionSite.new()
	site.kind = kind
	site.position = pos
	site.size = Building.size_of(kind)    # 工地和盖好后一样大（箭塔小一圈）
	if kind == "tower":
		site.build_time = 7.0
	elif kind == "outpost":
		site.build_time = 10.0    # 前哨大一圈，多敲两秒（施工期间废墟停表）
	elif kind == "cut":
		site.build_time = 5.0     # 挖条壕沟比盖房子快：断道要在怪走到之前抢先挖好
	add_child(site)
	if eng != null and is_instance_valid(eng):
		eng.command_build(site)    # 谁下的令谁去盖
		_hud("工地已放置，工程师马上过去施工")
	else:
		_hud("工地已放置——工程师阵亡待复活，它一回来就会自动接手")
	return 0

## 工地完工回调：工程师敲满进度后调这里
func complete_site(site: ConstructionSite) -> void:
	if not is_instance_valid(site) or site.is_queued_for_deletion():
		return
	if site.kind == "cut":
		# 断道：完工不造房子，把那段土路挖开（挖不动就退钱，别让玩家白花木材）
		var g := _game()
		var ok := false
		if g != null and g.has_method("cut_road_at"):
			ok = g.cut_road_at(site.position)
		if ok:
			site.queue_free()
		else:
			var refund: Dictionary = COST_TABLE.get("cut", {})
			if g != null:
				g.economy.gain(refund)
				site.queue_free()
		return
	var b := add_building(site.kind, site.position, 0)
	_hud(_place_label(site.kind))
	building_built.emit(b)
	site.queue_free()

## 工地被 Goo 拆了：投入的资源打水漂
func site_destroyed(site: ConstructionSite) -> void:
	if not is_instance_valid(site) or site.is_queued_for_deletion():
		return
	var cost: Dictionary = COST_TABLE.get(site.kind, {})
	_hud("工地被 Goo 拆了！%s 打了水漂，护着点再放" % _game().economy.cost_text(cost))
	site.queue_free()

func _place_label(kind: String) -> String:
	match kind:
		"barracks":
			return "兵营完工！可以出兵了"
		"warehouse":
			return "仓库完工！附近的农民会改到仓库交货"
		"smelter":
			return "熔炉完工！框选农民右键熔炉，送来的矿石就炼成铁锭"
		"workshop":
			return "木工台完工！框选农民右键木工台，送来的木材就锯成木板"
		"tower":
			return "箭塔完工！塔上的弓手会自动射路过的敌人（选中它可用木板+铁锭升级）"
		"waterwheel":
			return "水车完工！附近 %d 以内的熔炉 / 木工台（最多 %d 座）一批快 30%%" % [int(Building.WHEEL_R), Building.WHEEL_MAX]
		"outpost":
			return "前哨完工！废墟清掉了，Goo 再也回不来；农民可以就近交货，塔上弓手看着这片矿"
	return "设施完工！"
