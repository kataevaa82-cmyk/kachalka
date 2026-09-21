extends Node3D
## Assembles Blender GLBs, collision proxies, lights, stations, player.

const GltfRuntime := preload("res://scripts/gym/gltf_runtime.gd")
const Surfaces := preload("res://scripts/gym/surfaces.gd")

const ROOM_HALF_X := 7.7
const ROOM_HALF_Z := 5.7



@onready var env_mount: Node3D = $EnvMount
@onready var stations_mount: Node3D = $StationsMount
@onready var player: CharacterBody3D = $Player
@onready var hud: CanvasLayer = $HUD
@onready var workout: CanvasLayer = $Workout
@onready var shop_layer: CanvasLayer = $Shop

var _near: Dictionary = {}
var _active_id: String = ""
var _wo_light: OmniLight3D
var _wo_ring: MeshInstance3D
var _prop_root: Node3D
var _sauna_steam: Node3D
var _sauna_puffs: Array[MeshInstance3D] = []
var _platform_paused: bool = false
var _paused_before_platform: bool = false
var _level_environment: Environment
var _level_light: OmniLight3D
var _level_sign: Label3D
var _booths: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The world must hear Esc while paused, but gameplay children must freeze with the tree.
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	workout.process_mode = Node.PROCESS_MODE_PAUSABLE
	_instance_glb("res://assets/models/gym_env.glb", env_mount)
	_instance_glb("res://assets/models/gym_stations.glb", stations_mount)
	var dressed: Dictionary = {}
	Surfaces.apply(env_mount, dressed)
	Surfaces.apply(stations_mount, dressed)
	_build_collision()
	_build_lights()
	_apply_level_theme(GameState.gym_level())
	_wire_stations()
	_spawn_props()
	_spawn_booths()
	_spawn_sauna_steam()
	_spawn_shower()
	player.global_position = Vector3(0.0, 0.02, 7.6)
	YandexSDK.loading_ready()
	YandexSDK.gameplay_start()
	Audio.start_music()
	YandexSDK.pause_requested.connect(_on_platform_pause)
	YandexSDK.resume_requested.connect(_on_platform_resume)
	GameState.level_unlocked.connect(_on_level_unlocked)
	Loc.language_changed.connect(func(_lang: String) -> void: _apply_level_theme(GameState.gym_level()))
	hud.call("set_prompt", "")


func _process(delta: float) -> void:
	_pulse_sauna_steam(delta)
	if GameState.in_set:
		_pulse_workout_fx(delta)
	if GameState.paused or GameState.in_set:
		return
	_tick_booths(delta)
	_near = _closest_target()
	if hud.has_method("set_aim"):
		hud.call("set_aim", not _near.is_empty())
	if _near.is_empty():
		hud.call("set_prompt", "")
		return
	var kind: String = str(_near.get("kind", "station"))
	var sid: String = str(_near.get("id", ""))
	if kind == "prop":
		hud.call("set_prompt", tr(str(_near.get("prompt", ""))))
	elif sid == "shop":
		hud.call("set_prompt", tr("Магазин"))
	elif not GameState.can_unlock(sid):
		var need := float(GameState.stations[sid].get("unlock_mass", 0))
		hud.call("set_prompt", tr("Закрыто. Набери %.0f кг (сейчас %.1f)") % [need, GameState.mass()], false)
	else:
		hud.call("set_prompt", tr(str(GameState.stations[sid].get("name", sid))))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game"):
		if YandexSDK.is_ad_active():
			return
		var shop_open := false
		var shop_root: Node = shop_layer.get_node_or_null("Root")
		if shop_root is CanvasItem:
			shop_open = (shop_root as CanvasItem).visible
		if shop_open:
			shop_layer.call("hide_shop")
			get_viewport().set_input_as_handled()
			return
		if GameState.in_set:
			return
		if GameState.paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return
	if GameState.paused or GameState.in_set:
		return
	if event.is_action_pressed("interact"):
		_try_interact()


