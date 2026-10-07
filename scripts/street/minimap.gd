class_name MiniMap
extends Control
## 小地图：缩略态 = 玩家居中的圆形 GPS 视野（北向固定），管「周围有什么 / 往哪走」；
## 展开态 = 岛冠展开全图（world_px 坐标本体），带分类图例 + 地标中文名，管「便利店在哪」。
##
## 【为什么放弃 41° 倾角星球圆盘】实测三大缺陷：① 只画正面半球（front<0.08）把
## 视野边缘的物件整片裁掉 —— 截图里所有点挤在盘顶、玩家箭头贴边缘；② 星球尺度下
## 画面大半是海/深空，岛冠只占中间一圈，330 个点缩成 1.8px 认不出来；③ 圆心是
## 星球心不是岛心，「往北走」没有稳定的屏幕方向。
## 【为什么矩形展开图不算「球面拉伸」】world_px（5200×4000）就是任务航点/传送/
## 存档用的导航坐标系本体 —— 展开图与这些系统 1:1 对齐，岛面上玩家走的 px 路径
## 也在图上连续。它是岛自己的地图，不是"把球硬压平"；航线在图上画直线即可。
## 室内仍走旧 setup()（矩形图），但室内本来就隐藏小地图，只是兼容保留。

## 缩略态尺寸（GPS 圆盘取正方形）
const SMALL_SIZE := Vector2(148, 148)
const MARGIN := 8.0

## GPS 视野半径（米）。岛冠 N-S 弧长 (52°-10°) × 0.89m/° ≈ 37m、E-W ≈ 90m（r=51 的
## 球面测地实测）：取 34m 覆盖大半个 N-S 走向；出视野的目标走盘缘方向箭头。
const GPS_RADIUS_M := 34.0


## 图例高度按分类数动态算 —— 常量在分类新增后会溢出：16→17 类（加了"购物"）后
## 第 5 行画在了面板外面，所以这里必须跟着 Game 每次现算。
func _legend_h() -> float:
	var rows := ceili(Game.categories_in_order().size() / 4.0)
	return rows * 15.0 + 16.0

## 独栋地标建筑：全图只有一栋的店铺/设施。普通物体按分类颜色画小圆点，
## 地标画成带白描边的菱形，展开态标中文名。
const LANDMARKS := {
	"furniture": "家具屋",
	"konbini": "便利店",
	"super": "超市",
	"cafe": "咖啡店",
	"ramen": "拉面店",
	"post_office": "邮局",
	"station": "车站",
	# 批次 9 公共设施：独栋设施同样当地标，展开态标中文名
	"temple": "寺",
	"school": "学校",
	"hospital": "病院",
	"bank": "銀行",
	"police": "警察署",
	"library": "図書館",
}

var world_m := Vector2(130, 100)
var _objects: Array = []      # Interactable 列表
var _player: Player
var expanded := false
var _t := 0.0

var _waypoint := Vector3.ZERO   # 当前追踪任务的航点（世界坐标）
var _has_waypoint := false

# ---- 星球模式 ----
var _planet: PlanetMath
var _world_px := Vector2.ZERO


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


## 星球模式：只存 planet 数学引用和 px 尺寸（GPS/展开图都从这推坐标）
func setup_planet(math: PlanetMath, world_px: Vector2, objects: Array, player: Player) -> void:
	setup(Vector2(1, 1), objects, player)
	_planet = math
	_world_px = world_px


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
		var w := minf(vr.x * 0.66, 420.0)
		# 图面保持 world 宽高比（星球模式 = 岛冠展开 px 比例；室内 = 米比例）
		var world := _world_px if _planet != null else world_m
		var h := w * world.y / world.x + MARGIN * 2.0 + _legend_h()
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
	# 玩家在动就低频重画（圆点每帧画没必要，4Hz 足够顺眼）
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		queue_redraw()


