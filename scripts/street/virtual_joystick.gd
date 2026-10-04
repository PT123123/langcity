class_name VirtualJoystick
extends Control
## 屏幕左侧虚拟摇杆：按下处出现底座，拖动输出归一化方向。

signal moved(vec: Vector2)
signal released

const MAX_R := 76.0

var _touch_idx := -1
var _base := Vector2.ZERO
var _knob := Vector2.ZERO
var idle_center := Vector2(130, 122)   # 之前 (90,90) 光环左缘离屏幕左边只有 14px，太贴角落


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _touch_idx == -1:
			_touch_idx = e.index
			_base = e.position
			_knob = Vector2.ZERO
			moved.emit(Vector2.ZERO)
			queue_redraw()
			accept_event()
		elif not e.pressed and e.index == _touch_idx:
			_reset()
			accept_event()
	elif e is InputEventScreenDrag and e.index == _touch_idx:
		_knob = (e.position - _base).limit_length(MAX_R)
		moved.emit(_knob / MAX_R)
		queue_redraw()
		accept_event()


func _reset() -> void:
	_touch_idx = -1
	_knob = Vector2.ZERO
	moved.emit(Vector2.ZERO)
	released.emit()
	queue_redraw()


func _draw() -> void:
	var center := _base if _touch_idx != -1 else idle_center
	var ring_a := 0.85 if _touch_idx != -1 else 0.3
	draw_circle(center, MAX_R, Color(1, 1, 1, 0.07))
	draw_arc(center, MAX_R, 0, TAU, 48, Color(1, 1, 1, 0.45 * ring_a + 0.1), 3.0)
	var knob := center + _knob
	draw_circle(knob, 34, Color(1, 1, 1, 0.22 + 0.1 * ring_a))
	draw_arc(knob, 34, 0, TAU, 32, Color(1, 1, 1, 0.6 * ring_a + 0.1), 2.5)
	draw_circle(center, 5, Color(1, 1, 1, 0.3))