func _try_interact() -> void:
	if _near.is_empty():
		return
	var kind: String = str(_near.get("kind", "station"))
	var sid: String = str(_near.get("id", ""))
	if kind == "prop":
		if sid.begins_with("booth"):
			_use_booth(sid)
		else:
			GameState.use_prop(sid)
		return
	if sid == "shop":
		shop_layer.call("show_shop")
		return
	if not GameState.can_unlock(sid):
		Audio.play("deny")
		GameState.emit_quote("unlock")
		return
	if GameState.too_tired():
		Audio.play("lowenergy")
		GameState.say("Забой. Сауна или скамейка, иначе сорвёшься.")
		hud.call("flash_energy")
		return
	var cost := float(GameState.stations[sid].get("energy", 12))
	if GameState.energy < cost:
		Audio.play("lowenergy")
		GameState.emit_quote("empty")
		hud.call("flash_energy")
		return
	_start_set(sid)


func _start_set(sid: String) -> void:
	GameState.in_set = true
	var cost := float(GameState.stations[sid].get("energy", 12))
	GameState.add_energy(-cost)
	GameState.note_effort(cost)
	var node: Node3D = _near["node"]
	player.global_position = Vector3(node.global_position.x, 0.02, node.global_position.z)
	player.rotation.y = _station_yaw(sid)
	player.call("begin_workout", sid)
	Audio.play("rack")
	_spawn_workout_fx(node.global_position)
	hud.call("set_prompt", "")
	if hud.has_method("set_workout"):
		hud.call("set_workout", true)
	workout.call("start_set", sid)


func end_set() -> void:
	player.call("end_workout")
	_clear_workout_fx()
	if hud.has_method("set_workout"):
		hud.call("set_workout", false)
	GameState.finish_set()
	if GameState.sets_since_ad >= 4:
		GameState.sets_since_ad = 0
		GameState.save_game()
		YandexSDK.gameplay_stop()
		get_tree().paused = true
		await YandexSDK.show_interstitial()
		# Pause menu / shop may have opened during the ad; they own the paused state.
		get_tree().paused = GameState.paused
		if not GameState.paused:
			YandexSDK.gameplay_start()


func _aim_origin_dir() -> Array:
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam:
		return [cam.global_position, -cam.global_transform.basis.z]
	return [player.global_position + Vector3(0, 1.5, 0), -player.global_transform.basis.z]


func _score_aim(at: Vector3, reach: float) -> float:
	var od: Array = _aim_origin_dir()
	var origin: Vector3 = od[0]
	var look: Vector3 = od[1]
	var to := at - origin
	var dist := to.length()
	if dist > maxf(reach, 2.5) + 0.35:
		return -1.0
	var align := look.dot(to / maxf(dist, 0.001))
	if align > 0.82:
		return align * 4.0 + (3.0 - dist)
	if dist <= reach * 0.72:
		return 0.35 + (reach - dist)
	return -1.0


func _closest_station() -> Dictionary:
	var best: Dictionary = {}
	var best_s: float = -1.0
	for n in _collect_named(stations_mount, "EMP_Station"):
		var s := _score_aim(n.global_position + Vector3(0.0, 0.9, 0.0), 1.7)
		if s > best_s:
			best_s = s
			var sid := str(n.get_meta("station_id", _id_from_name(n.name)))
			best = {"kind": "station", "id": sid, "node": n, "dist": player.global_position.distance_to(n.global_position), "score": s}
	return best


func _closest_target() -> Dictionary:
	var best := _closest_station()
	var best_s: float = float(best.get("score", -1.0))
	if _prop_root == null:
		return best
	for n in _prop_root.get_children():
		if not n is Node3D:
			continue
		var node := n as Node3D
		var reach := float(node.get_meta("reach", 1.35))
		var s := _score_aim(node.global_position + Vector3(0.0, 0.8, 0.0), reach)
		if s > best_s:
			best_s = s
			best = {
				"kind": "prop",
				"id": str(node.get_meta("prop_id", node.name)),
				"node": node,
				"dist": player.global_position.distance_to(node.global_position),
				"prompt": str(node.get_meta("prompt", "E")),
				"score": s,
			}
	return best


func _id_from_name(n: String) -> String:
	var key := n.replace("EMP_Station_", "").to_lower()
	if key == "dumbbells":
		return "dumbbell"
	if key == "pullup":
		return "pullup"
	if key == "kettlebells":
		return "kettlebell"
	if key == "legpress":
		return "legpress"
	return key


