extends Node2D
class_name ConstructionSite
## 工地：兵营放下后先变成工地，由英雄工程师施工。进度满 -> main 生成真建筑。
## 有血量——Goo 会啃它，被拆了投入的资源就打水漂。

var kind := "barracks"
var progress := 0.0
var build_time := 8.0
var assigned: Node2D = null    # 认领工地的工程师
var size := 60.0
var hp := 150.0
var max_hp := 150.0

func _ready() -> void:
	add_to_group("sites")

func _process(_delta: float) -> void:
	queue_redraw()

func take_damage(amount: float, _from: Node2D = null) -> void:
	hp -= amount
	if hp <= 0.0:
		var mgr := get_tree().get_first_node_in_group("build_mgr")
		if mgr:
			mgr.site_destroyed(self)
		else:
			queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var dark := Color(0.16, 0.13, 0.09)
	var r := Rect2(-size / 2.0, -size / 2.0, size, size)
	draw_rect(r, Color(0.16, 0.66, 0.58, 0.25))
	# 脚手架对角线
	draw_line(Vector2(-size / 2.0, -size / 2.0), Vector2(size / 2.0, size / 2.0), Color(0.16, 0.66, 0.58, 0.5), 2.0)
	draw_line(Vector2(size / 2.0, -size / 2.0), Vector2(-size / 2.0, size / 2.0), Color(0.16, 0.66, 0.58, 0.5), 2.0)
	draw_rect(r, dark, false, 2.0)
	# 血条（掉血才显示），比进度条更靠上
	if hp < max_hp:
		draw_rect(Rect2(-size / 2.0, -size / 2.0 - 21.0, size, 5.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-size / 2.0, -size / 2.0 - 21.0, size * hp / max_hp, 5.0), Color(0.92, 0.3, 0.25))
	# 进度条
	draw_rect(Rect2(-size / 2.0, -size / 2.0 - 12.0, size, 5.0), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(-size / 2.0, -size / 2.0 - 12.0, size * progress, 5.0), Color(0.95, 0.8, 0.3))
	var txt := "等待工程师" if assigned == null else "施工中 %d%%" % int(progress * 100.0)
	draw_string(ThemeDB.fallback_font, Vector2(-size / 2.0, -size / 2.0 - 26.0), txt, HORIZONTAL_ALIGNMENT_LEFT, size * 2.0, 12, Color(0.2, 0.18, 0.12))
