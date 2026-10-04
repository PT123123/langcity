class_name MiniMap
extends Control
## 小地图：俯瞰整个街区，按分类颜色画出所有可学单词的物体，白箭头是玩家。
## 点击放大 / 收起 —— 放大后带分类图例，用来找「家具区到底在哪」这类目标。

## 缩略态尺寸（世界 130x100m，保持比例）
const SMALL_SIZE := Vector2(150, 116)
const MARGIN := 8.0
const LEGEND_H := 64.0

## 独栋地标建筑：全图只有一栋的店铺/设施。普通物体按分类颜色画小圆点，
## 330 个点里根本认不出哪个是家具屋 —— 地标画成带白描边的菱形，展开态标中文名。
const LANDMARKS := {
	"furniture": "家具屋",
	"konbini": "便利店",
	"super": "超市",
	"cafe": "咖啡店",
	"ramen": "拉面店",
	"post_office": "邮局",
	"station": "车站",
}

var world_m := Vector2(130, 100)
var _objects: Array = []      # Interactable 列表
var _player: Player
var expanded := false
var _t := 0.0

var _waypoint := Vector3.ZERO   # 当前追踪任务的航点（世界坐标）
var _has_waypoint := false


## 设置/清除航点（传 null 清除）。street 在 tracking_changed 时调用。
func set_waypoint(pos: Variant) -> void:
	_has_waypoint = pos != null
	if _has_waypoint:
		_waypoint = pos
	queue_redraw()


func setup(world: Vector2, objects: Array, player: Player) -> void:
	world_m = world
	_objects = objects
	_player = player
	custom_minimum_size = SMALL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(e: InputEvent) -> void:
	var tapped := false
	if e is InputEventScreenTouch:
		tapped = e.pressed
	elif e is InputEventMouseButton:
		tapped = e.pressed and e.button_index == MOUSE_BUTTON_LEFT
	if tapped:
		_toggle()
		accept_event()


## 放大 / 收起。只用锚点+偏移切换，不建新节点。
func _toggle() -> void:
	expanded = not expanded
	if expanded:
		var vr := get_viewport().get_visible_rect().size
		var w := minf(vr.x * 0.72, 460.0)
		var h := w * world_m.y / world_m.x + MARGIN * 2.0 + LEGEND_H
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 0.5
		anchor_bottom = 0.5
		offset_left = -w * 0.5
		offset_right = w * 0.5
		offset_top = -h * 0.5
		offset_bottom = h * 0.5
	else:
		anchor_left = 1.0
		anchor_right = 1.0
		anchor_top = 0.0
		anchor_bottom = 0.0
		offset_right = -18.0
		offset_left = -18.0 - SMALL_SIZE.x
		offset_top = 60.0
		offset_bottom = 60.0 + SMALL_SIZE.y
	queue_redraw()


func _process(delta: float) -> void:
	# 玩家在动就低频重画（330 个圆点每帧画没必要，4Hz 足够顺眼）
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		queue_redraw()


func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.16, 0.78)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	var legend_h := LEGEND_H if expanded else 0.0
	var area := Rect2(MARGIN, MARGIN, size.x - MARGIN * 2.0, size.y - MARGIN * 2.0 - legend_h)
	draw_rect(area, Color(0.07, 0.08, 0.11, 0.85), true)
	var sc := minf(area.size.x / world_m.x, area.size.y / world_m.y)
	var used := Vector2(world_m.x, world_m.y) * sc
	var off := area.position + (area.size - used) * 0.5
	draw_rect(Rect2(off, used), Color(1, 1, 1, 0.15), false, 1.0)

	# 物体点：按词库分类颜色；已发现的更亮更大
	var dot_r := 3.0 if expanded else 1.8
	for it in _objects:
		if it.word_id.is_empty() or it.no_draw:
			continue
		var wid: String = it.word_id
		var cat: String = Game.word(wid).get("category", "")
		var c: Color = Game.category_color(cat)
		c.a = 0.95 if Game.is_discovered(wid) else 0.45
		draw_circle(Vector2(it.position.x, it.position.z) * sc + off, dot_r, c)

	# 地标建筑：菱形 + 白描边，压在普通圆点上面；展开态加中文名标注。
	# 标注靠地图右缘时翻到标记左侧画，避免文字出界。
	var font_m := UiKit.font()
	for it in _objects:
		if not LANDMARKS.has(it.kind):
			continue
		var lp := Vector2(it.position.x, it.position.z) * sc + off
		var lcat := "building"
		if not it.word_id.is_empty():
			lcat = str(Game.word(it.word_id).get("category", "building"))
		var lc: Color = Game.category_color(lcat)
		var r := 4.6 if expanded else 3.2
		var diamond := PackedVector2Array([
			lp + Vector2(0, -r), lp + Vector2(r, 0), lp + Vector2(0, r), lp + Vector2(-r, 0)])
		draw_colored_polygon(diamond, Color(lc, 0.95))
		var outline := diamond.duplicate()
		outline.append(diamond[0])
		draw_polyline(outline, Color(1, 1, 1, 0.9), 1.4, true)
		if expanded:
			var label := str(LANDMARKS[it.kind])
			var tw := font_m.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			var tp := lp + Vector2(r + 3.0, 4.0)
			if tp.x + tw > area.end.x - 2.0:
				tp = lp + Vector2(-r - 3.0 - tw, 4.0)
			draw_string(font_m, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))

	# 航点：金色脉动目标点 + 从玩家出发的虚线路线
	if _has_waypoint and _player != null:
		var wp := Vector2(_waypoint.x, _waypoint.z) * sc + off
		var pw := Vector2(_player.position.x, _player.position.z) * sc + off
		_dashed_line(pw, wp, Color(UiKit.GOLD, 0.85), 2.0, 5.0, 4.0)
		var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		draw_circle(wp, dot_r * 1.5 * pulse, Color(UiKit.GOLD, 0.28))
		draw_circle(wp, dot_r * 0.95, Color("ffd977"))

	# 玩家：白色三角箭头，指向面朝方向
	if _player != null:
		var pp := Vector2(_player.position.x, _player.position.z) * sc + off
		var f := _player.facing()
		var dir := Vector2(f.x, f.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.UP
		var tip := pp + dir * dot_r * 3.2
		var side := dir.orthogonal() * dot_r * 1.6
		draw_colored_polygon(PackedVector2Array([tip, pp - side, pp + side]), Color(1, 1, 1, 0.95))

	# 展开态：分类图例（色点 + 中文名，每行 4 个）
	if expanded:
		var cats: Array = Game.categories_in_order()
		var font := UiKit.font()
		var cols := 4
		var cell_w := (size.x - MARGIN * 2.0) / float(cols)
		for i in cats.size():
			var cid: String = cats[i]["id"]
			var col := i % cols
			var row := int(i / float(cols))
			var p := Vector2(MARGIN + col * cell_w + 6.0, size.y - legend_h + 12.0 + row * 15.0)
			draw_circle(p, 4.0, Game.category_color(cid))
			draw_string(font, p + Vector2(9.0, 4.5), str(Game.category_name(cid)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))


## 画虚线（a→b，按 dash/gap 交替），用于玩家到航点的路线
func _dashed_line(a: Vector2, b: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var total := a.distance_to(b)
	if total < 1.0:
		return
	var dir := (b - a) / total
	var step := dash + gap
	var t := 0.0
	while t < total:
		var e := minf(t + dash, total)
		draw_line(a + dir * t, a + dir * e, color, width)
		t += step
