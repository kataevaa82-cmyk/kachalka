extends Control
## Soft look-cursor (not a crosshair). Tightens when a station is under gaze.

var hot: bool = false:
	set(v):
		if hot == v:
			return
		hot = v
		queue_redraw()

var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(56, 56)


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fposmod(_pulse + delta * (2.4 if hot else 1.2), TAU)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := Color(0.20, 0.92, 0.78, 0.92) if hot else Color(1.0, 1.0, 1.0, 0.28)
	var glow := Color(col.r, col.g, col.b, 0.22 if hot else 0.08)
	var r := 5.0 if hot else 3.2
	draw_circle(c, r + 7.0, glow)
	draw_circle(c, r, col)
	if not hot:
		return
	var spread := 11.0 + 1.5 * sin(_pulse)
	# Soft brackets — a cursor, not a sight.
	_bracket(c + Vector2(-spread, 0), col, true)
	_bracket(c + Vector2(spread, 0), col, false)


func _bracket(p: Vector2, col: Color, left: bool) -> void:
	var s := -1.0 if left else 1.0
	var h := 7.0
	var w := 5.0
	draw_line(p + Vector2(s * w, -h), p + Vector2(0, -h), col, 1.8, true)
	draw_line(p + Vector2(0, -h), p + Vector2(0, h), col, 1.8, true)
	draw_line(p + Vector2(0, h), p + Vector2(s * w, h), col, 1.8, true)
