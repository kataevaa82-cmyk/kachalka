extends Node3D
## One gym-goer in a t-shirt: walks a loop, idles at corners.

const GltfRuntime := preload("res://scripts/gym/gltf_runtime.gd")

var speed: float = 1.15
var waypoints: PackedVector3Array = PackedVector3Array()

var _anim: AnimationPlayer
var _clip: String = ""
var _wp: int = 0
var _hold: float = 0.0


func setup(glb_path: String, origin: Vector3, pts: PackedVector3Array) -> void:
	waypoints = pts
	position = origin
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var vis := GltfRuntime.load_node(glb_path)
	if vis == null:
		push_error("NPC missing " + glb_path)
		return
	vis.name = "Rig"
	add_child(vis)
	_anim = _find_anim(vis)
	_play("walk")


func _process(delta: float) -> void:
	if GameState.paused or GameState.in_set:
		return
	if waypoints.size() < 2:
		_play("idle")
		return
	if _hold > 0.0:
		_hold -= delta
		_play("idle")
		return
	var target: Vector3 = waypoints[_wp]
	var here := Vector3(global_position.x, 0.0, global_position.z)
	var to := Vector3(target.x, 0.0, target.z) - here
	var dist := to.length()
	if dist < 0.22:
		_wp = (_wp + 1) % waypoints.size()
		_hold = 0.25
		return
	var dir := to / dist
	global_position.x += dir.x * speed * delta
	global_position.z += dir.z * speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 8.0 * delta)
	_play("walk")


func _play(clip: String) -> void:
	if _anim == null or clip == _clip:
		return
	var resolved := _resolve(clip)
	if resolved == "":
		if clip == "walk":
			resolved = _resolve("run")
		if resolved == "":
			return
	_clip = clip
	var res: Animation = _anim.get_animation(resolved)
	if res != null:
		res.loop_mode = Animation.LOOP_LINEAR
	_anim.active = true
	_anim.play(resolved)
	if clip == "walk":
		_anim.speed_scale = 0.72
	else:
		_anim.speed_scale = 1.0


func _resolve(clip: String) -> String:
	var want := clip.to_lower()
	if _anim.has_animation(clip):
		return clip
	for lib_name in _anim.get_animation_library_list():
		var lib: AnimationLibrary = _anim.get_animation_library(lib_name)
		for n in lib.get_animation_list():
			var low := n.to_lower()
			if want in low:
				var path := n if lib_name == "" else "%s/%s" % [lib_name, n]
				if _anim.has_animation(path):
					return path
				if _anim.has_animation(n):
					return n
				return path
	return ""


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim(c)
		if found:
			return found
	return null
