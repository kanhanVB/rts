class_name EdgeAlerts
extends Control
## 屏幕边缘的受袭指示：哪边在挨打、而那里又在画面外，就在那一侧的边上画一支脉动的红箭头。
## 小地图上的红点对"眼睛盯着战场中间"的玩家来说太远了——这是 RTS 的标配（帝国、星际都有）。
## 只画"看不见的"：受击点已经在画面里就什么都不画，别在屏幕上再糊一层红。
## **箭头能点**：点一下镜头就飞过去。看见箭头还得自己找小地图、拖镜头，等于白指了一次。

const MARGIN := 26.0        # 离屏幕边留出的像素（躲开顶栏/底栏的边）
const ARROW := 15.0         # 箭头大小
const HIT_R := 24.0         # 点击命中半径（比箭头大一圈：不用瞄准）

var main: Node2D

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

## 这一帧该在哪些位置画箭头：[{c: 屏幕坐标, dir: 指向, pos: 世界坐标, hot: 是不是基地}]
## 纯计算、不碰绘制——headless 跑测试时 _draw 根本不会被调用（不渲染），
## 命中判定要是写在 _draw 里就永远测不到了
func alert_hits() -> Array:
	var out: Array = []
	if main == null or not is_instance_valid(main):
		return out
	var alerts: Array = main.active_alerts()
	if alerts.is_empty():
		return out
	var vp := get_viewport_rect().size
	var ct: Transform2D = get_viewport().get_canvas_transform()
	# 地图可视区（避开顶栏/底栏），箭头只贴在这个区域的边上
	var ytop: float = float(main.hud_top_h()) + MARGIN
	var ybot: float = vp.y - float(main.hud_bottom_h()) - MARGIN
	for a in alerts:
		var sp: Vector2 = ct * (a["pos"] as Vector2)
		if sp.x > MARGIN and sp.x < vp.x - MARGIN and sp.y > ytop - MARGIN and sp.y < ybot + MARGIN:
			continue    # 画面里看得见，不用指
		var c := Vector2(clampf(sp.x, MARGIN, vp.x - MARGIN), clampf(sp.y, ytop, ybot))
		var dir := sp - vp * 0.5
		if dir.length() < 1.0:
			dir = Vector2.DOWN
		out.append({"c": c, "dir": dir.normalized(), "pos": a["pos"], "hot": String(a["what"]) == "base"})
	return out

## 屏幕坐标 → 那支箭头指的世界坐标；没点中返回 Vector2.INF
func hit_alert(screen: Vector2) -> Vector2:
	for h in alert_hits():
		if (h["c"] as Vector2).distance_to(screen) <= HIT_R:
			return h["pos"]
	return Vector2.INF

func _draw() -> void:
	var hits := alert_hits()
	if hits.is_empty():
		return
	var pulse := 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.006))
	var mv := get_local_mouse_position()
	for h in hits:
		var c: Vector2 = h["c"]
		var dir: Vector2 = h["dir"]
		var n := Vector2(-dir.y, dir.x)
		# 鼠标压上去就放大一点：不然玩家不知道这东西是能点的
		var k := ARROW * (1.25 if c.distance_to(mv) <= HIT_R else 1.0)
		# 是基地挨打就红得更狠：一眼能分出"家里出事"和"边角被摸"
		var col := Color(1.0, 0.3, 0.22, pulse) if bool(h["hot"]) else Color(1.0, 0.62, 0.2, pulse * 0.9)
		draw_line(c - dir * k * 0.4, c - dir * k * 1.9, Color(col.r, col.g, col.b, col.a * 0.45), 3.0, true)
		draw_colored_polygon(PackedVector2Array([
			c + dir * k,
			c - dir * k * 0.45 + n * k * 0.8,
			c - dir * k * 0.45 - n * k * 0.8,
		]), col)