func _collect_named(root: Node, prefix: String) -> Array[Node3D]:
	var acc: Array[Node3D] = []
	_walk_named(root, prefix, acc)
	return acc


func _walk_named(n: Node, prefix: String, acc: Array[Node3D]) -> void:
	if n is Node3D and n.name.begins_with(prefix):
		acc.append(n)
	for c in n.get_children():
		_walk_named(c, prefix, acc)


func _instance_glb(path: String, parent: Node) -> void:
	var inst := GltfRuntime.load_node(path)
	if inst == null:
		push_error("Missing " + path)
		_spawn_fallback_floor()
		return
	parent.add_child(inst)


func _spawn_fallback_floor() -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(16, 0.1, 12)
	mi.mesh = mesh
	mi.position = Vector3(0, -0.05, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.22, 0.25)
	mi.material_override = mat
	add_child(mi)


func _wall_x(x: float, z0: float, z1: float, h: float = 4.2) -> void:
	_box_body(Vector3(x, h * 0.5, 0.5 * (z0 + z1)), Vector3(0.22, h, abs(z1 - z0)))


func _wall_z(z: float, x0: float, x1: float, h: float = 4.2) -> void:
	_box_body(Vector3(0.5 * (x0 + x1), h * 0.5, z), Vector3(abs(x1 - x0), h, 0.22))


