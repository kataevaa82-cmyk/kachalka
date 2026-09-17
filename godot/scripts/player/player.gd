extends CharacterBody3D
class_name GymPlayer
## First-person walker. Body hidden; camera at eye height.

const GltfRuntime := preload("res://scripts/gym/gltf_runtime.gd")

const SPEED := 4.2
const ACCEL := 22.0
const GRAVITY := 22.0
const MOUSE_SENS := 0.0022
const TOUCH_SENS := 0.004
const PITCH_MIN := deg_to_rad(-85.0)
const PITCH_MAX := deg_to_rad(85.0)
const EYE_HEIGHT := 1.62
const STEP_STRIDE := 1.05

@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D

var stick: Vector2 = Vector2.ZERO
var _step_dist: float = 0.0
var locked: bool = false:
	set(v):
		locked = v
		_sync_mouse()
var _look_touch_id: int = -1
var _pitch: float = 0.0
var _fp: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _prop: MeshInstance3D
var _workout_sid: String = ""
var _workout_t: float = 0.0
var _impact: float = 0.0
var _base_head_y: float = EYE_HEIGHT
var _fp_from_glb: bool = false
var _fp_scale: float = 1.0
var _fp_vm: bool = false


func _ready() -> void:
	cam.current = true
	cam.near = 0.03
	_ensure_fp()
	if _fp:
		_fp.visible = true
		_animate_fp_idle(0.0)
	GameState.stats_changed.connect(_apply_muscles)
	_apply_muscles()
	_sync_mouse()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if locked:
		velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
		move_and_slide()
		if _workout_sid != "":
			_animate_workout(delta)
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if stick.length() > 0.12:
		input_dir = Vector2(stick.x, stick.y)

	var wish := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	elif wish.length() > 0.001:
		wish = wish.normalized() * wish.length()

	var target := wish * SPEED * GameState.move_scale()
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()

	_footsteps(delta)
	_animate_fp_idle(delta)


## One step per ~1.05 m of ground covered, so the cadence follows actual speed.
func _footsteps(delta: float) -> void:
	if not is_on_floor():
		return
	var ground := Vector2(velocity.x, velocity.z).length()
	if ground < 0.4:
		_step_dist = STEP_STRIDE * 0.55
		return
	_step_dist += ground * delta
	if _step_dist >= STEP_STRIDE:
		_step_dist -= STEP_STRIDE
		Audio.play("step", randf_range(0.88, 1.14), -4.0)


func _unhandled_input(event: InputEvent) -> void:
	if GameState.paused:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not locked and not GameState.is_touch():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func look_touch(rel: Vector2) -> void:
	if locked or GameState.paused:
		return
	_look(rel * (TOUCH_SENS / MOUSE_SENS))


func _look(rel: Vector2) -> void:
	rotate_y(-rel.x * MOUSE_SENS)
	_pitch = clampf(_pitch - rel.y * MOUSE_SENS, PITCH_MIN, PITCH_MAX)
	head.rotation.x = _pitch


func _sync_mouse() -> void:
	if GameState.paused or locked:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func begin_workout(sid: String) -> void:
	locked = true
	_workout_sid = sid
	_workout_t = 0.0
	_impact = 0.0
	_ensure_fp()
	_fp.visible = true
	_setup_prop(sid)
	match sid:
		"bench":
			_base_head_y = 0.52
			_pitch = deg_to_rad(-30.0)
		"dip":
			_base_head_y = 1.32
			_pitch = deg_to_rad(-12.0)
		"pullup":
			_base_head_y = 1.78
			_pitch = deg_to_rad(16.0)
		"lat":
			_base_head_y = 1.40
			_pitch = deg_to_rad(10.0)
		"bike":
			_base_head_y = 1.28
			_pitch = deg_to_rad(-8.0)
		"legpress":
			_base_head_y = 0.85
			_pitch = deg_to_rad(12.0)
		"shoulder":
			_base_head_y = 1.28
			_pitch = deg_to_rad(-6.0)
		"row":
			_base_head_y = 1.15
			_pitch = deg_to_rad(-8.0)
		"rower":
			_base_head_y = 1.05
			_pitch = deg_to_rad(-10.0)
		"hyper":
			_base_head_y = 1.05
			_pitch = deg_to_rad(-18.0)
		"ropes":
			_base_head_y = EYE_HEIGHT
			_pitch = deg_to_rad(-8.0)
		"squat":
			_base_head_y = EYE_HEIGHT
			_pitch = deg_to_rad(6.0)
		_:
			_base_head_y = EYE_HEIGHT
			_pitch = deg_to_rad(-4.0)
	head.position.y = _base_head_y
	head.rotation.x = _pitch


