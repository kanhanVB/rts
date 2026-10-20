extends Node2D
class_name Building
## 建筑：基地（交资源/造农民）、兵营（出兵）、巢穴（敌人老窝，拆了就赢）。
## KR 式建模：石基 + 半木墙 + 大出檐屋顶 + 旗帜；巢穴是黏液山包 + 尖刺 + 红光洞口。

var kind: String = "base"    # base / barracks / hive
var team: int = 0
var hp: float = 600.0
var max_hp: float = 600.0
var size: float = 76.0
var display_name := "建筑"
var selected := false        # 被玩家点中（画白圈 + 信息栏显示数值）

const OUTLINE := Color(0.2, 0.14, 0.1)
const COLORS := {
	"base": Color(0.35, 0.46, 0.62),     # 蓝瓦
	"barracks": Color(0.55, 0.38, 0.26), # 棕瓦
	"hive": Color(0.42, 0.38, 0.36),     # 岩石
}

func setup(k: String) -> void:
	kind = k
	match k:
		"base":
			hp = 600.0
			size = 76.0
		"barracks":
			hp = 300.0
			size = 60.0
		"warehouse":
			hp = 250.0
			size = 64.0
		"smelter":
			hp = 220.0
			size = 56.0
		"workshop":
			hp = 220.0
			size = 56.0
		"hive":
			hp = 900.0
			size = 84.0
	max_hp = hp
	display_name = label_text()

func _ready() -> void:
	add_to_group("buildings")

func take_damage(amount: float, _from: Node2D = null) -> void:
	if is_queued_for_deletion():
		return
	hp -= amount
	_hurt_until = Time.get_ticks_msec() + 160
	queue_redraw()
	if hp <= 0.0:
		if not is_queued_for_deletion():
			Fx.spawn(get_parent(), "dust", position + Vector2(0, size * 0.2), {"size": size * 1.6, "life": 0.8})
		queue_free()

## 城堡自带箭塔（王国保卫战式）：开局没兵也能顶住零星几只 Goo，但挡不住大波
const TOWER_RANGE := 170.0
const TOWER_DMG := 8.0
const TOWER_CD := 1.2
var _tower_cd := 0.0

func has_tower() -> bool:
	return kind == "base" and team == 0

func _tower(delta: float) -> void:
	_tower_cd -= delta
	if _tower_cd > 0.0:
		return
	var best: Node2D = null
	var best_d := TOWER_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		_tower_cd = 0.2    # 没目标时别每帧扫
		return
	_tower_cd = TOWER_CD
	best.take_damage(TOWER_DMG, self)
	var from := position + Vector2(-26.0 if best.position.x < position.x else 26.0, -size * 0.95)
	Fx.spawn(get_parent(), "arrow", from, {"to": best.position + Vector2(0, -12), "life": 0.3})

## 挨打抖动 / 选中圈要持续刷新（便宜：只在需要时重画）
var _was_selected := false
func _process(delta: float) -> void:
	if has_tower():
		_tower(delta)
	if Time.get_ticks_msec() < _hurt_until + 40 or selected != _was_selected:
		_was_selected = selected
		queue_redraw()

## ---------- 贴图版 ----------
const ART_W := 1.85            # 贴图显示宽度 = size × 这个系数
var _hurt_until := 0

func _art_draw() -> bool:
	var key := "buildings/" + kind
	if hp < max_hp * 0.5 and Art.has(key + "_damaged"):
		key += "_damaged"
	if not Art.has(key):
		return false
	var foot := Vector2(0, size * 0.42)
	Art.ellipse(self, foot - Vector2(0, 4), size * 0.85, Color(0.05, 0.1, 0.02, 0.3))
	if selected:
		Art.ellipse(self, foot - Vector2(0, 4), size * 0.95, Color(0.55, 1.0, 0.35) if team == 0 else Color(1.0, 0.35, 0.25), false, 3.0)
	var shake := 0.0
	var mod := Color.WHITE
	if Time.get_ticks_msec() < _hurt_until:
		shake = sin(Time.get_ticks_msec() * 0.08) * 2.0
		mod = Color(1.0, 0.75, 0.7)
	# 受损版和正常版同一比例导出：按两张图宽度之比画，换图时房子不会缩放跳动
	var w := size * ART_W
	if key.ends_with("_damaged"):
		var nw: float = Art.info(key.trim_suffix("_damaged")).get("w", 0.0)
		if nw > 0.0:
			w *= float(Art.info(key).w) / nw
	var h := Art.draw_w(self, key, foot + Vector2(shake, 0), w, mod)
	if hp < max_hp or selected:
		Art.hp_bar(self, foot - Vector2(0, h + 6.0), size * 0.7, hp / max_hp, team == 0, 4.0)
	return true