func _build_collision() -> void:
	# Floor covers the whole complex. Thick slab so Jolt cannot drop the capsule at seams.
	# Top stays at y=0. Blender (x,y) → Godot (x, -y as z).
	_box_body(Vector3(0, -0.25, 0), Vector3(30.0, 0.5, 22.0))
	# Main hall X±8.1 Z±5.1 with door gaps 1.6m
	_wall_z(-5.1, -8.1, -0.8)
	_wall_z(-5.1, 0.8, 8.1)
	_wall_z(5.1, -8.1, -0.8)
	_wall_z(5.1, 0.8, 8.1)
	_wall_x(-8.1, -5.1, -0.8)
	_wall_x(-8.1, 0.8, 5.1)
	_wall_x(8.1, -5.1, -0.8)
	_wall_x(8.1, 0.8, 5.1)
	# Reception — south entrance sealed; west wall has a door into the WC
	_wall_z(10.1, -8.1, -0.8, 3.15)
	_wall_z(10.1, 0.8, 4.1, 3.15)
	_wall_x(4.1, 5.1, 10.1, 3.15)
	_wall_x(-4.1, 5.1, 6.7, 3.15)
	_wall_x(-4.1, 8.3, 10.1, 3.15)
	_box_body(Vector3(0.0, 1.1, 10.12), Vector3(1.8, 2.2, 0.36))
	# WC west of reception
	_wall_x(-8.1, 5.1, 10.1, 3.15)
	# Lockers west; north wall has a 1.6 m door into the sauna at x=-13.05
	_wall_x(-14.1, -4.1, 4.1, 3.35)
	_wall_z(4.1, -14.1, -8.1, 3.35)
	_wall_z(-4.1, -14.1, -13.85, 3.35)
	_wall_z(-4.1, -12.25, -8.1, 3.35)
	# Sauna north of lockers (Blender y>4.1 → Godot z<-4.1)
	_wall_x(-14.2, -8.35, -4.1, 2.55)
	_wall_z(-8.35, -14.2, -9.80, 2.55)
	_wall_x(-9.80, -8.35, -4.1, 2.55)
	_box_body(Vector3(-13.70, 0.50, -6.55), Vector3(0.60, 1.00, 2.60))
	_box_body(Vector3(-12.35, 0.50, -7.95), Vector3(2.75, 1.00, 0.60))
	_box_body(Vector3(-10.45, 0.45, -7.55), Vector3(0.70, 0.90, 0.70))
	# Cardio east
	_wall_x(14.1, -4.1, 4.1, 3.55)
	_wall_z(-4.1, 8.1, 14.1, 3.55)
	_wall_z(4.1, 8.1, 14.1, 3.55)
	# Bar north (godot z negative)
	_wall_z(-10.1, -5.1, 5.1, 3.25)
	_wall_x(-5.1, -10.1, -5.1, 3.25)
	_wall_x(5.1, -10.1, -5.1, 3.25)
	# Stations (Blender x,y → Godot x,-y). Aisles kept clear of doors.
	_box_body(Vector3(-5.5, 0.45, 3.35), Vector3(1.1, 0.9, 1.8))
	_box_body(Vector3(2.35, 1.1, 3.35), Vector3(1.5, 2.2, 1.2))
	_box_body(Vector3(5.65, 0.4, 3.35), Vector3(1.6, 0.8, 0.8))
	_box_body(Vector3(-5.5, 1.2, -3.35), Vector3(1.3, 2.4, 0.55))
	_box_body(Vector3(11.2, 0.55, -2.25), Vector3(0.95, 1.15, 1.9))
	_box_body(Vector3(-6.35, 1.1, -2.55), Vector3(1.0, 2.2, 0.9))
	_box_body(Vector3(11.2, 0.6, 2.25), Vector3(0.7, 1.2, 1.1))
	_box_body(Vector3(2.35, 0.85, -3.35), Vector3(1.15, 1.7, 0.7))
	_box_body(Vector3(5.65, 0.35, -3.35), Vector3(1.2, 0.7, 0.85))
	_box_body(Vector3(-2.15, 0.55, -3.35), Vector3(1.2, 1.1, 1.6))
	_box_body(Vector3(-2.15, 0.70, 3.35), Vector3(0.95, 1.4, 0.80))
	_box_body(Vector3(0.15, 0.55, -3.35), Vector3(0.75, 1.1, 1.6))
	_box_body(Vector3(11.2, 0.28, -0.05), Vector3(0.45, 0.55, 1.9))
	_box_body(Vector3(5.65, 0.40, -0.05), Vector3(0.60, 0.80, 1.2))
	_box_body(Vector3(13.15, 0.55, -2.35), Vector3(0.55, 1.1, 0.55))
	_box_body(Vector3(-3.35, 1.0, -8.85), Vector3(1.2, 2.0, 0.95))
	_box_body(Vector3(-4.78, 0.38, -6.90), Vector3(0.65, 0.76, 1.90))
	_box_body(Vector3(0.0, 0.55, -8.35), Vector3(3.7, 1.1, 0.75))
	_box_body(Vector3(-1.05, 0.47, -7.50), Vector3(0.45, 0.95, 0.42))
	_box_body(Vector3(1.05, 0.47, -7.50), Vector3(0.45, 0.95, 0.42))
	_box_body(Vector3(-13.78, 1.0, -0.35), Vector3(0.52, 2.0, 6.2))
	_box_body(Vector3(-12.18, 0.55, 3.40), Vector3(0.95, 1.10, 0.95))
	_box_body(Vector3(-11.15, 0.25, -3.55), Vector3(1.65, 0.5, 0.42))
	_box_body(Vector3(13.2, 1.1, 0.0), Vector3(0.5, 2.2, 0.5))
	_box_body(Vector3(2.70, 0.42, 7.60), Vector3(0.90, 0.85, 1.65))
	_box_body(Vector3(-2.15, 0.40, 6.70), Vector3(1.05, 0.85, 0.90))
	_box_body(Vector3(-2.15, 0.40, 8.40), Vector3(1.05, 0.85, 0.90))
	_box_body(Vector3(-3.40, 0.85, 9.35), Vector3(0.40, 1.70, 0.40))
	_box_body(Vector3(3.30, 0.70, 9.35), Vector3(0.50, 1.40, 0.50))
	_box_body(Vector3(-7.45, 0.42, 8.95), Vector3(1.15, 0.85, 0.80))
	_box_body(Vector3(-7.45, 0.42, 7.25), Vector3(1.15, 0.85, 0.80))
	_box_body(Vector3(-5.35, 0.45, 9.72), Vector3(0.60, 0.90, 0.50))
	_box_body(Vector3(-7.15, 1.00, 8.10), Vector3(1.10, 1.80, 0.08))
	_box_body(Vector3(-3.6, 2.1, 2.2), Vector3(0.4, 4.2, 0.4))
	_box_body(Vector3(3.6, 2.1, 2.2), Vector3(0.4, 4.2, 0.4))
	_box_body(Vector3(-3.6, 2.1, -2.2), Vector3(0.4, 4.2, 0.4))
	_box_body(Vector3(3.6, 2.1, -2.2), Vector3(0.4, 4.2, 0.4))


