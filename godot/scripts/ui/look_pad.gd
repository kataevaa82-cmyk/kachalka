extends Control
## Right-hand look zone for touch / Yandex mobile.

var _id: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_vis()
	resized.connect(_sync_vis)


func _sync_vis() -> void:
	# Touch only: on desktop web this zone would swallow the click that captures the mouse.
	visible = GameState.is_touch()
	if GameState.in_set:
		visible = false


func _gui_input(event: InputEvent) -> void:
	if GameState.paused or GameState.in_set:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or bool(p.get("locked")):
		return
	if event is InputEventScreenTouch:
		if event.pressed and _id < 0:
			_id = event.index
			accept_event()
		elif not event.pressed and event.index == _id:
			_id = -1
			accept_event()
	elif event is InputEventScreenDrag and event.index == _id:
		if p.has_method("look_touch"):
			p.call("look_touch", event.relative)
		accept_event()
