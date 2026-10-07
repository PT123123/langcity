class_name QuestTracker
extends Control
## HUD 任务追踪器：左上角显示当前追踪任务的目标与实时距离；
## 目标在屏幕内 → 画一个金色标记；目标在屏幕外/身后 → 屏幕中央画一个指向它的罗盘箭头。
## 由 street 在 tracking_changed / 每帧刷新。

const PANEL_W := 300.0
const ARROW_R := 96.0
const GOLD := Color("d9a441")

var player: Player

var _panel: PanelContainer
var _title_label: Label
var _obj_label: Label
var _dist_label: Label

var _title := ""
var _objective := ""
var _target := Vector3.ZERO
var _has_target := false
var _pulse := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.19, 0.84)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(GOLD, 0.55)
	sb.set_border_width_all(2)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 9
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = 18.0
	_panel.offset_top = 114.0
	_panel.offset_right = 18.0 + PANEL_W
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_title_label = UiKit.label("", 18, GOLD)
	_title_label.clip_text = true
	vbox.add_child(_title_label)
	_obj_label = UiKit.label("", 17, Color(1, 1, 1, 0.95))
	_obj_label.clip_text = true
	vbox.add_child(_obj_label)
	_dist_label = UiKit.label("", 15, Color(1, 1, 1, 0.62))
	vbox.add_child(_dist_label)

	_panel.visible = false


## 刷新追踪内容。waypoint 为 null（没有追踪任务 / 收集类任务）时不显示航点与箭头。
func set_quest(title: String, objective: String, waypoint: Variant) -> void:
	_title = title
	_objective = objective
	_has_target = waypoint != null
	if _has_target:
		_target = waypoint
	var has_quest := not title.is_empty()
	_panel.visible = has_quest
	if not has_quest:
		return
	_title_label.text = title
	_obj_label.text = objective
	_dist_label.text = ""
	queue_redraw()


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	# CanvasLayer 下锚点偶尔不生效，兜底铺满视口（_draw 依赖 size 定位罗盘箭头）
	var vp := get_viewport_rect().size
	if size != vp:
		size = vp
	_pulse += delta
	if _has_target and player != null and is_instance_valid(player):
		var dist := player.position.distance_to(_target)
		_dist_label.text = "距离 %.0f m" % dist
	queue_redraw()


func _draw() -> void:
	if not _has_target or player == null or not is_instance_valid(player):
		return
	var cam: Camera3D = player.cam
	if cam == null:
		return
	var marker_pos := _target + player.up_axis() * 1.2

	# 目标在屏幕内：画金色菱形标记，不再画边缘箭头
	if not cam.is_position_behind(marker_pos):
		var sp := cam.unproject_position(marker_pos)
		var safe := Rect2(Vector2.ZERO, size).grow(-26.0)
		if safe.has_point(sp):
			var s := 9.0 + 1.5 * sin(_pulse * 4.0)
			draw_colored_polygon(PackedVector2Array([
				sp + Vector2(0, -s), sp + Vector2(s, 0),
				sp + Vector2(0, s), sp + Vector2(-s, 0)]), GOLD)
			draw_arc(sp, s + 8.0 + 2.0 * sin(_pulse * 4.0), 0, TAU, 32, Color(GOLD, 0.7), 2.0)
			return

	# 目标在屏幕外/身后：屏幕中央画指向箭头。
	# 【星球】方向投影到玩家脚下切平面（旧版 to.y = 0 等价于 up 恒为 +Y 的特例）
	var to := _target - player.position
	var up := player.up_axis()
	to -= up * to.dot(up)
	if to.length() < 0.01:
		return
	var d := to.normalized()
	var f := player.cam_forward()
	var r := player.cam_right()
	var dir := Vector2(d.dot(r), -d.dot(f))
	if dir.length() < 0.001:
		dir = Vector2.UP
	dir = dir.normalized()
	var center := size * 0.5
	var p := center + dir * ARROW_R
	var perp := dir.orthogonal()
	draw_circle(p, 26.0, Color(GOLD, 0.14))
	draw_colored_polygon(PackedVector2Array([
		p + dir * 20.0,
		p - dir * 10.0 + perp * 14.0,
		p - dir * 10.0 - perp * 14.0,
	]), Color(GOLD, 0.95))