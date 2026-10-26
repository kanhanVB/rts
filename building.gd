extends Node2D
class_name Building
## 建筑：基地（交资源/造农民）、兵营（出兵）、巢穴（敌人老窝，拆了就赢）。
## KR 式建模：石基 + 半木墙 + 大出檐屋顶 + 旗帜；巢穴是黏液山包 + 尖刺 + 红光洞口。

var kind: String = "base"    # base / barracks / warehouse / smelter / workshop / hive / tower / waterwheel / outpost / camp（Goo 据点，见 camp.gd）/ ruins（据点废墟，见 ruins.gd）
var team: int = 0
var hp: float = 600.0
var max_hp: float = 600.0
var size: float = 76.0
var display_name := "建筑"
var selected := false        # 被玩家点中（画白圈 + 信息栏显示数值）

const OUTLINE := Color(0.2, 0.14, 0.1)
const COLORS := {
	"base": Color(0.35, 0.46, 0.62),     # 蓝瓦
	"barracks": Color(0.55, 0.38, 0.26), # 棕瓦
	"hive": Color(0.42, 0.38, 0.36),     # 岩石
}

## 建筑整体缩放（碰撞 + 贴图一起）：按起源比例小人缩小后，建筑原尺寸显得太大，
## 起源的塔约是小兵的 3 倍宽；全缩到 0.7 又太小，取 0.85
const SIZE_SCALE := 0.85

## 各建筑的占地（缩放前）：放置预览 / 工地 / 真建筑共用
const BASE_SIZE := {"base": 76.0, "barracks": 60.0, "warehouse": 64.0, "smelter": 56.0, "workshop": 56.0, "hive": 84.0, "tower": 40.0, "camp": 58.0,
	"waterwheel": 56.0, "outpost": 70.0, "ruins": 58.0}

static func size_of(k: String) -> float:
	return float(BASE_SIZE.get(k, 60.0)) * SIZE_SCALE

## 贴图显示宽度：箭塔的画布比别的建筑窄高（还要给二级的旗留边）
static func art_w(k: String, sz: float) -> float:
	if k == "waterwheel":
		return sz * WHEEL_ART_W
	return sz * (TOWER_ART_W if k == "tower" else ART_W)

func setup(k: String) -> void:
	kind = k
	match k:
		"base":
			hp = 600.0
			size = 76.0
		"barracks":
			hp = 300.0
			size = 60.0
		"warehouse":
			hp = 250.0
			size = 64.0
		"smelter":
			hp = 220.0
			size = 56.0
		"workshop":
			hp = 220.0
			size = 56.0
		"hive":
			hp = 900.0
			size = 84.0
		"tower":
			hp = 260.0
			size = 40.0
		"camp":
			hp = 420.0
			size = 58.0
		"waterwheel":
			hp = 200.0
			size = 56.0
		"outpost":
			hp = 350.0
			size = 70.0
		"ruins":
			hp = 1.0
			size = 58.0
	size *= SIZE_SCALE
	max_hp = hp
	display_name = label_text()

var _fp: Array = []    # 压住的地形格（A* 绕开）

func _ready() -> void:
	add_to_group("buildings")
	if kind == "waterwheel":
		wheel_flip = wheel_flip_at(position)
	if Terrain.current != null:
		_fp = Terrain.current.footprint(position, size * 0.5)
		Terrain.current.occupy(_fp, 1)

func _exit_tree() -> void:
	if Terrain.current != null and not _fp.is_empty():
		Terrain.current.occupy(_fp, -1)
		_fp = []

func take_damage(amount: float, from: Node2D = null) -> void:
	if is_queued_for_deletion():
		return
	# 基地 / 前哨被怪打：小地图在这儿闪 + 报警号角（main 按地点和时间节流）
	if team == 0 and (kind == "base" or kind == "outpost") and from != null and is_instance_valid(from) and from.get("team") == 1:
		if _game_ref == null or not is_instance_valid(_game_ref):
			_game_ref = get_tree().get_first_node_in_group("game")
		if _game_ref != null and _game_ref.has_method("alert_attack"):
			_game_ref.alert_attack(position, kind)
	hp -= amount
	_hurt_until = Time.get_ticks_msec() + 160
	queue_redraw()
	# 巢穴：一挨打就往外吐守军（拆巢穴不能白给）。被拆死的那一下不吐
	if kind == "hive" and team == 1 and hp > 0.0:
		_spit_check(from)
	if hp <= 0.0:
		if not is_queued_for_deletion():
			Fx.spawn(get_parent(), "dust", position + Vector2(0, size * 0.2), {"size": size * 1.6, "life": 0.8})
		queue_free()
		release_garrison()    # 房子塌了：躲着的人跑出来（警钟还响着就去别处躲）

## ---------- 巢穴：被捅了会吐守军 ----------
## 以前拆巢穴基本是白给：一队兵围上去砍 900 血，中间零阻力，"太容易拆了"。
## 现在巢穴一挨打就开始往外吐怪，三段节奏：
##   1) 第一下挨打：一口气吐一窝（捅马蜂窝的那声"嗡"）——哪怕玩家一波秒拆也得先打这窝
##   2) 之后每 SPIT_CD 秒吐一只，血越少吐的品种越狠（快被拆时掏岩壳护窝）
##   3) 血跌破 SPIT_RAGE_HP：再一口气吐一窝（垂死反扑）
## 总量有上限：防止玩家拿一个兵慢慢磨血、把守军刷成一片海。
## 吐出来的怪设成"守军"（见 main.hive_spit）：守着巢穴不走土路，而胜利判定不算守军——
## 所以把巢穴拆掉的那一刻照样直接赢，不用回头清场。
const SPIT_CD := 3.2            # 挨打期间最快隔这么久吐一只
const SPIT_MAX := 9             # 一座巢穴最多吐这么多只
const SPIT_RAGE_HP := 0.35      # 血跌破这个比例：垂死反扑，再吐一窝
var _spit_hurt := false         # 已经挨过打（第一窝出过没有）
var _spit_rage := false         # 已经跌破过红线（反扑出过没有）
var _spit_n := 0                # 这一座已经吐了几只
var _spit_cd := 0.0             # 下一只还要等多久

func _spit_check(from: Node2D) -> void:
	if _spit_n >= SPIT_MAX:
		return
	var batch: Array = []
	if not _spit_hurt:
		_spit_hurt = true
		_spit_cd = SPIT_CD
		batch = ["goo", "goo", "runner"]
	elif not _spit_rage and hp < max_hp * SPIT_RAGE_HP:
		_spit_rage = true
		batch = ["goo", "runner", "brute"]
	elif _spit_cd <= 0.0:
		_spit_cd = SPIT_CD
		batch = [_spit_pick()]
	if batch.is_empty():
		return
	# 名额不够时从前面砍，把尾部的岩壳留下：垂死反扑那一窝如果被砍掉岩壳，
	# 就只剩两只软怪，"反扑"等于没反
	while _spit_n + batch.size() > SPIT_MAX:
		batch.pop_front()
	if batch.is_empty():
		return
	_spit_n += batch.size()
	if _game_ref == null or not is_instance_valid(_game_ref):
		_game_ref = get_tree().get_first_node_in_group("game")
	if _game_ref != null and _game_ref.has_method("hive_spit"):
		_game_ref.hive_spit(self, batch, from)

## 吐什么：血越少越狠
func _spit_pick() -> String:
	var frac := hp / max_hp
	if frac <= 0.3:
		return "brute" if _spit_n % 4 == 3 else ("runner" if _spit_n % 2 == 1 else "goo")
	if frac <= 0.6:
		return "runner" if _spit_n % 2 == 1 else "goo"
	return "goo"

## ---------- 巢穴：孵化（拖得越久越凶）----------
## 以前"拖着不打"是零代价：十波倒计时慢慢走，巢穴安安静静。
## 现在每座巢穴都在孵，涨满就额外派一窝沿土路来——早打有钱（提前叫波奖励），
## 拖着有代价，两头才算对称。血越少孵得越急（被逼急了拼命生），波次越高也越快。
const BROOD_T := 78.0          # 满血、第 1 波时孵一窝要多久（秒）
const BROOD_MIN := 34.0        # 再怎么快也不快过这个
const BROOD_WARN := 0.8        # 涨到这个比例先喊一嗓子（给玩家反应时间）
var brood := 0.0               # 孵化进度 0~1
var _brood_warned := false
var _brood_drawn := 0.0        # 已经画出来的进度（每 1% 才重绘一次，别每帧重画）

