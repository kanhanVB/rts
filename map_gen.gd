class_name MapGen
extends RefCounted
## 随机地图生成（帝国时代式）：主城在正中，两个巢穴在相对的两侧边缘，各有一条弯曲土路通到主城；
## 地图四周一圈装饰密林，中间散布成片的树林（能砍）和矿堆（主城旁 2 片，远处若干片分矿），
## 再加 2~3 个 Goo 据点（野怪小窝）各守一片富矿——想要富矿先带兵拆窝，RTS 式抢分矿。
## 还有一条河横穿土路（过路处架桥，另留 1~2 处浅滩、几块盖水车的空岸）、会分叉的土路、野地和据点里的宝箱遗物。
## 只算布局、不建节点：返回一个字典，main 按它铺地形、摆建筑和资源。同一个 seed 永远生成同一张图。
##
## 返回字典：
##   base: Vector2                       主城位置（地图正中）
##   hives: Array[Vector2]               巢穴位置
##   roads: Array[Array[Vector2]]        每个巢穴一条路，点从主城端排到巢穴端（Goo 反着走）
##   cells: PackedByteArray              每格地形：0 空地 / C_TREE 能砍的树 / C_WOODS 边缘密林 / C_ORE 矿
##   gw, gh: int                         网格尺寸
##   ore: Array[Vector2]                 每堆矿的位置（格心 + 抖开，一片片随机长成一团）
##   trees: Array[Vector2]               每棵能砍的树的位置
##   decor: Array[Dictionary]            {key, pos, flip} 纯装饰
##   camps: Array[Dictionary]            {pos, tier, rich: Array[Vector2]} Goo 据点（野怪小窝）和它守着的富矿
##   road_hive: Array[int]               roads[i] 属于哪个巢穴（前 n_hives 条是主路，后面是分叉出去的岔路，整条从主城排到巢穴）
##   river: Dictionary                   {pts: Array[Vector2], hw: Array[float]} 河的中线和每点半宽（没有河 = 空字典）
##   bridges: Array[Dictionary]          {a, b} 土路过河那段的桥（两岸桥头）
##   fords: Array[Vector2]               浅滩中心（能趟过去，慢）
##   mills: Array[Vector2]               河边留出来盖水车的空岸（不长树，磨坊盖在这点上轮子正好泡进水里）
##   chests: Array[Dictionary]           {pos, loot, camp} 宝箱（camp = 藏在据点警戒圈里）
##   relics: Array[Dictionary]           {pos, id, camp} 遗物（扛回去永久加成，见 relic.gd）

const CELL := 32.0
const C_EMPTY := 0
const C_TREE := 1
const C_WOODS := 2
const C_ORE := 3
const C_RICH := 4    # 富矿（据点守着的那片，每堆储量是普通矿的两倍多）
const C_WATER := 5   # 河（深水，挡路）
const C_SHALLOW := 6 # 浅滩（能趟过去，走得慢）
const C_BRIDGE := 7  # 桥（土路过河那段，照常走）
## Goo 据点：离主城这么远（太近开局就被咬，太远没人去），彼此隔开、不挨土路和巢穴
const CAMP_MIN_D := 640.0
const CAMP_MAX_D := 1350.0
const CAMP_TIER2_D := 1000.0    # 再远的据点多一只岩壳，缴获也多
const CAMP_CLEAR_R := 240.0     # 据点警戒圈（190）外再留点余量：这么近没有树和普通矿
## 分叉路：主路走到 66~76% 处分出一支，绕个大弯，在 28~36% 处（离主城至少 330）并回来；第二条路也分叉的概率
const SECOND_FORK_P := 0.35
## 河：离主城、巢穴至少这么远；桥面半宽（这么宽的水格改成桥，人和怪都照常走）
const RIVER_BASE_D := 430.0
const RIVER_HIVE_D := 320.0
const RIVER_BASE_D_MIN := 360.0    # 巢穴都在上下边、路太短时放宽到这么近
const RIVER_HIVE_D_MIN := 270.0
const BRIDGE_HALF := 46.0
const MILL_N := 4          # 河边留几块盖水车的空岸
const MILL_GAP := 420.0
const FORD_R := 66.0

## 能走的格子（灌水 / 连通检查用）：空地、浅滩、桥
static func passable(v: int) -> bool:
	return v == C_EMPTY or v == C_SHALLOW or v == C_BRIDGE