func _draw() -> void:
	if _art_draw():
		return
	# 选中白圈
	if selected:
		draw_arc(Vector2.ZERO, size * 0.78, 0, TAU, 36, Color(1, 1, 1, 0.9), 2.5)
	# 软投影
	draw_set_transform(Vector2(0, size * 0.32), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, size * 0.62, Color(0.08, 0.12, 0.05, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match kind:
		"base":
			_draw_base()
		"barracks":
			_draw_barracks()
		"warehouse":
			_draw_warehouse()
		"smelter":
			_draw_smelter()
		"workshop":
			_draw_workshop()
		"hive":
			_draw_hive()
	# 血条（悬在屋顶上方）
	if hp < max_hp:
		draw_rect(Rect2(-size * 0.5, -size * 0.74, size, 6.0), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(-size * 0.5, -size * 0.74, size * hp / max_hp, 6.0), Color(0.3, 0.9, 0.3))

## ---------- 通用小件 ----------
## 填充多边形 + 一体厚描边
func _poly(pts: PackedVector2Array, fill: Color, line_w: float = 3.0) -> void:
	draw_colored_polygon(pts, fill)
	draw_polyline(pts + PackedVector2Array([pts[0]]), OUTLINE, line_w)

## 发暖光的窗（KR 夜景感的小性价比）
func _window(pos: Vector2, w: float) -> void:
	draw_rect(Rect2(pos - Vector2(w / 2.0, w / 2.0), Vector2(w, w)), OUTLINE)
	draw_rect(Rect2(pos - Vector2(w / 2.0 - 1.5, w / 2.0 - 1.5), Vector2(w - 3.0, w - 3.0)), Color(0.99, 0.85, 0.45))

## 蓝底白十字盾徽（挂墙上的 KR 味小件）
func _shield(c: Vector2, r: float) -> void:
	draw_circle(c, r + 1.5, OUTLINE)
	draw_circle(c, r, Color(0.3, 0.42, 0.62))
	draw_colored_polygon(PackedVector2Array([
		Vector2(c.x - r * 0.8, c.y + r * 0.55), Vector2(c.x + r * 0.8, c.y + r * 0.55), c + Vector2(0, r * 1.4)
	]), Color(0.3, 0.42, 0.62))
	draw_polyline(PackedVector2Array([
		Vector2(c.x - r * 0.8, c.y + r * 0.55), c + Vector2(0, r * 1.4), Vector2(c.x + r * 0.8, c.y + r * 0.55)
	]), OUTLINE, 2.0)
	draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), Color(0.93, 0.9, 0.8), 2.2)
	draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, 0), Color(0.93, 0.9, 0.8), 2.2)

## 拱形木门
func _door(cx: float, top: float, w: float, h: float) -> void:
	draw_rect(Rect2(cx - w / 2.0 - 1.5, top - 1.5, w + 3.0, h + 1.5), OUTLINE)
	draw_rect(Rect2(cx - w / 2.0, top, w, h), Color(0.5, 0.36, 0.2))
	draw_circle(Vector2(cx, top), w / 2.0, Color(0.5, 0.36, 0.2))
	draw_circle(Vector2(cx, top), w / 2.0 + 1.5, OUTLINE, false, 2.0)
	draw_line(Vector2(cx, top + w * 0.2), Vector2(cx, top + h), OUTLINE, 1.5)

## 旗杆 + 飘着的小三角旗
func _banner(top: Vector2, h: float, col: Color) -> void:
	draw_line(top, top + Vector2(0, -h), OUTLINE, 2.5)
	var tip := top + Vector2(0, -h)
	_poly(PackedVector2Array([
		tip, tip + Vector2(20.0, -3.0), tip + Vector2(0, -13.0)
	]), col, 2.0)

