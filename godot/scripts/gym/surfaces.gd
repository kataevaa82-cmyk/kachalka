extends RefCounted
## Procedural surface detail for the gym.
##
## The Blender build ships no texture maps: every one of the ~30 materials is a
## flat colour, which is why the room reads as moulded plastic. Rather than add
## megabytes of image files to a web build, this synthesises a handful of small
## greyscale maps at boot — the same trick the audio autoload uses — and hangs
## them on the imported materials.
##
## The Blender smart-UV unwrap normalises each object's UVs to 0..1, so a tiled
## map would come out a different size on every object. Architecture therefore
## uses triplanar mapping (world-space, ignores UVs); props keep plain UVs,
## where an inconsistent grain scale is not noticeable.

const SIZE := 96

## Average brightness of every generated map. Albedo is divided by it so the
## authored colour survives the multiply; keeping it near white means even light
## materials can carry the detail without their colour clipping at 1.0.
const MEAN := 0.8

## tex, uv scale, albedo multiplier, roughness delta, triplanar
const TABLE := {
	# Architecture: big flat spans that need world-consistent detail.
	"MAT_RubberFloor": ["speckle", 2.6, 1.25, 0.0, true],
	"MAT_Wall": ["grain", 1.9, 1.5, 0.0, true],
	"MAT_Concrete": ["grain", 1.8, 1.1, 0.0, true],
	"MAT_Trim": ["grain", 2.2, 1.15, 0.0, true],
	"MAT_PaintWarm": ["grain", 2.0, 1.5, 0.0, true],
	"MAT_PaintCool": ["grain", 2.0, 1.5, 0.0, true],
	# Iron is over a quarter of the gym's triangles and was nearly black.
	"MAT_Iron": ["brush", 2.4, 1.2, -0.04, false],
	"MAT_Plate": ["brush", 2.0, 1.6, -0.04, false],
	"MAT_Chrome": ["brush", 2.6, 1.0, -0.03, false],
	"MAT_LockerSteel": ["brush", 2.2, 1.05, -0.03, false],
	"MAT_StallEdge": ["brush", 2.2, 1.0, 0.0, false],
	"MAT_Stall": ["grain", 1.6, 1.05, 0.0, false],
	"MAT_Leather": ["grain", 2.2, 1.7, 0.0, false],
	"MAT_Tank": ["grain", 2.0, 1.0, 0.0, false],
	"MAT_Wood": ["planks", 1.8, 1.2, 0.0, false],
	"MAT_SaunaWood": ["planks", 1.6, 1.1, 0.0, false],
	"MAT_SaunaBench": ["planks", 1.6, 1.1, 0.0, false],
	"MAT_SaunaStone": ["speckle", 2.4, 1.3, 0.0, false],
}

static var _cache: Dictionary = {}


static func _hash(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 1442695040888963407) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## Value noise: lattice hash with smooth interpolation, summed over octaves.
static func _noise(x: float, y: float, freq: float, salt: int) -> float:
	var fx := x * freq
	var fy := y * freq
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := lerpf(_hash(x0, y0, salt), _hash(x0 + 1, y0, salt), tx)
	var b := lerpf(_hash(x0, y0 + 1, salt), _hash(x0 + 1, y0 + 1, salt), tx)
	return lerpf(a, b, ty)


static func _texture(kind: String) -> ImageTexture:
	if _cache.has(kind):
		return _cache[kind]
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 3)
	for py in SIZE:
		for px in SIZE:
			var u := float(px) / float(SIZE)
			var v := float(py) / float(SIZE)
			var t := 0.5
			match kind:
				"grain":
					# Plaster tooth. Kept quiet on purpose: at full contrast a
					# noise map on every wall reads as television static.
					t = 0.5 + (_noise(u, v, 38.0, 1) - 0.5) * 0.085
					t += (_noise(u, v, 11.0, 2) - 0.5) * 0.03
				"speckle":
					# Rubber flooring: dark mat with lighter flecks pressed in.
					var base := 0.48 + (_noise(u, v, 12.0, 3) - 0.5) * 0.07
					var fleck: float = _noise(u, v, 52.0, 4)
					t = base + (0.30 if fleck > 0.80 else 0.0) * (fleck - 0.80) * 2.0
				"brush":
					# Brushed metal: streaks along U, slow variation across V.
					t = 0.5 + (_noise(u * 34.0, v, 7.0, 5) - 0.5) * 0.17
					t += (_noise(u, v, 4.0, 6) - 0.5) * 0.06
				"planks":
					# Timber: bands across V with grain running along U.
					var band := fposmod(v * 5.0, 1.0)
					var edge: float = smoothstep(0.0, 0.05, band) * smoothstep(1.0, 0.95, band)
					t = 0.40 + edge * 0.18
					t += (_noise(u * 18.0, v, 11.0, 7) - 0.5) * 0.10
			# Re-centre on MEAN instead of 0.5, keeping relative contrast. A map
			# centred on 0.5 needs its albedo doubled to stay the same brightness,
			# and doubling clamps for anything already lighter than 0.5 — chrome
			# and brushed aluminium came out a third darker than authored.
			t = MEAN + (t - 0.5) * (MEAN / 0.5)
			var c := int(clampf(t, 0.0, 1.0) * 255.0)
			var o := (py * SIZE + px) * 3
			data[o] = c
			data[o + 1] = c
			data[o + 2] = c
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, data)
	var tex := ImageTexture.create_from_image(img)
	_cache[kind] = tex
	return tex


## Walk an instanced GLB scene and dress every material the table knows about.
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
			var key := std.resource_name
			if not TABLE.has(key) or done.has(std.get_instance_id()):
				continue
			done[std.get_instance_id()] = true
			var rule: Array = TABLE[key]
			std.albedo_texture = _texture(str(rule[0]))
			var scale := float(rule[1])
			std.uv1_scale = Vector3(scale, scale, scale)
			std.uv1_triplanar = bool(rule[4])
			# Undo the map's average darkening, then apply the artistic lift, so
			# rule[2] reads as a plain multiplier on the authored colour.
			std.albedo_color = _lift(std.albedo_color, float(rule[2]) / MEAN)
			std.roughness = clampf(std.roughness + float(rule[3]), 0.0, 1.0)


static func _lift(c: Color, mul: float) -> Color:
	return Color(minf(c.r * mul, 1.0), minf(c.g * mul, 1.0), minf(c.b * mul, 1.0), c.a)


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var acc: Array[MeshInstance3D] = []
	_walk(n, acc)
	return acc


static func _walk(n: Node, acc: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		acc.append(n as MeshInstance3D)
	for c in n.get_children():
		_walk(c, acc)
