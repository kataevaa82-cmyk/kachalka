extends Node
## Headless screenshot rig: drops the player at a few fixed spots in the gym and
## writes a PNG of each. Used to eyeball lighting and materials without a
## machine to play on.
##
##   godot --path godot --rendering-driver opengl3 res://tools/shots_scene.tscn -- out=/tmp/shots

const SHOTS: Array[Dictionary] = [
	{"name": "hall", "pos": Vector3(0.0, 0.0, 6.2), "yaw": 0.0, "pitch": -4.0},
	{"name": "hall_far", "pos": Vector3(-3.2, 0.0, 1.0), "yaw": 35.0, "pitch": -6.0},
	{"name": "lockers", "pos": Vector3(-11.4, 0.0, 0.6), "yaw": 185.0, "pitch": -2.0},
	{"name": "booths", "pos": Vector3(-12.2, 0.0, 1.1), "yaw": 190.0, "pitch": -6.0},
	{"name": "mirror", "pos": Vector3(-10.45, 0.0, -2.2), "yaw": 0.0, "pitch": 2.0},
	{"name": "cardio", "pos": Vector3(10.6, 0.0, 0.6), "yaw": 250.0, "pitch": -4.0},
	{"name": "bar", "pos": Vector3(0.0, 0.0, -6.4), "yaw": 180.0, "pitch": -2.0},
	{"name": "reception", "pos": Vector3(0.0, 0.0, 8.4), "yaw": 0.0, "pitch": -4.0},
]

var _out := "/tmp/shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("out="):
			_out = str(a).substr(4)
	DirAccess.make_dir_recursive_absolute(_out)
	_run()


func _run() -> void:
	var scene: Node = load("res://scenes/gym/gym.tscn").instantiate()
	# Parented to this node, not the root: the root is still building its own
	# children while _ready runs and refuses the add.
	add_child(scene)
	await get_tree().process_frame
	var player: Node3D = scene.get_node("Player")
	var head: Node3D = player.get_node("Head")
	# The HUD would cover the room; these shots are about the room.
	for layer in ["HUD", "Workout", "Shop"]:
		var n: Node = scene.get_node_or_null(layer)
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	for shot in SHOTS:
		player.global_position = shot["pos"] + Vector3(0.0, 0.02, 0.0)
		player.rotation.y = deg_to_rad(float(shot["yaw"]))
		head.rotation.x = deg_to_rad(float(shot["pitch"]))
		# Several frames so shadows, tonemapping and the lazy meshes all settle.
		for i in 6:
			await get_tree().process_frame
		# Reading the viewport before the draw lands gives a blank image.
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [_out, shot["name"]]
		img.save_png(path)
		print("SHOT ", path)
	print("SHOTS_DONE")
	get_tree().quit()