## ---------- 基地：石墙主楼 + 蓝瓦大顶 + 旗（KR 主堡感） ----------
func _draw_base() -> void:
	var s := size
	var stone := Color(0.56, 0.58, 0.6)
	var seam := Color(0.44, 0.46, 0.48)
	# 石墙主体
	draw_rect(Rect2(-s * 0.42, -s * 0.3, s * 0.84, s * 0.62), OUTLINE)
	draw_rect(Rect2(-s * 0.38, -s * 0.26, s * 0.76, s * 0.54), stone)
	for i in 3:
		var x := -s * 0.38 + s * 0.76 * (i + 1) / 4.0
		draw_line(Vector2(x, -s * 0.24), Vector2(x, s * 0.28), seam, 2.0)
	draw_line(Vector2(-s * 0.36, -s * 0.04), Vector2(s * 0.36, -s * 0.04), seam, 2.0)
	# 拱门 + 暖窗
	_door(0.0, s * 0.08, s * 0.2, s * 0.24)
	_window(Vector2(-s * 0.24, -s * 0.1), s * 0.12)
	_window(Vector2(s * 0.24, -s * 0.1), s * 0.12)
	# 蓝瓦大屋顶（出檐 + 瓦线 + 脊线高光）
	var roof: Color = COLORS["base"]
	_poly(PackedVector2Array([
		Vector2(-s * 0.56, -s * 0.24), Vector2(s * 0.56, -s * 0.24),
		Vector2(s * 0.28, -s * 0.64), Vector2(-s * 0.28, -s * 0.64)
	]), roof)
	draw_line(Vector2(-s * 0.4, -s * 0.37), Vector2(s * 0.4, -s * 0.37), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.24, -s * 0.52), Vector2(s * 0.24, -s * 0.52), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.28, -s * 0.64), Vector2(s * 0.28, -s * 0.64), roof.lightened(0.15), 3.0)
	# 蓝旗
	_banner(Vector2(-s * 0.28, -s * 0.64), s * 0.18, roof)

## ---------- 兵营：石基 + 灰泥木架墙 + 棕瓦顶 + 盾徽（KR 民房同款） ----------
func _draw_barracks() -> void:
	var s := size
	var plaster := Color(0.9, 0.85, 0.7)
	var beam := Color(0.5, 0.38, 0.26)
	# 石砌地基
	draw_rect(Rect2(-s * 0.48, s * 0.08, s * 0.96, s * 0.3), OUTLINE)
	draw_rect(Rect2(-s * 0.44, s * 0.12, s * 0.88, s * 0.22), Color(0.56, 0.58, 0.6))
	draw_line(Vector2(-s * 0.44, s * 0.23), Vector2(s * 0.44, s * 0.23), Color(0.44, 0.46, 0.48), 2.0)
	# 灰泥墙 + 木架
	draw_rect(Rect2(-s * 0.36, -s * 0.26, s * 0.72, s * 0.48), OUTLINE)
	draw_rect(Rect2(-s * 0.33, -s * 0.23, s * 0.66, s * 0.42), plaster)
	draw_line(Vector2(-s * 0.15, -s * 0.23), Vector2(-s * 0.15, s * 0.19), beam, 3.0)
	draw_line(Vector2(s * 0.15, -s * 0.23), Vector2(s * 0.15, s * 0.19), beam, 3.0)
	# X 木架（山墙感）
	draw_line(Vector2(-s * 0.33, s * 0.19), Vector2(-s * 0.05, -s * 0.23), beam, 2.5)
	draw_line(Vector2(s * 0.05, -s * 0.23), Vector2(s * 0.33, s * 0.19), beam, 2.5)
	# 拱门 + 圆窗 + 盾徽
	_door(-s * 0.16, s * 0.02, s * 0.16, s * 0.22)
	draw_circle(Vector2(s * 0.24, -s * 0.02), s * 0.07 + 1.5, OUTLINE)
	draw_circle(Vector2(s * 0.24, -s * 0.02), s * 0.07, Color(0.99, 0.85, 0.45))
	_shield(Vector2(0, -s * 0.04), s * 0.1)
	# 棕瓦屋顶
	var roof := Color(0.55, 0.38, 0.26)
	_poly(PackedVector2Array([
		Vector2(-s * 0.56, -s * 0.2), Vector2(s * 0.56, -s * 0.2),
		Vector2(s * 0.26, -s * 0.58), Vector2(-s * 0.26, -s * 0.58)
	]), roof)
	draw_line(Vector2(-s * 0.38, -s * 0.34), Vector2(s * 0.38, -s * 0.34), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.24, -s * 0.48), Vector2(s * 0.24, -s * 0.48), roof.darkened(0.22), 2.5)
	# 红旗
	_banner(Vector2(s * 0.26, -s * 0.58), s * 0.16, Color(0.75, 0.3, 0.25))

