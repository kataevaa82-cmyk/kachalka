extends Control
class_name GymStick
## Left-hand move zone. Stick origin is the first touch (phone FPS).

signal stick_changed(value: Vector2)

@export var radius: float = 64.0
var _touch_id: int = -1
var _knob: Vector2 = Vector2.ZERO
var _value: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_vis()


func _sync_vis() -> void:
	# Touch only: on desktop web a visible zone swallows the click that captures the mouse.
	visible = GameState.is_touch()
	if GameState.in_set:
		visible = false


func _draw() -> void:
	if not visible:
		return
	var c := _knob if _touch_id >= 0 else size * Vector2(0.55, 0.62)
	draw_circle(c, radius, Color(1, 1, 1, 0.07))
	draw_arc(c, radius, 0, TAU, 36, Color(0.15, 0.85, 0.95, 0.5), 2.4, true)
	draw_circle(c + _value * radius, 26.0, Color(0.95, 0.18, 0.55, 0.78))


func _gui_input(event: InputEvent) -> void:
	if GameState.in_set or GameState.paused:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id < 0:
			_touch_id = event.index
			_knob = event.position
			_update(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch_id:
			_release()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_update(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_id = 0
			_knob = event.position
			_update(event.position)
		else:
			_release()


func _update(pos: Vector2) -> void:
	var delta: Vector2 = pos - _knob
	if delta.length() > radius:
		delta = delta.normalized() * radius
	_value = delta / radius
	stick_changed.emit(_value)
	queue_redraw()


func _release() -> void:
	_touch_id = -1
	_value = Vector2.ZERO
	stick_changed.emit(_value)
	queue_redraw()


func set_workout(on: bool) -> void:
	visible = not on and GameState.is_touch()
	if on:
		_release()