func _box_body(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.add_child(shape)
	add_child(body)


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_energy = 0.95
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.light_specular = 0.45
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 26.0
	add_child(sun)
	_level_light = _omni(Vector3(0.0, 3.15, 0.0), Color(1.0, 0.97, 0.92), 1.15)
	# The main hall is 16 x 10 m; one lamp in the middle left the corners black.
	_omni(Vector3(-5.2, 3.05, -2.6), Color(1.0, 0.96, 0.90), 0.72)
	_omni(Vector3(5.2, 3.05, -2.6), Color(1.0, 0.96, 0.90), 0.72)
	_omni(Vector3(-5.2, 3.05, 2.6), Color(1.0, 0.96, 0.90), 0.72)
	_omni(Vector3(5.2, 3.05, 2.6), Color(1.0, 0.96, 0.90), 0.72)
	_omni(Vector3(0.0, 2.45, 7.4), Color(0.98, 0.92, 0.82), 0.95)
	_omni(Vector3(-11.0, 2.45, 0.0), Color(0.84, 0.89, 0.96), 1.00)
	_omni(Vector3(-11.6, 2.35, 3.1), Color(0.86, 0.90, 0.95), 0.75)
	_omni(Vector3(-12.0, 1.85, -6.20), Color(1.0, 0.66, 0.42), 0.85)
	_omni(Vector3(11.0, 2.45, 0.0), Color(0.86, 0.94, 0.98), 0.95)
	_omni(Vector3(0.0, 2.45, -7.5), Color(0.86, 0.95, 0.84), 0.92)
	_omni(Vector3(-6.4, 2.25, 8.1), Color(0.92, 0.94, 0.96), 0.78)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.09, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.40, 0.41, 0.43)
	env.ambient_light_energy = 0.70
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	_level_environment = env
	we.environment = env
	add_child(we)
	_level_sign = Label3D.new()
	_level_sign.name = "LevelSign"
	# Sits on the far wall like a real gym sign. It used to billboard, which swung
	# the wide two-line text through the board mesh whenever the player stood off
	# to one side and left the wall slicing the text in half.
	_level_sign.position = Vector3(0.0, 3.25, -4.84)
	_level_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_level_sign.font_size = 44
	_level_sign.pixel_size = 0.0042
	_level_sign.outline_size = 10
	# Without a width the rule renders as one long line that overhangs the board.
	_level_sign.width = 820.0
	_level_sign.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_sign.modulate = Color(0.15, 0.85, 0.95)
	add_child(_level_sign)
	var cam: Camera3D = player.get_node_or_null("Head/Camera3D")
	if cam:
		cam.environment = env
		cam.fov = 75.0
		cam.near = 0.03


func _omni(pos: Vector3, color: Color, energy: float) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = 7.6
	o.omni_attenuation = 1.35
	o.light_specular = 0.22
	o.shadow_enabled = false
	add_child(o)
	return o


func _on_level_unlocked(level: int, _title: String, _rule: String) -> void:
	_apply_level_theme(level)


func _apply_level_theme(level: int) -> void:
	var data := GameState.level_data(level)
	var accent := GameState.level_accent(level)
	if _level_environment:
		_level_environment.background_color = Color.from_string(str(data.get("background", "#12151c")), Color(0.08, 0.09, 0.11))
		_level_environment.ambient_light_color = Color.from_string(str(data.get("ambient", "#697381")), Color(0.40, 0.41, 0.43))
		_level_environment.ambient_light_energy = 0.68 + float(level - 1) * 0.03
	if _level_light:
		_level_light.light_color = accent.lerp(Color.WHITE, 0.55)
		_level_light.light_energy = 1.10 + float(level - 1) * 0.07
	if _level_sign:
		_level_sign.text = tr("УРОВЕНЬ %d/6  ·  %s\n%s") % [level, GameState.level_name(level).to_upper(), GameState.level_rule(level)]
		_level_sign.modulate = accent


