extends CanvasLayer
## One minigame per station. Touch + keyboard.

@onready var root: Control = $Root
@onready var title: Label = $Root/Title
@onready var hint: Label = $Root/Hint
@onready var reps_label: Label = $Root/Reps
@onready var bar: ColorRect = $Root/Bar
@onready var green: ColorRect = $Root/Bar/Green
@onready var perfect: ColorRect = $Root/Bar/Perfect
@onready var marker: ColorRect = $Root/Bar/Marker
@onready var grade_label: Label = $Root/Grade
@onready var hit_btn: Button = $Root/Hit
@onready var flash: ColorRect = $Root/Flash

var _sid: String = ""
var _mode: String = "timing"
var _phase: float = 0.0
var _reps_done: int = 0
var _reps_total: int = 8
var _period: float = 0.85
var _green: float = 0.18
var _perfect: float = 0.08
var _perfects: int = 0
var _misses: int = 0
var _lock_input: bool = false
var _gloves_used: bool = false

var _host: Control
var _prompt: Label
var _green2: ColorRect
var _simon_pads: Array = []
var _simon_seq: Array = []
var _simon_step: int = 0
var _simon_show: int = -1
var _simon_timer: float = 0.0
var _simon_state: String = "show"
var _alt_expect: int = 0
var _alt_btns: Array = []
var _mash_fill: float = 0.0
var _mash_bar: ColorRect
var _mash_inner: ColorRect
var _lane_x: float = 0.5
var _lane_v: float = 0.0
var _lane_mark: ColorRect
var _hold_needle: ColorRect
var _holding: bool = false
var _step: int = 0
var _step_grade: String = "good"
var _climb_y: float = 0.0
var _climb_i: int = 0
var _climb_track: ColorRect
var _climb_mark: ColorRect
var _climb_rungs: Array = []
var _fill: float = 0.0
var _fill_box: ColorRect
var _fill_inner: ColorRect
var _fill_zone: ColorRect
var _ang: float = 0.0
var _target_board: ColorRect
var _target_slot: ColorRect
var _target_pip: ColorRect
var _pend_board: ColorRect
var _pend_ball: ColorRect
var _pause_t: float = 0.0
var _pause_ready: bool = true
var _rpm: float = 0.35
var _rpm_ok: float = 0.0
var _quit_btn: Button


func _ready() -> void:
	root.visible = false
	hit_btn.focus_mode = Control.FOCUS_NONE
	hit_btn.pressed.connect(_on_hit_btn)
	hit_btn.button_up.connect(_on_hit_up)
	root.gui_input.connect(_on_root_gui)
	if flash:
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim: Control = root.get_node_or_null("Dim")
	if dim:
		dim.mouse_filter = Control.MOUSE_FILTER_PASS
		dim.gui_input.connect(_on_root_gui)
	_build_extra_ui()