static func generate(seed_: int, w: float, h: float, n_hives := 2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.frequency = 0.09
	var gw := int(ceil(w / CELL))
	var gh := int(ceil(h / CELL))
	var cells := PackedByteArray()
	cells.resize(gw * gh)
	var reserved := PackedByteArray()    # 1 = 不许长树（路、主城、巢穴周围）
	reserved.resize(gw * gh)
	var base := Vector2(w * 0.5, h * 0.5)

	# ---- 巢穴：第一个随机方向，第二个在大致对面（±35°），都贴着边缘那一圈 ----
	var hives: Array = []
	var a0 := rng.randf() * TAU
	for i in n_hives:
		var a := a0 + TAU * float(i) / float(n_hives) + rng.randf_range(-0.6, 0.6) * (1.0 if i > 0 else 0.0)
		var p := base + Vector2(cos(a) * (w * 0.5 - 330.0), sin(a) * (h * 0.5 - 280.0))
		p.x = clampf(p.x, 330.0, w - 330.0)
		p.y = clampf(p.y, 290.0, h - 290.0)
		hives.append(p)

	# ---- 土路：主城门口 → 三个随机侧偏的控制点 → 巢穴，Catmull-Rom 平滑 ----
	var roads: Array = []
	for hp in hives:
		var dir: Vector2 = (hp - base).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var ctrl: Array = [base, base + dir * 90.0]
		# 两个控制点，侧偏 40~140px：路是缓缓地拐，不是蛇形
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		for t in [0.36, 0.7]:
			var q: Vector2 = base.lerp(hp, t) + perp * side * rng.randf_range(40.0, 140.0)
			ctrl.append(q)
			if rng.randf() < 0.6:
				side = -side
		ctrl.append(hp)
		roads.append(_catmull(ctrl, 22.0))

	# ---- 分叉路：一条（有时两条）土路走到半路分成两支、快到主城再并回来；怪出巢时随机挑一支走 ----
	# 单独的随机数：加岔路不打乱原来那套树/矿/装饰的随机序列
	var road_hive: Array = []
	for i in roads.size():
		road_hive.append(i)
	var frng := RandomNumberGenerator.new()
	frng.seed = seed_ * 31 + 7
	var order: Array = range(hives.size())
	if frng.randf() < 0.5:
		order.reverse()
	var n_forks := 0
	for k in order:
		if n_forks >= 1 and frng.randf() > SECOND_FORK_P:
			break
		var alt := _fork(roads, road_hive, k, base, hives, w, h, frng)
		if not alt.is_empty():
			roads.append(alt)
			road_hive.append(k)
			n_forks += 1

	# ---- 保留区：路两边 3 格、主城周围、巢穴周围都不长树 ----
	for rd in roads:
		for p in rd:
			_mark_disc(reserved, gw, gh, p, 100.0, 1)
	_mark_disc(reserved, gw, gh, base, 170.0, 1)    # 主城跟前留出盖房的空地，再往外就可以长树
	for hp in hives:
		_mark_disc(reserved, gw, gh, hp, 210.0, 1)

	# ---- 边缘密林：厚度 2~5 格，用噪声让内沿参差不齐 ----
	for gy in gh:
		for gx in gw:
			var depth := mini(mini(gx, gy), mini(gw - 1 - gx, gh - 1 - gy))
			var th := 2.0 + (noise.get_noise_2d(gx * 1.7, gy * 1.7) + 1.0) * 1.6
			if depth < th:
				cells[gy * gw + gx] = C_WOODS

	# ---- 河：从地图一边弯弯曲曲流到另一边，横穿土路——路过河的地方架桥，河上再留 1~2 处浅滩能趟过去 ----
	var rrng := RandomNumberGenerator.new()
	rrng.seed = seed_ * 7727 + 29
	var river := {}
	var bridges: Array = []
	var fords: Array = []
	for attempt in 6:
		var rv := _river(roads, base, hives, w, h, rrng)
		if rv.is_empty():
			continue
		var trial := cells.duplicate()
		var res := _carve_river(trial, gw, gh, rv, roads, base, hives, w, h, rrng)
		if res.is_empty():
			continue
		cells = trial
		river = rv
		bridges = res.bridges
		fords = res.fords
		break
	for fp in fords:
		_mark_disc(reserved, gw, gh, fp, 140.0, 1)    # 浅滩两岸别长树：得走得到
	for br in bridges:
		_mark_disc(reserved, gw, gh, br.a, 90.0, 1)
		_mark_disc(reserved, gw, gh, br.b, 90.0, 1)
	# 水车位：河边挑几处离桥、浅滩、土路、主城、巢穴都远的岸，留一片空地不长树（不然两岸全是林子，没地方盖水车）
	var mills := _mill_sites(river, bridges, fords, roads, base, hives, w, h)
	for mp in mills:
		_mark_disc(reserved, gw, gh, mp, 110.0, 1)

	# ---- 能砍的树林：主城旁两片林子（帝国式主林，开局第一屏就看得见），再撒十来片大小不一的 ----
	var clumps: Array = []    # [中心, 半径x, 半径y]
	var road_dirs: Array = []
	for hp in hives:
		road_dirs.append((hp - base).angle())
	# 主林：林子中心要落在开局镜头里（主城左右 560px、上下 190px 内），离土路远一点
	var a_main := INF
	var d_main := 320.0
	for i in 160:
		var a := rng.randf() * TAU
		var d := rng.randf_range(260.0, 340.0)
		var c := base + Vector2.from_angle(a) * d
		if absf(c.x - base.x) > 560.0 or absf(c.y - base.y) > 190.0 or _near_road(roads, c, 130.0):
			continue
		var ok := true
		for t in road_dirs:
			if absf(angle_difference(a, t)) < 0.7:
				ok = false
				break
		if ok:
			a_main = a
			d_main = d
			break
	if a_main == INF:
		a_main = _free_angle(rng, road_dirs, 0.9)
	clumps.append([base + Vector2.from_angle(a_main) * d_main, rng.randf_range(3.4, 4.2), rng.randf_range(2.4, 3.0)])
	road_dirs.append(a_main)
	var a2 := _free_angle(rng, road_dirs, 1.0)
	clumps.append([base + Vector2.from_angle(a2) * rng.randf_range(340.0, 400.0), rng.randf_range(2.8, 3.6), rng.randf_range(2.2, 2.8)])
	road_dirs.append(a2)
	var tries := 0
	while clumps.size() < 14 and tries < 600:
		tries += 1
		var c := Vector2(rng.randf_range(200.0, w - 200.0), rng.randf_range(200.0, h - 200.0))
		if c.distance_to(base) < 520.0:
			continue
		var ok := true
		for o in clumps:
			if c.distance_to(o[0]) < 300.0:
				ok = false
				break
		for hp in hives:
			if c.distance_to(hp) < 330.0:
				ok = false
		if not ok:
			continue
		clumps.append([c, rng.randf_range(2.5, 5.5), rng.randf_range(2.0, 4.0)])
	for cl in clumps:
		var c: Vector2 = cl[0]
		var rx: float = cl[1]
		var ry: float = cl[2]
		var cc := Vector2i(int(c.x / CELL), int(c.y / CELL))
		for dy in range(-int(ry) - 2, int(ry) + 3):
			for dx in range(-int(rx) - 2, int(rx) + 3):
				var q := cc + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= gw or q.y >= gh:
					continue
				var i := q.y * gw + q.x
				if reserved[i] == 1 or cells[i] != C_EMPTY:
					continue
				var e := pow(dx / rx, 2.0) + pow(dy / ry, 2.0)
				if e < 1.0 + noise.get_noise_2d(q.x * 2.3, q.y * 2.3) * 0.55:
					cells[i] = C_TREE

	# ---- 连通性：从主城出发灌水，灌不到的空地（林子里的空洞）填成树，免得单位被关在里面 ----
	var seen := _flood(cells, gw, gh, Vector2i(int(base.x / CELL), int(base.y / CELL)))
	for i in gw * gh:
		if cells[i] == C_EMPTY and seen[i] == 0:
			var gx := i % gw
			var gy := i / gw
			var near_tree := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(gx, gy) + d
				if q.x >= 0 and q.y >= 0 and q.x < gw and q.y < gh and cells[q.y * gw + q.x] == C_TREE:
					near_tree = true
			cells[i] = C_TREE if near_tree else C_WOODS

	# ---- 矿：主城旁两片（避开路和林子的方向），远处再撒 5 片分矿 ----
	var ore: Array = []
	var ore_dirs: Array = road_dirs.duplicate()
	var home_n := 0
	tries = 0
	while home_n < 2 and tries < 200:
		tries += 1
		var a := _free_angle(rng, ore_dirs, 0.8 if tries < 100 else 0.3)
		var c := base + Vector2.from_angle(a) * rng.randf_range(230.0, 280.0)
		if not _near_road(roads, c, 100.0) and _place_ore(cells, gw, gh, c, rng, ore, true, seen):
			ore_dirs.append(a)
			home_n += 1
	var far := 0
	tries = 0
	while far < 5 and tries < 400:
		tries += 1
		var c := Vector2(rng.randf_range(260.0, w - 260.0), rng.randf_range(240.0, h - 240.0))
		if c.distance_to(base) < 600.0:
			continue
		var ok := true
		for hp in hives:
			if c.distance_to(hp) < 320.0:
				ok = false
		if _near_road(roads, c, 110.0):
			ok = false
		for o in ore:
			if c.distance_to(o) < 420.0:
				ok = false
				break
		if ok and _place_ore(cells, gw, gh, c, rng, ore, false, seen):
			far += 1

	# ---- Goo 据点：守着一片富矿的野怪小窝（最多 3 个）。富矿压在据点背后（离主城更远那侧），想采先拆窝 ----
	# 用单独的随机数：加据点不打乱原来那套树/矿/装饰的随机序列
	var crng := RandomNumberGenerator.new()
	crng.seed = seed_ * 7919 + 13
	var camps: Array = []
	tries = 0
	while camps.size() < 3 and tries < 3000:
		tries += 1
		var relax := tries > 900    # 实在摆不下第三个：窝和窝、窝和普通矿之间都挨近一点（矿还是在清场圈 240 外）
		var c := Vector2(crng.randf_range(300.0, w - 300.0), crng.randf_range(260.0, h - 260.0))
		var dist := c.distance_to(base)
		if dist < CAMP_MIN_D or dist > CAMP_MAX_D or _near_road(roads, c, 250.0):
			continue
		var ok := true
		for hp in hives:
			if c.distance_to(hp) < 460.0:
				ok = false
		for o in camps:
			if c.distance_to(o.pos) < (540.0 if relax else 650.0):
				ok = false
		for o in ore:
			if c.distance_to(o) < (250.0 if relax else 300.0):
				ok = false
		if not relax:    # 别把留好的水车位圈进禁建圈（实在摆不下再说）
			for mp in mills:
				if c.distance_to(mp) < Camp.NO_BUILD_R + 40.0:
					ok = false
		# 窝脚下一块平地；警戒圈里不许有普通矿，零星几棵树就砍掉清出一块空场
		# （不然自动去砍树的农民一头撞进窝里）。先在副本上试，富矿也摆得下才算数
		if not ok or not _area_empty(cells, gw, gh, c, 84.0):
			continue
		var trial := cells.duplicate()
		if not _clear_around(trial, gw, gh, c, CAMP_CLEAR_R, 16):
			continue
		var rich: Array = []
		var away: float = (c - base).angle()
		for k in 14:
			var spread := 0.8 if k < 8 else 1.7    # 背后摆不下（贴着地图边的密林）就往两侧挪
			var rc := c + Vector2.from_angle(away + crng.randf_range(-spread, spread)) * crng.randf_range(100.0, 122.0)    # 整片都在警戒圈（190）里
			if not _near_road(roads, rc, 150.0) and _place_rich(trial, gw, gh, rc, crng, rich, seen):
				break
		if rich.is_empty():
			continue
		cells = trial
		camps.append({"pos": c, "tier": 2 if dist > CAMP_TIER2_D else 1, "rich": rich})
	# 每张图至少一个难窝（带岩壳、缴获多）：都落在近处就把最远那个升二档
	var far_i := -1
	for i in camps.size():
		if camps[i].tier == 2:
			far_i = -1
			break
		if far_i < 0 or camps[i].pos.distance_to(base) > camps[far_i].pos.distance_to(base):
			far_i = i
	if far_i >= 0:
		camps[far_i].tier = 2

	# ---- 宝箱和遗物：野地里撒几个宝箱（白捡），每个据点窝边藏一个（最远那个难窝藏遗物），远处野地再放一件遗物 ----
	var trng := RandomNumberGenerator.new()
	trng.seed = seed_ * 104729 + 3
	var tre := _treasures(cells, gw, gh, seen, roads, base, hives, camps, w, h, trng)
	var chests: Array = tre.chests
	var relics: Array = tre.relics

	# ---- 主城周围零散的几棵树（帝国式"散树"）：不压路、不贴矿、不挨着别的树 ----
	var strays := 0
	tries = 0
	while strays < 6 and tries < 300:
		tries += 1
		var c := base + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(160.0, 250.0)
		if _near_road(roads, c, 80.0):
			continue
		var cc := Vector2i(int(c.x / CELL), int(c.y / CELL))
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := cc + Vector2i(dx, dy)
				if q.x < 2 or q.y < 2 or q.x >= gw - 2 or q.y >= gh - 2 or cells[q.y * gw + q.x] != C_EMPTY:
					ok = false
		if not ok:
			continue
		cells[cc.y * gw + cc.x] = C_TREE
		strays += 1

	# ---- 能砍的树：每格一棵，位置在格心附近抖一点 ----
	var trees: Array = []
	for i in gw * gh:
		if cells[i] == C_TREE:
			var gx := i % gw
			var gy := i / gw
			trees.append(Vector2(gx + 0.5, gy + 0.5) * CELL + Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-4.0, 4.0)))

	# ---- 装饰：灌木/花丛/石头，避开路、树、矿、主城和巢穴，彼此隔开 ----
	var decor: Array = []
	# 石头少放：灰石头远看和矿堆分不清
	var keys := ["decor/bush_1", "decor/bush_2", "decor/bush_1", "decor/flowers", "decor/flowers", "decor/flowers", "decor/rock_1"]
	var block := PackedByteArray()
	block.resize(gw * gh)
	for rd in roads:
		for q in rd:
			_mark_disc(block, gw, gh, q, 56.0, 1)
	_mark_disc(block, gw, gh, base, 200.0, 1)
	for hp in hives:
		_mark_disc(block, gw, gh, hp, 130.0, 1)
	for cp in camps:
		_mark_disc(block, gw, gh, cp.pos, 110.0, 1)
	for t in chests + relics:
		_mark_disc(block, gw, gh, t.pos, 50.0, 1)
	for br in bridges:
		_mark_disc(block, gw, gh, (br.a + br.b) * 0.5, 120.0, 1)
	tries = 0
	while decor.size() < 170 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(100.0, w - 100.0), rng.randf_range(100.0, h - 100.0))
		var i := int(p.y / CELL) * gw + int(p.x / CELL)
		if cells[i] != C_EMPTY or block[i] == 1:
			continue
		decor.append({"key": keys[rng.randi() % keys.size()], "pos": p, "flip": rng.randf() < 0.5})
		_mark_disc(block, gw, gh, p, 64.0, 1)
	decor.sort_custom(func(a, b): return a.pos.y < b.pos.y)

	return {"base": base, "hives": hives, "roads": roads, "cells": cells, "gw": gw, "gh": gh,
		"ore": ore, "trees": trees, "decor": decor, "camps": camps, "seed": seed_,
		"road_hive": road_hive, "river": river, "bridges": bridges, "fords": fords, "mills": mills,
		"chests": chests, "relics": relics}

