extends Node
## Marketing capture only. Runs in an isolated copy; never loads the player's save.
var gym: Node3D
var frame := 0
var shot := -1
var last_hit := -100
var lang := "ru"
var quick := false
var mobile := false
var out_dir := "C:/kach/marketing/yandex/ru/screenshots_desktop"

func _ready() -> void:
	seed(42)
	for arg in OS.get_cmdline_user_args():
		if arg == "en": lang = "en"
		if arg == "quick": quick = true
		if arg == "mobile": mobile = true
	Loc.set_language(lang)
	out_dir = "C:/kach/marketing/yandex/" + lang + "/screenshots_desktop"
	if mobile: out_dir = "C:/kach/marketing/yandex/" + lang + "/screenshots_mobile"
	DirAccess.make_dir_recursive_absolute(out_dir)
	gym = load("res://scenes/gym/gym.tscn").instantiate()
	add_child(gym)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	DisplayServer.window_set_position(Vector2i(-3000, -3000))
	process_priority = 100
	print("CAPTURE READY")
	for n in gym._collect_named(gym.stations_mount, "EMP_Station"):
		print(n.name, " ", n.global_position)

func _process(_delta: float) -> void:
	var s := 0
	if frame >= 210: s = 1
	if frame >= 360: s = 2
	if frame >= 570: s = 3
	if s != shot:
		shot = s
		_setup_shot(s)
	if s == 1:
		var t := float(frame - 210) / 150.0
		gym.player.rotation.y = lerpf(0.35, -0.55, t)
	elif s == 3:
		var t := float(frame - 570) / 150.0
		gym.player.rotation.y = lerpf(-0.45, 0.3, t)
	_autoplay()
	if frame in [105, 295, 465, 645]:
		_save_screen(frame)
	frame += 1
	if (quick and frame >= 110) or frame >= 720:
		get_tree().quit()

func _setup_shot(s: int) -> void:
	if GameState.in_set:
		gym.workout.root.hide()
		gym.end_set()
	GameState.energy = 100.0
	GameState.fatigue = 0.0
	GameState.hygiene = 100.0
	GameState.recovery = 95.0
	GameState.combo = 0
	GameState.sets_since_ad = 0
	if s >= 2:
		# A separate, attainable later save. Hard cut makes the time jump explicit.
		for muscle in ["chest", "arms", "back", "legs", "cardio"]:
			GameState.set(muscle, 72.0)
		GameState.money = 860
	GameState.stats_changed.emit()
	gym._apply_level_theme(GameState.gym_level())
	if s == 0 or s == 2:
		var sid := "dumbbell" if s == 0 else "bench"
		for n in gym._collect_named(gym.stations_mount, "EMP_Station"):
			if str(n.get_meta("station_id", gym._id_from_name(n.name))) == sid:
				gym._near = {"kind": "station", "id": sid, "node": n}
				gym._start_set(sid)
				# Camera framing for the trailer; meshes, animation, UI and scoring stay intact.
				gym.player.rotation.y = PI * 0.38 if sid == "dumbbell" else -0.2
				gym.player._pitch = 0.06 if sid == "bench" else -0.04
				break
	else:
		gym.player.global_position = Vector3(0, 0.02, 3.8)
		gym.player._pitch = -0.09
		gym.player.head.rotation.x = -0.09
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

func _autoplay() -> void:
	var wo = gym.workout
	if not GameState.in_set or wo._lock_input or frame - last_hit < 10:
		return
	if absf(wo._phase - 0.5) < 0.02:
		if wo._mode == "timing": wo._try_hit()
		elif wo._mode == "alternate": wo._try_alt(wo._alt_expect)
		last_hit = frame

func _save_screen(f: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var name := {105: "01_dumbbells", 295: "02_explore", 465: "03_bench", 645: "04_progress"}
	img.save_png(out_dir + "/" + str(name[f]) + ".png")
	print("SCREENSHOT ", f)
	print("CAM ", gym.player.cam.global_position, " PLAYER ", gym.player.global_position, " FP ", gym.player._fp.visible)
