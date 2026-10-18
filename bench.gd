extends SceneTree
## 性能基准：120 个单位混战下的每帧耗时 + A* 寻路耗时
## 用法：Godot --headless --path . -s bench.gd

func _initialize() -> void:
	Engine.max_fps = 0
	var main: Node2D = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._wave_mgr.wave_timer = 9999.0
	seed(42)
	for i in 40:
		var s := Soldier.new()
		s.setup(i % 2 == 0)
		s.hp = 99999.0
		s.position = Vector2(500 + (i % 8) * 20, 300 + int(i / 8) * 20)
		main.add_child(s)
	for i in 80:
		var g := Goo.new()
		g.position = Vector2(700 + (i % 10) * 18, 250 + int(i / 10) * 18)
		main.add_child(g)
		g.hp = 99999.0
		g.max_hp = 99999.0
	for i in 10:
		await process_frame
	# 直接计时单位逻辑（绕开无头模式约 7ms 的帧节拍下限）
	var units := get_nodes_in_group("units")
	for u in units:
		u.set_process(false)
	var frames := 300
	var acc := 0
	for i in frames:
		var t0 := Time.get_ticks_usec()
		for u in units:
			if is_instance_valid(u):
				u._process(1.0 / 60.0)
		acc += Time.get_ticks_usec() - t0
		await process_frame    # 让引擎推进帧号，每帧缓存才会刷新
	var wall := acc / 1000.0 / frames
	var n_units := get_nodes_in_group("units").size()
	# 寻路基准：加一道墙让 A* 有活干
	var ter: Terrain = main.terrain
	ter.paint(Rect2(600, 0, 32, 600), Terrain.T.CLIFF)
	if ter.has_method("_rebuild_astar"):
		ter._rebuild_astar()
	var p0 := Time.get_ticks_usec()
	var ok := 0
	for i in 300:
		var path := ter.find_path(Vector2(100 + i % 50, 600), Vector2(1200, 100 + i % 50))
		if path.size() > 0:
			ok += 1
	var pt := (Time.get_ticks_usec() - p0) / 1000.0 / 300.0
	print("BENCH units=%d  unit_logic=%.2fms/frame  astar=%.3fms/path (ok %d/300)" % [n_units, wall, pt, ok])
	quit(0)