func _tick_brood(delta: float) -> void:
	if hp <= 0.0:
		return
	if _game_ref == null or not is_instance_valid(_game_ref):
		_game_ref = get_tree().get_first_node_in_group("game")
	var g: Node = _game_ref
	if g == null:
		return
	var st = g.get("game_state")
	if st != null and String(st) != "play":
		return    # 暂停 / 结算时别偷偷孵
	var wave := 0
	var wm = g.get("_wave_mgr")
	if wm != null:
		wave = int(wm.get("wave"))
	# 十波打完之后老窝消停：孵出来的怪也算"场上的怪"，会一直拖住"十波全清"的胜利判定，
	# 玩家把最后一波清干净了却赢不了，只能回头去拆巢穴——那不是这条机制的本意
	if wave >= WaveManager.MAX_WAVES:
		# 顺手把没孵完的进度清掉：不清的话头顶那条紫红条会永远冻在半路，
		# 玩家以为它在憋大招，其实它已经不孵了
		if brood != 0.0:
			brood = 0.0
			_brood_warned = false
			queue_redraw()
		return
	var span: float = maxf(BROOD_MIN, BROOD_T - float(wave) * 5.0)
	span *= lerpf(0.55, 1.0, clampf(hp / max_hp, 0.0, 1.0))    # 残血 = 孵得更急
	brood = minf(1.0, brood + delta / span)
	if int(brood * 100.0) != int(_brood_drawn * 100.0):
		_brood_drawn = brood
		queue_redraw()    # 建筑平时不重绘：孵化条得跟着涨
	if not _brood_warned and brood >= BROOD_WARN:
		_brood_warned = true
		if g.has_method("_hud_msg"):
			g._hud_msg("一座巢穴躁动起来——它要提前派一窝出来了")
	if brood >= 1.0:
		brood = 0.0
		_brood_warned = false
		if g.has_method("hive_brood"):
			g.hive_brood(self)

## 还要多久孵出来（秒）：信息栏用
func brood_left() -> float:
	var g: Node = _game_ref
	if g == null or not is_instance_valid(g):
		return -1.0
	var wave := 0
	var wm = g.get("_wave_mgr")
	if wm != null:
		wave = int(wm.get("wave"))
	var span: float = maxf(BROOD_MIN, BROOD_T - float(wave) * 5.0)
	span *= lerpf(0.55, 1.0, clampf(hp / max_hp, 0.0, 1.0))
	return maxf(0.0, (1.0 - brood) * span)

## 城堡自带箭塔（王国保卫战式）：开局没兵也能顶住零星几只 Goo，但挡不住大波
const TOWER_RANGE := 170.0
const TOWER_DMG := 8.0
const TOWER_CD := 1.2

## 箭塔（工程师盖在路边）：塔上的弓手自动射路过的敌人，专挑跑在最前面（离基地最近）的打。
## 普通 Goo / 窜窜够不着塔上的人，只有岩壳会拆塔。用加工线的木板 + 铁锭升二级：两名弓手、射得更远更狠
const TOWER_LV := {
	1: {"range": 190.0, "dmg": 9.0, "cd": 1.0, "archers": 1},
	2: {"range": 225.0, "dmg": 14.0, "cd": 1.0, "archers": 2},
}
const TOWER_UP_HP := 140.0      # 升级加的血
const TOWER_ART_W := 1.8        # 箭塔贴图（150px 画布）显示宽度 = size × 这个
## 箭塔画布上的位置（像素，tools/make_tower.py 拼图时定的）：弓手脚底 y、两名弓手的 x 偏移
const TOWER_CANVAS := Vector2(150, 196)
const TOWER_FEET_Y := 92.0
const TOWER_ARCHER_H := 46.0
var level := 1
var kills := 0
var _arch_cd: Array = [0.0, 0.5]           # 每名弓手各自的冷却（二级两人错开放箭）
var _arch_face: Array = [1.0, -1.0]        # 弓手朝向
var _arch_shot: Array = [-9.0, -9.0]       # 上次放箭的时间（秒）：拉弓姿势留一会儿
var _game_ref: Node = null

func has_tower() -> bool:
	return team == 0 and (kind == "base" or kind == "tower" or kind == "outpost")

## ---------- 警钟：农民进屋躲着（帝国式 Town Bell）----------
## 基地 / 仓库 / 前哨 / 箭塔能躲人；躲进会射箭的房子（基地、前哨、箭塔）每人每轮多射一支箭。
## 躲着的农民：藏起来、停止处理、不在 units / player_units 组里（怪打不着、选不中），人口照算
const SHELTER_CAP := {"base": 10, "warehouse": 8, "outpost": 5, "tower": 3}
const SHELTER_CAP_TOWER2 := 4
static var alarm_on := false        # 警钟响着（main 设）：基地顶上挂口钟晃
var sheltered: Array = []          # 躲在里面的农民
var _shelter_res: Array = []        # 正往这儿跑、已经占了位子的农民

func shelter_cap() -> int:
	if team != 0:
		return 0
	if kind == "tower" and level >= 2:
		return SHELTER_CAP_TOWER2
	return int(SHELTER_CAP.get(kind, 0))

func can_shelter() -> bool:
	return shelter_cap() > 0 and hp > 0.0 and not is_queued_for_deletion()

## 还空几个位子（except = 问的人自己已经占的那个不算）
func shelter_free(except = null) -> int:
	_shelter_res = _shelter_res.filter(func(w): return is_instance_valid(w) and w.shelter_at == self)
	var n := sheltered.size() + _shelter_res.size()
	if except != null and _shelter_res.has(except):
		n -= 1
	return shelter_cap() - n

## 已占的位子（屋里的 + 路上的）
func cap_used() -> int:
	return shelter_cap() - shelter_free()

func reserve_shelter(w) -> void:
	if not _shelter_res.has(w):
		_shelter_res.append(w)

func unreserve_shelter(w) -> void:
	_shelter_res.erase(w)

## 进门：满了返回 false
func admit(w) -> bool:
	_shelter_res.erase(w)
	if sheltered.has(w):
		return true
	if sheltered.size() >= shelter_cap():
		return false
	sheltered.append(w)
	queue_redraw()
	return true

## 全放出来（警报解除 / 房子塌了）
func release_garrison() -> void:
	var list := sheltered.duplicate()
	sheltered.clear()
	for w in list:
		if is_instance_valid(w):
			w.leave_shelter()
	queue_redraw()

## 躲在里面的农民从窗口 / 垛口往外射：每人跟着第一名弓手每轮多射一支，同样先打跑在最前面的
func _garrison_volley(st: Dictionary) -> void:
	var n := sheltered.size()
	for k in n:
		var t := _tower_target(st.range)
		if t == null:
			return
		t.take_damage(st.dmg, self)
		if t.get("dead") == true:
			kills += 1
		var to: Vector2 = t.position + Vector2(randf_range(-4.0, 4.0), -9.0 + randf_range(-3.0, 3.0))
		Fx.spawn(get_parent(), "arrow", position + _loophole(k, n), {"to": to, "life": 0.3})

## 第 k 个躲着的人从哪儿放箭（本地坐标）：箭塔 / 前哨在垛口一排，基地在墙上的窗口一排
func _loophole(k: int, n: int) -> Vector2:
	var fx := (float(k) + 0.5) / float(n) - 0.5
	var up := float(k % 2)
	if kind == "tower" or kind == "outpost":
		var af := _archer_feet(0)
		return Vector2((af.x if kind == "outpost" else 0.0) + fx * size * 0.8, af.y - 4.0 - 5.0 * up)
	return Vector2(fx * size * 0.9, -size * (0.62 + 0.14 * up))

## 屋顶上的小牌子：农民头像 + 躲着几个 / 能躲几个
func _shelter_badge(at: Vector2) -> void:
	var txt := "%d/%d" % [sheltered.size(), shelter_cap()]
	var f := Art.font()
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var w := tw + 24.0
	var r := Rect2(at + Vector2(-w * 0.5, -15.0), Vector2(w, 15.0))
	for c in [Vector2(r.position.x, r.get_center().y), Vector2(r.end.x, r.get_center().y)]:
		draw_circle(c, 8.5, OUTLINE)
		draw_circle(c, 7.5, Color(0.36, 0.24, 0.13))
	draw_rect(r.grow_individual(0, 1, 0, 1), OUTLINE)
	draw_rect(r, Color(0.36, 0.24, 0.13))
	if Art.has("units/worker_idle"):
		Art.draw(self, "units/worker_idle", Vector2(r.position.x + 7.0, r.end.y + 1.0), 16.0)
	Art.text(self, Vector2(r.position.x + 17.0 + tw * 0.5, r.end.y - 3.0), txt, 12, Color(1.0, 0.86, 0.35))

