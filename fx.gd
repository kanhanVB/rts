class_name Fx
extends Node2D
## 纯视觉的一次性特效：尸体淡出 / 黏液飞溅 / 尘土 / 交货漂字。不进任何逻辑分组，测试和玩法都看不到它。

var kind := ""          # corpse / splat / dust / floater
var key := ""
var text := ""
var color := Color.WHITE
var flip := false
var size := 40.0
var life := 1.0
var _t := 0.0
var to := Vector2.ZERO  # arrow：飞向的世界坐标
var _y_off := 0.0       # 尸体往上挪一点参与 y 排序，保证垫在活人下面

static func spawn(parent: Node, k: String, pos: Vector2, opts := {}) -> Fx:
	if parent == null or not parent.is_inside_tree():
		return null
	var f := Fx.new()
	f.kind = k
	for o in opts:
		f.set(o, opts[o])
	f.position = pos
	if k == "corpse" or k == "splat":
		f._y_off = 40.0
		f.position.y -= f._y_off
	if k == "floater" or k == "arrow":
		f.z_index = 20
	parent.add_child(f)
	return f

func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var p := _t / life
	var base := Vector2(0, _y_off)
	match kind:
		"corpse":
			var a := clampf((1.0 - p) * 2.5, 0.0, 1.0)
			Art.draw(self, key, base, size, flip, Color(1, 1, 1, a))
		"splat":
			var a := clampf((1.0 - p) * 2.0, 0.0, 1.0)
			Art.draw(self, "fx/goo_splat", base, size * (0.7 + p * 0.5), flip, Color(1, 1, 1, a))
		"dust":
			for i in 5:
				var ang := TAU * i / 5.0
				var off := Vector2(cos(ang), sin(ang) * 0.5) * size * 0.5 * (0.4 + p)
				Art.draw(self, "fx/dust", off - Vector2(0, size * 0.2 * p), size * 0.5 * (0.6 + p * 0.6), false, Color(1, 1, 1, 1.0 - p))
		"arrow":
			# 抛物线箭：从塔顶飞到目标，箭头顺着速度方向
			var d := to - position
			var arc := 28.0 + d.length() * 0.12
			var at := d * p + Vector2(0, -sin(p * PI) * arc)
			var vel := d + Vector2(0, -cos(p * PI) * PI * arc)
			if Art.has("fx/arrow"):
				Art.draw(self, "fx/arrow", at, 7.0, false, Color.WHITE, vel.angle())
			else:
				draw_line(at - vel.normalized() * 10.0, at, Color(0.3, 0.2, 0.1), 2.0)
		"floater":
			modulate.a = clampf((1.0 - p) * 2.5, 0.0, 1.0)
			Art.text(self, Vector2(0, -p * 26.0), text, 15, color)
