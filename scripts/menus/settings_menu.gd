extends Control
## 设置：发音选项、TTS 状态与音量音调、重置进度。

var tts_status: Label


func _ready() -> void:
	theme = UiKit.theme()

	var bg := ColorRect.new()
	bg.color = UiKit.PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 18
	root.offset_bottom = -18
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	var back := UiKit.button("← 返回", false, 20)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top.add_child(back)
	var title := UiKit.label("设置", 34, UiKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.panel_style(UiKit.WHITE, 20))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.custom_minimum_size = Vector2(860, 0)
	inner.add_theme_constant_override("separation", 18)
	scroll.add_child(inner)
	root.add_child(card)

	# ---- 开关 ----
	inner.add_child(_toggle_row("发现新词时自动发音", "auto_speak"))
	inner.add_child(_toggle_row("弹窗中显示罗马音", "show_romaji"))

	# ---- 音量 / 音调 ----
	var vol := _slider_row("发音音量", 0.0, 1.0, 0.05, float(Game.settings.get("volume", 0.8)))
	vol[1].value_changed.connect(func(v: float):
		Game.settings["volume"] = v
		Game.save_soon()
	)
	inner.add_child(vol[0])
	var pitch := _slider_row("发音音调", 0.7, 1.3, 0.05, float(Game.settings.get("pitch", 1.0)))
	pitch[1].value_changed.connect(func(v: float):
		Game.settings["pitch"] = v
		Game.save_soon()
	)
	inner.add_child(pitch[0])

	# ---- 试听 ----
	var test_row := HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 16)
	var test_label := UiKit.label("发音测试", 22, UiKit.INK)
	test_label.custom_minimum_size = Vector2(150, 0)
	test_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	test_row.add_child(test_label)
	var test_btn := UiKit.button("♪ こんにちは、日本の町へようこそ", false, 20)
	test_btn.pressed.connect(func():
		if not Tts.speak("こんにちは、日本の町へようこそ"):
			Toast.show_once(self, "设备没有日语语音包，可在系统设置中安装")
	)
	test_row.add_child(test_btn)
	inner.add_child(test_row)

	# ---- TTS 状态 ----
	tts_status = UiKit.label("", 18, UiKit.INK_SOFT)
	inner.add_child(tts_status)
	_refresh_tts_status()

	# ---- 重置 ----
	var reset_row := HBoxContainer.new()
	reset_row.add_theme_constant_override("separation", 16)
	var reset_label := UiKit.label("学习进度", 22, UiKit.INK)
	reset_label.custom_minimum_size = Vector2(150, 0)
	reset_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reset_row.add_child(reset_label)
	var reset_btn := UiKit.button("重置全部进度", false, 20)
	reset_btn.add_theme_color_override("font_color", UiKit.VERMILION)
	reset_btn.pressed.connect(_confirm_reset)
	reset_row.add_child(reset_btn)
	inner.add_child(reset_row)

	# ---- 关于 ----
	var about := UiKit.label(
		"日语街道 v0.1 — 打开手机，逛日本小镇，看到什么就学什么。\n场景 / 单词 / 进度 / 发音全部离线保存在本机，无需登录。",
		17, Color("a09a88"))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(about)


func _toggle_row(text: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UiKit.label(text, 22, UiKit.INK)
	l.custom_minimum_size = Vector2(300, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var cb := CheckBox.new()
	cb.button_pressed = bool(Game.settings.get(key, true))
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v: bool):
		Game.settings[key] = v
		Game.save_soon()
		Game.play_sfx("click")
	)
	row.add_child(cb)
	return row


func _slider_row(text: String, minv: float, maxv: float, step: float, value: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UiKit.label(text, 22, UiKit.INK)
	l.custom_minimum_size = Vector2(150, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(320, 32)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.focus_mode = Control.FOCUS_NONE
	row.add_child(s)
	var v := UiKit.label("%0.2f" % value, 18, UiKit.INK_SOFT)
	v.custom_minimum_size = Vector2(64, 0)
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.value_changed.connect(func(val: float): v.text = "%0.2f" % val)
	row.add_child(v)
	return [row, s]


func _refresh_tts_status() -> void:
	if OS.has_feature("android") or OS.has_feature("ios"):
		tts_status.text = "✓ 发音使用内置语音包（已随游戏打包，无需联网）"
		tts_status.add_theme_color_override("font_color", UiKit.GREEN_OK)
		return
	if Tts.available:
		tts_status.text = "✓ 已找到日语语音（%s）" % Tts.voice_id
		tts_status.add_theme_color_override("font_color", UiKit.GREEN_OK)
	else:
		tts_status.text = "✗ 未找到日语语音包：请在系统设置里为 TTS 安装日语语音（如 Google 语音的日语），之后重启游戏。"
		tts_status.add_theme_color_override("font_color", UiKit.VERMILION)
		tts_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _confirm_reset() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "确认重置"
	dlg.dialog_text = "将清空已发现单词、收藏和复习记录。\n此操作无法撤销，确定继续吗？"
	dlg.ok_button_text = "重置"
	dlg.cancel_button_text = "取消"
	dlg.confirmed.connect(func():
		Game.reset_progress()
		Tts.stop()
		Toast.show_once(self, "进度已重置")
	)
	add_child(dlg)
	dlg.popup_centered()
