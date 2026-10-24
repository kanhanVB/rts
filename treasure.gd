extends Node2D
class_name Treasure
## 宝箱 / 遗物：散在野地、藏在 Goo 据点窝边。选农民右键它 → 走过去弯腰扛起来（0.8 秒）→ 扛回基地 / 仓库 / 前哨才算到手：
## 宝箱开出一笔资源，遗物永久生效（relic.gd）。扛着的农民死了，东西掉在原地，再派人来捡。
## 据点里的那几件有守军看着：先带兵清场再派农民。

var kind := "chest"         # chest / relic
var loot := {}              # 宝箱：开出来的资源
var relic_id := ""          # 遗物：哪一件
var selected := false       # 被点中查看（只看说明）
var team := 2               # 中立：信息栏头像按非己方画
var _t0 := 0.0

const PICK_R := 26.0        # 农民走到这么近就能捡

func _ready() -> void:
	add_to_group("treasures")
	_t0 = randf() * 10.0

static func make(d: Dictionary) -> Treasure:
	var t := Treasure.new()
	t.kind = d.get("kind", "chest")
	t.loot = d.get("loot", {}).duplicate()
	t.relic_id = d.get("relic", "")
	return t

## 扛走：交出数据、自己消失
func take() -> Dictionary:
	var d := {"kind": kind, "loot": loot.duplicate(), "relic": relic_id}
	queue_free()
	return d

func title() -> String:
	return Relic.relic_name(relic_id) if kind == "relic" else "宝箱"

func color() -> Color:
	return Relic.DEFS[relic_id].color if kind == "relic" and Relic.DEFS.has(relic_id) else Color(1.0, 0.85, 0.35)

## 有没有 Goo 守军站在旁边（据点里的那几件）
func guarded() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.dead and e.get("pack_center") != null and e.is_guard() and e.pack_center.distance_to(position) < 160.0:
			return true
	return false

func info_text(econ) -> String:
	if kind == "relic":
		var d: Dictionary = Relic.DEFS.get(relic_id, {})
		return "遗物 · %s   %s（永久生效）\n选农民右键它，扛回基地 / 仓库 / 前哨就到手%s" % [title(), d.get("tip", ""),
			" · 有 Goo 守军看着，先清场" if guarded() else ""]
	return "宝箱   开出来：%s\n选农民右键它，扛回基地 / 仓库 / 前哨就开箱%s" % [Treasure.loot_text(loot),
		" · 有 Goo 守军看着，先清场" if guarded() else ""]

static func loot_text(l: Dictionary) -> String:
	var parts: Array = []
	for k in l:
		parts.append("%d %s" % [int(l[k]), Economy.KIND_NAME.get(k, k)])
	return "、".join(parts)

## 头顶小图标（农民扛着走的时候也用这套）
static func draw_icon(ci: CanvasItem, d: Dictionary, at: Vector2, h: float) -> void:
	if d.get("kind", "") == "relic":
		var col: Color = Relic.DEFS[d.relic].color if Relic.DEFS.has(d.get("relic", "")) else Color.WHITE
		ci.draw_circle(at + Vector2(0, -h * 0.5), h * 0.62, Color(col, 0.28))
		if Art.has("props/relic_gem"):
			Art.draw(ci, "props/relic_gem", at, h, false, col.lightened(0.15))
		else:
			ci.draw_circle(at + Vector2(0, -h * 0.5), h * 0.35, col)
	elif Art.has("props/chest"):
		Art.draw(ci, "props/chest", at, h)
	else:
		ci.draw_rect(Rect2(at + Vector2(-h * 0.6, -h), Vector2(h * 1.2, h)), Color(0.6, 0.4, 0.2))

func _process(_delta: float) -> void:
	queue_redraw()    # 闪光 / 宝石上下浮动（一张图只有几件，每帧重画很便宜）

func _draw() -> void:
	var now := Time.get_ticks_msec() / 1000.0 + _t0
	Art.ellipse(self, Vector2(0, 1), 13.0, Color(0.05, 0.08, 0.02, 0.32))
	if selected:
		Art.ellipse(self, Vector2(0, 1), 17.0, Color(1.0, 0.9, 0.5), false, 2.5)
	if kind == "relic":
		var col := color()
		if Art.has("props/plinth"):
			Art.draw(self, "props/plinth", Vector2(0, 2), 15.0)
		var bob := sin(now * 2.2) * 2.0
		var gp := Vector2(0, -13.0 + bob)
		var pulse := 0.5 + 0.5 * sin(now * 3.0)
		draw_circle(gp + Vector2(0, -8), 13.0, Color(col, 0.14 + 0.1 * pulse))
		draw_circle(gp + Vector2(0, -8), 8.0, Color(col, 0.2 + 0.12 * pulse))
		draw_icon(self, {"kind": "relic", "relic": relic_id}, gp, 17.0)
		_sparkle(gp + Vector2(7, -15), now * 1.3, col.lightened(0.5))
	else:
		draw_icon(self, {"kind": "chest"}, Vector2(0, 2), 21.0)
		_sparkle(Vector2(9, -18), now, Color(1.0, 0.95, 0.6))

## 一闪一闪的四角星
func _sparkle(p: Vector2, t: float, col: Color) -> void:
	var k := maxf(0.0, sin(t * 2.4))
	k = k * k * k
	if k < 0.05:
		return
	var r := 5.5 * k
	var pts := PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.25, -r * 0.25), p + Vector2(r, 0), p + Vector2(r * 0.25, r * 0.25),
		p + Vector2(0, r), p + Vector2(-r * 0.25, r * 0.25), p + Vector2(-r, 0), p + Vector2(-r * 0.25, -r * 0.25)])
	draw_colored_polygon(pts, Color(col, 0.95 * k))
