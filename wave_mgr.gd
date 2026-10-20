class_name WaveManager
extends Node
## 波次系统：倒计时 → 出 Goo → 十波全清判胜。
## 塔防保留为外部压力，但不再是游戏的全部。

const FIRST_WAVE_AT := 60.0    # 第一波倒计时（城堡箭塔 + 首批兵刚好赶得上）
const WAVE_INTERVAL := 45.0
const MAX_WAVES := 10

var wave := 0
var wave_timer := FIRST_WAVE_AT

func _ready() -> void:
	add_to_group("wave_mgr")

func _game() -> Node2D:
	return get_tree().get_first_node_in_group("game")

func update(delta: float) -> void:
	wave_timer -= delta
	if wave_timer <= 0.0 and wave < MAX_WAVES:
		wave += 1
		wave_timer = WAVE_INTERVAL
		# 只数：2, 3, 4, 6, 8, 10, 12, 14, 16, 19——前几波给新手喘口气，后面越来越凶
		for i in 1 + wave + wave * wave / 12:
			_spawn_goo()
	if wave >= MAX_WAVES and get_tree().get_nodes_in_group("enemies").is_empty():
		var g := _game()
		if g:
			g._end("win", "十波全清，守住了！")

## 每只 Goo 轮流从还活着的巢穴出来，沿那个巢穴自己的土路走
var _spawn_i := 0

func _spawn_goo() -> void:
	var g := _game()
	if g == null:
		return
	var alive: Array = g.hives.filter(func(h): return is_instance_valid(h))
	if alive.is_empty():
		return
	var h: Node2D = alive[_spawn_i % alive.size()]
	_spawn_i += 1
	var goo := Goo.new()
	var rd: Array = g.road_for(h)
	# 出生点：巢穴脚下朝路的方向偏一点（别刷在巢穴背后的林子里）
	var out_dir := Vector2(0, 1)
	if rd.size() >= 2:
		out_dir = (rd[maxi(rd.size() - 6, 0)] - h.position).normalized()
	goo.position = h.position + out_dir * randf_range(60.0, 90.0) + out_dir.orthogonal() * randf_range(-40.0, 40.0)
	g.add_child(goo)
	# 血量每波 +6%：后期光靠堆人数不够，得配弓手
	goo.max_hp *= 1.0 + 0.06 * maxf(wave - 1, 0)
	goo.hp = goo.max_hp
	goo.start_lane(rd)
