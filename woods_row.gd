class_name WoodsRow
extends Node2D
## 地图边缘装饰密林的一行：同一行的树合成一个节点画（参与 y 排序：单位在这行树的上方就被树挡住）。
## 只是看的，不能砍；挡路靠地形格子（Terrain.T.WOODS）。

var trees: Array = []    # [{x, dy, v, flip, h}]

func _draw() -> void:
	for t in trees:
		var key := "resources/tree_%d" % t.v
		if Art.has(key):
			Art.draw(self, key, Vector2(t.x, t.dy + 12.0), t.h, t.flip, t.get("mod", Color.WHITE))
		else:
			draw_circle(Vector2(t.x, t.dy - 14.0), 16.0, Color(0.2, 0.42, 0.16))