static func _near_road(roads: Array, c: Vector2, d: float) -> bool:
	for rd in roads:
		for p in rd:
			if c.distance_to(p) < d:
				return true
	return false

## 离已有方向都至少 gap 弧度的随机方向（找不到就随便给一个）
static func _free_angle(rng: RandomNumberGenerator, taken: Array, gap: float) -> float:
	for i in 60:
		var a := rng.randf() * TAU
		var ok := true
		for t in taken:
			if absf(angle_difference(a, t)) < gap:
				ok = false
				break
		if ok:
			return a
	return rng.randf() * TAU

## 一团矿的形状：从中心格开始随机往外长 n 格（8 邻接；只挨着斜角的少长一点 → 抱成团又不方方正正）。
## extent = 离中心最多几格
static func _blob(n: int, extent: int, rng: RandomNumberGenerator) -> Array:
	var shape: Array = [Vector2i.ZERO]
	var tries := 0
	while shape.size() < n and tries < 300:
		tries += 1
		var q: Vector2i = shape[rng.randi() % shape.size()] + Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if shape.has(q) or absi(q.x) > extent or absi(q.y) > extent:
			continue
		var side := 0
		var hole := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if shape.has(q + d):
				side += 1
			elif _walled(shape, q, q + d):
				hole = true    # 会围出一个四面都是矿的空格：人进不去（寻路也会挑它当落脚点）
		if hole or (side == 0 and rng.randf() < 0.55):
			continue
		shape.append(q)
	return shape