func _rect(parent: Control, n: String, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.name = n
	r.position = pos
	r.size = size
	r.color = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _build_extra_ui() -> void:
	_green2 = _rect(bar, "Green2", Vector2.ZERO, Vector2(40, 40), Color(0.2, 0.75, 0.35, 0.85))
	_green2.visible = false
	_host = Control.new()
	_host.name = "PlayHost"
	_host.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_host.offset_left = 0
	_host.offset_right = 0
	_host.offset_top = -420
	_host.offset_bottom = -160
	_host.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_host)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.position = Vector2(0, -8)
	_prompt.size = Vector2(1280, 36)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 26)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host.add_child(_prompt)
	for i in range(4):
		var b := Button.new()
		b.name = "Simon%d" % i
		b.text = ["Q", "W", "E", "R"][i]
		b.position = Vector2(360 + i * 150, 40)
		b.size = Vector2(130, 90)
		b.visible = false
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func() -> void: _simon_press(idx))
		_host.add_child(b)
		_simon_pads.append(b)
	for i in range(2):
		var b := Button.new()
		b.name = "Alt%d" % i
		b.text = tr("ЛЕВАЯ") if i == 0 else tr("ПРАВАЯ")
		b.position = Vector2(340 + i * 300, 50)
		b.size = Vector2(260, 100)
		b.visible = false
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func() -> void: _alt_or_cadence(idx))
		_host.add_child(b)
		_alt_btns.append(b)
	_mash_bar = _rect(_host, "MashBar", Vector2(360, 70), Vector2(560, 48), Color(0.08, 0.09, 0.1, 0.95))
	_mash_bar.visible = false
	_mash_inner = _rect(_mash_bar, "Inner", Vector2.ZERO, Vector2(0, 48), Color(0.95, 0.35, 0.2))
	var track := _rect(_host, "LaneTrack", Vector2(360, 70), Vector2(560, 54), Color(0.08, 0.09, 0.1, 0.95))
	track.visible = false
	_rect(track, "Zone", Vector2(210, 0), Vector2(140, 54), Color(0.15, 0.85, 0.55, 0.45))
	_lane_mark = _rect(track, "Mark", Vector2(271, 0), Vector2(18, 54), Color(1, 1, 1))
	_lane_mark.visible = false
	_hold_needle = _rect(bar, "HoldNeedle", Vector2.ZERO, Vector2(10, 56), Color(1, 1, 1))
	_hold_needle.visible = false
	_climb_track = _rect(_host, "ClimbTrack", Vector2(610, 8), Vector2(60, 230), Color(0.08, 0.09, 0.1, 0.95))
	_climb_track.visible = false
	for i in 4:
		var y := 178.0 - float(i) * 52.0
		_climb_rungs.append(_rect(_climb_track, "Rung%d" % i, Vector2(4, y), Vector2(52, 10), Color(0.55, 0.58, 0.62, 0.9)))
	_climb_mark = _rect(_climb_track, "Mark", Vector2(8, 210), Vector2(44, 14), Color(1, 1, 1))
	_fill_box = _rect(_host, "FillBox", Vector2(616, 8), Vector2(52, 230), Color(0.08, 0.09, 0.1, 0.95))
	_fill_box.visible = false
	_fill_zone = _rect(_fill_box, "Zone", Vector2(0, 40), Vector2(52, 50), Color(0.15, 0.85, 0.55, 0.4))
	_fill_inner = _rect(_fill_box, "Inner", Vector2(6, 230), Vector2(40, 0), Color(0.95, 0.55, 0.2))
	_target_board = _rect(_host, "TargetBoard", Vector2(520, 4), Vector2(240, 230), Color(0.08, 0.09, 0.1, 0.92))
	_target_board.visible = false
	_rect(_target_board, "Ring", Vector2(28, 22), Vector2(184, 184), Color(0.18, 0.2, 0.22, 1))
	_target_slot = _rect(_target_board, "Slot", Vector2(102, 18), Vector2(36, 28), Color(0.15, 0.85, 0.55, 0.85))
	_target_pip = _rect(_target_board, "Pip", Vector2(109, 105), Vector2(22, 22), Color(1, 1, 1))
	_pend_board = _rect(_host, "PendBoard", Vector2(500, 20), Vector2(280, 200), Color(0.08, 0.09, 0.1, 0.0))
	_pend_board.visible = false
	_rect(_pend_board, "Apex", Vector2(126, 8), Vector2(28, 22), Color(0.15, 0.85, 0.55, 0.8))
	_pend_ball = _rect(_pend_board, "Ball", Vector2(128, 20), Vector2(24, 24), Color(1, 0.82, 0.25))
	_quit_btn = Button.new()
	_quit_btn.name = "Quit"
	# FOCUS_NONE or space would double as "rep" and "leave" at the same time.
	_quit_btn.focus_mode = Control.FOCUS_NONE
	_quit_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_quit_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_quit_btn.offset_left = -248.0
	_quit_btn.offset_top = 40.0
	_quit_btn.offset_right = -36.0
	_quit_btn.offset_bottom = 96.0
	_quit_btn.pressed.connect(quit_set)
	root.add_child(_quit_btn)


func start_set(station_id: String) -> void:
	_sid = station_id
	var st: Dictionary = GameState.stations[station_id]
	_mode = str(st.get("minigame", "timing"))
	_reps_total = int(st.get("reps", 8))
	_reps_done = 0
	_perfects = 0
	_misses = 0
	_phase = 0.0
	_period = float(st.get("period", 0.85)) * GameState.level_period_scale()
	var scale := GameState.green_window_scale()
	_green = float(st.get("green", 0.18)) * scale
	_perfect = float(st.get("perfect", 0.08)) * scale
	_gloves_used = false
	_mash_fill = 0.0
	_lane_x = 0.5
	_lane_v = 0.0
	_holding = false
	_alt_expect = 0
	_step = 0
	_step_grade = "good"
	_climb_y = 0.0
	_climb_i = 0
	_fill = 0.0
	_ang = 1.85
	_pause_t = 0.0
	_pause_ready = true
	_rpm = 0.35
	_rpm_ok = 0.0
	title.text = tr(str(st.get("name", station_id))).to_upper()
	var hint_text := str(st.get("hint", "Жми в зелёную."))
	if GameState.is_touch():
		hint_text = str(st.get("hint_touch", hint_text))
	hint_text = tr(hint_text)
	var qh := GameState.quest_hint_for(station_id)
	if qh != "":
		hint_text += "  ·  " + qh
	hint.text = hint_text
	grade_label.text = ""
	root.visible = true
	_lock_input = false
	_refresh_reps()
	_show_mode_ui()
	_layout_touch_play()
	await get_tree().process_frame
	_layout_windows()
	if _mode == "simon":
		_simon_new()