func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.16, 0.84)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.draw(get_canvas_item(), Rect2(Vector2.ZERO, size))

	if _planet != null:
		if expanded:
			_draw_atlas()
		else:
			_draw_gps()
	else:
		_draw_flat()

	# 展开态：分类图例（色点 + 中文名，每行 4 个）
	if expanded:
		var cats: Array = Game.categories_in_order()
		var font := UiKit.font()
		var cols := 4
		var cell_w := (size.x - MARGIN * 2.0) / float(cols)
		var legend_h := _legend_h()
		for i in cats.size():
			var cid: String = cats[i]["id"]
			var col := i % cols
			var row := int(i / float(cols))
			var p := Vector2(MARGIN + col * cell_w + 6.0, size.y - legend_h + 12.0 + row * 15.0)
			draw_circle(p, 4.0, Game.category_color(cid))
			draw_string(font, p + Vector2(9.0, 4.5), str(Game.category_name(cid)),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.85))


## 缩略态：玩家居中的圆形 GPS 视野。玩家恒在圆心，屏幕上方 = 北
## （world_px 的 y=0 是岛顶/北极侧 —— 与展开全图同向，方向感两态一致）。
## 视野外目标不画，跟踪航点钉在盘缘给方向箭头。
func _draw_gps() -> void:
	var r := minf(size.x, size.y) * 0.5 - MARGIN
	var center := size * 0.5

	# 圆盘底盘：深空描边 + 陆地底色
	draw_circle(center, r + 3.0, Color(0.02, 0.02, 0.05, 0.9))
	draw_circle(center, r, Color(0.13, 0.17, 0.14, 0.95))
	draw_arc(center, r + 3.0, 0, TAU, 64, Color(1, 1, 1, 0.22), 1.2)
	if _player == null:
		return

	# 玩家切平面基：东=屏幕右、北=屏幕上。极点附近 north_at 内部有兜底。
	var pdir := (_player.position - _planet.center).normalized()
	var right := _planet.east_at(pdir)
	var up := _planet.north_at(pdir)
	# px/单位：局部投影 p 约 = 弦长/行星半径；行星标称半径在 _planet.radius（含 scale）
	var px_per_unit := r * _planet.radius / GPS_RADIUS_M

	# 物件点：视野外跳过（越界标的 "找方向" 由盘缘航点箭头负责，圆点堆边缘只会糊）
	var dot_r := 2.4
	for it in _objects:
		if it.word_id.is_empty() or it.no_draw:
			continue
		var d: Vector3 = (it.position - _planet.center).normalized()
		var sp := center + Vector2(d.dot(right), -d.dot(up)) * px_per_unit
		# 点本身有半径，按 r-dot_r 裁才不会压到盘缘描边上
		if sp.distance_squared_to(center) > (r - dot_r) * (r - dot_r):
			continue
		var wid: String = it.word_id
		var cat: String = Game.word(wid).get("category", "")
		var c: Color = Game.category_color(cat)
		c.a = 0.95 if Game.is_discovered(wid) else 0.5
		draw_circle(sp, dot_r, c)

	# 地标：视野内的画菱形 + 中文名（缩略态就标 —— 找地方靠它，不用先点开）
	var font_m := UiKit.font()
	for it in _objects:
		if not LANDMARKS.has(it.kind):
			continue
		var d: Vector3 = (it.position - _planet.center).normalized()
		var p := Vector2(d.dot(right), -d.dot(up))
		var sp := center + p * px_per_unit
		if sp.distance_squared_to(center) > (r - 8.0) * (r - 8.0):
			continue
		var lcat := "building"
		if not it.word_id.is_empty():
			lcat = str(Game.word(it.word_id).get("category", "building"))
		var lc: Color = Game.category_color(lcat)
		var lr := 4.2
		var diamond := PackedVector2Array([
			sp + Vector2(0, -lr), sp + Vector2(lr, 0), sp + Vector2(0, lr), sp + Vector2(-lr, 0)])
		draw_colored_polygon(diamond, Color(lc, 0.95))
		var outline := diamond.duplicate()
		outline.append(diamond[0])
		draw_polyline(outline, Color(1, 1, 1, 0.9), 1.3, true)
		var label := str(LANDMARKS[it.kind])
		var tw := font_m.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var tp := sp + Vector2(lr + 3.0, 3.5)
		if tp.x + tw > size.x - MARGIN:
			tp = sp + Vector2(-lr - 3.0 - tw, 3.5)
		draw_string(font_m, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.92))

	# 航点：视野外 → 盘缘金色方向箭头；视野内 → 金点 + 玩家到航点的虚线
	if _has_waypoint:
		var wd := (_waypoint - _planet.center).normalized()
		var wp2 := Vector2(wd.dot(right), -wd.dot(up))
		var dist_m := wd.angle_to(pdir) * _planet.radius   # 球面大圆弧长（米）
		if dist_m <= GPS_RADIUS_M:
			var spw := center + wp2 * px_per_unit
			_dashed_line(center, spw, Color(UiKit.GOLD, 0.85), 2.0, 4.0, 3.0)
			var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
			draw_circle(spw, dot_r * 1.5 * pulse, Color(UiKit.GOLD, 0.28))
			draw_circle(spw, dot_r * 0.95, Color("ffd977"))
		else:
			var dir2 := wp2.normalized()
			var pos := center + dir2 * (r - 7.0)
			var tip := pos + dir2 * 5.5
			var side := dir2.orthogonal() * 3.6
			draw_colored_polygon(PackedVector2Array([tip, pos - side, pos + side]),
				Color("ffd977"))

	# 玩家：圆心白色三角箭头（面朝方向的切向投影）+ 微环
	var f := _player.facing()
	var hdir := Vector2(f.dot(right), -f.dot(up))
	hdir = hdir.normalized() if hdir.length() > 0.01 else Vector2.UP
	var tip := center + hdir * dot_r * 3.2
	var side := hdir.orthogonal() * dot_r * 1.6
	draw_circle(center, dot_r * 0.9, Color(1, 1, 1, 0.25))
	draw_colored_polygon(PackedVector2Array([tip, center - side, center + side]),
		Color(1, 1, 1, 0.95))

	# 顶部「北」标记：两态同向（图上方 = 岛顶侧），缩略态也保留方向感
	draw_string(font_m, Vector2(center.x - 4.0, MARGIN + 13.0), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.55))


