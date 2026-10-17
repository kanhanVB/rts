extends Node2D
class_name ResNode
## 资源点：矿（琥珀石）/ 树（双冠小树），被工人采空就消失。
## KR 式画法：先画一层深色放大版做描边，再叠填充，最后点高光。

var kind: String = "ore"    # ore / wood
var amount: float = 250.0
var radius: float = 16.0    # 绕障用的碰撞半径

func _ready() -> void:
	add_to_group("res_nodes")

func _draw() -> void:
	var dark := Color(0.16, 0.13, 0.09)
	# 软投影
	draw_set_transform(Vector2(0, 11), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 16.0, Color(0.08, 0.12, 0.05, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if kind == "ore":
		# 描边层
		draw_circle(Vector2(-4, -3), 12.0, dark)
		draw_circle(Vector2(6, 3), 9.0, dark)
		# 填充层：石座 + 两块矿
		draw_circle(Vector2(0, 4), 10.0, Color(0.5, 0.47, 0.42))
		draw_circle(Vector2(-4, -3), 10.0, Color(0.85, 0.66, 0.16))
		draw_circle(Vector2(6, 3), 7.0, Color(0.95, 0.8, 0.3))
		draw_arc(Vector2(-4, -3), 10.0, 0, TAU, 24, dark, 2.0)
		draw_arc(Vector2(6, 3), 7.0, 0, TAU, 20, dark, 2.0)
		draw_circle(Vector2(-7, -7), 2.5, Color(1, 1, 0.85, 0.85))
	else:
		# 描边层（树冠三团 + 树干）
		draw_circle(Vector2(-5, -6), 13.0, dark)
		draw_circle(Vector2(6, -3), 11.0, dark)
		draw_circle(Vector2(0, -12), 11.0, dark)
		draw_rect(Rect2(-4.5, 1, 9, 14), dark)
		# 填充层
		draw_rect(Rect2(-3, 2, 6, 12), Color(0.45, 0.3, 0.18))
		draw_circle(Vector2(-5, -6), 11.0, Color(0.3, 0.62, 0.3))
		draw_circle(Vector2(6, -3), 9.0, Color(0.34, 0.68, 0.32))
		draw_circle(Vector2(0, -12), 9.0, Color(0.38, 0.72, 0.34))
		draw_circle(Vector2(-2, -14), 2.5, Color(0.75, 0.95, 0.6, 0.7))