func _show_mode_ui() -> void:
	var two := _mode == "bounce" or _mode == "lockout" or _mode == "cadence"
	bar.visible = _mode == "timing" or _mode == "hold" or _mode == "pause" or _mode == "alternate" or two
	marker.visible = bar.visible and _mode != "hold"
	_green2.visible = two
	hit_btn.visible = _uses_hit()
	hit_btn.text = _hit_caption()
	_quit_btn.text = tr("СЛЕЗТЬ") if GameState.is_touch() else tr("СЛЕЗТЬ  ESC")
	_prompt.text = _prompt_text()
	for b in _simon_pads:
		b.visible = _mode == "simon"
	for i in range(_alt_btns.size()):
		var b: Button = _alt_btns[i]
		b.visible = _mode == "alternate" or _mode == "lane" or _mode == "cadence"
		if _mode == "lane":
			b.text = tr("ВЛЕВО") if i == 0 else tr("ВПРАВО")
		elif _mode == "cadence":
			b.text = tr("НОГИ") if i == 0 else tr("РУКИ")
		else:
			b.text = _alt_label(i)
	for i in range(_simon_pads.size()):
		var pad: Button = _simon_pads[i]
		pad.text = "" if GameState.is_touch() else ["Q", "W", "E", "R"][i]
	if _mode == "alternate":
		_refresh_alt_ui()
	_mash_bar.visible = _mode == "mash"
	var track: Control = _host.get_node_or_null("LaneTrack")
	if track:
		track.visible = _mode == "lane"
	_lane_mark.visible = _mode == "lane"
	_hold_needle.visible = _mode == "hold"
	_climb_track.visible = _mode == "climb"
	_fill_box.visible = _mode == "pump" or _mode == "charge" or _mode == "rpm"
	_target_board.visible = _mode == "target"
	_pend_board.visible = _mode == "pendulum"
	if _mode == "pump":
		_fill_zone.position.y = 48.0
		_fill_zone.size.y = 58.0
	elif _mode == "charge":
		_fill_zone.position.y = 22.0
		_fill_zone.size.y = 42.0
	elif _mode == "rpm":
		_fill_zone.position.y = 72.0
		_fill_zone.size.y = 62.0


func _uses_hit() -> bool:
	return _mode in ["timing", "mash", "hold", "bounce", "lockout", "climb", "target", "pendulum", "pump", "charge", "pause", "rpm", "alternate"]


func _hit_caption() -> String:
	match _mode:
		"hold", "pause":
			return tr("ДЕРЖИ")
		"mash":
			return tr("МОЛОТИ")
		"pump", "charge":
			return tr("ДАВИ")
		"rpm":
			return tr("КРУТИ")
		"lockout":
			return tr("ВНИЗ") if _step == 0 else tr("ВВЕРХ")
		"bounce":
			return tr("ВНИЗ") if _step == 0 else tr("ВВЕРХ")
		"climb":
			return tr("ТЯНИ")
		"pendulum":
			return tr("СВИНГ")
		"target":
			return tr("В ПИК")
		"alternate":
			return tr("ЛЕВАЯ") if _alt_expect == 0 else tr("ПРАВАЯ")
		_:
			return tr("ЖМИ")


func _prompt_text() -> String:
	match _mode:
		"bounce":
			return tr("Присед: вниз, потом вверх")
		"lockout":
			return tr("Брусья: вниз, потом выжим")
		"cadence":
			return tr("Гребля: ноги, потом руки")
		"climb":
			return tr("Турник: жми на каждой перекладине")
		"pump":
			return tr("Дави и отпусти в зелёной зоне")
		"charge":
			return tr("Тяни до щелчка и бросай")
		"rpm":
			return tr("Держи обороты в зелёной")
		"target":
			return tr("Жми, когда точка в зелёном")
		"pendulum":
			return tr("Гиря: жми в верхней точке дуги")
		"pause":
			return tr("Замри в зелёной на миг")
		"alternate":
			var side := tr("ЛЕВАЯ") if _alt_expect == 0 else tr("ПРАВАЯ")
			if GameState.is_touch():
				return tr("Сгибание: сейчас %s. Жми в зелёную.") % side
			return tr("Сгибание: сейчас %s. Жми в зелёную (%s или пробел).") % [side, "A" if _alt_expect == 0 else "D"]
		_:
			return ""