func end_workout() -> void:
	_workout_sid = ""
	if _fp:
		_fp.visible = true
	_pitch = 0.0
	head.position.y = EYE_HEIGHT
	head.rotation.x = 0.0
	cam.fov = 75.0
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	locked = false
	_animate_fp_idle(0.0)


func workout_impact(grade: String) -> void:
	if grade == "perfect":
		_impact = 1.0
	elif grade == "good":
		_impact = 0.55
	else:
		_impact = 0.28


func _ensure_fp() -> void:
	if _fp != null:
		return
	var loaded := GltfRuntime.load_node("res://assets/models/fp_arms.glb")
	if loaded:
		_arm_l = _find_named(loaded, "ArmL")
		_arm_r = _find_named(loaded, "ArmR")
		if _arm_l and _arm_r:
			_fp = Node3D.new()
			_fp.name = "FPView"
			cam.add_child(_fp)
			_adopt(_arm_l, _fp)
			_adopt(_arm_r, _fp)
			_fp_from_glb = true
			_fp_scale = 0.86
			_tune_fp_meshes(_fp)
			loaded.free()
		else:
			_fp = loaded
			_fp.name = "FPView"
			cam.add_child(_fp)
			_fp_from_glb = true
			_fp_vm = true
			_arm_l = _fp
			_arm_r = _fp
			_fp.position = Vector3(0.0, -0.04, 0.02)
			_tune_fp_meshes(_fp)
	if _fp == null:
		_fp = Node3D.new()
		_fp.name = "FPView"
		cam.add_child(_fp)
		_arm_l = _make_arm(-1.0)
		_arm_r = _make_arm(1.0)
	_add_fp_fill()
	_prop = MeshInstance3D.new()
	_prop.name = "FPProp"
	var bar := CylinderMesh.new()
	bar.top_radius = 0.013
	bar.bottom_radius = 0.013
	bar.height = 0.78
	bar.radial_segments = 16
	_prop.mesh = bar
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.62, 0.64, 0.68)
	chrome.metallic = 0.55
	chrome.roughness = 0.35
	_prop.material_override = chrome
	_prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_prop.visible = false
	_fp.add_child(_prop)


func _adopt(n: Node3D, parent: Node) -> void:
	n.owner = null
	var old := n.get_parent()
	if old:
		old.remove_child(n)
	parent.add_child(n)
	n.position = Vector3.ZERO
	n.rotation = Vector3.ZERO
	n.scale = Vector3.ONE


func _find_named(n: Node, want: String) -> Node3D:
	if n is Node3D and n.name == want:
		return n
	for c in n.get_children():
		var f := _find_named(c, want)
		if f:
			return f
	return null


func _tune_fp_meshes(n: Node) -> void:
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		gi.extra_cull_margin = 2.0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			(mi.material_override as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for c in n.get_children():
		_tune_fp_meshes(c)


func _add_fp_fill() -> void:
	var fill := OmniLight3D.new()
	fill.name = "FPFill"
	fill.light_color = Color(1.0, 0.96, 0.92)
	fill.light_energy = 0.28
	fill.omni_range = 1.4
	fill.omni_attenuation = 1.4
	fill.shadow_enabled = false
	fill.position = Vector3(0.0, 0.06, 0.10)
	_fp.add_child(fill)


func _make_arm(side: float) -> Node3D:
	var root := Node3D.new()
	root.name = "ArmL" if side < 0.0 else "ArmR"
	_fp.add_child(root)
	var skin := _std_mat(Color(0.76, 0.55, 0.42), 0.0, 0.46)
	var skin_d := _std_mat(Color(0.62, 0.42, 0.32), 0.0, 0.52)
	var sleeve := _std_mat(Color(0.78, 0.10, 0.12), 0.02, 0.58)
	var nail := _std_mat(Color(0.90, 0.74, 0.70), 0.08, 0.26)
	_add_capsule(root, sleeve, 0.050, 0.16, Vector3(0.0, -0.08, 0.0), 14)
	_add_capsule(root, skin, 0.040, 0.20, Vector3(0.0, -0.24, 0.0), 14)
	_add_sphere(root, skin_d, 0.030, Vector3(0.0, -0.34, 0.0), 12)
	_add_capsule(root, skin, 0.032, 0.18, Vector3(0.0, -0.44, 0.0), 14)
	var hand := MeshInstance3D.new()
	var h := BoxMesh.new()
	h.size = Vector3(0.074, 0.088, 0.028)
	hand.mesh = h
	hand.material_override = skin
	hand.position = Vector3(0.0, -0.55, 0.012)
	hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hand)
	for i in 4:
		var ox := -0.027 + 0.018 * float(i)
		_add_capsule(root, skin, 0.009, 0.046, Vector3(ox, -0.62, 0.010), 8)
		_add_sphere(root, nail, 0.006, Vector3(ox, -0.645, 0.014), 8)
	_add_capsule(root, skin, 0.011, 0.038, Vector3(0.046 * side, -0.54, 0.018), 8)
	return root


