class_name WordPopup
extends Control
## 单词弹窗：底部滑出的和纸卡片，显示 日语/假名/罗马音/中文 + 发音/收藏。
## 街道与词汇库共用。

signal closed

var _word := {}
var _is_new := false

var _new_badge: PanelContainer
var _ja_label: Label
var _kana_label: Label
var _romaji_label: Label
var _zh_label: Label
var _fav_btn: Button
var _panel: PanelContainer


func _ready() -> void:
	# 显式铺满父级（CanvasLayer 下即整个视口）
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var blocker := ColorRect.new()
	blocker.color = Color(0.08, 0.08, 0.13, 0.42)
	blocker.anchor_right = 1.0
	blocker.anchor_bottom = 1.0
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(blocker)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.PAPER, 22))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -330
	_panel.offset_right = 330
	_panel.offset_bottom = -26
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN  # 底部锚定，内容向上展开
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# 顶部：NEW 徽标 + 关闭
	var top := HBoxContainer.new()
	_new_badge = PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = UiKit.VERMILION
	badge_style.set_corner_radius_all(12)
	badge_style.content_margin_left = 14
	badge_style.content_margin_right = 14
	badge_style.content_margin_top = 3
	badge_style.content_margin_bottom = 5
	_new_badge.add_theme_stylebox_override("panel", badge_style)
	var badge_label := UiKit.label("NEW WORD", 16, UiKit.WHITE)
	_new_badge.add_child(badge_label)
	top.add_child(_new_badge)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_override("font", UiKit.font())
	close_btn.add_theme_font_size_override("font_size", 30)
	close_btn.add_theme_color_override("font_color", UiKit.INK_SOFT)
	close_btn.flat = true
	close_btn.pressed.connect(close)
	top.add_child(close_btn)
	vbox.add_child(top)

	vbox.add_child(UiKit.vspace(2))
	_ja_label = UiKit.label("", 48, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_ja_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_ja_label)

	_kana_label = UiKit.label("", 25, UiKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_kana_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_kana_label)

	_romaji_label = UiKit.label("", 17, Color("98937f"), HORIZONTAL_ALIGNMENT_CENTER)
	_romaji_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_romaji_label)

	var divider := ColorRect.new()
	divider.color = Color("ddd5c2")
	divider.custom_minimum_size = Vector2(0, 2)
	var dm := MarginContainer.new()
	dm.add_theme_constant_override("margin_top", 8)
	dm.add_theme_constant_override("margin_bottom", 8)
	dm.add_child(divider)
	vbox.add_child(dm)

	_zh_label = UiKit.label("", 30, UiKit.VERMILION, HORIZONTAL_ALIGNMENT_CENTER)
	_zh_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_zh_label)

	vbox.add_child(UiKit.vspace(8))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 14)
	var speak_btn := UiKit.button("♪ 发音", false, 22)
	speak_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speak_btn.pressed.connect(_on_speak)
	btns.add_child(speak_btn)
	_fav_btn = UiKit.button("☆ 收藏", false, 22)
	_fav_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fav_btn.pressed.connect(_on_fav)
	btns.add_child(_fav_btn)
	vbox.add_child(btns)


func show_word(w: Dictionary, is_new: bool) -> void:
	_word = w
	_is_new = is_new
	# 兜底：确保根节点铺满视口（部分父容器下锚点不会自动生效）
	var vp := get_viewport_rect().size
	if size != vp:
		position = Vector2.ZERO
		size = vp
	_ja_label.text = String(w.get("ja", ""))
	_kana_label.text = String(w.get("kana", ""))
	_romaji_label.text = String(w.get("romaji", "")) if bool(Game.settings.get("show_romaji", true)) else ""
	_romaji_label.visible = not _romaji_label.text.is_empty()
	_zh_label.text = String(w.get("zh", ""))
	_new_badge.visible = is_new
	_refresh_fav()
	if not visible:
		visible = true
		_panel.position.y += 90
		_panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_panel, "position:y", _panel.position.y - 90.0, 0.22)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	if is_new and bool(Game.settings.get("auto_speak", true)):
		Tts.speak_word(w)


func close() -> void:
	visible = false
	Tts.stop()
	closed.emit()


func _on_speak() -> void:
	Game.play_sfx("click")
	if not Tts.speak_word(_word):
		Toast.show_once(get_viewport(), "设备没有日语语音包，可在系统设置中安装")


func _on_fav() -> void:
	var fav := Game.toggle_favorite(String(_word.get("id", "")))
	Game.play_sfx("click" if not fav else "discover")
	_refresh_fav()


func _refresh_fav() -> void:
	var fav := Game.is_favorite(String(_word.get("id", "")))
	_fav_btn.text = "★ 已收藏" if fav else "☆ 收藏"
	_fav_btn.add_theme_color_override("font_color", UiKit.GOLD if fav else UiKit.INK)
