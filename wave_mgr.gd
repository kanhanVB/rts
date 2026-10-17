class_name WaveManager
extends Node
## 波次系统：倒计时 → 出 Goo → 十波全清判胜。
## 塔防保留为外部压力，但不再是游戏的全部。

const FIRST_WAVE_AT := 50.0    # 第一波倒计时
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
		for i in 2 + wave:
			_spawn_goo()
	if wave >= MAX_WAVES and get_tree().get_nodes_in_group("enemies").is_empty():
		var g := _game()
		if g:
			g._end("win", "十波全清，守住了！")

func _spawn_goo() -> void:
	var g := _game()
	if g == null:
		return
	var hive_pos := Vector2(1110, 160)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b.kind == "hive" and is_instance_valid(b):
			hive_pos = b.position
			break
	var goo := Goo.new()
	goo.position = hive_pos + Vector2(randf_range(-60.0, 60.0), randf_range(60.0, 100.0))
	g.add_child(goo)