func _std_mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m


func _add_capsule(parent: Node3D, mat: Material, radius: float, height: float, pos: Vector3, segs: int) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = segs
	mesh.rings = 4
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _add_sphere(parent: Node3D, mat: Material, radius: float, pos: Vector3, segs: int) -> void:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segs
	mesh.rings = segs
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _setup_prop(sid: String) -> void:
	if _prop == null:
		return
	_prop.visible = sid in ["bench", "squat", "lat", "pullup"]
	_prop.rotation_degrees = Vector3(0.0, 0.0, 90.0)


func _animate_fp_idle(delta: float) -> void:
	if _fp == null or not _fp.visible or _workout_sid != "":
		return
	_workout_t += delta
	var spd := Vector2(velocity.x, velocity.z).length()
	var walk := clampf(spd / SPEED, 0.0, 1.0)
	var bob := sin(_workout_t * (1.8 + 6.4 * walk)) * (0.007 + 0.016 * walk)
	var swing := sin(_workout_t * 7.4) * walk
	if _fp_vm:
		_pose_vm(
			Vector3(0.0, -0.04 + bob, 0.02),
			Vector3(deg_to_rad(2.0 * walk), deg_to_rad(6.0 * swing), deg_to_rad(2.0 * bob * 20.0))
		)
	else:
		_pose_arm(
			-1.0,
			Vector3(-0.21, -0.26 + bob, -0.36),
			Vector3(deg_to_rad(-46.0 + 6.0 * walk), deg_to_rad(3.0), deg_to_rad(-10.0 - 10.0 * swing))
		)
		_pose_arm(
			1.0,
			Vector3(0.21, -0.26 - bob * 0.7, -0.36),
			Vector3(deg_to_rad(-46.0 + 6.0 * walk), deg_to_rad(-3.0), deg_to_rad(10.0 + 10.0 * swing))
		)
	if _prop:
		_prop.visible = false
	cam.fov = 75.0
	cam.h_offset = 0.0
	cam.v_offset = 0.0