## ---------- 仓库：木板谷仓 + 大坡屋顶 + 门前货堆（基建的收货点） ----------
func _draw_warehouse() -> void:
	var s := size
	var plank := Color(0.72, 0.55, 0.34)
	var plank_dark := Color(0.55, 0.4, 0.24)
	# 石砌地基
	draw_rect(Rect2(-s * 0.46, s * 0.06, s * 0.92, s * 0.32), OUTLINE)
	draw_rect(Rect2(-s * 0.42, s * 0.1, s * 0.84, s * 0.24), Color(0.56, 0.58, 0.6))
	# 木板墙：横向板纹
	draw_rect(Rect2(-s * 0.38, -s * 0.3, s * 0.76, s * 0.48), OUTLINE)
	draw_rect(Rect2(-s * 0.35, -s * 0.27, s * 0.7, s * 0.42), plank)
	for i in 4:
		var y := -s * 0.27 + s * 0.42 * (i + 1) / 5.0
		draw_line(Vector2(-s * 0.35, y), Vector2(s * 0.35, y), plank_dark, 2.0)
	# 双开大门
	_door(0.0, s * 0.0, s * 0.26, s * 0.22)
	draw_line(Vector2(0, s * 0.02), Vector2(0, s * 0.22), OUTLINE, 2.0)
	# 大坡瓦顶
	var roof := Color(0.5, 0.35, 0.24)
	_poly(PackedVector2Array([
		Vector2(-s * 0.54, -s * 0.24), Vector2(s * 0.54, -s * 0.24),
		Vector2(s * 0.24, -s * 0.62), Vector2(-s * 0.24, -s * 0.62)
	]), roof)
	draw_line(Vector2(-s * 0.36, -s * 0.38), Vector2(s * 0.36, -s * 0.38), roof.darkened(0.22), 2.5)
	draw_line(Vector2(-s * 0.2, -s * 0.5), Vector2(s * 0.2, -s * 0.5), roof.darkened(0.22), 2.5)
	# 门前货堆：木箱 + 矿石堆，一眼看出是收货点
	var box := Color(0.62, 0.48, 0.3)
	draw_rect(Rect2(-s * 0.30, s * 0.20, s * 0.16, s * 0.12), OUTLINE)
	draw_rect(Rect2(-s * 0.29, s * 0.21, s * 0.14, s * 0.10), box)
	draw_rect(Rect2(-s * 0.12, s * 0.24, s * 0.12, s * 0.08), OUTLINE)
	draw_rect(Rect2(-s * 0.11, s * 0.25, s * 0.10, s * 0.06), box)
	for i in 3:
		var p := Vector2(s * 0.18 + (i % 2) * s * 0.08, s * 0.28 - int(i / 2) * s * 0.07)
		draw_circle(p, s * 0.05, Color(0.85, 0.66, 0.16))
		draw_arc(p, s * 0.05, 0, TAU, 14, OUTLINE, 1.5)

## ---------- 熔炉：石炉 + 烟囱冒烟 + 炉口橙光（矿石 -> 铁锭） ----------
func _draw_smelter() -> void:
	var s := size
	var stone := Color(0.58, 0.56, 0.54)
	# 石砌炉身
	draw_rect(Rect2(-s * 0.44, -s * 0.1, s * 0.88, s * 0.44), OUTLINE)
	draw_rect(Rect2(-s * 0.40, -s * 0.06, s * 0.80, s * 0.36), stone)
	draw_line(Vector2(-s * 0.40, s * 0.08), Vector2(s * 0.40, s * 0.08), Color(0.45, 0.43, 0.42), 2.0)
	# 炉口（橙光 + 铁水）
	draw_circle(Vector2(0, s * 0.06), s * 0.13 + 1.6, OUTLINE)
	draw_circle(Vector2(0, s * 0.06), s * 0.13, Color(0.92, 0.42, 0.12))
	draw_circle(Vector2(0, s * 0.06), s * 0.07, Color(1.0, 0.75, 0.25))
	# 烟囱 + 三团烟（往上飘散）
	draw_rect(Rect2(s * 0.18, -s * 0.34, s * 0.16, s * 0.26), OUTLINE)
	draw_rect(Rect2(s * 0.20, -s * 0.32, s * 0.12, s * 0.22), stone)
	for i in 3:
		var p := Vector2(s * 0.26 + i * s * 0.06, -s * 0.38 - i * s * 0.14)
		draw_circle(p, s * 0.06 + i * s * 0.02, Color(0.75, 0.74, 0.72, 0.85 - i * 0.2))
	# 成品铁锭堆（体现产出）
	for i in 2:
		var q := Vector2(-s * 0.36 + i * s * 0.16, s * 0.24)
		draw_rect(Rect2(q.x, q.y, s * 0.14, s * 0.08), OUTLINE)
		draw_rect(Rect2(q.x + 1.5, q.y + 1.5, s * 0.11, s * 0.05), Color(0.78, 0.79, 0.81))