func _layout_touch_play() -> void:
	if not DisplayServer.is_touchscreen_available() and not OS.has_feature("web"):
		return
	hit_btn.offset_left = -210.0
	hit_btn.offset_right = 210.0
	hit_btn.offset_top = -196.0
	hit_btn.offset_bottom = -28.0
	for i in range(_simon_pads.size()):
		var b: Button = _simon_pads[i]
		b.size = Vector2(148, 108)
		b.position = Vector2(28 + i * 158, 8)
	for i in range(_alt_btns.size()):
		var b: Button = _alt_btns[i]
		b.size = Vector2(300, 124)
		b.position = Vector2(40 + i * 340, 36)
	_quit_btn.offset_left = -236.0
	_quit_btn.offset_top = 28.0
	_quit_btn.offset_right = -24.0
	_quit_btn.offset_bottom = 108.0


func _process(delta: float) -> void:
	if not root.visible or _lock_input:
		return
	match _mode:
		"timing":
			_tick_timing(delta)
		"simon":
			_tick_simon(delta)
		"alternate":
			_tick_alternate(delta)
		"mash":
			_tick_mash(delta)
		"hold":
			_tick_hold(delta)
		"lane":
			_tick_lane(delta)
		"bounce", "lockout":
			_tick_two_bar(delta)
		"cadence":
			_tick_cadence(delta)
		"climb":
			_tick_climb(delta)
		"pump", "charge":
			_tick_fill(delta)
		"target":
			_tick_target(delta)
		"pendulum":
			_tick_pendulum(delta)
		"pause":
			_tick_pause(delta)
		"rpm":
			_tick_rpm(delta)


