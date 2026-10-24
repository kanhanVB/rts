class_name Relic
extends RefCounted
## 遗物：散在野地、藏在 Goo 据点里的古物。派农民扛回基地/仓库/前哨，永久生效（全局，一局一份，main._ready 里清空）。
## 每张图随机放两件（map_gen._treasures）；效果都很小，但能叠在科技上面。宝箱另算：扛回去开出一笔资源。

const GEAR_MULT := 0.8      # 古老齿轮：熔炉/木工台一批的读条 ×0.8
const EYE_RANGE := 25.0     # 鹰眼石：箭塔、基地、前哨射程 +25
const HORN_MULT := 1.2      # 丰饶号角：采矿、伐木快 20%
const BOOTS_MULT := 1.15    # 疾风靴：农民、工程师移速 +15%
const HEART_MULT := 1.25    # 磐石之心：己方建筑血量上限 +25%（现有的按比例回血）

const IDS := ["relic_gear", "relic_eye", "relic_horn", "relic_boots", "relic_heart"]
const DEFS := {
	"relic_gear": {"name": "古老齿轮", "tip": "熔炉、木工台一批快 20%", "color": Color(0.95, 0.72, 0.3)},
	"relic_eye": {"name": "鹰眼石", "tip": "箭塔、基地、前哨射程 +25", "color": Color(0.4, 0.85, 1.0)},
	"relic_horn": {"name": "丰饶号角", "tip": "采矿、伐木快 20%", "color": Color(0.55, 1.0, 0.45)},
	"relic_boots": {"name": "疾风靴", "tip": "农民、工程师移速 +15%", "color": Color(1.0, 0.95, 0.55)},
	"relic_heart": {"name": "磐石之心", "tip": "己方建筑血量上限 +25%", "color": Color(1.0, 0.45, 0.45)},
}

static var owned := {}

static func reset() -> void:
	owned = {}

static func has(id: String) -> bool:
	return owned.has(id)

static func relic_name(id: String) -> String:
	return DEFS[id].name if DEFS.has(id) else id

static func owned_names() -> Array:
	var out: Array = []
	for id in IDS:
		if has(id):
			out.append(DEFS[id].name)
	return out

static func craft_mult() -> float:
	return GEAR_MULT if has("relic_gear") else 1.0

static func range_bonus() -> float:
	return EYE_RANGE if has("relic_eye") else 0.0

static func gather_mult() -> float:
	return HORN_MULT if has("relic_horn") else 1.0

static func speed_mult() -> float:
	return BOOTS_MULT if has("relic_boots") else 1.0

static func hp_mult() -> float:
	return HEART_MULT if has("relic_heart") else 1.0