func _wire_stations() -> void:
	for n in _collect_named(stations_mount, "EMP_Station"):
		var sid := _id_from_name(n.name)
		n.set_meta("station_id", sid)


func _spawn_props() -> void:
	_prop_root = Node3D.new()
	_prop_root.name = "Props"
	add_child(_prop_root)
	var defs: Array = [
		{"id": "cooler", "pos": Vector3(1.70, 0.0, -8.75), "prompt": "Напиться", "reach": 1.4},
		{"id": "chair", "pos": Vector3(-2.15, 0.0, 6.70), "prompt": "Сесть", "reach": 1.3},
		{"id": "toilet", "pos": Vector3(-7.45, 0.0, 8.10), "prompt": "Туалет", "reach": 1.4},
		{"id": "sink", "pos": Vector3(-5.35, 0.0, 9.72), "prompt": "Умыться", "reach": 1.2},
		{"id": "tv", "pos": Vector3(-4.78, 0.0, -6.90), "prompt": "Телек", "reach": 1.5},
		{"id": "locker", "pos": Vector3(-13.2, 0.0, 0.0), "prompt": "Шкафчик", "reach": 1.5},
		{"id": "bag", "pos": Vector3(13.2, 0.0, 0.0), "prompt": "Груша", "reach": 1.4},
		{"id": "coat", "pos": Vector3(-3.40, 0.0, 9.35), "prompt": "Вешалка", "reach": 1.2},
		{"id": "benchrest", "pos": Vector3(-10.45, 0.0, -3.55), "prompt": "Присесть", "reach": 1.3},
		{"id": "sauna", "pos": Vector3(-12.00, 0.0, -6.20), "prompt": "Попариться", "reach": 1.7},
		{"id": "shower", "pos": Vector3(-12.18, 0.0, 3.40), "prompt": "Душ", "reach": 1.4},
	]
	for d in defs:
		var p := Node3D.new()
		p.name = "EMP_Prop_%s" % str(d["id"])
		p.position = d["pos"]
		p.set_meta("prop_id", d["id"])
		p.set_meta("prompt", d["prompt"])
		p.set_meta("reach", d["reach"])
		_prop_root.add_child(p)


## The three changing stalls along the locker-room south wall. Blender bakes the
## booths into one mesh, so the doors are stripped from that mesh and rebuilt
## here where they can actually swing. The middle stall is the shower and stands
## open; the other two are worth rummaging through.
const BOOTH_X: Array[float] = [-13.28, -12.18, -11.08]
const BOOTH_FRONT_Z := 2.84
const BOOTH_SHOWER := 1
const BOOTH_OPEN_ANGLE := 1.3
const BOOTH_RESTOCK := 75.0


func _spawn_booths() -> void:
	var panel := _std_mat(Color(0.86, 0.82, 0.74), 0.0, 0.55)
	var chrome := _std_mat(Color(0.62, 0.64, 0.68), 0.55, 0.38)
	for i in BOOTH_X.size():
		var cx: float = BOOTH_X[i]
		var pivot := Node3D.new()
		pivot.name = "BoothDoor%d" % i
		# Hinge sits where the baked aluminium hinge post already is, so the door
		# swings on the frame instead of floating beside it.
		pivot.position = Vector3(cx - 0.48, 0.0, BOOTH_FRONT_Z)
		add_child(pivot)
		var leaf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.92, 1.72, 0.04)
		leaf.mesh = box
		leaf.material_override = panel
		leaf.position = Vector3(0.46, 1.14, 0.0)
		pivot.add_child(leaf)
		var handle := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.05, 0.10, 0.04)
		handle.mesh = hb
		handle.material_override = chrome
		handle.position = Vector3(0.84, 1.15, 0.05)
		pivot.add_child(handle)

		var shower := i == BOOTH_SHOWER
		if shower:
			pivot.rotation.y = BOOTH_OPEN_ANGLE
			continue

		var item := _spawn_booth_item(cx)
		var marker := Node3D.new()
		marker.name = "EMP_Prop_booth%d" % i
		marker.position = Vector3(cx, 0.0, BOOTH_FRONT_Z - 0.35)
		marker.set_meta("prop_id", "booth%d" % i)
		marker.set_meta("reach", 1.5)
		_prop_root.add_child(marker)
		_booths.append({"pivot": pivot, "item": item, "marker": marker, "open": false, "loot": true, "cd": 0.0})
		_refresh_booth(_booths[_booths.size() - 1])


