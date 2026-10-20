class_name MapGen
extends RefCounted
## 随机地图生成（帝国时代式）：主城在正中，两个巢穴在相对的两侧边缘，各有一条弯曲土路通到主城；
## 地图四周一圈装饰密林，中间散布成片的树林（能砍）和矿堆（主城旁 2 片，远处若干片分矿）。
## 只算布局、不建节点：返回一个字典，main 按它铺地形、摆建筑和资源。同一个 seed 永远生成同一张图。
##
## 返回字典：
##   base: Vector2                       主城位置（地图正中）
##   hives: Array[Vector2]               巢穴位置
##   roads: Array[Array[Vector2]]        每个巢穴一条路，点从主城端排到巢穴端（Goo 反着走）
##   cells: PackedByteArray              每格地形：0 空地 / C_TREE 能砍的树 / C_WOODS 边缘密林 / C_ORE 矿
##   gw, gh: int                         网格尺寸
##   ore: Array[Vector2]                 每堆矿的位置（格心 + 一点抖动）
##   trees: Array[Vector2]               每棵能砍的树的位置
##   decor: Array[Dictionary]            {key, pos, flip} 纯装饰

const CELL := 32.0
const C_EMPTY := 0
const C_TREE := 1
const C_WOODS := 2
const C_ORE := 3

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

	# ---- 保留区：路两边 3 格、主城周围、巢穴周围都不长树 ----
	for rd in roads:
		for p in rd:
			_mark_disc(reserved, gw, gh, p, 100.0, 1)
	_mark_disc(reserved, gw, gh, base, 300.0, 1)
	for hp in hives:
		_mark_disc(reserved, gw, gh, hp, 210.0, 1)

	# ---- 边缘密林：厚度 2~5 格，用噪声让内沿参差不齐 ----
	for gy in gh:
		for gx in gw:
			var depth := mini(mini(gx, gy), mini(gw - 1 - gx, gh - 1 - gy))
			var th := 2.0 + (noise.get_noise_2d(gx * 1.7, gy * 1.7) + 1.0) * 1.6
			if depth < th:
				cells[gy * gw + gx] = C_WOODS

	# ---- 能砍的树林：主城旁两片小林子（开局就有木头砍），再撒十来片大小不一的 ----
	var clumps: Array = []    # [中心, 半径x, 半径y]
	var road_dirs: Array = []
	for hp in hives:
		road_dirs.append((hp - base).angle())
	for k in 2:
		var a := _free_angle(rng, road_dirs, 1.0)
		var c := base + Vector2.from_angle(a) * rng.randf_range(380.0, 440.0)
		clumps.append([c, rng.randf_range(2.6, 3.4), rng.randf_range(2.0, 2.8)])
		road_dirs.append(a)
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
		"ore": ore, "trees": trees, "decor": decor, "seed": seed_}

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

## 一片矿：2×2 或 1×3/3×1 的矿堆（每堆占一格），周围一圈必须是空地；home=主城矿，4 堆
static func _place_ore(cells: PackedByteArray, gw: int, gh: int, c: Vector2,
		rng: RandomNumberGenerator, out: Array, home: bool, seen: PackedByteArray) -> bool:
	var cc := Vector2i(int(c.x / CELL), int(c.y / CELL))
	if cc.x < 3 or cc.y < 3 or cc.x >= gw - 3 or cc.y >= gh - 3 or seen[cc.y * gw + cc.x] == 0:
		return false    # 落在灌不到的地方（林子里的空洞）= 农民走不过去
	var shape: Array
	if home or rng.randf() < 0.5:
		shape = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	elif rng.randf() < 0.5:
		shape = [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]
	else:
		shape = [Vector2i(0, -1), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0)]
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
		out.append(Vector2(q.x + 0.5, q.y + 0.5) * CELL + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-2.0, 2.0)))
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
			if seen[i] == 1 or cells[i] != C_EMPTY:
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