func _animate_workout(delta: float) -> void:
	_workout_t += delta
	_impact = move_toward(_impact, 0.0, delta * 3.6)
	var st: Dictionary = GameState.stations.get(_workout_sid, {})
	var period := maxf(float(st.get("period", 0.85)), 0.2)
	var u := fposmod(_workout_t / period, 1.0)
	var s := sin(u * TAU)
	var c := 0.5 + 0.5 * sin(u * TAU - PI * 0.5)
	cam.fov = 75.0 - 8.0 * _impact
	cam.h_offset = sin(_workout_t * 28.0) * 0.018 * _impact
	cam.v_offset = cos(_workout_t * 22.0) * 0.012 * _impact
	if _fp_vm:
		_animate_vm(s, c)
		head.rotation.x = _pitch + deg_to_rad(s * 2.5)
		return
	match _workout_sid:
		"bench":
			_pose_arm(-1.0, Vector3(-0.16, -0.10 - 0.04 * (1.0 - c), -0.34 - 0.20 * c), Vector3(deg_to_rad(-82.0 + 18.0 * c), 0.0, deg_to_rad(-8.0)))
			_pose_arm(1.0, Vector3(0.16, -0.10 - 0.04 * (1.0 - c), -0.34 - 0.20 * c), Vector3(deg_to_rad(-82.0 + 18.0 * c), 0.0, deg_to_rad(8.0)))
			_prop.position = Vector3(0.0, -0.08, -0.42 - 0.20 * c)
			head.position.y = _base_head_y + 0.02 * c
		"squat":
			_pose_arm(-1.0, Vector3(-0.30, -0.02, -0.28), Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(-72.0)))
			_pose_arm(1.0, Vector3(0.30, -0.02, -0.28), Vector3(deg_to_rad(-18.0), 0.0, deg_to_rad(72.0)))
			_prop.position = Vector3(0.0, 0.10, -0.22)
			head.position.y = _base_head_y - 0.30 * (1.0 - c)
		"dumbbell":
			_pose_arm(-1.0, Vector3(-0.22, -0.30 + 0.20 * c, -0.38), Vector3(deg_to_rad(-25.0 - 65.0 * c), 0.0, deg_to_rad(-10.0)))
			_pose_arm(1.0, Vector3(0.22, -0.30 + 0.20 * c, -0.38), Vector3(deg_to_rad(-25.0 - 65.0 * c), 0.0, deg_to_rad(10.0)))
			head.position.y = _base_head_y
		"pullup":
			_pose_arm(-1.0, Vector3(-0.20, 0.10 + 0.06 * c, -0.26), Vector3(deg_to_rad(-150.0), 0.0, deg_to_rad(-6.0)))
			_pose_arm(1.0, Vector3(0.20, 0.10 + 0.06 * c, -0.26), Vector3(deg_to_rad(-150.0), 0.0, deg_to_rad(6.0)))
			_prop.position = Vector3(0.0, 0.28, -0.22)
			head.position.y = _base_head_y + 0.18 * c
		"lat":
			_pose_arm(-1.0, Vector3(-0.22, 0.16 - 0.22 * c, -0.30), Vector3(deg_to_rad(-130.0 + 40.0 * c), 0.0, deg_to_rad(-8.0)))
			_pose_arm(1.0, Vector3(0.22, 0.16 - 0.22 * c, -0.30), Vector3(deg_to_rad(-130.0 + 40.0 * c), 0.0, deg_to_rad(8.0)))
			_prop.position = Vector3(0.0, 0.22 - 0.20 * c, -0.28)
			head.position.y = _base_head_y
		"treadmill":
			_pose_arm(-1.0, Vector3(-0.18, -0.22 + 0.08 * s, -0.36), Vector3(deg_to_rad(-42.0 + 22.0 * s), 0.0, deg_to_rad(-8.0)))
			_pose_arm(1.0, Vector3(0.18, -0.22 - 0.08 * s, -0.36), Vector3(deg_to_rad(-42.0 - 22.0 * s), 0.0, deg_to_rad(8.0)))
			head.position.y = _base_head_y + 0.03 * s
		"bike":
			_pose_arm(-1.0, Vector3(-0.16, -0.18 + 0.02 * s, -0.42), Vector3(deg_to_rad(-52.0), 0.0, deg_to_rad(-6.0)))
			_pose_arm(1.0, Vector3(0.16, -0.18 - 0.02 * s, -0.42), Vector3(deg_to_rad(-52.0), 0.0, deg_to_rad(6.0)))
			head.position.y = _base_head_y + 0.015 * s
		"dip":
			_pose_arm(-1.0, Vector3(-0.30, -0.12 - 0.10 * (1.0 - c), -0.28), Vector3(deg_to_rad(-95.0), 0.0, deg_to_rad(-22.0)))
			_pose_arm(1.0, Vector3(0.30, -0.12 - 0.10 * (1.0 - c), -0.28), Vector3(deg_to_rad(-95.0), 0.0, deg_to_rad(22.0)))
			head.position.y = _base_head_y - 0.16 * (1.0 - c)
		"kettlebell":
			_pose_arm(-1.0, Vector3(-0.10, -0.32 + 0.28 * c, -0.36 + 0.08 * s), Vector3(deg_to_rad(-35.0 - 40.0 * s), 0.0, deg_to_rad(-8.0)))
			_pose_arm(1.0, Vector3(0.10, -0.32 + 0.28 * c, -0.36 + 0.08 * s), Vector3(deg_to_rad(-35.0 - 40.0 * s), 0.0, deg_to_rad(8.0)))
			head.position.y = _base_head_y + 0.04 * c
		_:
			_pose_arm(-1.0, Vector3(-0.22, -0.28, -0.38), Vector3(deg_to_rad(-50.0), 0.0, deg_to_rad(-8.0)))
			_pose_arm(1.0, Vector3(0.22, -0.28, -0.38), Vector3(deg_to_rad(-50.0), 0.0, deg_to_rad(8.0)))
	head.rotation.x = _pitch + deg_to_rad(s * 2.5)


