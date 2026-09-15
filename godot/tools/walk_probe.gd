extends SceneTree
## Capsule flood-fill. Uses _process so headless actually ticks.

const R := 0.28
const STEP := 0.30
const Y := 0.90
const X0 := -14.6
const X1 := 14.6
const Z0 := -8.8
const Z1 := 10.4

var _gym: Node
var _frames: int = 0
var _done: bool = false


func _init() -> void:
	var packed: PackedScene = load("res://scenes/gym/gym.tscn")
	_gym = packed.instantiate()
	root.add_child(_gym)


func _process(_dt: float) -> bool:
	if _done:
		return true
	_frames += 1
	if _frames < 8:
		return false
	_done = true
	_probe(_gym)
	quit()
	return true


func _probe(gym: Node) -> void:
	var world: World3D = gym.get_world_3d()
	if world == null:
		print("NO_WORLD")
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = R
	cap.height = 1.7
	var nx := int(floor((X1 - X0) / STEP)) + 1
	var nz := int(floor((Z1 - Z0) / STEP)) + 1
	var free := PackedByteArray()
	free.resize(nx * nz)
	var hits := 0
	var open := 0
	for iz in nz:
		for ix in nx:
			var p := Vector3(X0 + float(ix) * STEP, Y, Z0 + float(iz) * STEP)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, p)
			q.collision_mask = 1
			q.collide_with_areas = false
			var got: Array = space.intersect_shape(q, 1)
			var ok := got.is_empty()
			free[iz * nx + ix] = 1 if ok else 0
			if ok:
				open += 1
			else:
				hits += 1
	var sx := clampi(int(round((0.0 - X0) / STEP)), 0, nx - 1)
	var sz := clampi(int(round((7.6 - Z0) / STEP)), 0, nz - 1)
	var start := sz * nx + sx
	if free[start] == 0:
		start = _nearest_free(free, nx, nz, sx, sz)
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var qarr: Array[int] = [start]
	seen[start] = 1
	var qi := 0
	while qi < qarr.size():
		var i: int = qarr[qi]
		qi += 1
		var cx: int = i % nx
		var cz: int = int(i / nx)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x2: int = cx + d.x
			var z2: int = cz + d.y
			if x2 < 0 or z2 < 0 or x2 >= nx or z2 >= nz:
				continue
			var j: int = z2 * nx + x2
			if seen[j] == 1 or free[j] == 0:
				continue
			seen[j] = 1
			qarr.append(j)
	var reach := qarr.size()
	var lines: PackedStringArray = []
	lines.append("GRID %d x %d step=%.2f open=%d blocked=%d reach=%d" % [nx, nz, STEP, open, hits, reach])
	var player: Node3D = gym.get_node_or_null("Player")
	if player:
		var cb := player as CharacterBody3D
		lines.append("PLAYER_POS %s on_floor=%s" % [str(player.global_position), str(cb.is_on_floor() if cb else "?")])
	var rooms: Dictionary = {
		"spawn": Vector3(0.0, 0.0, 7.6),
		"hall": Vector3(0.0, 0.0, 0.0),
		"door_recep": Vector3(0.0, 0.0, 5.1),
		"door_shop": Vector3(0.0, 0.0, -5.1),
		"door_lock": Vector3(-8.1, 0.0, 0.0),
		"door_cardio": Vector3(8.1, 0.0, 0.0),
		"door_wc": Vector3(-4.1, 0.0, 7.5),
		"door_sauna": Vector3(-13.05, 0.0, -4.1),
		"wc": Vector3(-6.1, 0.0, 8.0),
		"lockers": Vector3(-11.0, 0.0, 0.0),
		"sauna": Vector3(-12.0, 0.0, -6.2),
		"cardio": Vector3(11.0, 0.0, 0.0),
		"shop": Vector3(0.0, 0.0, -7.6),
	}
	for k in rooms.keys():
		lines.append(_mark(k, rooms[k], free, seen, nx, nz))
	var st_root: Node = gym.get_node_or_null("StationsMount")
	if st_root:
		_walk_named(st_root, "EMP_Station", lines, free, seen, nx, nz)
	var props: Node = gym.get_node_or_null("Props")
	if props:
		for n in props.get_children():
			if n is Node3D:
				lines.append(_mark("prop:" + n.name, (n as Node3D).global_position, free, seen, nx, nz, 1.35))
	var blocked := 0
	for s in lines:
		if s.begins_with("BLOCK"):
			blocked += 1
	lines.append("SUMMARY reach=%d / open=%d blocked_targets=%d" % [reach, open, blocked])
	var text := "\n".join(lines)
	print(text)
	var f := FileAccess.open("res://tools/walk_result.txt", FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


func _nearest_free(free: PackedByteArray, nx: int, nz: int, sx: int, sz: int) -> int:
	var best := sz * nx + sx
	var bd := 999
	for iz in nz:
		for ix in nx:
			if free[iz * nx + ix] == 0:
				continue
			var d: int = absi(ix - sx) + absi(iz - sz)
			if d < bd:
				bd = d
				best = iz * nx + ix
	return best


func _idx(x: float, z: float, nx: int, nz: int) -> int:
	var ix := clampi(int(round((x - X0) / STEP)), 0, nx - 1)
	var iz := clampi(int(round((z - Z0) / STEP)), 0, nz - 1)
	return iz * nx + ix


func _mark(name: String, pos: Vector3, free: PackedByteArray, seen: PackedByteArray, nx: int, nz: int, near: float = 0.9) -> String:
	var i := _idx(pos.x, pos.z, nx, nz)
	if seen[i] == 1:
		return "OK %s (%.2f, %.2f)" % [name, pos.x, pos.z]
	var r := int(ceil(near / STEP))
	var ix := i % nx
	var iz := int(i / nx)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x2: int = ix + dx
			var z2: int = iz + dz
			if x2 < 0 or z2 < 0 or x2 >= nx or z2 >= nz:
				continue
			var j: int = z2 * nx + x2
			if seen[j] == 1:
				return "NEAR %s (%.2f, %.2f) via (%.2f, %.2f)" % [name, pos.x, pos.z, X0 + float(x2) * STEP, Z0 + float(z2) * STEP]
	if free[i] == 1:
		return "BLOCK %s (%.2f, %.2f) cell_free_but_unreachable" % [name, pos.x, pos.z]
	return "BLOCK %s (%.2f, %.2f) inside_collider" % [name, pos.x, pos.z]


func _walk_named(n: Node, prefix: String, lines: PackedStringArray, free: PackedByteArray, seen: PackedByteArray, nx: int, nz: int) -> void:
	if n is Node3D and n.name.begins_with(prefix):
		lines.append(_mark("st:" + n.name, (n as Node3D).global_position, free, seen, nx, nz, 1.5))
	for c in n.get_children():
		_walk_named(c, prefix, lines, free, seen, nx, nz)
