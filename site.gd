extends Node2D
class_name ConstructionSite
## 工地：兵营放下后先变成工地，由英雄工程师施工。进度满 -> main 生成真建筑。
## 有血量——Goo 会啃它，被拆了投入的资源就打水漂。

var kind := "barracks"
var progress := 0.0
var build_time := 8.0
var assigned: Node2D = null    # 认领工地的工程师
var size := 60.0 * Building.SIZE_SCALE    # 和兵营同大，跟着建筑缩放
var hp := 150.0
var max_hp := 150.0

var _fp: Array = []    # 压住的地形格（A* 绕开）

func _ready() -> void:
	add_to_group("sites")
	if Terrain.current != null:
		_fp = Terrain.current.footprint(position, size * 0.5)
		Terrain.current.occupy(_fp, 1)

func _exit_tree() -> void:
	if Terrain.current != null and not _fp.is_empty():
		Terrain.current.occupy(_fp, -1)
		_fp = []

func _process(_delta: float) -> void:
	queue_redraw()

func take_damage(amount: float, _from: Node2D = null) -> void:
	if is_queued_for_deletion():
		return
	hp -= amount
	if hp <= 0.0:
		var mgr := get_tree().get_first_node_in_group("build_mgr")
		if mgr:
			mgr.site_destroyed(self)
		else:
			queue_free()
		return
	queue_redraw()

## 贴图版：脚手架工地 + 目标建筑从地基往上"长"出来
func _art_draw() -> bool:
	if not Art.has("buildings/site"):
		return false
	var foot := Vector2(0, size * 0.42)
	Art.ellipse(self, foot - Vector2(0, 4), size * 0.85, Color(0.05, 0.1, 0.02, 0.3))
	var sh := Art.draw_w(self, "buildings/site", foot, size * 1.85)
	var bkey := "buildings/" + kind
	var top := foot.y - sh
	if Art.has(bkey) and progress > 0.01:
		var t := Art.tex(bkey)
		var d := Art.info(bkey)
		var w := size * 1.85
		var h := w * float(d.h) / float(d.w)
		var frac := clampf(progress, 0.0, 1.0)
		var src := Rect2(0, d.h * (1.0 - frac), d.w, d.h * frac)
		var dst := Rect2(-w * 0.5, foot.y - h * frac, w, h * frac)
		draw_texture_rect_region(t, dst, src, Color(1, 1, 1, 0.92))
		top = minf(top, foot.y - h * frac)
	# 进度条 + 状态字
	var by := top - 10.0
	draw_rect(Rect2(-size * 0.35 - 1, by - 1, size * 0.7 + 2, 6), Art.HP_BG)
	draw_rect(Rect2(-size * 0.35, by, size * 0.7 * progress, 4), Color(0.9, 0.76, 0.4))
	if hp < max_hp:
		Art.hp_bar(self, Vector2(0, by - 8.0), size * 0.7, hp / max_hp, true, 4.0)
	var txt := "等待工程师" if assigned == null else "施工中 %d%%" % int(progress * 100.0)
	Art.text(self, Vector2(0, by - (16.0 if hp < max_hp else 5.0)), txt, 13)
	return true

func _draw() -> void:
	if _art_draw():
		return
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
