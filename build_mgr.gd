class_name BuildManager
extends Node2D
## 建造系统：设施放置（扣款 → 工地）+ 施工完工 → 真建筑 + 工地被拆。
## 基建方向要加设施种类（仓库/熔炉/木工台）时，只改 COST_TABLE 和
## _place_label 两处，main 那边通过 building_built 信号按 kind 归类。

const W := 1280
const H := 720

## 设施成本表：kind -> 成本字典
const COST_TABLE := {
	"barracks": Economy.COST_BARRACKS,
	"warehouse": Economy.COST_WAREHOUSE,
	"smelter": Economy.COST_SMELTER,
	"workshop": Economy.COST_WORKSHOP,
}

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
	add_child(b)
	return b

## 放设施：0=成功落工地  1=可重试的失败（位置不合适）  2=买不起，该取消放置
## 放置校验（放置预览和真正落地共用）：返回 "" = 能放，否则是给玩家看的原因
func placement_error(pos: Vector2) -> String:
	if pos.x < 40.0 or pos.x > W - 40.0 or pos.y < 90.0 or pos.y > H - 80.0:
		return "放不下：离边界太近，往中间点"
	for b in get_tree().get_nodes_in_group("buildings"):
		if pos.distance_to(b.position) < b.size + 40.0:
			return "放不下：离建筑太近，挪远一点"
	for s in get_tree().get_nodes_in_group("sites"):
		if is_instance_valid(s) and pos.distance_to(s.position) < s.size + 30.0:
			return "放不下：和别的工地挤在一起了"
	for n in get_tree().get_nodes_in_group("res_nodes"):
		if is_instance_valid(n) and pos.distance_to(n.position) < 52.0:
			return "放不下：压到矿/树了，挪开一点"
	if Art.forest_at(pos) or Art.forest_at(pos + Vector2(0, 26)):
		return "放不下：那里是树林"
	return ""

func try_place(kind: String, pos: Vector2, eng: Node2D) -> int:
	var why := placement_error(pos)
	if why != "":
		_hud(why)
		return 1
	var cost: Dictionary = COST_TABLE.get(kind, {})
	var g := _game()
	if g == null or not g.economy.can_afford(cost):
		_hud(_game().economy.short_msg(cost))
		return 2
	g.economy.spend(cost)
	var site := ConstructionSite.new()
	site.kind = kind
	site.position = pos
	add_child(site)
	if eng != null and is_instance_valid(eng):
		eng.command_build(site)    # 谁下的令谁去盖
		_hud("工地已放置，工程师马上过去施工")
	else:
		_hud("工地已放置——工程师阵亡待复活，它一回来就会自动接手")
	return 0

## 工地完工回调：工程师敲满进度后调这里
func complete_site(site: ConstructionSite) -> void:
	if not is_instance_valid(site):
		return
	var b := add_building(site.kind, site.position, 0)
	_hud(_place_label(site.kind))
	building_built.emit(b)
	site.queue_free()

## 工地被 Goo 拆了：投入的资源打水漂
func site_destroyed(site: ConstructionSite) -> void:
	if not is_instance_valid(site):
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
			return "熔炉完工！采矿的农民会把矿石送去炼成铁锭"
		"workshop":
			return "木工台完工！伐木的农民会把木材送去锯成木板"
	return "设施完工！"