## 前哨塔上的一名弓手（比箭塔射得远一点点，单发和城堡一样）
const OUTPOST_TOWER := {"range": 190.0, "dmg": 8.0, "cd": 1.3, "archers": 1}

func tower_stats() -> Dictionary:
	var st: Dictionary = {"range": TOWER_RANGE, "dmg": TOWER_DMG, "cd": TOWER_CD, "archers": 1}
	if kind == "tower":
		st = TOWER_LV[level]
	elif kind == "outpost":
		st = OUTPOST_TOWER
	if team == 0 and Relic.range_bonus() > 0.0:    # 鹰眼石：射程 +25
		st = st.duplicate()
		st.range = float(st.range) + Relic.range_bonus()
	if team == 0 and Tech.has("up_arrows"):    # 破甲箭头：每箭 +3（表是常量，复制一份再改）
		st = st.duplicate()
		st.dmg = float(st.dmg) + Tech.ARROW_BONUS
	return st

func can_upgrade() -> bool:
	return kind == "tower" and team == 0 and level < 2

## 升二级（钱由 main 扣）：两名弓手 + 加血 + 插旗挂盾徽
func upgrade() -> void:
	if not can_upgrade():
		return
	level = 2
	max_hp += TOWER_UP_HP
	hp += TOWER_UP_HP
	display_name = label_text()
	_arch_cd = [0.3, 0.8]
	Fx.spawn(get_parent(), "dust", position + Vector2(0, size * 0.2), {"size": size * 1.4, "life": 0.7})
	queue_redraw()

## 弓手人数 = 当前等级的 archers；二级的两人站垛口左右
func _archer_x(i: int) -> float:
	if tower_stats().archers <= 1:
		return 0.0
	return -26.0 if i == 0 else 26.0

## 弓手脚底 / 放箭点（本地坐标）
func _archer_feet(i: int) -> Vector2:
	if kind == "outpost":
		var ko := art_w(kind, size) / OUTPOST_CANVAS.x
		return Vector2(0, size * 0.42) + (OUTPOST_FEET - Vector2(OUTPOST_CANVAS.x * 0.5, OUTPOST_CANVAS.y)) * ko
	var k := art_w(kind, size) / TOWER_CANVAS.x
	return Vector2(0, size * 0.42) + Vector2(_archer_x(i) * k, -(TOWER_CANVAS.y - TOWER_FEET_Y) * k)

## 挑最前面的敌人：射程内离基地最近的（王国保卫战的"先打头"）
func _tower_target(rng: float) -> Node2D:
	if _game_ref == null or not is_instance_valid(_game_ref):
		_game_ref = get_tree().get_first_node_in_group("game")
	var home: Vector2 = position
	if _game_ref != null and is_instance_valid(_game_ref.get("base")):
		home = _game_ref.base.position
	var best: Node2D = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or e.get("dead") == true:
			continue
		if position.distance_to(e.position) > rng:
			continue
		var d := home.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _tower(delta: float) -> void:
	var st := tower_stats()
	for i in int(st.archers):
		_arch_cd[i] -= delta
		if _arch_cd[i] > 0.0:
			continue
		var t := _tower_target(st.range)
		if t == null:
			_arch_cd[i] = 0.2    # 没目标时别每帧扫
			continue
		_arch_cd[i] = st.cd
		var from: Vector2
		if kind == "tower" or kind == "outpost":
			from = position + _archer_feet(i) + Vector2(0, -12.0)
			_arch_face[i] = 1.0 if t.position.x >= position.x + _archer_feet(i).x else -1.0
			_arch_shot[i] = Time.get_ticks_msec() / 1000.0
		else:
			from = position + Vector2((-0.34 if t.position.x < position.x else 0.34) * size, -size * 0.95)
		t.take_damage(st.dmg, self)
		if t.get("dead") == true:
			kills += 1
		Fx.spawn(get_parent(), "arrow", from, {"to": t.position + Vector2(0, -9), "life": 0.3})
		if i == 0 and not sheltered.is_empty():
			_garrison_volley(st)    # 躲着的农民跟着第一名弓手一起放

## 箭塔贴图：塔身（含垛口）→ 塔上的弓手（朝目标、放箭时拉弓）→ 挑檐（挡住弓手的脚）
func _draw_tower_art(foot: Vector2, mod: Color, shake: float) -> float:
	var sfx := "2" if level >= 2 else ""
	var w := art_w(kind, size)
	var h := Art.draw_w(self, "buildings/tower_body" + sfx, foot + Vector2(shake, 0), w, mod)
	var k := w / TOWER_CANVAS.x
	var now := Time.get_ticks_msec() / 1000.0
	for i in int(tower_stats().archers):
		var act: bool = now - float(_arch_shot[i]) < 0.35
		var key := "units/archer_act" if act and Art.has("units/archer_act") else "units/archer_idle"
		var ah := TOWER_ARCHER_H * k * Unit.pose_scale("archer", key)
		Art.draw(self, key, _archer_feet(i) + Vector2(shake, 0), ah, float(_arch_face[i]) < 0.0, mod)
	Art.draw_w(self, "buildings/tower_top", foot + Vector2(shake, 0), w, mod)
	return h

## ---------- 生产队列（帝国式）：点一次排一个，排队时就扣钱；排头的读条，读满出兵；最多排 5 个 ----
const QUEUE_MAX := 5
var queue: Array = []              # [{kind, left, total, cost}]
var rally := Vector2.INF           # 集结点（INF = 没设：农民自动上岗、兵在门口列队）
var rally_node: Node2D = null      # 集结点设在矿/树上：新农民出来直接去采
var waiting_pop := false           # 排头读满了但人口已满，卡着等

## 集结点实际坐标（没设 = 门口）。轻 RTS：兵把这里当防区中心，集结点一改全队跟着挪
func rally_point() -> Vector2:
	return rally if rally != Vector2.INF else position + Vector2(0, size * 0.62 + 16.0)

func trains() -> bool:
	return team == 0 and (kind == "base" or kind == "barracks" or kind == "outpost")

func _produce(delta: float) -> void:
	var g := get_tree().get_first_node_in_group("game")
	if g == null or g.game_state != "play":
		return
	var q: Dictionary = queue[0]
	q.left = maxf(0.0, float(q.left) - delta)
	if q.left > 0.0:
		return
	if g.pop_blocked(q.kind):
		if not waiting_pop:
			g._hud_msg("人口已满：%s 训练好了，等有空位再出来" % g.train_name(q.kind))
		waiting_pop = true
		return
	waiting_pop = false
	queue.pop_front()
	g.on_trained(self, q.kind)

## 挨打抖动 / 选中圈要持续刷新（便宜：只在需要时重画）
var _was_selected := false
func _process(delta: float) -> void:
	# 巢穴吐守军：两只之间要隔一会儿（吐的节奏靠这个倒计时）
	if _spit_cd > 0.0:
		_spit_cd = maxf(0.0, _spit_cd - delta)
	if kind == "hive" and team == 1:
		_tick_brood(delta)
	if has_tower():
		_tower(delta)
	if kind == "tower":
		queue_redraw()    # 塔上的弓手会转身、拉弓
		return
	if kind == "waterwheel":
		_wheel_ang += delta * 1.2    # 轮子一直在转（河一直在流）
		queue_redraw()
		return
	if kind == "outpost":
		queue_redraw()
	if not queue.is_empty():
		_produce(delta)
	if is_processor():
		_run_line(delta)
		queue_redraw()    # 读条 / 炉火 / 烟每帧在动
		return
	if Time.get_ticks_msec() < _hurt_until + 40 or selected != _was_selected or (alarm_on and kind == "base"):
		_was_selected = selected
		queue_redraw()

## ---------- 贴图版 ----------
const ART_W := 1.85            # 贴图显示宽度 = size × 这个系数
const CAMP_MOD := Color(1.08, 0.9, 0.62)    # 据点：巢穴贴图压成土黄色，一眼和紫色的大巢穴分开
var _hurt_until := 0