func _spawn_booth_item(cx: float) -> Node3D:
	var root := Node3D.new()
	root.name = "BoothLoot"
	# On the bench at the back of the stall, where a real gym bag would sit.
	root.position = Vector3(cx, 0.56, 3.66)
	root.visible = false
	add_child(root)
	var bag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.34, 0.20, 0.20)
	bag.mesh = bm
	var mat := _std_mat(Color(0.20, 0.42, 0.52), 0.1, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.55, 0.62)
	mat.emission_energy_multiplier = 0.55
	bag.material_override = mat
	root.add_child(bag)
	var strap := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.016
	sc.bottom_radius = 0.016
	sc.height = 0.30
	strap.mesh = sc
	strap.material_override = _std_mat(Color(0.14, 0.15, 0.17), 0.0, 0.7)
	strap.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	strap.position = Vector3(0.0, 0.12, 0.0)
	root.add_child(strap)
	return root


func _std_mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	return m


func _refresh_booth(b: Dictionary) -> void:
	var item: Node3D = b["item"]
	item.visible = b["open"] and b["loot"]
	var marker: Node3D = b["marker"]
	if not b["open"]:
		marker.set_meta("prompt", "Открыть кабинку")
	elif b["loot"]:
		marker.set_meta("prompt", "Забрать")
	else:
		marker.set_meta("prompt", "Пусто")


func _use_booth(sid: String) -> void:
	for b in _booths:
		if str(b["marker"].get_meta("prop_id", "")) != sid:
			continue
		if not b["open"]:
			b["open"] = true
			Audio.play("rack", 0.7, -8.0)
			var tw := create_tween()
			tw.tween_property(b["pivot"], "rotation:y", BOOTH_OPEN_ANGLE, 0.45) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		elif b["loot"]:
			b["loot"] = false
			b["cd"] = BOOTH_RESTOCK
			GameState.loot_booth()
		else:
			Audio.play("deny", 1.0, -9.0)
			GameState.say("Пусто. Только чужой запах и чья-то надежда.")
		_refresh_booth(b)
		return


## Someone drops a bag in an empty stall eventually; that is the restock.
func _tick_booths(delta: float) -> void:
	for b in _booths:
		if b["loot"] or b["cd"] <= 0.0:
			continue
		b["cd"] = float(b["cd"]) - delta
		if b["cd"] > 0.0:
			continue
		b["loot"] = true
		b["open"] = false
		var tw := create_tween()
		tw.tween_property(b["pivot"], "rotation:y", 0.0, 0.5).set_trans(Tween.TRANS_SINE)
		_refresh_booth(b)


func _spawn_shower() -> void:
	var root := Node3D.new()
	root.name = "Shower"
	root.position = Vector3(-12.18, 0.0, 3.40)
	add_child(root)
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.62, 0.64, 0.68)
	chrome.metallic = 0.55
	chrome.roughness = 0.38
	var pipe := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.018
	pc.bottom_radius = 0.018
	pc.height = 1.15
	pipe.mesh = pc
	pipe.material_override = chrome
	pipe.position = Vector3(0.0, 1.85, -0.42)
	root.add_child(pipe)
	var arm := MeshInstance3D.new()
	var ac := CylinderMesh.new()
	ac.top_radius = 0.016
	ac.bottom_radius = 0.016
	ac.height = 0.38
	arm.mesh = ac
	arm.material_override = chrome
	arm.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	arm.position = Vector3(0.0, 2.40, -0.24)
	root.add_child(arm)
	var head := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.07
	hs.height = 0.09
	head.mesh = hs
	head.material_override = chrome
	head.position = Vector3(0.0, 2.40, -0.04)
	root.add_child(head)
	var tray := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(0.72, 0.03, 0.72)
	tray.mesh = tb
	var tile := StandardMaterial3D.new()
	tile.albedo_color = Color(0.48, 0.50, 0.52)
	tile.roughness = 0.55
	tray.material_override = tile
	tray.position = Vector3(0.0, 0.02, 0.0)
	root.add_child(tray)


