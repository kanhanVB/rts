class_name DecorLayer
extends Node2D
## 地面装饰层（灌木/花丛/石头/树桩）：垫在单位下面，只在有变化（砍出新树桩）时重画。

const DECOR_H := {"decor/bush_1": 26.0, "decor/bush_2": 26.0, "decor/flowers": 16.0, "decor/rock_1": 16.0, "decor/stump": 20.0}
var items: Array = []    # [{key, pos, flip}]

func _ready() -> void:
	z_index = -1

func add_item(key: String, pos: Vector2, flip := false) -> void:
	items.append({"key": key, "pos": pos, "flip": flip})
	queue_redraw()

func _draw() -> void:
	for d in items:
		if Art.has(d.key):
			Art.draw(self, d.key, d.pos, DECOR_H.get(d.key, 20.0), d.flip)