func _art_draw() -> bool:
	var key := "buildings/" + kind
	if kind == "tower":
		key = "buildings/tower_body"
	elif kind == "waterwheel":
		key = "buildings/waterwheel_house"
	elif kind == "outpost":
		key = "buildings/outpost_body"
	elif kind == "camp":
		key = "buildings/hive"    # 据点 = 缩小一号、泛土黄的巢穴
	if hp < max_hp * 0.5 and Art.has(key + "_damaged"):
		key += "_damaged"
	if not Art.has(key):
		return false
	var foot := Vector2(0, size * 0.42)
	Art.ellipse(self, foot - Vector2(0, 4), size * 0.85, Color(0.05, 0.1, 0.02, 0.3))
	if selected:
		Art.ellipse(self, foot - Vector2(0, 4), size * 0.95, Color(0.55, 1.0, 0.35) if team == 0 else Color(1.0, 0.35, 0.25), false, 3.0)
	var shake := 0.0
	var mod := CAMP_MOD if kind == "camp" else Color.WHITE
	if Time.get_ticks_msec() < _hurt_until:
		shake = sin(Time.get_ticks_msec() * 0.08) * 2.0
		mod = Color(1.0, 0.75, 0.7) * mod
	# 受损版和正常版同一比例导出：按两张图宽度之比画，换图时房子不会缩放跳动
	var w := size * ART_W
	if key.ends_with("_damaged"):
		var nw: float = Art.info(key.trim_suffix("_damaged")).get("w", 0.0)
		if nw > 0.0:
			w *= float(Art.info(key).w) / nw
	var h := 0.0
	if kind == "tower":
		h = _draw_tower_art(foot, mod, shake)
	elif kind == "waterwheel":
		h = _draw_wheel_art(foot, mod, shake)
	elif kind == "outpost":
		h = _draw_outpost_art(foot, mod, shake)
	else:
		h = Art.draw_w(self, key, foot + Vector2(shake, 0), w, mod)
	if hp < max_hp or selected:
		Art.hp_bar(self, foot - Vector2(0, h + 6.0), size * 0.7, hp / max_hp, team == 0, 4.0)
	var top := foot - Vector2(0, h + (12.0 if hp < max_hp or selected else 4.0))
	if not sheltered.is_empty():
		_shelter_badge(top)
		top.y -= 18.0
	if alarm_on and kind == "base":
		# 警钟响着：基地顶上挂口钟来回晃
		Hud.bell_glyph(self, top + Vector2(0, -12.0), 0.9, sin(Time.get_ticks_msec() * 0.012) * 0.45)
	if is_processor():
		_proc_draw(foot, h)
	return true

func _draw() -> void:
	if _art_draw():
		return
	# 选中白圈
	if selected:
		draw_arc(Vector2.ZERO, size * 0.78, 0, TAU, 36, Color(1, 1, 1, 0.9), 2.5)
	# 软投影
	draw_set_transform(Vector2(0, size * 0.32), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, size * 0.62, Color(0.08, 0.12, 0.05, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match kind:
		"base":
			_draw_base()
		"barracks":
			_draw_barracks()
		"warehouse":
			_draw_warehouse()
		"smelter":
			_draw_smelter()
		"workshop":
			_draw_workshop()
		"hive", "camp":
			_draw_hive()
		"tower":
			_draw_tower()
	# 血条（悬在屋顶上方）
	if hp < max_hp:
		draw_rect(Rect2(-size * 0.5, -size * 0.74, size, 6.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-size * 0.5, -size * 0.74, size * hp / max_hp, 6.0), Color(0.3, 0.9, 0.3))
	# 巢穴孵化条（紫红色，在血条上面一条）：涨满就多派一窝过来。
	# 不画的话玩家完全不知道它在"长大"，只会在挨打时莫名其妙多出一队怪
	if kind == "hive" and team == 1 and brood > 0.12:
		var by: float = -size * 0.74 - 9.0
		draw_rect(Rect2(-size * 0.5, by, size, 5.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-size * 0.5, by, size * clampf(brood, 0.0, 1.0), 5.0),
			Color(0.85, 0.35, 0.85) if brood < BROOD_WARN else Color(0.95, 0.25, 0.3))
	if is_processor():
		_proc_draw(Vector2(0, size * 0.42), size * 1.1)

## ---------- 通用小件 ----------
## 填充多边形 + 一体厚描边
func _poly(pts: PackedVector2Array, fill: Color, line_w: float = 3.0) -> void:
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), OUTLINE, line_w)

## 发暖光的窗（KR 夜景感的小性价比）
func _window(pos: Vector2, w: float) -> void:
	draw_rect(Rect2(pos - Vector2(w / 2.0, w / 2.0), Vector2(w, w)), OUTLINE)
	draw_rect(Rect2(pos - Vector2(w / 2.0 - 1.5, w / 2.0 - 1.5), Vector2(w - 3.0, w - 3.0)), Color(0.99, 0.85, 0.45))

## 蓝底白十字盾徽（挂墙上的 KR 味小件）
func _shield(c: Vector2, r: float) -> void:
	draw_circle(c, r + 1.5, OUTLINE)
	draw_circle(c, r, Color(0.3, 0.42, 0.62))
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - r * 0.8, c.y + r * 0.55), Vector2(c.x + r * 0.8, c.y + r * 0.55), c + Vector2(0, r * 1.4)
	]), Color(0.3, 0.42, 0.62))
	draw_polyline(PackedVector2Array([
		Vector2(c.x - r * 0.8, c.y + r * 0.55), c + Vector2(0, r * 1.4), Vector2(c.x + r * 0.8, c.y + r * 0.55)
	]), OUTLINE, 2.0)
	draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), Color(0.93, 0.9, 0.8), 2.2)
	draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, 0), Color(0.93, 0.9, 0.8), 2.2)

## 拱形木门
func _door(cx: float, top: float, w: float, h: float) -> void:
	draw_rect(Rect2(cx - w / 2.0 - 1.5, top - 1.5, w + 3.0, h + 1.5), OUTLINE)
	draw_rect(Rect2(cx - w / 2.0, top, w, h), Color(0.5, 0.36, 0.2))
	draw_circle(Vector2(cx, top), w / 2.0, Color(0.5, 0.36, 0.2))
	draw_circle(Vector2(cx, top), w / 2.0 + 1.5, OUTLINE, false, 2.0)
	draw_line(Vector2(cx, top + w * 0.2), Vector2(cx, top + h), OUTLINE, 1.5)

## 旗杆 + 飘着的小三角旗
func _banner(top: Vector2, h: float, col: Color) -> void:
	draw_line(top, top + Vector2(0, -h), OUTLINE, 2.5)
	var tip := top + Vector2(0, -h)
	_poly(PackedVector2Array([
		tip, tip + Vector2(20.0, -3.0), tip + Vector2(0, -13.0)
	]), col, 2.0)

## ---------- 基地：石墙主楼 + 蓝瓦大顶 + 旗（KR 主堡感） ----------
func _draw_base() -> void:
	var s := size
	var stone := Color(0.56, 0.58, 0.6)
	var seam := Color(0.44, 0.46, 0.48)
	# 石墙主体
	draw_rect(Rect2(-s * 0.42, -s * 0.3, s * 0.84, s * 0.62), OUTLINE)
	draw_rect(Rect2(-s * 0.38, -s * 0.26, s * 0.76, s * 0.54), stone)
	for i in 3:
		var x := -s * 0.38 + s * 0.76 * (i + 1) / 4.0
		draw_line(Vector2(x, -s * 0.24), Vector2(x, s * 0.28), seam, 2.0)
	draw_line(Vector2(-s * 0.36, -s * 0.04), Vector2(s * 0.36, -s * 0.04), seam, 2.0)
	# 拱门 + 暖窗
	_door(0.0, s * 0.08, s * 0.2, s * 0.24)
	_window(Vector2(-s * 0.24, -s * 0.1), s * 0.12)
	_window(Vector2(s * 0.24, -s * 0.1), s * 0.12)
	# 蓝瓦大屋顶（出檐 + 瓦线 + 脊线高光）
	var roof: Color = COLORS["base"]
	_poly(PackedVector2Array([
		Vector2(-s * 0.56, -s * 0.24), Vector2(s * 0.56, -s * 0.24),
		Vector2(s * 0.28, -s * 0.64), Vector2(-s * 0.28, -s * 0.64)
	]), roof)
	draw_line(Vector2(-s * 0.4, -s * 0.37), Vector2(s * 0.4, -s * 0.37), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.24, -s * 0.52), Vector2(s * 0.24, -s * 0.52), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.28, -s * 0.64), Vector2(s * 0.28, -s * 0.64), roof.lightened(0.15), 3.0)
	# 蓝旗
	_banner(Vector2(-s * 0.28, -s * 0.64), s * 0.18, roof)

