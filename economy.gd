class_name Economy
extends RefCounted
## 资源账本：所有资源的唯一出入账口径，外加建筑/单位成本表。
## 基建方向要加资源种类（铁锭/木板等）时，只改这里的 KIND_NAME 和三个方法。

const KIND_NAME := {"ore": "矿石", "wood": "木材", "ingot": "铁锭", "plank": "木板"}
const KIND_SHORT := {"ore": "矿", "wood": "木", "ingot": "铁", "plank": "板"}

const COST_WORKER := {"wood": 30}
const COST_WAREHOUSE := {"wood": 60}
const COST_SMELTER := {"ore": 40, "wood": 40}
const COST_WORKSHOP := {"ore": 20, "wood": 60}
const COST_BARRACKS := {"ore": 80, "wood": 60}
const COST_SWORD := {"ore": 20, "ingot": 15}
const COST_ARCHER := {"ore": 20, "plank": 15}
const COST_TOWER := {"ore": 40, "wood": 50}
const COST_TOWER_UP := {"plank": 20, "ingot": 15}    # 升二级吃加工线的成品：塔防和经济绑在一起

var ore: float = 100.0
var wood: float = 100.0
var ingot: float = 0.0
var plank: float = 0.0

const RATE_WINDOW := 15.0    # 产能面板统计最近多少秒
var _log: Array = []         # 入账流水 [{t: 秒, kind, n}]，产能面板算速率用

## 入账流水（产能面板用：看每条产线每秒进多少货）
func _note(kind: String, n: float) -> void:
	_log.append({"t": _now(), "kind": kind, "n": n})
	# 只留窗口内的记录，别让数组无限长
	_log = _log.filter(func(e): return _now() - float(e.t) <= RATE_WINDOW * 2.0)

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## 某种资源最近窗口内的入账速率（单位/秒）
func rate(kind: String) -> float:
	var now := _now()
	var total := 0.0
	for e in _log:
		if e.kind == kind and now - float(e.t) <= RATE_WINDOW:
			total += float(e.n)
	return total / RATE_WINDOW

func amount(kind: String) -> float:
	match kind:
		"ore":
			return ore
		"wood":
			return wood
		"ingot":
			return ingot
		"plank":
			return plank
	return 0.0

func add(kind: String, n: float) -> void:
	match kind:
		"ore":
			ore += n
		"wood":
			wood += n
		"ingot":
			ingot += n
		"plank":
			plank += n
	_note(kind, n)

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if amount(k) < cost[k]:
			return false
	return true

func spend(cost: Dictionary) -> void:
	for k in cost:
		match k:
			"ore":
				ore -= cost[k]
			"wood":
				wood -= cost[k]
			"ingot":
				ingot -= cost[k]
			"plank":
				plank -= cost[k]

## 成本总额的紧凑写法（"80矿60木"）
func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		parts.append("%d%s" % [int(cost[k]), KIND_SHORT.get(k, k)])
	return "".join(parts)

## 缺什么、差多少（UI 提示用）
func short_msg(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		if amount(k) < cost[k]:
			parts.append("%s不够，还差 %d" % [KIND_NAME.get(k, k), int(cost[k] - amount(k))])
	return "；".join(parts)