## 加上 extra 以后，空格 e 是不是上下左右都被矿堵死了
static func _walled(shape: Array, extra: Vector2i, e: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var q: Vector2i = e + d
		if q != extra and not shape.has(q):
			return false
	return true

## 矿堆在格子里的落点：格心再抖开一点（±8, ±6），别排成棋盘；还在本格里（res_node 按坐标认格子）
static func _pile_pos(q: Vector2i, rng: RandomNumberGenerator) -> Vector2:
	return (Vector2(q) + Vector2(0.5, 0.5)) * CELL + Vector2(rng.randf_range(-8.0, 8.0), rng.randf_range(-6.0, 6.0))

## 一片矿：从中心格随机长出来的一团（home = 主城旁 4 堆；远处分矿 3~5 堆），每堆占一格、在格里抖开，
## 大小/朝向/深浅 res_node 按坐标再错开——看着是一窝天然矿脉，不是码好的方阵。周围一圈必须是空地
static func _place_ore(cells: PackedByteArray, gw: int, gh: int, c: Vector2,
		rng: RandomNumberGenerator, out: Array, home: bool, seen: PackedByteArray) -> bool:
	var cc := Vector2i(int(c.x / CELL), int(c.y / CELL))
	if cc.x < 3 or cc.y < 3 or cc.x >= gw - 3 or cc.y >= gh - 3 or seen[cc.y * gw + cc.x] == 0:
		return false    # 落在灌不到的地方（林子里的空洞）= 农民走不过去
	var n: int = 4 if home else [3, 4, 4, 5][rng.randi() % 4]
	var shape := _blob(n, 2, rng)
	# 落点和外围一圈都得是空地（不贴林子、不压路）
	for s in shape:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = cc + s + Vector2i(dx, dy)
				if q.x < 2 or q.y < 2 or q.x >= gw - 2 or q.y >= gh - 2:
					return false
				if cells[q.y * gw + q.x] != C_EMPTY:
					return false
	for s in shape:
		var q: Vector2i = cc + s
		cells[q.y * gw + q.x] = C_ORE
		out.append(_pile_pos(q, rng))
	return true

## 一片富矿：6 堆随机长成一团（挤在 3×3 里：一整窝、不是一块砖），外围一圈也得是空地；格子记成 C_RICH
static func _place_rich(cells: PackedByteArray, gw: int, gh: int, c: Vector2,
		rng: RandomNumberGenerator, out: Array, seen: PackedByteArray) -> bool:
	var cc := Vector2i(int(c.x / CELL), int(c.y / CELL))
	if cc.x < 4 or cc.y < 4 or cc.x >= gw - 5 or cc.y >= gh - 5 or seen[cc.y * gw + cc.x] == 0:
		return false
	var shape := _blob(6, 1, rng)    # 围着 c 长，别整片偏到一边（整片都要在据点警戒圈里）
	if shape.size() < 6:
		return false
	for sp in shape:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q: Vector2i = cc + sp + Vector2i(dx, dy)
				if q.x < 2 or q.y < 2 or q.x >= gw - 2 or q.y >= gh - 2 or cells[q.y * gw + q.x] != C_EMPTY:
					return false
	for sp in shape:
		var q: Vector2i = cc + sp
		cells[q.y * gw + q.x] = C_RICH
		out.append(_pile_pos(q, rng))
	return true

## 据点警戒圈清场：半径 r 内有矿 → 不行；能砍的树不超过 max_trees 棵就砍掉（格子改回空地），否则不行。
## 砍掉的树都连着窝脚下那块空地，不会砍出走不进去的空洞
static func _clear_around(cells: PackedByteArray, gw: int, gh: int, c: Vector2, r: float, max_trees: int) -> bool:
	var c0 := Vector2i(maxi(0, int((c.x - r) / CELL)), maxi(0, int((c.y - r) / CELL)))
	var c1 := Vector2i(mini(gw - 1, int((c.x + r) / CELL)), mini(gh - 1, int((c.y + r) / CELL)))
	var trees: Array = []
	for gy in range(c0.y, c1.y + 1):
		for gx in range(c0.x, c1.x + 1):
			if (Vector2(gx + 0.5, gy + 0.5) * CELL).distance_to(c) >= r:
				continue
			var v := cells[gy * gw + gx]
			if v == C_ORE or v == C_RICH:
				return false
			if v == C_TREE:
				trees.append(gy * gw + gx)
	if trees.size() > max_trees:
		return false
	for i in trees:
		cells[i] = C_EMPTY
	return true

## 以 c 为圆心、半径 r 内全是空地（据点要一块平地，四周没树没矿）
static func _area_empty(cells: PackedByteArray, gw: int, gh: int, c: Vector2, r: float) -> bool:
	var c0 := Vector2i(int((c.x - r) / CELL), int((c.y - r) / CELL))
	var c1 := Vector2i(int((c.x + r) / CELL), int((c.y + r) / CELL))
	if c0.x < 3 or c0.y < 3 or c1.x >= gw - 3 or c1.y >= gh - 3:
		return false
	for gy in range(c0.y, c1.y + 1):
		for gx in range(c0.x, c1.x + 1):
			if (Vector2(gx + 0.5, gy + 0.5) * CELL).distance_to(c) < r and cells[gy * gw + gx] != C_EMPTY:
				return false
	return true

static func _mark_disc(arr: PackedByteArray, gw: int, gh: int, p: Vector2, r: float, v: int) -> void:
	var c0 := Vector2i(int((p.x - r) / CELL), int((p.y - r) / CELL))
	var c1 := Vector2i(int((p.x + r) / CELL), int((p.y + r) / CELL))
	for gy in range(maxi(0, c0.y), mini(gh, c1.y + 1)):
		for gx in range(maxi(0, c0.x), mini(gw, c1.x + 1)):
			if (Vector2(gx + 0.5, gy + 0.5) * CELL).distance_to(p) < r:
				arr[gy * gw + gx] = v

## 4 邻接灌水：返回每格是否从 start 走得到
static func _flood(cells: PackedByteArray, gw: int, gh: int, start: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(gw * gh)
	var stack: Array = [start]
	seen[start.y * gw + start.x] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= gw or q.y >= gh:
				continue
			var i := q.y * gw + q.x
			if seen[i] == 1 or not passable(cells[i]):
				continue
			seen[i] = 1
			stack.append(q)
	return seen

## Catmull-Rom 样条：穿过所有控制点，按约 step 像素一个点采样
static func _catmull(ctrl: Array, step: float) -> Array:
	var out: Array = []
	for i in ctrl.size() - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, ctrl.size() - 1)]
		var n := maxi(2, int(p1.distance_to(p2) / step))
		for k in n:
			var t := float(k) / float(n)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[ctrl.size() - 1])
	return out

