class_name Tech
extends RefCounted
## 科技（帝国式研究）：基地 / 兵营命令卡第二排（A S D F），排进建筑的生产队列读条（占队列、取消全额退）；
## 一次性、全局生效——研究完场上已有的单位/建筑立刻吃到加成。花费多用铁锭/木板：升级和加工线绑在一起。
## 效果的数值都在下面这几个常量，表里的 tip 是给玩家看的说明。

const CART_MULT := 1.5          # 手推车：采集的农民每趟扛 10 → 15（加工线工人搬货还是 10）
const TOOLS_MULT := 1.3         # 精工工具：采集快 30%
const CRAFT_MULT := 0.7         # 熟练工匠：熔炉/木工台一批的读条 ×0.7
const ARROW_BONUS := 3.0        # 破甲箭头：箭塔、基地每箭 +3
const BLADE_BONUS := 4.0        # 锻铁剑：剑士攻击 +4
const MAIL_ARMOR := 2.0         # 锁子甲：剑士/弓手护甲 +2
const MAIL_HP := 15.0           #         血 +15
const LONGBOW_RANGE := 30.0     # 长弓：弓手射程 +30
const LONGBOW_DMG := 2.0        #       每箭 +2
const MEDIC_DELAY := 4.0        # 战地包扎：离开战斗这么久以后
const MEDIC_RATE := 3.0         #           每秒回这么多血

## at = 在哪研究；slot = 命令卡格子（5..8 = 第二排 A S D F）；icon = 图标贴图；glyph = 图标上再叠的小符号
const DEFS := {
	"up_cart": {"name": "手推车", "at": "base", "slot": 5, "cost": {"wood": 80, "plank": 20}, "time": 25.0,
		"icon": "units/worker_carry", "glyph": "",
		"tip": "采矿、伐木的农民每趟扛 10 → 15：少跑三分之一的腿", "done": "采集的农民每趟扛 15"},
	"up_tools": {"name": "精工工具", "at": "base", "slot": 6, "cost": {"ore": 60, "ingot": 15}, "time": 25.0,
		"icon": "units/worker_act", "glyph": "",
		"tip": "铁镐利斧：采矿、伐木快 30%（每秒 4 → 5.2）", "done": "采矿、伐木快 30%"},
	"up_craft": {"name": "熟练工匠", "at": "base", "slot": 7, "cost": {"ore": 60, "wood": 60}, "time": 30.0,
		"icon": "buildings/smelter", "glyph": "",
		"tip": "熔炉、木工台一批快 30%（炼铁 5 → 3.5 秒，锯板 4 → 2.8 秒）", "done": "熔炉、木工台一批快 30%"},
	"up_arrows": {"name": "破甲箭头", "at": "base", "slot": 8, "cost": {"ingot": 20, "plank": 20}, "time": 30.0,
		"icon": "buildings/tower", "glyph": "",
		"tip": "所有箭塔和基地每箭 +3（一级塔 9 → 12，二级 14 → 17）：岩壳的 4 点护甲没那么难啃了", "done": "箭塔、基地每箭 +3"},
	"up_blade": {"name": "锻铁剑", "at": "barracks", "slot": 5, "cost": {"ore": 40, "ingot": 25}, "time": 30.0,
		"icon": "units/swordsman_act", "glyph": "",
		"tip": "剑士攻击 12 → 16", "done": "剑士攻击 16"},
	"up_mail": {"name": "锁子甲", "at": "barracks", "slot": 6, "cost": {"wood": 30, "ingot": 30}, "time": 35.0,
		"icon": "units/swordsman_idle", "glyph": "shield",
		"tip": "剑士、弓手护甲 +2、血 +15（剑士 85 → 100，弓手 45 → 60）", "done": "剑士、弓手护甲 +2、血 +15"},
	"up_longbow": {"name": "长弓", "at": "barracks", "slot": 7, "cost": {"wood": 40, "plank": 25}, "time": 30.0,
		"icon": "units/archer_act", "glyph": "",
		"tip": "弓手射程 140 → 170、每箭 8 → 10", "done": "弓手射程 170、每箭 10"},
	"up_medic": {"name": "战地包扎", "at": "barracks", "slot": 8, "cost": {"wood": 40, "plank": 15, "ingot": 10}, "time": 30.0,
		"icon": "", "glyph": "medic",
		"tip": "剑士、弓手离开战斗 4 秒后每秒回 3 血（打完一波不用回城也能慢慢养好）",
		"done": "剑士、弓手脱战后自己回血"},
}

## 研究完的（全局，一局一份：开新局 main._ready 里清空）
static var done := {}

static func reset() -> void:
	done = {}

static func has(id: String) -> bool:
	return done.has(id)

static func is_tech(id: String) -> bool:
	return DEFS.has(id)

static func tech_name(id: String) -> String:
	return DEFS[id].name if DEFS.has(id) else id

## 某个建筑能研究的（按格子排）
static func ids_at(kind: String) -> Array:
	var out: Array = []
	for id in DEFS:
		if DEFS[id].at == kind:
			out.append(id)
	return out

## 已经研究完的名字（信息栏用）
static func done_names(kind: String) -> Array:
	var out: Array = []
	for id in ids_at(kind):
		if has(id):
			out.append(DEFS[id].name)
	return out

static func craft_mult() -> float:
	return CRAFT_MULT if has("up_craft") else 1.0

static func arrow_bonus() -> float:
	return ARROW_BONUS if has("up_arrows") else 0.0
