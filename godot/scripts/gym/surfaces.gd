extends RefCounted
## Albedo correction for the gym's imported materials.
##
## The Blender build authors the room nearly black — walls 0.16, rubber floor
## 0.07, iron 0.18 — which under the gym's dim lighting collapses into an unlit
## grey mush where nothing reads. These multipliers lift the darkest surfaces to
## where the shapes are legible without turning the basement into a showroom.
##
## Deliberately colour only: no texture maps, no triplanar. Detail maps cost
## sampling on every surface of a WebGL2 phone build, and the flat-shaded look
## is the game's style rather than a gap in it.

## Multiplier on the authored albedo.
const TABLE := {
	"MAT_RubberFloor": 1.25,
	"MAT_Wall": 1.5,
	"MAT_Concrete": 1.1,
	"MAT_Trim": 1.15,
	"MAT_PaintWarm": 1.5,
	"MAT_PaintCool": 1.5,
	# Iron is over a quarter of the gym's triangles and was nearly black.
	"MAT_Iron": 1.2,
	"MAT_Plate": 1.6,
	"MAT_Leather": 1.7,
	"MAT_Wood": 1.2,
	"MAT_SaunaWood": 1.1,
	"MAT_SaunaBench": 1.1,
	"MAT_SaunaStone": 1.3,
}


## Walk an instanced GLB scene and correct every material the table knows about.
## Materials are shared resources, so `done` keeps each one from being processed
## once per mesh that uses it.
static func apply(root: Node, done: Dictionary) -> void:
	for mi in _meshes(root):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if not mat is StandardMaterial3D:
				continue
			var std := mat as StandardMaterial3D
			if not TABLE.has(std.resource_name) or done.has(std.get_instance_id()):
				continue
			done[std.get_instance_id()] = true
			var mul := float(TABLE[std.resource_name])
			var c := std.albedo_color
			std.albedo_color = Color(minf(c.r * mul, 1.0), minf(c.g * mul, 1.0), minf(c.b * mul, 1.0), c.a)


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var acc: Array[MeshInstance3D] = []
	_walk(n, acc)
	return acc


static func _walk(n: Node, acc: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		acc.append(n as MeshInstance3D)
	for c in n.get_children():
		_walk(c, acc)