## 展开态：岛冠展开全图。x → 东（经度）、y → 南（离极角距），坐标与任务航点/
## 传送/存档的 world_px 1:1 —— 图上直线就是玩家实际走的导航路径。
func _draw_atlas() -> void:
	var legend_h := _legend_h()
	var area := Rect2(MARGIN, MARGIN, size.x - MARGIN * 2.0, size.y - MARGIN * 2.0 - legend_h)
	# 海底/深空底 + 岛冠陆地底（world_px 全矩形都是可走岛面，见 planet.json lat 范围）
	draw_rect(area, Color(0.07, 0.08, 0.11, 0.92), true)
	var sc := minf(area.size.x / _world_px.x, area.size.y / _world_px.y)
	var used := _world_px * sc
	var off := area.position + (area.size - used) * 0.5
	draw_rect(Rect2(off, used), Color(0.13, 0.17, 0.14, 0.95), true)
	draw_rect(Rect2(off, used), Color(1, 1, 1, 0.2), false, 1.0)

	var dot_r := 2.6
	for it in _objects:
		if it.word_id.is_empty() or it.no_draw:
			continue
		var pp := _planet.px_from_world(it.position, _world_px) * sc + off
		var wid: String = it.word_id
		var cat: String = Game.word(wid).get("category", "")
		var c: Color = Game.category_color(cat)
		c.a = 0.95 if Game.is_discovered(wid) else 0.45
		draw_circle(pp, dot_r, c)

	# 地标建筑：菱形 + 白描边 + 中文名；靠右缘自动翻到左侧画，防文字出界
	var font_m := UiKit.font()
	for it in _objects:
		if not LANDMARKS.has(it.kind):
			continue
		var lp := _planet.px_from_world(it.position, _world_px) * sc + off
		var lcat := "building"
		if not it.word_id.is_empty():
			lcat = str(Game.word(it.word_id).get("category", "building"))
		var lc: Color = Game.category_color(lcat)
		var lr := 4.6
		var diamond := PackedVector2Array([
			lp + Vector2(0, -lr), lp + Vector2(lr, 0), lp + Vector2(0, lr), lp + Vector2(-lr, 0)])
		draw_colored_polygon(diamond, Color(lc, 0.95))
		var outline := diamond.duplicate()
		outline.append(diamond[0])
		draw_polyline(outline, Color(1, 1, 1, 0.9), 1.4, true)
		var label := str(LANDMARKS[it.kind])
		var tw := font_m.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var tp := lp + Vector2(lr + 3.0, 4.0)
		if tp.x + tw > area.end.x - 2.0:
			tp = lp + Vector2(-lr - 3.0 - tw, 4.0)
		draw_string(font_m, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.92))

	# 航点：金色脉动目标点 + px 空间直线虚线路线（px 就是导航坐标，直线=实走航线）
	if _has_waypoint and _player != null:
		var wp := _planet.px_from_world(_waypoint, _world_px) * sc + off
		var pw := _planet.px_from_world(_player.position, _world_px) * sc + off
		_dashed_line(pw, wp, Color(UiKit.GOLD, 0.85), 2.0, 5.0, 4.0)
		var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		draw_circle(wp, dot_r * 1.5 * pulse, Color(UiKit.GOLD, 0.28))
		draw_circle(wp, dot_r * 0.95, Color("ffd977"))

	# 玩家：白色三角箭头（切向东/南投影；图上 y+ = 南）
	if _player != null:
		var pp2 := _planet.px_from_world(_player.position, _world_px) * sc + off
		var pdir := (_player.position - _planet.center).normalized()
		var e := _planet.east_at(pdir)
		var s := -_planet.north_at(pdir)
		var f := _player.facing()
		var dir2 := Vector2(f.dot(e), f.dot(s))
		dir2 = dir2.normalized() if dir2.length() > 0.01 else Vector2.UP
		var tip := pp2 + dir2 * dot_r * 3.2
		var side := dir2.orthogonal() * dot_r * 1.6
		draw_colored_polygon(PackedVector2Array([tip, pp2 - side, pp2 + side]), Color(1, 1, 1, 0.95))