## ---------- 兵营：石基 + 灰泥木架墙 + 棕瓦顶 + 盾徽（KR 民房同款） ----------
func _draw_barracks() -> void:
	var s := size
	var plaster := Color(0.9, 0.85, 0.7)
	var beam := Color(0.5, 0.38, 0.26)
	# 石砌地基
	draw_rect(Rect2(-s * 0.48, s * 0.08, s * 0.96, s * 0.3), OUTLINE)
	draw_rect(Rect2(-s * 0.44, s * 0.12, s * 0.88, s * 0.22), Color(0.56, 0.58, 0.6))
	draw_line(Vector2(-s * 0.44, s * 0.23), Vector2(s * 0.44, s * 0.23), Color(0.44, 0.46, 0.48), 2.0)
	# 灰泥墙 + 木架
	draw_rect(Rect2(-s * 0.36, -s * 0.26, s * 0.72, s * 0.48), OUTLINE)
	draw_rect(Rect2(-s * 0.33, -s * 0.23, s * 0.66, s * 0.42), plaster)
	draw_line(Vector2(-s * 0.15, -s * 0.23), Vector2(-s * 0.15, s * 0.19), beam, 3.0)
	draw_line(Vector2(s * 0.15, -s * 0.23), Vector2(s * 0.15, s * 0.19), beam, 3.0)
	# X 木架（山墙感）
	draw_line(Vector2(-s * 0.33, s * 0.19), Vector2(-s * 0.05, -s * 0.23), beam, 2.5)
	draw_line(Vector2(s * 0.05, -s * 0.23), Vector2(s * 0.33, s * 0.19), beam, 2.5)
	# 拱门 + 圆窗 + 盾徽
	_door(-s * 0.16, s * 0.02, s * 0.16, s * 0.22)
	draw_circle(Vector2(s * 0.24, -s * 0.02), s * 0.07 + 1.5, OUTLINE)
	draw_circle(Vector2(s * 0.24, -s * 0.02), s * 0.07, Color(0.99, 0.85, 0.45))
	_shield(Vector2(0, -s * 0.04), s * 0.1)
	# 棕瓦屋顶
	var roof := Color(0.55, 0.38, 0.26)
	_poly(PackedVector2Array([
		Vector2(-s * 0.56, -s * 0.2), Vector2(s * 0.56, -s * 0.2),
		Vector2(s * 0.26, -s * 0.58), Vector2(-s * 0.26, -s * 0.58)
	]), roof)
	draw_line(Vector2(-s * 0.38, -s * 0.34), Vector2(s * 0.38, -s * 0.34), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.24, -s * 0.48), Vector2(s * 0.24, -s * 0.48), roof.darkened(0.22), 2.5)
	# 红旗
	_banner(Vector2(s * 0.26, -s * 0.58), s * 0.16, Color(0.75, 0.3, 0.25))

## ---------- 仓库：木板谷仓 + 大坡屋顶 + 门前货堆（基建的收货点） ----------
func _draw_warehouse() -> void:
	var s := size
	var plank := Color(0.72, 0.55, 0.34)
	var plank_dark := Color(0.55, 0.4, 0.24)
	# 石砌地基
	draw_rect(Rect2(-s * 0.46, s * 0.06, s * 0.92, s * 0.32), OUTLINE)
	draw_rect(Rect2(-s * 0.42, s * 0.1, s * 0.84, s * 0.24), Color(0.56, 0.58, 0.6))
	# 木板墙：横向板纹
	draw_rect(Rect2(-s * 0.38, -s * 0.3, s * 0.76, s * 0.48), OUTLINE)
	draw_rect(Rect2(-s * 0.35, -s * 0.27, s * 0.7, s * 0.42), plank)
	for i in 4:
		var y := -s * 0.27 + s * 0.42 * (i + 1) / 5.0
		draw_line(Vector2(-s * 0.35, y), Vector2(s * 0.35, y), plank_dark, 2.0)
	# 双开大门
	_door(0.0, s * 0.0, s * 0.26, s * 0.22)
	draw_line(Vector2(0, s * 0.02), Vector2(0, s * 0.22), OUTLINE, 2.0)
	# 大坡瓦顶
	var roof := Color(0.5, 0.35, 0.24)
	_poly(PackedVector2Array([
		Vector2(-s * 0.54, -s * 0.24), Vector2(s * 0.54, -s * 0.24),
		Vector2(s * 0.24, -s * 0.62), Vector2(-s * 0.24, -s * 0.62)
	]), roof)
	draw_line(Vector2(-s * 0.36, -s * 0.38), Vector2(s * 0.36, -s * 0.38), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.2, -s * 0.5), Vector2(s * 0.2, -s * 0.5), roof.darkened(0.22), 2.5)
	# 门前货堆：木箱 + 矿石堆，一眼看出是收货点
	var box := Color(0.62, 0.48, 0.3)
	draw_rect(Rect2(-s * 0.30, s * 0.20, s * 0.16, s * 0.12), OUTLINE)
	draw_rect(Rect2(-s * 0.29, s * 0.21, s * 0.14, s * 0.10), box)
	draw_rect(Rect2(-s * 0.12, s * 0.24, s * 0.12, s * 0.08), OUTLINE)
	draw_rect(Rect2(-s * 0.11, s * 0.25, s * 0.10, s * 0.06), box)
	for i in 3:
		var p := Vector2(s * 0.18 + (i % 2) * s * 0.08, s * 0.28 - int(i / 2) * s * 0.07)
		draw_circle(p, s * 0.05, Color(0.85, 0.66, 0.16))
		draw_arc(p, s * 0.05, 0, TAU, 14, OUTLINE, 1.5)

## ---------- 熔炉：石炉 + 烟囱冒烟 + 炉口橙光（矿石 -> 铁锭） ----------
func _draw_smelter() -> void:
	var s := size
	var stone := Color(0.58, 0.56, 0.54)
	# 石砌炉身
	draw_rect(Rect2(-s * 0.44, -s * 0.1, s * 0.88, s * 0.44), OUTLINE)
	draw_rect(Rect2(-s * 0.40, -s * 0.06, s * 0.80, s * 0.36), stone)
	draw_line(Vector2(-s * 0.40, s * 0.08), Vector2(s * 0.40, s * 0.08), Color(0.45, 0.43, 0.42), 2.0)
	# 炉口（橙光 + 铁水）
	draw_circle(Vector2(0, s * 0.06), s * 0.13 + 1.6, OUTLINE)
	draw_circle(Vector2(0, s * 0.06), s * 0.13, Color(0.92, 0.42, 0.12))
	draw_circle(Vector2(0, s * 0.06), s * 0.07, Color(1.0, 0.75, 0.25))
	# 烟囱 + 三团烟（往上飘散）
	draw_rect(Rect2(s * 0.18, -s * 0.34, s * 0.16, s * 0.26), OUTLINE)
	draw_rect(Rect2(s * 0.20, -s * 0.32, s * 0.12, s * 0.22), stone)
	for i in 3:
		var p := Vector2(s * 0.26 + i * s * 0.06, -s * 0.38 - i * s * 0.14)
		draw_circle(p, s * 0.06 + i * s * 0.02, Color(0.75, 0.74, 0.72, 0.85 - i * 0.2))
	# 成品铁锭堆（体现产出）
	for i in 2:
		var q := Vector2(-s * 0.36 + i * s * 0.16, s * 0.24)
		draw_rect(Rect2(q.x, q.y, s * 0.14, s * 0.08), OUTLINE)
		draw_rect(Rect2(q.x + 1.5, q.y + 1.5, s * 0.11, s * 0.05), Color(0.78, 0.79, 0.81))

