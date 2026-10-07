class_name DialogueBox
extends Control
## NPC 对话框（和纸风底部弹窗）：点 NPC 先聊天再办事。
## 数据来自 Dialogues（data/dialogues.json，见该文件的结构注释）：
##   逐条放 lines（日文大字 + 中文小字，自动 TTS 朗读日文），
##   放完显示 choices 按钮跳节点；没 choices 或 next=="END" 就结束。
## action=="quests"：关掉对话并请求打开该 NPC 的任务面板（quests_requested 信号）。
## 说话动画：open_for 传入的 talker 会在对话期间保持 talk 状态（有 talk 动画的话）。

signal finished
signal quests_requested(npc_id: String)

var _npc_id := ""
var _dlg := {}
var _node_id := ""
var _line_idx := 0
var _talker: Node = null

var _panel: PanelContainer
var _name_label: Label
var _ja_label: Label
var _zh_label: Label
var _choices_box: VBoxContainer
var _tap_hint: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 空白处不挡游戏；面板自己 STOP

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.PAPER, 0.94), 18))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	_name_label = UiKit.label("", 20, UiKit.VERMILION)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name_label)
	var replay := UiKit.button("🔊", false, 18)
	replay.focus_mode = Control.FOCUS_NONE
	replay.pressed.connect(_speak_current)
	top.add_child(replay)

	_ja_label = UiKit.label("", 25, UiKit.INK)
	_ja_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ja_label.custom_minimum_size = Vector2(560, 0)
	vb.add_child(_ja_label)
	_zh_label = UiKit.label("", 17, UiKit.INK_SOFT)
	_zh_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_zh_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 8)
	vb.add_child(_choices_box)

	_tap_hint = UiKit.label("▼ 点这里继续", 15, UiKit.INK_SOFT)
	_tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_tap_hint)

	# 点面板任意处推进对话（选项按钮自己消费点击）
	_panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
				or e is InputEventScreenTouch and e.pressed:
			advance())


## 打开 NPC 对话。talker 是能播 talk 动画的节点（ArtNpc），可为 null。
func open_for(npc_id: String, talker: Node = null) -> void:
	_npc_id = npc_id
	_talker = talker
	_dlg = Dialogues.get_dialogue(npc_id)
	if _dlg.is_empty():
		finish()
		return
	if _talker != null and _talker.has_method("talk"):
		_talker.call("talk", true)
	_name_label.text = "%s の会話" % QuestPanel.npc_display_name(npc_id)
	_node_id = String(_dlg.get("start", ""))
	_line_idx = 0   # 上一个对话推进到第几行会影响这里 —— 不复位的话，新对话会从旧进度直接跳过台词
	_layout()
	visible = true
	_show_node()


func close() -> void:
	if visible:
		finish()


## 关闭并恢复 NPC 站立动画。
func finish() -> void:
	visible = false
	if _talker != null and _talker.has_method("talk"):
		_talker.call("talk", false)
	_talker = null
	finished.emit()


## 推进：当前节点还有台词就放下一句，台词放完了等选项（没选项直接结束）。
func advance() -> void:
	if not visible or _dlg.is_empty():
		return
	var node := _current_node()
	var lines: Array = node.get("lines", [])
	if _line_idx < lines.size():
		_line_idx += 1
		_show_node()
		return
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		finish()


func _current_node() -> Dictionary:
	return (_dlg.get("nodes", {}) as Dictionary).get(_node_id, {})


func _show_node() -> void:
	var node := _current_node()
	var lines: Array = node.get("lines", [])
	_clear_choices()
	if _line_idx < lines.size():
		var ln: Dictionary = lines[_line_idx]
		_ja_label.text = String(ln.get("ja", ""))
		_zh_label.text = String(ln.get("zh", ""))
		_tap_hint.visible = true
		_speak_current()
		return
	# 台词放完：显示选项；没选项 = 对话自然结束
	var choices: Array = node.get("choices", [])
	if choices.is_empty():
		finish()
		return
	_ja_label.text = ""
	_zh_label.text = ""
	_tap_hint.visible = false
	for c: Dictionary in choices:
		_choices_box.add_child(_choice_button(c))


func _choice_button(c: Dictionary) -> Button:
	var b := Button.new()
	b.text = String(c.get("text", "")) if String(c.get("zh", "")).is_empty() \
		else "%s　%s" % [String(c.get("text", "")), String(c.get("zh", ""))]
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 19)
	b.pressed.connect(func(): _pick_choice(c))
	return b


func _pick_choice(c: Dictionary) -> void:
	Game.play_sfx("click")
	var action := String(c.get("action", ""))
	var next := String(c.get("next", "END"))
	if next.is_empty() or next == "END":
		var want_quests := action == "quests"
		finish()
		if want_quests:
			quests_requested.emit(_npc_id)
		return
	_node_id = next
	_line_idx = 0
	_show_node()


func _clear_choices() -> void:
	for ch in _choices_box.get_children():
		ch.queue_free()


func _speak_current() -> void:
	if _ja_label.text.is_empty():
		return
	# 打包音频按单词 id 命名，对话整句没有对应文件 → 直接走系统 TTS（桌面端）
	Tts.speak(_ja_label.text)


func _layout() -> void:
	var vr := get_viewport_rect().size
	var w := minf(vr.x * 0.9, 640.0)
	_panel.size = Vector2.ZERO
	var min_size := _panel.get_combined_minimum_size()
	w = maxf(w, min_size.x)
	_panel.size = Vector2(w, min_size.y)
	_panel.position = Vector2((vr.x - w) * 0.5, vr.y - min_size.y - 24.0)


func _process(_delta: float) -> void:
	if visible:
		_layout()