## 旧平面图（室内兼容路径；室内实际隐藏小地图）
func _draw_flat() -> void:
	var legend_h := _legend_h() if expanded else 0.0
	var area := Rect2(MARGIN, MARGIN, size.x - MARGIN * 2.0, size.y - MARGIN * 2.0 - legend_h)
	draw_rect(area, Color(0.07, 0.08, 0.11, 0.85), true)
	var sc := minf(area.size.x / world_m.x, area.size.y / world_m.y)
	var used := Vector2(world_m.x, world_m.y) * sc
	var off := area.position + (area.size - used) * 0.5
	draw_rect(Rect2(off, used), Color(1, 1, 1, 0.15), false, 1.0)

	var dot_r := 3.0 if expanded else 1.8
	for it in _objects:
		if it.word_id.is_empty() or it.no_draw:
			continue
		var wid: String = it.word_id
		var cat: String = Game.word(wid).get("category", "")
		var c: Color = Game.category_color(cat)
		c.a = 0.95 if Game.is_discovered(wid) else 0.45
		draw_circle(Vector2(it.position.x, it.position.z) * sc + off, dot_r, c)

	if _has_waypoint and _player != null:
		var wp := Vector2(_waypoint.x, _waypoint.z) * sc + off
		var pw := Vector2(_player.position.x, _player.position.z) * sc + off
		_dashed_line(pw, wp, Color(UiKit.GOLD, 0.85), 2.0, 5.0, 4.0)
		var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
		draw_circle(wp, dot_r * 1.5 * pulse, Color(UiKit.GOLD, 0.28))
		draw_circle(wp, dot_r * 0.95, Color("ffd977"))

	if _player != null:
		var pp := Vector2(_player.position.x, _player.position.z) * sc + off
		var f := _player.facing()
		var dir := Vector2(f.x, f.z)
		dir = dir.normalized() if dir.length() > 0.01 else Vector2.UP
		var tip := pp + dir * dot_r * 3.2
		var side := dir.orthogonal() * dot_r * 1.6
		draw_colored_polygon(PackedVector2Array([tip, pp - side, pp + side]), Color(1, 1, 1, 0.95))


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