## ---------- 分叉路 ----------
## 每段路的累计长度（cum[i] = 从起点走到第 i 个点的路程）
static func _arc(pts: Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	for i in range(1, pts.size()):
		cum[i] = cum[i - 1] + (pts[i] as Vector2).distance_to(pts[i - 1])
	return cum

## 路程 d 处是第几个点
static func _at_len(cum: PackedFloat32Array, d: float) -> int:
	for i in cum.size():
		if cum[i] >= d:
			return i
	return cum.size() - 1

## 给第 k 条主路分一支岔路：从 66~76% 处分出去，往主路弯的反方向绕 240~330px，在 28~36% 处并回来。
## 返回整条岔路线（主城端 → 并路点 → 岔路 → 分路点 → 巢穴端，前后两截和主路共用）；摆不下返回空
static func _fork(roads: Array, road_hive: Array, k: int, base: Vector2, hives: Array, w: float, h: float,
		rng: RandomNumberGenerator) -> Array:
	var rd: Array = roads[k]
	var cum := _arc(rd)
	var total: float = cum[cum.size() - 1]
	for attempt in 14:
		var ir := _at_len(cum, maxf(total * rng.randf_range(0.28, 0.36), 330.0))
		var is_ := _at_len(cum, total * rng.randf_range(0.66, 0.76))
		if is_ - ir < 8:
			continue
		var pr: Vector2 = rd[ir]
		var ps: Vector2 = rd[is_]
		var chord := ps - pr
		var perp := chord.orthogonal().normalized()
		var mid: Vector2 = rd[(ir + is_) / 2]
		var dev := (mid - pr).dot(perp)    # 主路中段往哪边弯
		var side := -signf(dev) if absf(dev) > 20.0 else (1.0 if rng.randf() < 0.5 else -1.0)
		if attempt % 2 == 1:
			side = -side    # 这边摆不下（贴边/挨着别的路）就试另一边
		var off := rng.randf_range(240.0, 330.0) + maxf(0.0, dev * side)
		var ctrl: Array = [pr, pr + chord * 0.2 + perp * side * off * 0.8, pr + chord * 0.5 + perp * side * off,
			pr + chord * 0.8 + perp * side * off * 0.8, ps]
		var br := _catmull(ctrl, 22.0)
		if _fork_ok(br, rd, ir, is_, roads, road_hive, k, base, hives, w, h):
			return rd.slice(0, ir) + br + rd.slice(is_ + 1)
	return []

static func _fork_ok(br: Array, rd: Array, ir: int, is_: int, roads: Array, road_hive: Array, k: int,
		base: Vector2, hives: Array, w: float, h: float) -> bool:
	for j in range(3, br.size() - 3):    # 两头岔口那几个点就在主路上，不查
		var p: Vector2 = br[j]
		if p.x < 270.0 or p.x > w - 270.0 or p.y < 250.0 or p.y > h - 250.0:
			return false
		if p.distance_to(base) < 280.0:
			return false
		for hi in hives.size():
			if hi != k and p.distance_to(hives[hi]) < 420.0:
				return false
		for ri in roads.size():
			if road_hive[ri] == k:
				continue
			for q in roads[ri]:
				if p.distance_to(q) < 240.0:
					return false
		# 两支得分得开（岔口附近那几个点除外）：不然看着就是一条加宽的路
		if j >= 7 and j < br.size() - 7:
			for i in range(ir, is_ + 1):
				if p.distance_to(rd[i]) < 150.0:
					return false
	return true

## ---------- 河 ----------
## 河的中线：从第 k 条主路 40~62% 处那一点出发，大致垂直于路往两头流，正弦摆着弯，一直流出地图边。
## 中线离主城、巢穴太近，或者顺着土路淌（会架出一长条桥）就不要
static func _river(roads: Array, base: Vector2, hives: Array, w: float, h: float, rng: RandomNumberGenerator) -> Dictionary:
	for attempt in 20:
		var k := rng.randi() % hives.size()
		var rd: Array = roads[k]
		var cum := _arc(rd)
		var i := _at_len(cum, cum[cum.size() - 1] * rng.randf_range(0.40, 0.62))
		var rv := _river_at(rd, i, base, hives, w, h, rng, RIVER_BASE_D, RIVER_HIVE_D)
		if not rv.is_empty():
			return rv
	# 两个巢穴都在上下边：路只有七百来像素，40~62% 那段离主城太近，河怎么摆都贴着主城。
	# 改在离主城、巢穴都够远的那段路上挑过河点，离主城的要求也放宽一点
	for attempt in 20:
		var k := rng.randi() % hives.size()
		var rd: Array = roads[k]
		var cand: Array = []
		for i in range(2, rd.size() - 2):
			var q: Vector2 = rd[i]
			if q.distance_to(base) < RIVER_BASE_D_MIN + 30.0:
				continue
			if hives.all(func(hp): return q.distance_to(hp) >= RIVER_HIVE_D_MIN + 40.0):
				cand.append(i)
		if cand.is_empty():
			continue
		var rv := _river_at(rd, cand[rng.randi() % cand.size()], base, hives, w, h, rng, RIVER_BASE_D_MIN, RIVER_HIVE_D_MIN)
		if not rv.is_empty():
			return rv
	return {}

## 从 rd[i] 这一点过路，大致垂直于路往两头流，正弦摆着弯；中线离主城 / 巢穴近于 base_d / hive_d 就不要
static func _river_at(rd: Array, i: int, base: Vector2, hives: Array, w: float, h: float, rng: RandomNumberGenerator,
		base_d: float, hive_d: float) -> Dictionary:
	var c: Vector2 = rd[i]
	var tan: Vector2 = (rd[mini(i + 2, rd.size() - 1)] - rd[maxi(i - 2, 0)]).normalized()
	var a0 := tan.orthogonal().angle() + rng.randf_range(-0.35, 0.35)
	var amp := rng.randf_range(0.35, 0.6)
	var wave := rng.randf_range(220.0, 340.0)
	# 过路那一点的摆角别太大：桥要大致横跨河面，不然斜着架出老长一座
	var phase := rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0)
	var fwd := _river_walk(c, a0, amp, wave, phase, 1.0, w, h)
	var back := _river_walk(c, a0, amp, wave, phase, -1.0, w, h)
	back.reverse()
	var pts: Array = back + [c] + fwd
	if pts.size() <= 20:
		return {}
	for p in pts:
		if p.distance_to(base) < base_d:
			return {}
		for hp in hives:
			if p.distance_to(hp) < hive_d:
				return {}
	var hw: Array = []
	var ph2 := rng.randf() * TAU
	for j in pts.size():
		hw.append(38.0 + 7.0 * sin(j * 30.0 / 410.0 + ph2))
	return {"pts": pts, "hw": hw}

