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
	if FileAccess.file_exists(path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		if bytes.size() > 0:
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			var err: Error = doc.append_from_buffer(bytes, path.get_base_dir(), state)
			if err == OK:
				var node: Node = doc.generate_scene(state)
				if node:
					return node
			push_error("GLTF buffer failed %s code=%s" % [path, err])
	var abs_path := ProjectSettings.globalize_path(path)
	if abs_path != path and FileAccess.file_exists(abs_path):
		var doc2 := GLTFDocument.new()
		var state2 := GLTFState.new()
		if doc2.append_from_file(abs_path, state2) == OK:
			return doc2.generate_scene(state2)
	push_error("GLTF load failed: " + path)
	return null