func _animate_vm(s: float, c: float) -> void:
	match _workout_sid:
		"bench":
			_pose_vm(Vector3(0.0, -0.02 - 0.05 * (1.0 - c), 0.04 - 0.10 * c), Vector3(deg_to_rad(-10.0 + 14.0 * c), 0.0, 0.0))
			_prop.position = Vector3(0.0, 0.02, -0.30 - 0.12 * c)
			head.position.y = _base_head_y + 0.02 * c
		"squat":
			_pose_vm(Vector3(0.0, 0.04, 0.0), Vector3(deg_to_rad(8.0), 0.0, 0.0))
			_prop.position = Vector3(0.0, 0.14, -0.18)
			head.position.y = _base_head_y - 0.30 * (1.0 - c)
		"dumbbell":
			_pose_vm(Vector3(0.0, -0.06 + 0.10 * c, 0.02), Vector3(deg_to_rad(-6.0 - 18.0 * c), 0.0, 0.0))
			head.position.y = _base_head_y
		"pullup":
			_pose_vm(Vector3(0.0, 0.08 + 0.04 * c, -0.04), Vector3(deg_to_rad(12.0), 0.0, 0.0))
			_prop.position = Vector3(0.0, 0.22, -0.16)
			head.position.y = _base_head_y + 0.18 * c
		"lat":
			_pose_vm(Vector3(0.0, 0.06 - 0.12 * c, 0.0), Vector3(deg_to_rad(8.0 - 16.0 * c), 0.0, 0.0))
			_prop.position = Vector3(0.0, 0.16 - 0.14 * c, -0.22)
			head.position.y = _base_head_y
		"treadmill":
			_pose_vm(Vector3(0.0, -0.03 + 0.02 * s, 0.02), Vector3(deg_to_rad(s * 6.0), 0.0, deg_to_rad(s * 4.0)))
			head.position.y = _base_head_y + 0.03 * s
		"bike":
			_pose_vm(Vector3(0.0, -0.06, 0.06), Vector3(deg_to_rad(-8.0), 0.0, deg_to_rad(s * 3.0)))
			head.position.y = _base_head_y + 0.015 * s
		"dip":
			_pose_vm(Vector3(0.0, -0.04 - 0.08 * (1.0 - c), 0.0), Vector3(deg_to_rad(-4.0), 0.0, 0.0))
			head.position.y = _base_head_y - 0.16 * (1.0 - c)
		"kettlebell":
			_pose_vm(Vector3(0.0, -0.08 + 0.16 * c, 0.02 + 0.04 * s), Vector3(deg_to_rad(-12.0 + 20.0 * c), 0.0, deg_to_rad(s * 8.0)))
			head.position.y = _base_head_y + 0.04 * c
		_:
			_pose_vm(Vector3(0.0, -0.04 + 0.02 * s, 0.02), Vector3(deg_to_rad(s * 4.0), 0.0, 0.0))
			head.position.y = _base_head_y


func _pose_vm(pos: Vector3, rot: Vector3) -> void:
	if _fp == null:
		return
	var s := 1.0 + 0.32 * (1.0 - exp(-GameState.arms / 80.0))
	_fp.position = pos
	_fp.rotation = rot
	_fp.scale = Vector3(s, s, s)


func _pose_arm(side: float, pos: Vector3, rot: Vector3) -> void:
	if _fp_vm:
		return
	var n: Node3D = _arm_l if side < 0.0 else _arm_r
	if n == null:
		return
	n.position = pos
	n.rotation = rot
	var s := _fp_scale * (1.0 + 0.32 * (1.0 - exp(-GameState.arms / 80.0)))
	n.scale = Vector3(s, s, s)


func _apply_muscles() -> void:
	if _fp_vm and _fp:
		var vs := 1.0 + 0.32 * (1.0 - exp(-GameState.arms / 80.0))
		_fp.scale = Vector3(vs, vs, vs)
	else:
		var arm_s := _fp_scale * (1.0 + 0.32 * (1.0 - exp(-GameState.arms / 80.0)))
		if _arm_l:
			_arm_l.scale = Vector3(arm_s, arm_s, arm_s)
		if _arm_r:
			_arm_r.scale = Vector3(arm_s, arm_s, arm_s)
