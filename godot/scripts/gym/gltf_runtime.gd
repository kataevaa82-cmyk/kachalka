extends RefCounted
## Load GLB in editor AND exported pck.
## 1) PackedScene from Godot import remap
## 2) bytes via FileAccess (res:// inside pck)
## 3) absolute file path (dev)


static func load_node(path: String) -> Node:
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is PackedScene:
			var inst: Node = (res as PackedScene).instantiate()
			if inst:
				return inst
	var node := _parse_at_runtime(path)
	if node:
		return node
	push_error("GLTF load failed: " + path)
	return null


## Only reached when the import cache is missing, which never happens in an
## exported build — the remap above always resolves there. The gltf module is
## therefore compiled out of the shipped web template, so the classes are looked
## up through ClassDB rather than named directly: naming them would fail to
## parse where the module is absent, while this just returns null.
static func _parse_at_runtime(path: String) -> Node:
	var doc: Object = ClassDB.instantiate("GLTFDocument")
	var state: Object = ClassDB.instantiate("GLTFState")
	if doc == null or state == null:
		return null
	if FileAccess.file_exists(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0 and doc.call("append_from_buffer", bytes, path.get_base_dir(), state) == OK:
			var node: Node = doc.call("generate_scene", state)
			if node:
				return node
	var abs_path := ProjectSettings.globalize_path(path)
	if abs_path != path and FileAccess.file_exists(abs_path):
		var state2: Object = ClassDB.instantiate("GLTFState")
		if doc.call("append_from_file", abs_path, state2) == OK:
			return doc.call("generate_scene", state2)
	return null