## 河边留给水车的几块岸：沿河从一头往另一头挑，两两隔开 MILL_GAP，最多 MILL_N 处。不用随机数
## 轮子横着长在磨坊一侧，东西走向的河段轮子够不着水——只挑套得上 build_mgr 放置规则的岸（见 _mill_spot）
static func _mill_sites(rv: Dictionary, bridges: Array, fords: Array, roads: Array, base: Vector2, hives: Array, w: float, h: float) -> Array:
	var out: Array = []
	if rv.is_empty():
		return out
	var pts: Array = rv.pts
	for i in range(2, pts.size() - 2, 2):
		var nrm: Vector2 = (pts[i + 1] - pts[i - 1]).orthogonal().normalized()
		for side in [1.0, -1.0]:
			var p := _mill_spot(rv, pts[i], nrm * side, float(rv.hw[i]))
			if p == Vector2.INF or p.x < 240.0 or p.x > w - 240.0 or p.y < 220.0 or p.y > h - 220.0 or p.distance_to(base) < 420.0:
				continue
			if hives.any(func(hp): return p.distance_to(hp) < 360.0) or fords.any(func(f): return p.distance_to(f) < 200.0):
				continue
			if bridges.any(func(br): return p.distance_to((br.a + br.b) * 0.5) < 200.0) or _near_road(roads, p, 170.0):
				continue
			if out.all(func(q): return p.distance_to(q) >= MILL_GAP):
				out.append(p)
				if out.size() >= MILL_N:
					return out
	return out

