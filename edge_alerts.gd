class_name EdgeAlerts
extends Control
## 屏幕边缘的受袭指示：哪边在挨打、而那里又在画面外，就在那一侧的边上画一支脉动的红箭头。
## 小地图上的红点对"眼睛盯着战场中间"的玩家来说太远了——这是 RTS 的标配（帝国、星际都有）。
## 只画"看不见的"：受击点已经在画面里就什么都不画，别在屏幕上再糊一层红。

const MARGIN := 26.0        # 离屏幕边留出的像素（躲开顶栏/底栏的边）
const ARROW := 15.0         # 箭头大小

var main: Node2D

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if main == null or not is_instance_valid(main):
		return
	var alerts: Array = main.active_alerts()
	if alerts.is_empty():
		return
	var vp := get_viewport_rect().size
	var ct: Transform2D = get_viewport().get_canvas_transform()
	# 地图可视区（避开顶栏/底栏），箭头只贴在这个区域的边上
	var ytop: float = float(main.hud_top_h()) + MARGIN
	var ybot: float = vp.y - float(main.hud_bottom_h()) - MARGIN
	var pulse := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.006))
	for a in alerts:
		var sp: Vector2 = ct * (a["pos"] as Vector2)
		if sp.x > MARGIN and sp.x < vp.x - MARGIN and sp.y > ytop - MARGIN and sp.y < ybot + MARGIN:
			continue    # 画面里看得见，不用指
		var c := Vector2(clampf(sp.x, MARGIN, vp.x - MARGIN), clampf(sp.y, ytop, ybot))
		var dir := sp - vp * 0.5
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		dir = dir.normalized()
		var n := Vector2(-dir.y, dir.x)
		# 是基地挨打就红得更狠：一眼能分出"家里出事"和"边角被摸"
		var hot := String(a["what"]) == "base"
		var col := Color(1.0, 0.3, 0.22, pulse) if hot else Color(1.0, 0.62, 0.2, pulse * 0.9)
		draw_line(c - dir * ARROW * 0.4, c - dir * ARROW * 1.9, Color(col.r, col.g, col.b, col.a * 0.45), 3.0, true)
		draw_colored_polygon(PackedVector2Array([
			c + dir * ARROW,
			c - dir * ARROW * 0.45 + n * ARROW * 0.8,
			c - dir * ARROW * 0.45 - n * ARROW * 0.8,
		]), col)
