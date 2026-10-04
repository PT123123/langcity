class_name QuestPanel
extends Control
## 任务面板（和纸风全屏弹窗）：顶部等级 + XP 条，下面是任务卡片列表。
## 卡片可「接取 / 追踪」，跑腿任务接取后 HUD 立即出现路线指引。

signal closed

var _root_panel: PanelContainer
var _list: VBoxContainer
var _level_label: Label
var _xp_bar: ProgressBar
var _xp_text: Label


func _ready() -> void:
	# 显式铺满父级（CanvasLayer 下锚点偶尔不生效，不用 set_anchors_preset）
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var blocker := ColorRect.new()
	blocker.color = Color(0.08, 0.08, 0.13, 0.5)
	blocker.anchor_right = 1.0
	blocker.anchor_bottom = 1.0
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close()
		elif e is InputEventScreenTouch and e.pressed:
			close())
	add_child(blocker)

	_root_panel = PanelContainer.new()
	_root_panel.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PAPER, 22))
	_root_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_root_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# ---- 顶栏：标题 + 关闭 ----
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	var title := UiKit.label("任务", 34, UiKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	var close_btn := UiKit.button("×", false, 26)
	close_btn.custom_minimum_size = Vector2(56, 48)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)

	# ---- 等级 + XP 条 ----
	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 12)
	root.add_child(lv_row)
	_level_label = UiKit.label("", 24, UiKit.VERMILION)
	lv_row.add_child(_level_label)
	_xp_bar = _make_bar(UiKit.VERMILION)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.custom_minimum_size = Vector2(0, 12)
	lv_row.add_child(_xp_bar)
	_xp_text = UiKit.label("", 17, UiKit.INK_SOFT)
	lv_row.add_child(_xp_text)

	# ---- 任务列表（滚动）----
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)

	Quests.tracking_changed.connect(_refresh_if_open)
	Quests.quest_completed.connect(_on_completed)
	Game.xp_changed.connect(func(_t, _l): _refresh_if_open())


func open() -> void:
	_layout()
	visible = true
	_refresh()
	_root_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root_panel, "modulate:a", 1.0, 0.15)


func close() -> void:
	visible = false
	Game.play_sfx("click")
	closed.emit()


func _layout() -> void:
	var vr := get_viewport_rect().size
	var w := minf(vr.x * 0.86, 760.0)
	var h := minf(vr.y * 0.86, 620.0)
	# CanvasLayer 下锚点偶尔不生效：不靠中心锚点，直接显式定位 + 定尺寸居中
	var min_size := _root_panel.get_combined_minimum_size()
	w = maxf(w, min_size.x)
	h = maxf(h, min_size.y)
	_root_panel.size = Vector2(w, h)
	_root_panel.position = ((vr - Vector2(w, h)) * 0.5).floor()


func _process(_delta: float) -> void:
	if not visible:
		return
	# CanvasLayer 下锚点偶尔不生效，兜底铺满视口（遮罩盖全屏 + 点空白可关）
	var vp := get_viewport_rect().size
	if size != vp:
		size = vp


func _refresh_if_open() -> void:
	if visible:
		_refresh()


func _on_completed(id: String) -> void:
	var q := Quests.quest(id)
	Toast.show_once(self, "任务完成：%s  +%d XP" % [
		String(q.get("title_zh", q.get("title", ""))), int(q.get("xp", 0))], 3.0)


func _refresh() -> void:
	var lv := Game.player_level()
	var prog: Array = Game.level_progress()
	_level_label.text = "Lv.%d" % lv
	_xp_bar.max_value = float(prog[1])
	_xp_bar.value = float(prog[0])
	_xp_text.text = "%d / %d XP" % [prog[0], prog[1]]

	for c in _list.get_children():
		c.queue_free()
	for q: Dictionary in Quests.catalog():
		_list.add_child(_make_card(q))


func _make_card(q: Dictionary) -> Control:
	var id := String(q.get("id", ""))
	var done := Quests.is_done(id)
	var active := Quests.is_active(id)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiKit.WHITE if not done else Color("eee9db")
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = UiKit.GOLD if active else Color("c9c2b0")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", style)

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	card.add_child(outer)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	outer.add_child(vbox)

	# 标题行：日文名 + 中文名 + 状态
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	vbox.add_child(title_row)
	var t := UiKit.label(String(q.get("title", "")), 24, UiKit.INK)
	title_row.add_child(t)
	var tzh := UiKit.label(String(q.get("title_zh", "")), 16, UiKit.INK_SOFT)
	tzh.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	title_row.add_child(tzh)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	var chip := _status_chip(done, active)
	title_row.add_child(chip)

	vbox.add_child(UiKit.label(String(q.get("desc", "")), 18, UiKit.INK_SOFT))

	# 进度条 + 进度文字
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 10)
	vbox.add_child(prog_row)
	var color := UiKit.GREEN_OK if done else (UiKit.GOLD if active else Color("b3ad9c"))
	var bar := _make_bar(color)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(0, 10)
	bar.value = _ratio(q)
	prog_row.add_child(bar)
	prog_row.add_child(UiKit.label(Quests.status_text(q), 15, UiKit.INK_SOFT))

	# 动作按钮
	var action := _action_button(q, done, active)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	outer.add_child(action)
	return card


func _ratio(q: Dictionary) -> float:
	var id := String(q.get("id", ""))
	match String(q.get("type", "")):
		"collect":
			var need := maxi(1, int(q.get("count", 1)))
			return float(Quests.collect_progress(q)) / float(need)
		"errand":
			var steps: Array = q.get("steps", [])
			if steps.is_empty():
				return 0.0
			return float(Quests.errand_step(q)) / float(steps.size())
	return 0.0


func _status_chip(done: bool, active: bool) -> Control:
	var text := "已完成" if done else ("进行中" if active else "可接取")
	var color := UiKit.GREEN_OK if done else (UiKit.GOLD if active else Color("9a9284"))
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(UiKit.label(text, 15, UiKit.WHITE))
	return chip


func _action_button(q: Dictionary, done: bool, active: bool) -> Button:
	var id := String(q.get("id", ""))
	var tracked := Quests.tracked_id() == id
	var btn: Button
	if done:
		btn = UiKit.button("＋%d XP" % int(q.get("xp", 0)), false, 18)
		btn.disabled = true
		return btn
	if not active:
		btn = UiKit.button("接取", true, 20)
		btn.custom_minimum_size = Vector2(96, 46)
		btn.pressed.connect(func():
			if Quests.accept(id):
				Game.play_sfx("open")
				_refresh())
		return btn
	if tracked:
		btn = UiKit.button("追踪中", false, 18)
		btn.disabled = true
		return btn
	btn = UiKit.button("追踪", false, 20)
	btn.custom_minimum_size = Vector2(96, 46)
	btn.pressed.connect(func():
		Quests.track(id)
		Game.play_sfx("click")
		_refresh())
	return btn


func _make_bar(color: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("d8d1bf")
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	return pb