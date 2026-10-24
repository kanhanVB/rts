extends Building
class_name Ruins
## Goo 据点废墟：窝拆了以后留下的一堆塌掉的碎石（中立 team 2：不挨打、不算胜负、怪和兵都不理它）。
## 没人看着就倒计时，到点 Goo 回来重新占领：窝立起来、守军刷满、背后那片富矿又被看住（再拆只缴获一半）。
## 停表：窝边的守军还没清完（本来就还是 Goo 的地盘）/ 有剑士弓手站在旁边 / 旁边有前哨工地。
## 在废墟旁盖好前哨 = 废墟清掉，这里永远是你的。

const REOCCUPY := 150.0     # 没人看着多久 Goo 回来
const WARN_AT := 30.0       # 还剩这么久时横幅提醒
const HOLD_R := 300.0       # 兵站在这么近 = 守着
const OUTPOST_R := 300.0    # 前哨要盖在这么近以内

var tier := 1
var loot_mult := 0.5        # 回来占的窝拆了缴获多少（按原来的比例）
var left := REOCCUPY
var hold := ""              # 停表的原因：guards / soldiers / site / ""（在倒计时）
var spotted := true
var _warned := false
var _think := 0.0

func setup_ruins(t: int) -> void:
	tier = t
	setup("ruins")
	team = 2

func _process(delta: float) -> void:
	if selected != _was_selected:
		_was_selected = selected
		queue_redraw()
	var g := get_tree().get_first_node_in_group("game")
	if g == null or g.game_state != "play":
		return
	_think -= delta
	if _think <= 0.0:
		_think = 0.5
		hold = hold_reason()
		queue_redraw()
	if hold != "":
		return
	left -= delta
	if left <= WARN_AT and not _warned:
		_warned = true
		if g.has_method("on_ruins_warning"):
			g.on_ruins_warning(self)
	if left <= 0.0 and not is_queued_for_deletion():
		if g.has_method("reoccupy"):
			g.reoccupy(self)

## 现在为什么不倒计时（"" = 正在倒计时）
func hold_reason() -> String:
	var tree := get_tree()
	for e in tree.get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and e.get("pack_center") != null and e.pack_center.distance_to(position) < 4.0:
			return "guards"
	for u in tree.get_nodes_in_group("player_units"):
		if is_instance_valid(u) and u is Soldier and not u.dead and u.position.distance_to(position) < HOLD_R:
			return "soldiers"
	for s in tree.get_nodes_in_group("sites"):
		if is_instance_valid(s) and s.kind == "outpost" and s.position.distance_to(position) < OUTPOST_R:
			return "site"
	return ""

func status_text() -> String:
	match hold:
		"guards":
			return "守军还没清完——还是 Goo 的地盘"
		"soldiers":
			return "有兵守着：Goo 不敢回来（倒计时停了，还剩 %d 秒）" % ceili(left)
		"site":
			return "前哨施工中：Goo 不敢回来"
	return "没人看着：%d 秒后 Goo 回来重新占领" % ceili(left)

func take_damage(_amount: float, _from: Node2D = null) -> void:
	pass    # 一堆碎石：打不坏

func _draw() -> void:
	var foot := Vector2(0, size * 0.42)
	Art.ellipse(self, foot - Vector2(0, 3), size * 0.95, Color(0.05, 0.08, 0.02, 0.28))
	if selected:
		Art.ellipse(self, foot - Vector2(0, 3), size * 1.05, Color(0.85, 0.8, 0.7), false, 3.0)
	var h := 0.0
	if Art.has("buildings/ruins"):
		h = Art.draw_w(self, "buildings/ruins", foot, size * 1.75)
	else:
		draw_circle(Vector2.ZERO, size * 0.5, Color(0.35, 0.3, 0.32))
		h = size * 0.6
	# 倒计时：头顶一圈橙色的表（停表时灰色、不转）
	if hold == "guards":
		return
	var c := foot - Vector2(0, h + 14.0)
	var frac := clampf(left / REOCCUPY, 0.0, 1.0)
	var col := Color(1.0, 0.6, 0.2) if hold == "" else Color(0.75, 0.75, 0.72)
	if hold == "" and left <= WARN_AT:
		col = Color(1.0, 0.32, 0.22)
	draw_circle(c, 9.5, Color(0.12, 0.08, 0.06, 0.75))
	draw_arc(c, 7.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 28, col, 3.0)
	draw_line(c, c + Vector2(0, -4.5), Color(1, 0.95, 0.85), 1.5)
	draw_line(c, c + Vector2(3.5, 0), Color(1, 0.95, 0.85), 1.5)
	if selected or (hold == "" and left <= WARN_AT):
		Art.text(self, c + Vector2(0, -14.0), "%d 秒" % ceili(left) if hold == "" else "停表", 12, col.lightened(0.3))