func _spawn_sauna_steam() -> void:
	_sauna_steam = Node3D.new()
	_sauna_steam.name = "SaunaSteam"
	_sauna_steam.position = Vector3(-10.55, 0.95, -7.45)
	add_child(_sauna_steam)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.92, 0.90, 0.86, 0.12)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 9:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var r := 0.16 + float(i % 4) * 0.05
		mesh.radius = r
		mesh.height = r * 2.0
		mesh.radial_segments = 10
		mesh.rings = 8
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(
			float((i % 3) - 1) * 0.22,
			float(i % 5) * 0.08,
			float((i / 3) - 1) * 0.18
		)
		_sauna_steam.add_child(mi)
		_sauna_puffs.append(mi)


func _pulse_sauna_steam(delta: float) -> void:
	if _sauna_steam == null:
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in _sauna_puffs.size():
		var puff := _sauna_puffs[i]
		var phase := t * (0.35 + float(i) * 0.07) + float(i)
		puff.position.y = 0.05 + fposmod(phase * 0.22, 1.15)
		var s := 0.75 + 0.35 * sin(phase)
		puff.scale = Vector3(s, s * 1.15, s)
		puff.transparency = clampf(puff.position.y * 0.35, 0.0, 0.65)


func _pause() -> void:
	Audio.play("click")
	GameState.paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	YandexSDK.gameplay_stop()
	hud.call("show_pause", true)


func _resume() -> void:
	Audio.play("back")
	GameState.paused = false
	get_tree().paused = false
	YandexSDK.gameplay_start()
	hud.call("show_pause", false)
	if not GameState.in_set:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_platform_pause() -> void:
	if _platform_paused:
		return
	_platform_paused = true
	_paused_before_platform = GameState.paused
	# Props grant money/muscle without saving; the tab may never come back.
	GameState.save_game()
	Audio.hold_mute("hidden")
	if not _paused_before_platform:
		_pause()


func _on_platform_resume() -> void:
	if not _platform_paused:
		return
	_platform_paused = false
	Audio.release_mute("hidden")
	if not _paused_before_platform:
		_resume()
	_paused_before_platform = false


func _station_yaw(sid: String) -> float:
	if sid == "dumbbell":
		return PI
	return 0.0


func _spawn_workout_fx(at: Vector3) -> void:
	_clear_workout_fx()
	_wo_light = OmniLight3D.new()
	_wo_light.position = at + Vector3(0.0, 2.1, 0.0)
	_wo_light.light_color = Color(1.0, 0.82, 0.45)
	_wo_light.light_energy = 1.15
	_wo_light.light_specular = 0.2
	_wo_light.omni_range = 4.5
	add_child(_wo_light)
	_wo_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.48
	torus.outer_radius = 0.62
	torus.rings = 12
	torus.ring_segments = 20
	_wo_ring.mesh = torus
	_wo_ring.position = at + Vector3(0.0, 0.04, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.25, 0.72, 0.68, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = false
	_wo_ring.material_override = mat
	add_child(_wo_ring)


func _pulse_workout_fx(delta: float) -> void:
	if _wo_light:
		_wo_light.light_energy = 1.5 + 0.7 * sin(Time.get_ticks_msec() * 0.007)
	if _wo_ring:
		_wo_ring.rotate_y(delta * 1.4)
		var s := 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.008)
		_wo_ring.scale = Vector3(s, 1.0, s)


func _clear_workout_fx() -> void:
	if _wo_light:
		_wo_light.queue_free()
		_wo_light = null
	if _wo_ring:
		_wo_ring.queue_free()
		_wo_ring = null


func on_rep_hit(grade: String) -> void:
	if player.has_method("workout_impact"):
		player.call("workout_impact", grade)
	if _wo_light:
		_wo_light.light_energy = 1.6 if grade == "perfect" else 1.25
