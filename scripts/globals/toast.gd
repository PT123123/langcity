class_name Toast
extends RefCounted
## 轻量顶部提示条，自动淡出。

static var _current: Node = null
static var _current_text := ""


static func show_once(host: Node, text: String, duration := 2.4) -> void:
	if _current != null and is_instance_valid(_current):
		if _current_text == text:
			return
		_current.queue_free()
	_current_text = text
	var tree := host.get_tree()
	var layer := CanvasLayer.new()
	layer.layer = 90
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiKit.panel_style(Color(0.13, 0.14, 0.19, 0.93), 14))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = 58
	var l := UiKit.label(text, 19, Color(1, 1, 1, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	anchor.add_child(box)
	layer.add_child(anchor)
	tree.root.add_child(layer)
	# CanvasLayer 没有 modulate，淡入淡出必须作用在内部的 Control 上
	anchor.modulate.a = 0.0
	_current = layer

	var tw := host.create_tween()
	tw.tween_property(anchor, "modulate:a", 1.0, 0.15)
	tw.tween_interval(duration)
	tw.tween_property(anchor, "modulate:a", 0.0, 0.3)
	tw.tween_callback(layer.queue_free)