## 岸边 c + out·(水面半宽 + dd) 处盖磨坊行不行：磨坊在岸上、轮心在水里，两头都比放置规则多留 4px 余量。
## 从贴着水面往岸上退着试；都不行 = Vector2.INF
static func _mill_spot(rv: Dictionary, c: Vector2, out: Vector2, hw: float) -> Vector2:
	for dd in [10.0, 14.0, 18.0, 24.0]:
		var p: Vector2 = c + out * (hw * RiverArt.EDGE_K + dd)
		if RiverArt.depth_in(rv, p) > -(BuildManager.WHEEL_BANK + 4.0):
			continue
		var wet := maxf(RiverArt.depth_in(rv, Building.wheel_hub(p, true)), RiverArt.depth_in(rv, Building.wheel_hub(p, false)))
		if wet >= BuildManager.WHEEL_DEEP + 4.0:
			return p
	return Vector2.INF

## 沿着 a0 方向一步 30px 往一头走（dir = -1 往回走：同一条正弦曲线的另一半，过路那点前后接得上）
static func _river_walk(start: Vector2, a0: float, amp: float, wave: float, phase: float, dir: float, w: float, h: float) -> Array:
	var out: Array = []
	var p := start
	var s := 0.0
	for i in 160:
		s += 30.0
		var a := a0 + amp * sin(dir * s / wave + phase)
		p += Vector2.from_angle(a) * 30.0 * dir
		out.append(p)
		if p.x < -60.0 or p.y < -60.0 or p.x > w + 60.0 or p.y > h + 60.0:
			break
	return out

## 河落到格子上：中线半宽内的空地 → 水（边缘密林那截还是密林，河从林子底下流出来）；
## 土路过河的那几格 → 桥；再挑 1~2 处离桥、路、主城都远的地方 → 浅滩。
## 河把地图切开以后，桥和浅滩必须把两岸连起来，否则返回空（这条河不要）
static func _carve_river(cells: PackedByteArray, gw: int, gh: int, rv: Dictionary, roads: Array,
		base: Vector2, hives: Array, w: float, h: float, rng: RandomNumberGenerator) -> Dictionary:
	var start := Vector2i(int(base.x / CELL), int(base.y / CELL))
	var before := _flood(cells, gw, gh, start)
	var water := PackedByteArray()
	water.resize(gw * gh)
	var pts: Array = rv.pts
	var hws: Array = rv.hw
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 8.0))
		for s in n + 1:
			var t := float(s) / n
			_mark_disc(water, gw, gh, a.lerp(b, t), lerpf(hws[i], hws[i + 1], t) + 6.0, 1)
	for i in gw * gh:
		if water[i] == 1 and cells[i] == C_EMPTY:
			cells[i] = C_WATER
	# 桥：每条路上连续落在水里的那几个点 = 一座桥（岔路和主路共用的那截只架一座）
	var bridges: Array = []
	for rd in roads:
		var run := -1
		for i in rd.size() + 1:
			var wet := false
			if i < rd.size():
				var c := Vector2i(int(rd[i].x / CELL), int(rd[i].y / CELL))
				wet = c.x >= 0 and c.y >= 0 and c.x < gw and c.y < gh and water[c.y * gw + c.x] == 1
			if wet and run < 0:
				run = i
			elif not wet and run >= 0:
				if i - run > 9:
					return {}    # 路顺着河淌了一长段
				var a: Vector2 = rd[maxi(run - 1, 0)]
				var b: Vector2 = rd[mini(i, rd.size() - 1)]
				var dup := false
				for o in bridges:
					if ((o.a + o.b) * 0.5).distance_to((a + b) * 0.5) < 60.0:
						dup = true
				if not dup:
					bridges.append({"a": a, "b": b})
				run = -1
	if bridges.is_empty() or bridges.size() > 3:
		return {}
	for br in bridges:
		_mark_seg(cells, gw, gh, br.a, br.b, BRIDGE_HALF, C_WATER, C_BRIDGE)
	# 浅滩：沿河每 40px 一个候选点，离桥、土路、主城、巢穴、地图边都远；两处之间隔开
	var cand: Array = []
	for i in range(0, pts.size()):
		var p: Vector2 = pts[i]
		if p.x < 300.0 or p.x > w - 300.0 or p.y < 280.0 or p.y > h - 280.0 or p.distance_to(base) < 450.0:
			continue
		var ok := true
		for hp in hives:
			if p.distance_to(hp) < 340.0:
				ok = false
		for br in bridges:
			if p.distance_to((br.a + br.b) * 0.5) < 480.0:
				ok = false
		if ok and _near_road(roads, p, 200.0):
			ok = false
		if ok:
			cand.append(p)
	var fords: Array = []
	for n in 2:
		var left: Array = cand.filter(func(q): return fords.all(func(f): return q.distance_to(f) > 650.0))
		if left.is_empty():
			break
		fords.append(left[rng.randi() % left.size()])
	if fords.is_empty():
		return {}
	for fp in fords:
		_mark_disc_if(cells, gw, gh, fp, FORD_R, C_WATER, C_SHALLOW)
	# 两岸得连着：灌水灌不到的空地不能比没河的时候多
	var after := _flood(cells, gw, gh, start)
	var lost := 0
	for i in gw * gh:
		if cells[i] == C_EMPTY and after[i] == 0 and before[i] == 1:
			lost += 1
	if lost > 12:
		return {}
	return {"bridges": bridges, "fords": fords}