## ---------- 木工台：敞棚 + 工作台 + 锯 + 板材（木材 -> 木板） ----------
func _draw_workshop() -> void:
	var s := size
	var timber := Color(0.66, 0.48, 0.28)
	# 立柱敞棚
	for x in [-s * 0.36, s * 0.36]:
		draw_rect(Rect2(x - s * 0.05, -s * 0.3, s * 0.1, s * 0.62), OUTLINE)
		draw_rect(Rect2(x - s * 0.035, -s * 0.285, s * 0.07, s * 0.59), timber)
	# 棚顶（木板坡）
	_poly(PackedVector2Array([
		Vector2(-s * 0.5, -s * 0.26), Vector2(s * 0.5, -s * 0.26),
		Vector2(s * 0.34, -s * 0.46), Vector2(-s * 0.34, -s * 0.46)
	]), Color(0.5, 0.36, 0.22))
	# 工作台
	draw_rect(Rect2(-s * 0.26, s * 0.02, s * 0.52, s * 0.16), OUTLINE)
	draw_rect(Rect2(-s * 0.24, s * 0.04, s * 0.48, s * 0.12), Color(0.74, 0.56, 0.34))
	# 锯（斜插在工作台上）
	draw_line(Vector2(-s * 0.1, s * 0.02), Vector2(s * 0.14, s * 0.2), OUTLINE, 3.0)
	draw_line(Vector2(-s * 0.1, s * 0.02), Vector2(s * 0.14, s * 0.2), Color(0.8, 0.82, 0.85), 1.5)
	# 成品木板（靠墙立着）
	for i in 2:
		var q := Vector2(-s * 0.3 + i * s * 0.1, s * 0.2)
		draw_rect(Rect2(q.x, q.y - s * 0.2, s * 0.09, s * 0.26), OUTLINE)
		draw_rect(Rect2(q.x + 1.5, q.y - s * 0.185, s * 0.06, s * 0.23), Color(0.85, 0.68, 0.42))

## ---------- 巢穴：岩石老窝 + 尖刺 + 红光洞口（无脸） ----------
func _draw_hive() -> void:
	var s := size
	var rock := Color(0.42, 0.38, 0.36)
	var lumps := [
		[Vector2(0, s * 0.05), s * 0.42],
		[Vector2(-s * 0.32, s * 0.16), s * 0.3],
		[Vector2(s * 0.34, s * 0.12), s * 0.32],
		[Vector2(0, -s * 0.16), s * 0.28],
	]
	# 一体化厚描边：先画深色放大 union
	for L in lumps:
		draw_circle(L[0], L[1] + 2.4, OUTLINE)
	for L in lumps:
		draw_circle(L[0], L[1], rock)
	# 底部暗面色带
	draw_set_transform(Vector2(0, s * 0.3), 0.0, Vector2(0.85, 0.4))
	draw_circle(Vector2.ZERO, s * 0.5, rock.darkened(0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 骨色尖刺（角）
	for p in [Vector2(-s * 0.2, -s * 0.3), Vector2(0, -s * 0.44), Vector2(s * 0.22, -s * 0.32)]:
		_poly(PackedVector2Array([
			p + Vector2(-s * 0.07, s * 0.1), p + Vector2(s * 0.07, s * 0.1), p + Vector2(0, -s * 0.14)
		]), Color(0.72, 0.68, 0.58), 2.0)
	# 左上高光
	draw_set_transform(Vector2(-s * 0.18, -s * 0.26), 0.0, Vector2(0.7, 0.45))
	draw_circle(Vector2.ZERO, s * 0.14, Color(0.55, 0.51, 0.47))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 红光洞口（老窝的大门）
	draw_circle(Vector2(0, s * 0.2), s * 0.17, OUTLINE)
	draw_circle(Vector2(0, s * 0.2), s * 0.14, Color(0.12, 0.06, 0.1))
	draw_circle(Vector2(0, s * 0.2), s * 0.09, Color(0.7, 0.2, 0.15))
	# 边缘挂两滴绿黏液（和 Goo 同色）
	for dx in [-s * 0.4, s * 0.42]:
		draw_circle(Vector2(dx, s * 0.28), 3.5 + 1.4, OUTLINE)
		draw_circle(Vector2(dx, s * 0.28), 3.5, Color(0.55, 0.6, 0.34))

func label_text() -> String:
	match kind:
		"base":
			return "基地"
		"barracks":
			return "兵营"
		"hive":
			return "巢穴"
		"warehouse":
			return "仓库"
		"smelter":
			return "熔炉"
		"workshop":
			return "木工台"
	return "?"