## ---------- 木工台：敞棚 + 工作台 + 锯 + 板材（木材 -> 木板） ----------
func _draw_workshop() -> void:
	var s := size
	var timber := Color(0.66, 0.48, 0.28)
	# 立柱敞棚
	for x in [-s * 0.36, s * 0.36]:
		draw_rect(Rect2(x - s * 0.05, -s * 0.3, s * 0.1, s * 0.62), OUTLINE)
		draw_rect(Rect2(x - s * 0.035, -s * 0.285, s * 0.07, s * 0.59), timber)
	# 棚顶（木板坡）
	_poly(PackedVector2Array([
		Vector2(-s * 0.5, -s * 0.26), Vector2(s * 0.5, -s * 0.26),
		Vector2(s * 0.34, -s * 0.46), Vector2(-s * 0.34, -s * 0.46)
	]), Color(0.5, 0.36, 0.22))
	# 工作台
	draw_rect(Rect2(-s * 0.26, s * 0.02, s * 0.52, s * 0.16), OUTLINE)
	draw_rect(Rect2(-s * 0.24, s * 0.04, s * 0.48, s * 0.12), Color(0.74, 0.56, 0.34))
	# 锯（斜插在工作台上）
	draw_line(Vector2(-s * 0.1, s * 0.02), Vector2(s * 0.14, s * 0.2), OUTLINE, 3.0)
	draw_line(Vector2(-s * 0.1, s * 0.02), Vector2(s * 0.14, s * 0.2), Color(0.8, 0.82, 0.85), 1.5)
	# 成品木板（靠墙立着）
	for i in 2:
		var q := Vector2(-s * 0.3 + i * s * 0.1, s * 0.2)
		draw_rect(Rect2(q.x, q.y - s * 0.2, s * 0.09, s * 0.26), OUTLINE)
		draw_rect(Rect2(q.x + 1.5, q.y - s * 0.185, s * 0.06, s * 0.23), Color(0.85, 0.68, 0.42))

## ---------- 箭塔（没贴图时的色块版）：石塔身 + 垛口 + 塔顶弓手小圆点 ----------
func _draw_tower() -> void:
	var s := size
	var stone := Color(0.6, 0.58, 0.55)
	draw_rect(Rect2(-s * 0.36, -s * 0.9, s * 0.72, s * 1.25), OUTLINE)
	draw_rect(Rect2(-s * 0.32, -s * 0.86, s * 0.64, s * 1.17), stone)
	for i in 3:
		var x := -s * 0.42 + i * s * 0.32
		draw_rect(Rect2(x, -s * 1.12, s * 0.2, s * 0.26), OUTLINE)
		draw_rect(Rect2(x + 2.0, -s * 1.1, s * 0.2 - 4.0, s * 0.22), stone.lightened(0.15))
	draw_rect(Rect2(-s * 0.06, -s * 0.6, s * 0.12, s * 0.3), OUTLINE)
	for i in int(tower_stats().archers):
		var p := Vector2(_archer_x(i) * s / 70.0, -s * 1.0)
		draw_circle(p, s * 0.13, Color(0.35, 0.45, 0.25))
		draw_arc(p, s * 0.13, 0, TAU, 16, OUTLINE, 2.0)