## 线段 a-b 两侧 r 以内、格子是 from 的改成 to（架桥）
static func _mark_seg(cells: PackedByteArray, gw: int, gh: int, a: Vector2, b: Vector2, r: float, from: int, to: int) -> void:
	var c0 := Vector2i(int((minf(a.x, b.x) - r) / CELL), int((minf(a.y, b.y) - r) / CELL))
	var c1 := Vector2i(int((maxf(a.x, b.x) + r) / CELL), int((maxf(a.y, b.y) + r) / CELL))
	for gy in range(maxi(0, c0.y), mini(gh, c1.y + 1)):
		for gx in range(maxi(0, c0.x), mini(gw, c1.x + 1)):
			var cc := Vector2(gx + 0.5, gy + 0.5) * CELL
			if cells[gy * gw + gx] == from and Geometry2D.get_closest_point_to_segment(cc, a, b).distance_to(cc) < r:
				cells[gy * gw + gx] = to

static func _mark_disc_if(cells: PackedByteArray, gw: int, gh: int, p: Vector2, r: float, from: int, to: int) -> void:
	var c0 := Vector2i(int((p.x - r) / CELL), int((p.y - r) / CELL))
	var c1 := Vector2i(int((p.x + r) / CELL), int((p.y + r) / CELL))
	for gy in range(maxi(0, c0.y), mini(gh, c1.y + 1)):
		for gx in range(maxi(0, c0.x), mini(gw, c1.x + 1)):
			if cells[gy * gw + gx] == from and (Vector2(gx + 0.5, gy + 0.5) * CELL).distance_to(p) < r:
				cells[gy * gw + gx] = to

## ---------- 宝箱和遗物 ----------
const CHEST_LOOT := [{"ore": 120}, {"wood": 120}, {"ore": 70, "wood": 70}, {"ingot": 20}, {"plank": 20}]

## 野地 4 个宝箱（离主城 480~1500，不挨路、不挨巢穴、不在据点警戒圈里）；每个据点窝边藏一个（最远的难窝藏遗物、
## 宝箱里的东西多一半）；远处野地再放一件遗物。都落在走得到的空地上，脚下 3×3 没树没矿
static func _treasures(cells: PackedByteArray, gw: int, gh: int, seen: PackedByteArray, roads: Array, base: Vector2,
		hives: Array, camps: Array, w: float, h: float, rng: RandomNumberGenerator) -> Dictionary:
	var chests: Array = []
	var relics: Array = []
	var ids: Array = Relic.IDS.duplicate()
	for i in ids.size():    # 打乱（洗牌用自己的随机数，同一 seed 同一套遗物）
		var j := rng.randi() % ids.size()
		var tmp = ids[i]
		ids[i] = ids[j]
		ids[j] = tmp
	var taken: Array = []
	# 据点里的：窝的侧后方 70~95px（守军站前面和两侧、富矿在正后方）
	var far_camp := -1
	for i in camps.size():
		if far_camp < 0 or camps[i].pos.distance_to(base) > camps[far_camp].pos.distance_to(base):
			far_camp = i
	for i in camps.size():
		var cp: Dictionary = camps[i]
		var away: float = (cp.pos - base).angle()
		for t in 60:
			var a := away + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.9, 1.7)
			var p: Vector2 = cp.pos + Vector2.from_angle(a) * rng.randf_range(70.0, 95.0)
			if not _treasure_cell_ok(cells, gw, gh, seen, p):
				continue
			if i == far_camp and relics.is_empty():
				relics.append({"pos": p, "id": ids[0], "camp": true})
			else:
				var lt: Dictionary = CHEST_LOOT[rng.randi() % CHEST_LOOT.size()].duplicate()
				for kk in lt:
					lt[kk] = int(lt[kk] * 1.6)
				chests.append({"pos": p, "loot": lt, "camp": true})
			taken.append(p)
			break
	# 野地里的：4 个宝箱 + 1 件遗物（遗物离主城更远）
	var want_chests := chests.size() + 4
	var want_relics := relics.size() + 1
	for t in 3000:
		if chests.size() >= want_chests and relics.size() >= want_relics:
			break
		var relic := chests.size() >= want_chests
		var p := Vector2(rng.randf_range(260.0, w - 260.0), rng.randf_range(240.0, h - 240.0))
		var d := p.distance_to(base)
		if d < (900.0 if relic else 480.0) or d > 1500.0:
			continue
		var ok := true
		for hp in hives:
			if p.distance_to(hp) < 300.0:
				ok = false
		for cp in camps:
			if p.distance_to(cp.pos) < 260.0:
				ok = false
		for q in taken:
			if p.distance_to(q) < 350.0:
				ok = false
		if not ok or _near_road(roads, p, 90.0) or not _treasure_cell_ok(cells, gw, gh, seen, p):
			continue
		if relic:
			relics.append({"pos": p, "id": ids[relics.size() % ids.size()], "camp": false})
		else:
			chests.append({"pos": p, "loot": CHEST_LOOT[rng.randi() % CHEST_LOOT.size()].duplicate(), "camp": false})
		taken.append(p)
	return {"chests": chests, "relics": relics}

static func _treasure_cell_ok(cells: PackedByteArray, gw: int, gh: int, seen: PackedByteArray, p: Vector2) -> bool:
	var c := Vector2i(int(p.x / CELL), int(p.y / CELL))
	if c.x < 3 or c.y < 3 or c.x >= gw - 3 or c.y >= gh - 3 or seen[c.y * gw + c.x] == 0:
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if cells[(c.y + dy) * gw + c.x + dx] != C_EMPTY:
				return false
	return true