func _tick_timing(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var w := bar.size.x
	marker.position.x = _phase * (w - marker.size.x)
	if Input.is_action_just_pressed("rep"):
		_try_hit()


func _tick_two_bar(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var w := bar.size.x
	marker.position.x = _phase * (w - marker.size.x)
	hit_btn.text = _hit_caption()
	_prompt.text = _prompt_text()
	if Input.is_action_just_pressed("rep"):
		_try_two_step(-1)


func _tick_cadence(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var w := bar.size.x
	marker.position.x = _phase * (w - marker.size.x)
	if Input.is_action_just_pressed("move_left"):
		_try_two_step(0)
	elif Input.is_action_just_pressed("move_right"):
		_try_two_step(1)


func _tick_simon(delta: float) -> void:
	if _simon_state != "show":
		return
	_simon_timer -= delta
	if _simon_timer > 0.0:
		return
	_simon_show += 1
	if _simon_show >= _simon_seq.size():
		_simon_state = "input"
		_simon_step = 0
		_flash_pads(-1)
		return
	_flash_pads(_simon_seq[_simon_show])
	_simon_timer = 0.42


func _tick_alternate(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var w := bar.size.x
	marker.position.x = _phase * (w - marker.size.x)
	if Input.is_action_just_pressed("rep"):
		_try_alt(-1)
	elif Input.is_action_just_pressed("move_left"):
		_try_alt(0)
	elif Input.is_action_just_pressed("move_right"):
		_try_alt(1)


func _tick_mash(delta: float) -> void:
	_phase += delta
	_mash_fill = move_toward(_mash_fill, 0.0, delta * 0.22)
	_mash_inner.size.x = _mash_fill * _mash_bar.size.x
	_mash_inner.color = Color(0.2 + 0.75 * _mash_fill, 0.85 * _mash_fill, 0.2)
	if Input.is_action_just_pressed("rep"):
		_mash_fill = minf(1.0, _mash_fill + 0.12)
	if _phase >= _period:
		_phase = 0.0
		var grade := "miss"
		if _mash_fill >= 0.88:
			grade = "perfect"
		elif _mash_fill >= 0.55:
			grade = "good"
		_score(grade)
		_mash_fill = 0.0


func _tick_hold(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var w := bar.size.x
	_hold_needle.position = Vector2(_phase * (w - 10.0), -8.0)
	_holding = Input.is_action_pressed("rep") or hit_btn.is_pressed()
	if Input.is_action_just_released("rep"):
		_score_hold()


func _tick_lane(delta: float) -> void:
	var steer := 0.0
	if Input.is_action_pressed("move_left"):
		steer -= 1.0
	if Input.is_action_pressed("move_right"):
		steer += 1.0
	if _alt_btns.size() >= 2:
		if _alt_btns[0].is_pressed():
			steer -= 1.0
		if _alt_btns[1].is_pressed():
			steer += 1.0
	_lane_v += (steer * 2.4 - _lane_v) * delta * 8.0
	_lane_v += sin(_phase * 7.0) * 0.35 * delta
	_lane_x = clampf(_lane_x + _lane_v * delta, 0.06, 0.94)
	_phase += delta
	_lane_mark.position = Vector2(_lane_x * 560.0 - 9.0, 0.0)
	if _phase >= _period:
		_phase = 0.0
		var dist := absf(_lane_x - 0.5)
		var grade := "miss"
		if dist < 0.09:
			grade = "perfect"
		elif dist < 0.20:
			grade = "good"
		_score(grade)


func _tick_climb(delta: float) -> void:
	_climb_y += delta / maxf(_period * 1.35, 0.4)
	var rungs := [0.22, 0.44, 0.66, 0.88]
	if _climb_i < rungs.size() and _climb_y > rungs[_climb_i] + 0.10:
		_score("miss")
		_climb_y = 0.0
		_climb_i = 0
	if _climb_y >= 1.0:
		_climb_y = 0.0
		_climb_i = 0
	_climb_mark.position.y = 216.0 - _climb_y * 210.0
	if Input.is_action_just_pressed("rep"):
		_try_climb()


func _tick_fill(delta: float) -> void:
	_holding = Input.is_action_pressed("rep") or hit_btn.is_pressed()
	var rate := 1.15 if _mode == "charge" else 0.85
	if _holding:
		_fill = minf(1.05, _fill + delta * rate)
	if _fill >= 1.02:
		_score("miss")
		_fill = 0.0
	_draw_fill()
	if Input.is_action_just_released("rep"):
		_score_fill()


func _tick_target(delta: float) -> void:
	_ang += delta * (TAU / maxf(_period, 0.35))
	var c := Vector2(120, 114)
	var p: Vector2 = c + Vector2(sin(_ang), -cos(_ang)) * 86.0
	_target_pip.position = p - Vector2(11, 11)
	if Input.is_action_just_pressed("rep"):
		_try_target()


func _tick_pendulum(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var swing := sin(_phase * TAU)
	var theta := swing * 1.05
	var c := Vector2(140, 24)
	var p: Vector2 = c + Vector2(sin(theta), cos(theta)) * 150.0
	_pend_ball.position = p - Vector2(12, 12)
	if Input.is_action_just_pressed("rep"):
		_try_pendulum()


func _tick_pause(delta: float) -> void:
	_phase = fposmod(_phase + delta / _period, 1.0)
	var w := bar.size.x
	marker.position.x = _phase * (w - marker.size.x)
	var in_g := absf(_phase - 0.5) <= _green * 0.5
	_holding = Input.is_action_pressed("rep") or hit_btn.is_pressed()
	if not in_g:
		_pause_t = 0.0
		if not _holding:
			_pause_ready = true
		return
	if not _pause_ready or not _holding:
		return
	_pause_t += delta
	if _pause_t >= _pause_need():
		var g := "perfect" if absf(_phase - 0.5) <= _perfect * 0.5 else "good"
		_score(g)
		_pause_t = 0.0
		_pause_ready = false


## Leaving the green zone resets the freeze, so the hold has to fit inside it.
## A fixed hold could not: the window is only _green * _period seconds wide, and
## fatigue and the level's period scale shrink it further. Staying under half the
## window keeps the rep winnable at every difficulty and still leaves the second
## half as the margin for starting the freeze late.
func _pause_need() -> float:
	return minf(_green * _period * 0.45, 0.3)


func _tick_rpm(delta: float) -> void:
	if Input.is_action_just_pressed("rep"):
		_rpm = minf(1.0, _rpm + 0.11)
	_rpm = move_toward(_rpm, 0.0, delta * 0.38)
	_fill = _rpm
	_draw_fill()
	var in_band := _rpm >= 0.42 and _rpm <= 0.74
	if in_band:
		_rpm_ok += delta
	_phase += delta
	if _phase >= _period:
		var ratio := _rpm_ok / maxf(_period, 0.01)
		var grade := "miss"
		if ratio >= 0.72:
			grade = "perfect"
		elif ratio >= 0.38:
			grade = "good"
		_score(grade)
		_phase = 0.0
		_rpm_ok = 0.0


func _draw_fill() -> void:
	var h := clampf(_fill, 0.0, 1.0) * 220.0
	_fill_inner.size = Vector2(40, h)
	_fill_inner.position = Vector2(6, 226.0 - h)
	if _fill > 0.92:
		_fill_inner.color = Color(0.95, 0.25, 0.2)
	elif _fill > 0.55:
		_fill_inner.color = Color(0.25, 0.85, 0.45)
	else:
		_fill_inner.color = Color(0.95, 0.7, 0.2)


func _layout_windows() -> void:
	var w: float = maxf(bar.size.x, 1.0)
	var gw: float = _green * w
	var pw: float = _perfect * w
	if _mode == "bounce" or _mode == "lockout" or _mode == "cadence":
		var a := 0.28 if _mode != "lockout" else 0.22
		var b := 0.72 if _mode != "lockout" else 0.78
		green.size = Vector2(gw, bar.size.y)
		green.position = Vector2(a * w - gw * 0.5, 0)
		_green2.size = Vector2(gw, bar.size.y)
		_green2.position = Vector2(b * w - gw * 0.5, 0)
		_green2.visible = true
		perfect.size = Vector2(pw, bar.size.y)
		perfect.position = Vector2(a * w - pw * 0.5, 0)
	else:
		_green2.visible = false
		green.size = Vector2(gw, bar.size.y)
		green.position = Vector2((w - gw) * 0.5, 0)
		perfect.size = Vector2(pw, bar.size.y)
		perfect.position = Vector2((w - pw) * 0.5, 0)


func _on_hit_btn() -> void:
	match _mode:
		"timing":
			_try_hit()
		"mash":
			_mash_fill = minf(1.0, _mash_fill + 0.12)
		"bounce", "lockout":
			_try_two_step(-1)
		"climb":
			_try_climb()
		"target":
			_try_target()
		"pendulum":
			_try_pendulum()
		"rpm":
			_rpm = minf(1.0, _rpm + 0.11)
		"alternate":
			_try_alt(-1)


func _on_hit_up() -> void:
	if _mode == "hold":
		_score_hold()
	elif _mode == "pump" or _mode == "charge":
		_score_fill()


func _score_hold() -> void:
	if _mode != "hold" or _lock_input:
		return
	var dist := absf(_phase - 0.5)
	var grade := "miss"
	if dist <= _perfect * 0.5:
		grade = "perfect"
	elif dist <= _green * 0.5:
		grade = "good"
	_score(grade)


func _score_fill() -> void:
	if _lock_input or _fill <= 0.02:
		return
	var lo := 0.62
	var hi := 0.90
	var plo := 0.72
	var phi := 0.84
	if _mode == "charge":
		lo = 0.76
		hi = 0.96
		plo = 0.84
		phi = 0.93
	var grade := "miss"
	if _fill >= plo and _fill <= phi:
		grade = "perfect"
	elif _fill >= lo and _fill <= hi:
		grade = "good"
	_score(grade)
	_fill = 0.0
	_draw_fill()


func _on_root_gui(event: InputEvent) -> void:
	if _lock_input:
		return
	if not (event is InputEventScreenTouch and event.pressed):
		return
	if not _uses_hit():
		return
	if _mode == "pump" or _mode == "charge" or _mode == "hold" or _mode == "pause":
		return
	_on_hit_btn()
	get_viewport().set_input_as_handled()


func _try_hit() -> void:
	if not root.visible or _lock_input or _mode != "timing":
		return
	var dist := absf(_phase - 0.5)
	var grade := "miss"
	if dist <= _perfect * 0.5:
		grade = "perfect"
	elif dist <= _green * 0.5:
		grade = "good"
	_score(grade)


func _try_two_step(side: int) -> void:
	if _lock_input:
		return
	if _mode == "cadence" and side != _step:
		_score("miss")
		_step = 0
		return
	var a := 0.28 if _mode != "lockout" else 0.22
	var b := 0.72 if _mode != "lockout" else 0.78
	var target := a if _step == 0 else b
	var dist := absf(_phase - target)
	var grade := "miss"
	if dist <= _perfect * 0.55:
		grade = "perfect"
	elif dist <= _green * 0.55:
		grade = "good"
	if grade == "miss":
		_score("miss")
		_step = 0
		hit_btn.text = _hit_caption()
		return
	if _step == 0:
		_step_grade = grade
		_step = 1
		hit_btn.text = _hit_caption()
		grade_label.text = tr("ЕЩЁ")
		grade_label.modulate = Color(0.9, 0.9, 0.5)
		return
	var final := "perfect" if _step_grade == "perfect" and grade == "perfect" else "good"
	_step = 0
	hit_btn.text = _hit_caption()
	_score(final)


func _try_climb() -> void:
	if _lock_input or _mode != "climb":
		return
	var rungs := [0.22, 0.44, 0.66, 0.88]
	if _climb_i >= rungs.size():
		_climb_i = 0
		_climb_y = 0.0
		return
	var dist := absf(_climb_y - rungs[_climb_i])
	var grade := "miss"
	if dist <= 0.055:
		grade = "perfect"
	elif dist <= 0.10:
		grade = "good"
	if grade == "miss":
		_score("miss")
		_climb_y = 0.0
		_climb_i = 0
		return
	_climb_i += 1
	_score(grade)
	if _climb_i >= rungs.size():
		_climb_i = 0
		_climb_y = 0.0


func _try_target() -> void:
	if _lock_input or _mode != "target":
		return
	var wrapped := fposmod(_ang + PI, TAU) - PI
	var dist := absf(wrapped)
	var grade := "miss"
	if dist <= 0.22:
		grade = "perfect"
	elif dist <= 0.48:
		grade = "good"
	_score(grade)


func _try_pendulum() -> void:
	if _lock_input or _mode != "pendulum":
		return
	# Apex when sin(phase*TAU) is near +1, i.e. phase ~ 0.25
	var dist := absf(_phase - 0.25)
	if dist > 0.5:
		dist = 1.0 - dist
	# also accept the other apex (0.75) as a late swing
	var dist2 := absf(_phase - 0.75)
	if dist2 > 0.5:
		dist2 = 1.0 - dist2
	dist = minf(dist, dist2)
	var grade := "miss"
	if dist <= _perfect * 0.7:
		grade = "perfect"
	elif dist <= _green * 0.7:
		grade = "good"
	_score(grade)


func _alt_or_cadence(side: int) -> void:
	if _mode == "cadence":
		_try_two_step(side)
	elif _mode == "alternate":
		_alt_press(side)


func _refresh_alt_ui() -> void:
	if _alt_btns.size() < 2:
		return
	for i in range(_alt_btns.size()):
		var b: Button = _alt_btns[i]
		var on := i == _alt_expect
		b.modulate = Color(1.15, 1.05, 0.35) if on else Color(0.42, 0.44, 0.48)
		b.text = ("► " + _alt_label(i)) if on else (tr("левая") if i == 0 else tr("правая"))
	_prompt.text = _prompt_text()
	hit_btn.text = _hit_caption()


## Key letters only on keyboard devices.
func _alt_label(i: int) -> String:
	var t := tr("ЛЕВАЯ") if i == 0 else tr("ПРАВАЯ")
	if GameState.is_touch():
		return t
	return t + ("  A" if i == 0 else "  D")


func _try_alt(side: int) -> void:
	if _mode != "alternate" or _lock_input:
		return
	if side >= 0 and side != _alt_expect:
		var grade := "miss"
		if _sid == "dumbbell" and GameState.has_gear("gloves") and not _gloves_used:
			_gloves_used = true
			grade = "good"
		else:
			_score("miss")
			return
		_alt_expect = 1 - _alt_expect
		_refresh_alt_ui()
		_score(grade)
		return
	var dist := absf(_phase - 0.5)
	var grade := "miss"
	if dist <= _perfect * 0.5:
		grade = "perfect"
	elif dist <= _green * 0.5:
		grade = "good"
	else:
		if _sid == "dumbbell" and GameState.has_gear("gloves") and not _gloves_used:
			_gloves_used = true
			grade = "good"
	if grade != "miss":
		_alt_expect = 1 - _alt_expect
		_refresh_alt_ui()
	_score(grade)


func _alt_press(side: int) -> void:
	_try_alt(side)


func _simon_press(idx: int) -> void:
	if _mode != "simon" or _simon_state != "input" or _lock_input:
		return
	_flash_pads(idx)
	if idx != int(_simon_seq[_simon_step]):
		_score("miss")
		_simon_new()
		return
	_simon_step += 1
	if _simon_step >= _simon_seq.size():
		var grade := "perfect" if _simon_seq.size() >= 4 else "good"
		_score(grade)
		_simon_new()


func _simon_new() -> void:
	_simon_seq.clear()
	var n := mini(3 + int(_reps_done / 2), 5)
	for i in n:
		_simon_seq.append(randi() % 4)
	_simon_show = -1
	_simon_step = 0
	_simon_state = "show"
	_simon_timer = 0.35
	_flash_pads(-1)


func _flash_pads(lit: int) -> void:
	var cols := [
		Color(0.95, 0.25, 0.3),
		Color(0.25, 0.85, 0.4),
		Color(0.25, 0.55, 1.0),
		Color(0.95, 0.8, 0.2),
	]
	for i in range(_simon_pads.size()):
		var b: Button = _simon_pads[i]
		b.modulate = cols[i] * (1.4 if i == lit else 0.55)


func _score(grade: String) -> void:
	if _lock_input:
		return
	grade = _grade_after_gear(grade)
	if grade == "perfect":
		_perfects += 1
	elif grade == "miss":
		_misses += 1
	var res: Dictionary = GameState.apply_rep(_sid, grade)
	Audio.play_rep(grade, GameState.combo)
	if grade != "miss":
		# A rep also makes a noise in the room: iron, a light machine, or footfalls.
		Audio.play(_rep_sfx(), randf_range(0.93, 1.08), -5.0)
	match grade:
		"perfect":
			grade_label.text = tr("ИДЕАЛЬНО  +%d₽") % int(res.get("cash", 0))
			grade_label.modulate = Color(0.3, 1.0, 0.85)
			_flash_hit(Color(0.35, 1.0, 0.9, 0.28))
		"good":
			grade_label.text = tr("ЕСТЬ")
			grade_label.modulate = Color(0.9, 0.9, 0.4)
			_flash_hit(Color(1.0, 0.95, 0.4, 0.16))
		_:
			grade_label.text = tr("МИМО")
			grade_label.modulate = Color(1.0, 0.35, 0.4)
			_flash_hit(Color(1.0, 0.2, 0.2, 0.22))
	var world := get_parent()
	if world.has_method("on_rep_hit"):
		world.on_rep_hit(grade)
	_reps_done += 1
	_refresh_reps()
	if _misses >= 3:
		GameState.note_set(_sid, _perfects, _misses, _reps_done, false)
		_close(tr("Сет сорван. Три мимо."), false)
		return
	if _reps_done >= _reps_total:
		GameState.note_set(_sid, _perfects, _misses, _reps_done, true)
		_close(tr("Сет закрыт. Идеальных: %d") % _perfects, true)


func _grade_after_gear(grade: String) -> String:
	if grade == "miss" and _sid == "dumbbell" and GameState.has_gear("gloves") and not _gloves_used:
		_gloves_used = true
		return "good"
	return grade


func _flash_hit(col: Color) -> void:
	if flash == null:
		return
	flash.color = col
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.18)


func _refresh_reps() -> void:
	reps_label.text = tr("ПОВТОР  %d / %d") % [_reps_done, _reps_total]


## Abandoning a set keeps the reps already banked but not the completion bonus,
## and the energy spent mounting is gone. Leaving is a way out, not a free reset.
func quit_set() -> void:
	if not root.visible or _lock_input:
		return
	GameState.note_set(_sid, _perfects, _misses, _reps_done, false)
	_close(tr("Слез с тренажёра."), false, "back")


func _unhandled_input(event: InputEvent) -> void:
	if not root.visible or _lock_input:
		return
	# Esc does nothing in gym_world while a set runs, so it is free to mean
	# "get me off this thing". Swallowing it keeps the pause menu from opening
	# on top of the dismount.
	if event.is_action_pressed("pause_game") and not YandexSDK.is_ad_active():
		quit_set()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _mode != "simon":
		return
	var k: int = event.keycode
	if k == KEY_Q or k == KEY_1:
		_simon_press(0)
	elif k == KEY_W or k == KEY_2:
		_simon_press(1)
	elif k == KEY_E or k == KEY_3:
		_simon_press(2)
	elif k == KEY_R or k == KEY_4:
		_simon_press(3)


## Heavy iron, light machine or treadmill — the rep should sound like the station.
func _rep_sfx() -> String:
	match _sid:
		"bench", "squat", "legpress", "deadlift":
			return "plate"
		"treadmill", "rower", "bike":
			return "step"
		_:
			return "clank"


func _close(msg: String, success: bool, sfx: String = "") -> void:
	Audio.play(sfx if sfx != "" else ("setdone" if success else "setfail"))
	_lock_input = true
	hint.text = msg
	# Respect pause: a platform pause right after the last rep must not end the set behind the menu.
	await get_tree().create_timer(0.85, false).timeout
	root.visible = false
	_lock_input = false
	var world := get_parent()
	if world.has_method("end_set"):
		world.end_set()
