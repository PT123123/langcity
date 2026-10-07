class_name TeleportMenu
extends Control
## 传送面板：列出星球上的重要地点，点选瞬移（解锁后 stuck 在山沟里也能一键回城）。
## 风格与 QuestPanel 同一套和纸弹窗；只列地图里真实存在的地点 —— kind 找不到
## 对应物件时整行不出现。
##
## 【为什么不做成地图物件】传送点是「系统级便利功能」，不是可拍摄的词条物件；
## 走 HUD 面板而不是摆 portal，省得和建筑/任务物件抢 surface() 落点。

signal picked(kind: String)

## 候选地点（kind → 显示名）。顺序即面板顺序：车站置顶（小镇的正门）。
const SPOTS := [
	{"kind": "station", "label": "车站"},
	{"kind": "konbini", "label": "便利店"},
	{"kind": "ramen", "label": "拉面店"},
	{"kind": "super", "label": "超市"},
	{"kind": "cafe", "label": "咖啡馆"},
	{"kind": "post_office", "label": "邮局"},
	{"kind": "parksign", "label": "公园入口"},
]

var _panel: PanelContainer
var _list: VBoxContainer


func _ready() -> void:
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

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.panel_style(Color(UiKit.PAPER, 0.92), 22))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# 传送是低频操作，面板收窄（宽度在 open() 里按内容居中，与 QuestPanel 同法）
	_panel.custom_minimum_size = Vector2(360, 0)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)
	var title := UiKit.label("去哪儿？", 30, UiKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(title)
	var close_btn := UiKit.button("×", false, 26)
	close_btn.custom_minimum_size = Vector2(56, 48)
	close_btn.pressed.connect(close)
	top.add_child(close_btn)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	root.add_child(_list)


## 填充地点列表。kinds_in_map 是当前地图实际存在的 kind 集合；
## 调用方在打开前刷新（星球/室内物件集合可能变过）。
func open(kinds_in_map: Dictionary) -> void:
	for c in _list.get_children():
		c.queue_free()
	var any := false
	for spot: Dictionary in SPOTS:
		var kind := String(spot["kind"])
		if not kinds_in_map.has(kind):
			continue
		any = true
		var btn := UiKit.button(String(spot["label"]), true, 24)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): picked.emit(kind))
		_list.add_child(btn)
	if not any:
		close()
		return
	visible = true
	# 居中：按内容最小尺寸摆到画面中央（锚点对 PanelContainer 不做自动居中）
	var ms := _panel.get_combined_minimum_size()
	_panel.position = (size - ms) * 0.5


func close() -> void:
	visible = false