## ---------- 巢穴：岩石老窝 + 尖刺 + 红光洞口（无脸） ----------
func _draw_hive() -> void:
	var s := size
	var rock := Color(0.42, 0.38, 0.36)
	var lumps := [
		[Vector2(0, s * 0.05), s * 0.42],
		[Vector2(-s * 0.32, s * 0.16), s * 0.3],
		[Vector2(s * 0.34, s * 0.12), s * 0.32],
		[Vector2(0, -s * 0.16), s * 0.28],
	]
	# 一体化厚描边：先画深色放大 union
	for L in lumps:
		draw_circle(L[0], L[1] + 2.4, OUTLINE)
	for L in lumps:
		draw_circle(L[0], L[1], rock)
	# 底部暗面色带
	draw_set_transform(Vector2(0, s * 0.3), 0.0, Vector2(0.85, 0.4))
	draw_circle(Vector2.ZERO, s * 0.5, rock.darkened(0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 骨色尖刺（角）
	for p in [Vector2(-s * 0.2, -s * 0.3), Vector2(0, -s * 0.44), Vector2(s * 0.22, -s * 0.32)]:
		_poly(PackedVector2Array([
			p + Vector2(-s * 0.07, s * 0.1), p + Vector2(s * 0.07, s * 0.1), p + Vector2(0, -s * 0.14)
		]), Color(0.72, 0.68, 0.58), 2.0)
	# 左上高光
	draw_set_transform(Vector2(-s * 0.18, -s * 0.26), 0.0, Vector2(0.7, 0.45))
	draw_circle(Vector2.ZERO, s * 0.14, Color(0.55, 0.51, 0.47))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 红光洞口（老窝的大门）
	draw_circle(Vector2(0, s * 0.2), s * 0.17, OUTLINE)
	draw_circle(Vector2(0, s * 0.2), s * 0.14, Color(0.12, 0.06, 0.1))
	draw_circle(Vector2(0, s * 0.2), s * 0.09, Color(0.7, 0.2, 0.15))
	# 边缘挂两滴绿黏液（和 Goo 同色）
	for dx in [-s * 0.4, s * 0.42]:
		draw_circle(Vector2(dx, s * 0.28), 3.5 + 1.4, OUTLINE)
		draw_circle(Vector2(dx, s * 0.28), 3.5, Color(0.55, 0.6, 0.34))

## ================= 加工线（熔炉 / 木工台）=================
## 流水线：原料堆进料场 → 工人守着炉子/工作台读条（一炉 5 个，要时间）→ 成品堆在门口 →
## 工人扛回仓库才入账。原料两条来路：采集的农民被右键指派直接送来（送货工），
## 或者工人自己去仓库扛（"自取"，仓库留底 30，别把造农民的木头吃光）。
## 没工人 = 停工；一个人既要守炉又要搬货，干一阵停一阵；两个人轮班才连续出货。
const RECIPES := {
	"smelter": {"in": "ore", "out": "ingot", "n": 5, "time": 5.0, "verb": "炼铁", "done": "炼好"},
	"workshop": {"in": "wood", "out": "plank", "n": 5, "time": 4.0, "verb": "锯木板", "done": "锯好"},
}
const OP_MAX := 2            # 每条线最多几个工人
const IN_CAP := 40.0         # 料场上限
const OUT_CAP := 30.0        # 成品堆上限（堆满停工，等人搬）
const LOAD := 10.0           # 工人一趟扛多少
const FETCH_RESERVE := 30.0  # 自取原料时仓库至少留这么多
const FETCH_FILL := 20.0     # 自取只把料场补到这么多（再多就是把仓库的矿/木压在门口，开局卡钱）；送货工照样能填到 IN_CAP

var stock_in := 0.0          # 料场里的原料
var stock_out := 0.0         # 门口堆着、还没搬回仓库的成品
var batch := 0.0             # 当前这一炉的进度 0..1
var batch_on := false        # 料已投进炉（读条中）
var operators: Array = []    # 在这条线上干活的工人（Worker）
var self_fetch := true       # 工人自己去仓库扛料
var line_status := ""        # work / away / no_op / no_in / full
var fetched_total := 0.0     # 工人从仓库扛来的原料累计
var made_total := 0.0        # 累计产出
var _heat := 0.0             # 炉火 / 干活的视觉强度 0..1：开工渐亮、停工渐暗

func is_processor() -> bool:
	return team == 0 and RECIPES.has(kind)

func recipe() -> Dictionary:
	return RECIPES.get(kind, {})

## 一批的读条秒数（研究过熟练工匠 ×0.7、古老齿轮 ×0.8、有水车带着 ×0.7，叠乘）
func batch_time() -> float:
	return float(recipe().get("time", 1.0)) * Tech.craft_mult() * Relic.craft_mult() * (WHEEL_MULT if powered() else 1.0)

## 有没有水车在带这条线
func powered() -> bool:
	return powered_by != null and is_instance_valid(powered_by) and not powered_by.is_queued_for_deletion()

## 秒数显示：整数不带小数（5 秒），否则一位小数（3.5 秒）
static func fmt_secs(t: float) -> String:
	return "%d" % int(roundf(t)) if absf(t - roundf(t)) < 0.05 else "%.1f" % t

## 送料进料场，返回实际收下多少（料场满了多的不收）
func put_input(n: float) -> float:
	var take := clampf(IN_CAP - stock_in, 0.0, n)
	stock_in += take
	return take

func take_output(n: float) -> float:
	var take := minf(stock_out, n)
	stock_out -= take
	return take

func op_count() -> int:
	_clean_ops()
	return operators.size()

func has_room() -> bool:
	return op_count() < OP_MAX

func add_operator(w) -> bool:
	_clean_ops()
	if operators.has(w):
		return true
	if operators.size() >= OP_MAX:
		return false
	operators.append(w)
	return true

func remove_operator(w) -> void:
	operators.erase(w)

func _clean_ops() -> void:
	operators = operators.filter(func(w): return is_instance_valid(w) and not w.dead and w.work_at == self)

## 工位：门口左右各一个（站在建筑前面，面朝炉口/工作台）
func work_spot(w) -> Vector2:
	var side := 1.0 if operators.find(w) == 1 else -1.0
	return position + Vector2(side * size * 0.3, size * 0.5 + 10.0)

## 守在线上的人数（读条速度按人头算：两个人一起干快一倍）
func _present() -> int:
	var n := 0
	for w in operators:
		if is_instance_valid(w) and w.op_phase == "work":
			n += 1
	return n

## 正在路上、会带料回来的量（except 自己不算）
func _incoming(except = null) -> float:
	var s := 0.0
	var inn: String = recipe().get("in", "")
	for w in operators:
		if w == except or not is_instance_valid(w):
			continue
		if w.op_phase == "trip" and can_fetch():
			s += LOAD
		elif w.op_phase == "go" and w.carry_kind == inn:
			s += w.carry_amount
	return s

func _econ():
	var g := get_tree().get_first_node_in_group("game") if is_inside_tree() else null
	return g.economy if g != null else null

## 能不能去仓库扛料：开着自取，而且仓库扛走以后还留得住底
func can_fetch() -> bool:
	if not self_fetch or not is_processor():
		return false
	var e = _econ()
	return e != null and e.amount(recipe().in) - FETCH_RESERVE >= 1.0

## 这一趟从仓库扛多少（料场装得下、仓库留得住底）
func fetch_amount(w = null) -> float:
	var e = _econ()
	if e == null or not can_fetch():
		return 0.0
	var room := minf(IN_CAP, FETCH_FILL) - stock_in - _incoming(w)
	return floorf(minf(LOAD, minf(e.amount(recipe().in) - FETCH_RESERVE, room)))

## 工人每隔一会儿问一次：接着守线（work）还是出门跑一趟（trip：扛成品去仓库、顺路取料）
func task_for(w) -> String:
	var r := recipe()
	var others := 0
	var away := 0
	for o in operators:
		if o == w or not is_instance_valid(o):
			continue
		if o.op_phase == "work":
			others += 1
		else:
			away += 1
	var lone := others == 0
	if batch_on and lone:
		return "work"    # 一个人守线：先把这一炉干完再走
	if away >= maxi(1, operators.size() - 1):
		return "work"    # 线上至少留一个人
	if stock_out >= LOAD or stock_out + r.n > OUT_CAP:
		return "trip"    # 成品够一车 / 快堆满了
	var have := stock_in + _incoming(w)
	if can_fetch() and have < r.n * (1 if lone else 2) and fetch_amount(w) >= 1.0:
		return "trip"    # 料快见底：去仓库扛（一个人时等料用完再去）
	if stock_out >= 1.0 and not batch_on and stock_in < r.n and _incoming(w) <= 0.0:
		return "trip"    # 没料了：剩下的零头也先搬回去
	return "work"

func _run_line(delta: float) -> void:
	_clean_ops()
	var r := recipe()
	var present := _present()
	if not batch_on and present > 0 and stock_in >= r.n and stock_out + r.n <= OUT_CAP:
		# 有人要马上出门（一个人守线、成品够一车）就先别投料，不然一炉干完人才走、成品越堆越多
		var stay := false
		for o in operators:
			if o.op_phase == "work" and task_for(o) == "work":
				stay = true
		if stay:
			stock_in -= r.n
			batch_on = true
			batch = 0.0
	var working := batch_on and present > 0
	if working:
		batch += delta * present / batch_time()
		if batch >= 1.0:
			batch_on = false
			batch = 0.0
			stock_out += r.n
			made_total += r.n
			Fx.spawn(get_parent(), "floater", position + Vector2(size * 0.5, -size * 0.2), {"life": 1.0,
				"text": "%s %d %s" % [r.done, r.n, Economy.KIND_SHORT[r.out]], "color": Color(0.85, 0.9, 1.0)})
	_heat = move_toward(_heat, 1.0 if working else 0.0, delta * 1.6)
	if operators.is_empty():
		line_status = "no_op"
	elif working:
		line_status = "work"
	elif batch_on:
		line_status = "away"
	elif stock_out + r.n > OUT_CAP:
		line_status = "full"
	elif stock_in < r.n:
		line_status = "away" if _incoming() > 0.0 else "no_in"
	elif present == 0:
		line_status = "away"
	else:
		line_status = "work"

## 状态一句话（信息栏 / 头顶泡泡 / 瓶颈提示共用）
func status_text() -> String:
	match line_status:
		"no_op":
			return "没人干活"
		"no_in":
			return "缺%s" % Economy.KIND_NAME[recipe().in]
		"full":
			return "成品堆满了"
		"away":
			return "工人搬货去了"
		"work":
			return "%s中" % recipe().verb
	return ""

## ---------- 加工线的现场表现：料堆 / 成品堆 / 炉火烟囱 / 锯末 / 头顶读条和状态 ----------
func _proc_draw(foot: Vector2, h: float) -> void:
	var r := recipe()
	var k := size * ART_W / 320.0    # 贴图像素 → 本地坐标
	var now := Time.get_ticks_msec() / 1000.0
	var tp := func(tx: float, ty: float) -> Vector2: return foot + Vector2((tx - 160.0) * k, (ty - 260.0) * k)
	if kind == "smelter":
		# 炉口：停工压暗（火灭了），开工火光一跳一跳 + 门前地上一片暖光
		var arch := PackedVector2Array()
		for i in 9:
			var a := PI + PI * i / 8.0
			arch.append(tp.call(153.0 + cos(a) * 42.0, 196.0 + sin(a) * 30.0))
		arch.append(tp.call(196.0, 226.0))
		arch.append(tp.call(110.0, 226.0))
		if _heat < 0.99:
			draw_colored_polygon(arch, Color(0.1, 0.07, 0.06, 0.82 * (1.0 - _heat)))
		if _heat > 0.01:
			var fl := 0.8 + 0.2 * sin(now * 13.0) * sin(now * 7.3)
			Art.ellipse(self, tp.call(153.0, 236.0), 26.0 * k * 2.0, Color(1.0, 0.55, 0.15, 0.22 * _heat * fl))
			draw_circle(tp.call(153.0, 205.0), 22.0 * k * fl, Color(1.0, 0.8, 0.3, 0.35 * _heat))
			# 烟囱冒烟：一串烟团往上飘、变大、变淡
			var top: Vector2 = tp.call(66.0, 14.0)
			for i in 5:
				var t := fmod(now * 0.45 + i / 5.0, 1.0)
				var p := top + Vector2(t * 10.0 + sin(now * 1.7 + i) * 2.5, -t * 34.0)
				var rad := 3.5 + t * 8.0
				var fade := minf(1.0, (1.0 - t) * 1.6) * _heat
				draw_circle(p, rad + 1.2, Color(0.25, 0.22, 0.2, 0.5 * fade))
				draw_circle(p, rad, Color(0.8, 0.78, 0.76, 0.92 * fade))
	elif _heat > 0.01:
		# 木工台：锯末一阵一阵往外蹦
		var c: Vector2 = tp.call(150.0, 190.0)
		for i in 6:
			var t := fmod(now * 1.6 + i / 6.0, 1.0)
			var ang := -PI * 0.5 + (float(i) - 2.5) * 0.45
			var p := c + Vector2(cos(ang) * 14.0 * t, sin(ang) * 10.0 * t + t * t * 14.0)
			draw_rect(Rect2(p - Vector2(1.5, 1.0), Vector2(3.0, 2.0)), Color(0.93, 0.78, 0.5, (1.0 - t) * _heat))
	# 料场 / 成品堆：门口左右两堆，堆多高看得见
	_pile(foot + Vector2(-size * 0.98, 2.0), r.in, stock_in, IN_CAP)
	_pile(foot + Vector2(size * 0.98, 2.0), r.out, stock_out, OUT_CAP)
	# 头顶：读条（干活中/暂停）或状态泡泡（出问题了）
	var y := foot.y - h - (16.0 if (hp < max_hp or selected) else 6.0)
	var bx := size * 0.3 if kind == "smelter" else 0.0    # 熔炉的读条挪到屋顶上方，别挡烟囱冒烟
	if batch_on:
		var bw := size * 0.62
		var rc := Rect2(bx - bw * 0.5, y - 3.0, bw, 6.0)
		draw_rect(rc.grow(1.5), Color(0.12, 0.08, 0.05, 0.9))
		draw_rect(Rect2(rc.position, Vector2(rc.size.x * batch, rc.size.y)),
			Color(1.0, 0.72, 0.2) if line_status == "work" else Color(0.6, 0.55, 0.45))
		Art.draw(self, "items/" + r.out, Vector2(bx - bw * 0.5 - 8.0, y + 5.0), 11.0)
	elif line_status in ["no_op", "no_in", "full"]:
		var bob := sin(now * 3.0) * 1.5
		Art.text(self, Vector2(bx, y + bob), "! " + status_text(), 13, Color(1.0, 0.62, 0.4))

## 一堆货：每 5 个一件，摞成小金字塔（最多 7 件），选中时标数字
func _pile(at: Vector2, item: String, n: float, cap: float) -> void:
	var key := "items/" + item
	if not Art.has(key):
		return
	var pieces := mini(int(ceil(n / 5.0 - 0.01)), 7)
	var slots := [Vector2(-7, 0), Vector2(7, 0), Vector2(0, 1), Vector2(-4, -6), Vector2(4, -6), Vector2(0, -11), Vector2(-9, -5)]
	if pieces == 0 and selected:
		Art.ellipse(self, at, 9.0, Color(0, 0, 0, 0.18))
	for i in pieces:
		Art.draw(self, key, at + slots[i], 9.0, i % 2 == 1)
	if selected:
		Art.text(self, at + Vector2(0, 13.0), "%d/%d" % [int(n), int(cap)], 11, Color(1.0, 0.95, 0.8))

func label_text() -> String:
	match kind:
		"base":
			return "基地"
		"barracks":
			return "兵营"
		"hive":
			return "巢穴"
		"camp":
			return "Goo 据点"
		"warehouse":
			return "仓库"
		"smelter":
			return "熔炉"
		"workshop":
			return "木工台"
		"tower":
			return "箭塔" if level < 2 else "二级箭塔"
		"waterwheel":
			return "水车"
		"outpost":
			return "前哨"
		"ruins":
			return "据点废墟"
	return "?"

## ---------- 水车：盖在河边水里，轮子泡在河里一直转；带动附近两条加工线（熔炉/木工台）一批快 30% ----------
## 贴图（tools/make_props.py）：磨坊（不含轮子）+ 单独一张轮子绕轴转；河在左边就整个镜像，轮子总朝着水
const WHEEL_ART_W := 2.6                     # 磨坊画布（360px，左边留白让锚点居中）显示宽度 = size × 这个
const WHEEL_CANVAS_W := 360.0
const WHEEL_ANCHOR := Vector2(180, 252)      # 贴图锚点（磨坊石基底边中点）
const WHEEL_HUB := Vector2(284, 178)         # 轮心（画布坐标）
const WHEEL_R_PX := 76.0                     # 轮子半径（画布像素）
const WHEEL_R := 260.0       # 带动范围：加工线离水车这么近
const WHEEL_MULT := 0.7      # 被带动的线一批 ×0.7
const WHEEL_MAX := 2         # 一架水车最多带两条线
var wheel_flip := false      # 轮子在左边（河在左边）
var _wheel_ang := 0.0
var powered_by: Building = null    # 加工线：哪架水车在带它（main 每 0.5 秒重新分）
var powering: Array = []           # 水车：带着哪几条线

## 轮子朝哪边：哪边水深就朝哪边（放置预览、工地也用）。有河的图按画出来的水面算，没有就看深水格
static func wheel_flip_at(p: Vector2) -> bool:
	if not RiverArt.river.is_empty():
		return RiverArt.water_depth(wheel_hub(p, true)) > RiverArt.water_depth(wheel_hub(p, false))
	return wheel_water(p) < 0

## 轮心（世界坐标）：磨坊盖在 p，轮子朝右（flip = 朝左）
static func wheel_hub(p: Vector2, flip: bool) -> Vector2:
	var sz := size_of("waterwheel")
	var off := (WHEEL_HUB - WHEEL_ANCHOR) * (art_w("waterwheel", sz) / WHEEL_CANVAS_W)
	if flip:
		off.x = -off.x
	return p + Vector2(0, sz * 0.42) + off

## 磨坊两侧的深水打分：右边每个深水采样点 +1、左边 -1（各 9 个点）。放置要求一侧至少 4 个
static func wheel_water(p: Vector2) -> int:
	var t := Terrain.current
	if t == null:
		return 0
	var score := 0
	for dy in [-16.0, 0.0, 16.0]:
		for dx in [24.0, 44.0, 64.0]:
			if t.type_at(p + Vector2(dx, dy)) == Terrain.T.DEEP:
				score += 1
			if t.type_at(p + Vector2(-dx, dy)) == Terrain.T.DEEP:
				score -= 1
	return score

func _draw_wheel_art(foot: Vector2, mod: Color, shake: float) -> float:
	var w := art_w(kind, size)
	var k := w / WHEEL_CANVAS_W
	var o := foot + Vector2(shake, 0)
	var h := Art.draw_w(self, "buildings/waterwheel_house", o, w, mod, wheel_flip)
	var off := (WHEEL_HUB - WHEEL_ANCHOR) * k
	if wheel_flip:
		off.x = -off.x
	var c := o + off
	var r := WHEEL_R_PX * k
	var now := Time.get_ticks_msec() / 1000.0
	# 水线以下：先画一圈圈往外荡的涟漪（在轮子后面）
	var wl := c + Vector2(0, r * 0.8)
	for i in 2:
		var t := fmod(now * 0.5 + i * 0.5, 1.0)
		Art.ellipse(self, wl + Vector2(0, 4), r * (1.0 + t * 0.8), Color(0.88, 0.97, 1.0, 0.4 * (1.0 - t)), false, 2.0)
	Art.draw(self, "buildings/waterwheel_wheel", c, float(Art.info("buildings/waterwheel_wheel").get("h", 160)) * k, wheel_flip, mod,
		_wheel_ang * (-1.0 if wheel_flip else 1.0))
	# 轮子下半截泡在水里：一片和河面同色的水盖住最下面的叶片（往河心那边偏一点，别漫上岸），两边翻白浪，叶片甩起一串水珠
	var dirx := -1.0 if wheel_flip else 1.0
	var wc := wl + Vector2(dirx * r * 0.12, 0)
	Art.ellipse(self, wc + Vector2(0, 2), r * 0.92, Color(0.24, 0.52, 0.67, 0.92))
	Art.ellipse(self, wc + Vector2(dirx * 2.0, 2), r * 0.72, Color(0.19, 0.45, 0.63, 0.92))
	for side in [-1.0, 1.0]:
		var fp := wc + Vector2(side * r * 0.6, -1.0)
		var wob := 1.0 + 0.25 * sin(now * 6.0 + side)
		Art.ellipse(self, fp, 4.5 * wob, Color(0.92, 0.98, 1.0, 0.75))
	for i in 7:
		var t := fmod(now * 1.1 + i / 7.0, 1.0)
		var p := wl + Vector2(dirx * (r * 0.35 + t * r * 0.75), -sin(t * PI) * r * 0.55 - 1.0)
		draw_circle(p, 1.7 * (1.0 - t * 0.5), Color(0.93, 0.98, 1.0, 0.9 * (1.0 - t)))
	return h

## ---------- 前哨：箭塔塔身 → 塔上弓手 → 挑檐 → 木屋和栅栏（make_props.py 拼的分层图，同一块画布）----------
const OUTPOST_CANVAS := Vector2(320, 262)
const OUTPOST_FEET := Vector2(87.0, 144.6)   # 弓手脚底（画布坐标）
const OUTPOST_TOWER_K := 0.92                # 塔身在画布里缩了多少（弓手跟着缩）

func _draw_outpost_art(foot: Vector2, mod: Color, shake: float) -> float:
	var w := art_w(kind, size)
	var o := foot + Vector2(shake, 0)
	var h := Art.draw_w(self, "buildings/outpost_body", o, w, mod)
	var k := w / OUTPOST_CANVAS.x
	var act: bool = Time.get_ticks_msec() / 1000.0 - float(_arch_shot[0]) < 0.35
	var key := "units/archer_act" if act and Art.has("units/archer_act") else "units/archer_idle"
	var ah := TOWER_ARCHER_H * OUTPOST_TOWER_K * k * Unit.pose_scale("archer", key)
	Art.draw(self, key, _archer_feet(0) + Vector2(shake, 0), ah, float(_arch_face[0]) < 0.0, mod)
	Art.draw_w(self, "buildings/outpost_top", o, w, mod)
	Art.draw_w(self, "buildings/outpost_front", o, w, mod)
	return h
