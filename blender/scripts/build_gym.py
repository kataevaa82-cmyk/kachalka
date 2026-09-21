# KACHALKA gym build — Blender 5.2
# Law: 1 BU = 1 metre. Idempotent. Principled BSDF only.
# Run via MCP or: blender --background --python build_gym.py

import bpy
import bmesh
import math
import os
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
EXPORT_DIR = os.path.join(ROOT, "blender", "export")
GODOT_MODELS = os.path.join(ROOT, "godot", "assets", "models")
BLEND_PATH = os.path.join(ROOT, "blender", "kachalka_gym.blend")
SHOT_DIR = os.path.join(ROOT, "blender", "screenshots")
VENDOR_FURN = os.path.join(ROOT, "blender", "vendor", "kenney_furniture", "Models", "GLTF format")
VENDOR_FOOD = os.path.join(ROOT, "blender", "vendor", "kenney_food", "Models", "GLB format")
FURN_SCALE = 2.15

ROOM_W = 16.0
ROOM_D = 10.0
ROOM_H = 4.2
WALL_T = 0.20
GRID = 2.0
DOOR_W = 1.6
DOOR_H = 2.15
H_RECEP = 3.15
H_LOCK = 3.35
H_CARD = 3.55
H_BAR = 3.25
H_SAUNA = 2.55

COLLECTIONS = [
    "COL_Kachalka",
    "COL_Reference",
    "COL_Geo_Env",
    "COL_Geo_Props",
    "COL_Geo_Hero",
    "COL_Collision",
    "COL_Stations",
    "COL_Lights",
    "COL_Cameras",
]

PALETTE = {
    "rubber": (0.07, 0.07, 0.08),
    "lane": (0.85, 0.72, 0.12),
    "wall": (0.16, 0.17, 0.19),
    "trim": (0.28, 0.29, 0.32),
    "cyan": (0.15, 0.85, 0.95),
    "mag": (0.95, 0.18, 0.55),
    "iron": (0.18, 0.19, 0.21),
    "chrome": (0.72, 0.74, 0.78),
    "plate": (0.05, 0.05, 0.06),
    "pad": (0.12, 0.12, 0.13),
    "skin": (0.76, 0.55, 0.42),
    "tank": (0.78, 0.10, 0.12),
    "shorts": (0.10, 0.10, 0.12),
    "shoe": (0.92, 0.92, 0.94),
    "hair": (0.08, 0.06, 0.05),
    "glass": (0.55, 0.72, 0.85),
    "poster": (1.0, 0.45, 0.10),
    "fridge": (0.22, 0.78, 0.38),
    "wood": (0.32, 0.20, 0.12),
    "concrete": (0.38, 0.37, 0.35),
}


def ensure_object_mode():
    if bpy.context.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def deselect_all():
    ensure_object_mode()
    bpy.ops.object.select_all(action="DESELECT")


def link_exclusive(obj, col_name):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    bpy.data.collections[col_name].objects.link(obj)


def ensure_collections():
    root = bpy.data.collections.get("COL_Kachalka")
    if root is None:
        root = bpy.data.collections.new("COL_Kachalka")
        bpy.context.scene.collection.children.link(root)
    for name in COLLECTIONS:
        if name == "COL_Kachalka":
            continue
        col = bpy.data.collections.get(name)
        if col is None:
            col = bpy.data.collections.new(name)
            root.children.link(col)
    return root


def nuke_production():
    ensure_object_mode()
    keep_world_cams = False
    names = [o.name for o in bpy.data.objects]
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None:
            continue
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for arm in list(bpy.data.armatures):
        if arm.users == 0:
            bpy.data.armatures.remove(arm)
    for act in list(bpy.data.actions):
        if act.users == 0:
            bpy.data.actions.remove(act)


def set_pbr(mat, color, metallic=0.0, roughness=0.5, emission=None, emission_str=0.0, alpha=1.0):
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = None
    for n in nt.nodes:
        if n.type == "BSDF_PRINCIPLED":
            bsdf = n
            break
    if bsdf is None:
        return
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 1.0:
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    if emission is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = (emission[0], emission[1], emission[2], 1.0)
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_str


def mat(name, color, metallic=0.0, roughness=0.5, emission=None, emission_str=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    set_pbr(m, color, metallic, roughness, emission, emission_str, alpha)
    return m


def assign_mat(obj, material):
    obj.data.materials.clear()
    obj.data.materials.append(material)


def sample_image_avg(img, step=23):
    w, h = img.size
    if w == 0 or h == 0:
        return (0.5, 0.5, 0.5, 1.0)
    px = img.pixels
    acc = [0.0, 0.0, 0.0]
    n = 0
    lim = len(px)
    i = 0
    while i + 2 < lim:
        acc[0] += px[i]
        acc[1] += px[i + 1]
        acc[2] += px[i + 2]
        n += 1
        i += 4 * step
    if n == 0:
        return (0.5, 0.5, 0.5, 1.0)
    return (acc[0] / n, acc[1] / n, acc[2] / n, 1.0)


def solidify_mesh(obj):
    """Drop image textures; keep a flat PBR color so GLB stays small."""
    if obj is None or obj.type != "MESH":
        return
    for mat in obj.data.materials:
        if mat is None or not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = None
        texs = []
        for n in nt.nodes:
            if n.type == "BSDF_PRINCIPLED":
                bsdf = n
            elif n.type == "TEX_IMAGE":
                texs.append(n)
        if bsdf and texs and texs[0].image:
            bsdf.inputs["Base Color"].default_value = sample_image_avg(texs[0].image)
        for n in texs:
            nt.nodes.remove(n)
        if bsdf is None:
            continue
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 0.0
        if bsdf.inputs["Roughness"].default_value < 0.32:
            bsdf.inputs["Roughness"].default_value = 0.38
        if bsdf.inputs["Metallic"].default_value > 0.55:
            bsdf.inputs["Metallic"].default_value = 0.45


def purge_images():
    for img in list(bpy.data.images):
        try:
            bpy.data.images.remove(img)
        except Exception:
            pass


def shade(obj, angle=40.0):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(angle))
    except Exception:
        bpy.ops.object.shade_smooth()


def add_bevel(obj, width=0.007, segs=3):
    if obj is None or obj.type != "MESH":
        return
    bev = obj.modifiers.new("Bevel", "BEVEL")
    bev.width = width
    bev.segments = segs
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(30)
    bev.affect = "EDGES"
    bev.miter_outer = "MITER_ARC"


def apply_mods(obj):
    ensure_object_mode()
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for n in [m.name for m in list(obj.modifiers)]:
        try:
            bpy.ops.object.modifier_apply(modifier=n)
        except Exception:
            pass


def apply_sr(obj):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def origin_floor(obj):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    mw = obj.matrix_world
    corners = [mw @ Vector(c) for c in obj.bound_box]
    min_z = min(v.z for v in corners)
    cx = 0.5 * (min(v.x for v in corners) + max(v.x for v in corners))
    cy = 0.5 * (min(v.y for v in corners) + max(v.y for v in corners))
    bpy.context.scene.cursor.location = (cx, cy, min_z)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    obj.location.z = 0.0


def import_glb(path, name, loc, col, scale=1.0, rot=(0, 0, 0), solidify=True):
    if not os.path.isfile(path):
        print("MISSING_GLB", path)
        return None
    ensure_object_mode()
    deselect_all()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    leftovers = [o.name for o in new if o.type != "MESH"]
    if not meshes:
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        print("NOMESH_GLB", path)
        return None
    deselect_all()
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    try:
        bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    except Exception:
        pass
    deselect_all()
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    if isinstance(scale, (int, float)):
        obj.scale = (scale, scale, scale)
    else:
        obj.scale = scale
    apply_sr(obj)
    origin_floor(obj)
    obj.rotation_mode = "XYZ"
    obj.location = Vector(loc)
    obj.rotation_euler = rot
    obj.name = name
    if obj.data:
        obj.data.name = name
    link_exclusive(obj, col)
    for n in leftovers:
        o = bpy.data.objects.get(n)
        if o is not None and o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    if solidify:
        solidify_mesh(obj)
    return obj


def food(filename, name, loc, col, scale=1.0, rot=(0, 0, 0)):
    return import_glb(os.path.join(VENDOR_FOOD, filename), name, loc, col, scale, rot, solidify=False)


def kenney_furn(filename, name, loc, col, scale=FURN_SCALE, rot=(0, 0, 0)):
    # After glTF import: sit / screen / cabinet front = local -Y.
    # Toilet bowl = local +Y (tank at -Y). rotZ +90: -Y → world +X; -90: -Y → world -X.
    return import_glb(os.path.join(VENDOR_FURN, filename), name, loc, col, scale, rot)


def flush_double_door(name, y, wood, metal, chrome):
    """Closed double doors that fill the 1.6 x 2.15 opening in a Y-facing wall."""
    box(name + "_L", (0.78, 0.05, 2.12), (-0.40, y, 1.06), "COL_Geo_Env", wood)
    box(name + "_R", (0.78, 0.05, 2.12), (0.40, y, 1.06), "COL_Geo_Env", wood)
    box(name + "_Bar", (1.56, 0.03, 0.06), (0.0, y, 1.06), "COL_Geo_Env", metal)
    cyl(name + "_HL", 0.018, 0.14, (-0.10, y + 0.04, 1.06), "COL_Geo_Env", chrome, rot=(math.radians(90), 0, 0), segs=8)
    cyl(name + "_HR", 0.018, 0.14, (0.10, y + 0.04, 1.06), "COL_Geo_Env", chrome, rot=(math.radians(90), 0, 0), segs=8)


def smart_uv(obj):
    deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=66.0, island_margin=0.03)
    bpy.ops.object.mode_set(mode="OBJECT")


def box(name, size, loc, col, material, rot=(0, 0, 0), bevel=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = size
    apply_sr(obj)
    assign_mat(obj, material)
    smallest = min(size)
    largest = max(size)
    bw = bevel
    if bw is None and smallest >= 0.05 and largest >= 0.28:
        bw = min(0.01, smallest * 0.18)
    if bw and bw > 0.0:
        add_bevel(obj, bw, 1)
        apply_mods(obj)
    shade(obj)
    link_exclusive(obj, col)
    return obj


def cyl(name, radius, depth, loc, col, material, rot=(0, 0, 0), segs=24):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=loc, rotation=rot, vertices=segs
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    apply_sr(obj)
    assign_mat(obj, material)
    shade(obj, 40)
    link_exclusive(obj, col)
    return obj


def uvsp(name, radius, loc, col, material, scale=(1, 1, 1), segs=20):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=segs, ring_count=max(10, segs // 2))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = scale
    apply_sr(obj)
    assign_mat(obj, material)
    shade(obj, 30)
    link_exclusive(obj, col)
    return obj


def plane(name, size, loc, col, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = (size[0], size[1], 1.0)
    apply_sr(obj)
    assign_mat(obj, material)
    link_exclusive(obj, col)
    return obj


def join_named(target_name, objects, col, floor=True):
    ensure_object_mode()
    deselect_all()
    if not objects:
        return None
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.active_object
    obj.name = target_name
    obj.data.name = target_name
    link_exclusive(obj, col)
    if floor:
        origin_floor(obj)
    shade(obj, 35)
    return obj


def wall_x(name, x, y0, y1, h, material, door_y=None):
    y_lo, y_hi = (min(y0, y1), max(y0, y1))
    if door_y is None:
        box(name, (WALL_T, y_hi - y_lo, h), (x, 0.5 * (y_lo + y_hi), h * 0.5), "COL_Geo_Env", material)
        return
    d0, d1 = door_y - DOOR_W * 0.5, door_y + DOOR_W * 0.5
    if d0 - y_lo > 0.15:
        wall_x(name + "_A", x, y_lo, d0, h, material)
    if y_hi - d1 > 0.15:
        wall_x(name + "_B", x, d1, y_hi, h, material)
    lint_h = max(0.2, h - DOOR_H)
    box(name + "_Lintel", (WALL_T, DOOR_W + 0.08, lint_h), (x, door_y, DOOR_H + lint_h * 0.5), "COL_Geo_Env", material)
    box(name + "_Frame", (WALL_T + 0.04, DOOR_W + 0.16, 0.08), (x, door_y, DOOR_H), "COL_Geo_Env", material)


def wall_y(name, y, x0, x1, h, material, door_x=None):
    x_lo, x_hi = (min(x0, x1), max(x0, x1))
    if door_x is None:
        box(name, (x_hi - x_lo, WALL_T, h), (0.5 * (x_lo + x_hi), y, h * 0.5), "COL_Geo_Env", material)
        return
    d0, d1 = door_x - DOOR_W * 0.5, door_x + DOOR_W * 0.5
    if d0 - x_lo > 0.15:
        wall_y(name + "_A", y, x_lo, d0, h, material)
    if x_hi - d1 > 0.15:
        wall_y(name + "_B", y, d1, x_hi, h, material)
    lint_h = max(0.2, h - DOOR_H)
    box(name + "_Lintel", (DOOR_W + 0.08, WALL_T, lint_h), (door_x, y, DOOR_H + lint_h * 0.5), "COL_Geo_Env", material)
    box(name + "_Frame", (DOOR_W + 0.16, WALL_T + 0.04, 0.08), (door_x, y, DOOR_H), "COL_Geo_Env", material)


def room_floor(name, cx, cy, sx, sy, material, z=0.0):
    f = box(name, (sx, sy, 0.10), (cx, cy, z - 0.05), "COL_Geo_Env", material)
    f.location.z = z - 0.10
    return f


def room_ceil(name, cx, cy, sx, sy, h, material):
    box(name, (sx, sy, 0.10), (cx, cy, h + 0.05), "COL_Geo_Env", material)


def empty_station(name, loc, station_id, display, muscle):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=loc)
    emp = bpy.context.active_object
    emp.name = name
    emp.empty_display_size = 0.4
    emp["station_id"] = station_id
    emp["display_name"] = display
    emp["muscle"] = muscle
    link_exclusive(emp, "COL_Stations")
    return emp


def tri_count(obj):
    if obj.type != "MESH":
        return 0
    return sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)


def make_materials():
    lib = {}
    lib["rubber"] = mat("MAT_RubberFloor", PALETTE["rubber"], 0.0, 0.88)
    lib["lane"] = mat("MAT_Lane", PALETTE["lane"], 0.05, 0.45)
    lib["wall"] = mat("MAT_Wall", PALETTE["wall"], 0.0, 0.72)
    lib["trim"] = mat("MAT_Trim", PALETTE["trim"], 0.1, 0.5)
    lib["iron"] = mat("MAT_Iron", PALETTE["iron"], 0.45, 0.52)
    lib["chrome"] = mat("MAT_Chrome", PALETTE["chrome"], 0.55, 0.38)
    lib["plate"] = mat("MAT_Plate", PALETTE["plate"], 0.40, 0.48)
    lib["pad"] = mat("MAT_Pad", PALETTE["pad"], 0.0, 0.7)
    lib["skin"] = mat("MAT_Skin", PALETTE["skin"], 0.0, 0.55)
    lib["tank"] = mat("MAT_Tank", PALETTE["tank"], 0.0, 0.62)
    lib["shorts"] = mat("MAT_Shorts", PALETTE["shorts"], 0.0, 0.68)
    lib["shoe"] = mat("MAT_Shoe", PALETTE["shoe"], 0.05, 0.4)
    lib["hair"] = mat("MAT_Hair", PALETTE["hair"], 0.0, 0.7)
    lib["glass"] = mat("MAT_Glass", PALETTE["glass"], 0.05, 0.05, alpha=0.35)
    lib["mirror"] = mat("MAT_Mirror", (0.7, 0.75, 0.8), 1.0, 0.04)
    lib["cyan_e"] = mat("MAT_NeonCyan", (0.22, 0.42, 0.48), 0.05, 0.55)
    lib["mag_e"] = mat("MAT_NeonMag", (0.48, 0.22, 0.32), 0.05, 0.55)
    lib["poster"] = mat("MAT_Poster", (0.42, 0.28, 0.18), 0.0, 0.58)
    lib["fridge"] = mat("MAT_Fridge", PALETTE["fridge"], 0.3, 0.35)
    lib["wood"] = mat("MAT_Wood", PALETTE["wood"], 0.0, 0.65)
    lib["concrete"] = mat("MAT_Concrete", PALETTE["concrete"], 0.0, 0.9)
    lib["sign"] = mat("MAT_Sign", (0.78, 0.80, 0.82), 0.05, 0.48)
    return lib


def phase_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"
    scene.render.fps = 30
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except Exception:
        try:
            scene.render.engine = "BLENDER_EEVEE_NEXT"
        except Exception:
            scene.render.engine = "CYCLES"
    scene.frame_start = 1
    scene.frame_end = 60
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.018, 0.02, 0.028, 1.0)
        bg.inputs[1].default_value = 0.35
    nuke_production()
    ensure_collections()


def phase_reference(lib):
    dummy = box("REF_Human_175cm", (0.4, 0.28, 1.75), (0.0, 0.0, 0.875), "COL_Reference", lib["skin"])
    dummy.display_type = "WIRE"
    dummy.hide_render = True
    dummy["role"] = "scale_reference"


def phase_environment(lib):
    mat_wood = mat("MAT_FloorWood", (0.28, 0.18, 0.10), 0.0, 0.62)
    mat_lock = mat("MAT_FloorLock", (0.12, 0.14, 0.18), 0.0, 0.8)
    mat_card = mat("MAT_FloorCardio", (0.10, 0.16, 0.18), 0.0, 0.72)
    mat_bar = mat("MAT_FloorBar", (0.10, 0.16, 0.11), 0.0, 0.7)
    mat_pad = mat("MAT_WallPad", (0.22, 0.23, 0.26), 0.0, 0.78)
    mat_paint = mat("MAT_PaintWarm", (0.22, 0.18, 0.14), 0.0, 0.78)
    mat_paint_c = mat("MAT_PaintCool", (0.14, 0.18, 0.22), 0.0, 0.78)

    # --- Main weights hall X±8 Y±5 ---
    room_floor("SM_Env_Floor_Main", 0.0, 0.0, 16.2, 10.2, lib["rubber"])
    room_ceil("SM_Env_Ceil_Main", 0.0, 0.0, 16.2, 10.2, ROOM_H, lib["trim"])
    wall_y("SM_Env_Main_N", 5.1, -8.1, 8.1, ROOM_H, lib["wall"], door_x=0.0)
    wall_y("SM_Env_Main_S", -5.1, -8.1, 8.1, ROOM_H, lib["wall"], door_x=0.0)
    wall_x("SM_Env_Main_W", -8.1, -5.1, 5.1, ROOM_H, lib["wall"], door_y=0.0)
    wall_x("SM_Env_Main_E", 8.1, -5.1, 5.1, ROOM_H, lib["wall"], door_y=0.0)

    n = 0
    for ix in range(-3, 4):
        for iy in range(-2, 3):
            n += 1
            col = lib["rubber"] if (ix + iy) % 2 == 0 else lib["trim"]
            box(f"SM_Env_Tile_{n}", (1.92, 1.92, 0.016), (ix * 2.0, iy * 2.0, 0.01), "COL_Geo_Env", col, bevel=0.0)

    for i, x in enumerate((-4.0, 0.0, 4.0)):
        box(f"SM_Env_Lane_{i}", (0.10, 8.6, 0.008), (x, 0.0, 0.02), "COL_Geo_Env", lib["lane"])

    for i, (cx, cy) in enumerate(((-3.6, -2.2), (3.6, -2.2), (-3.6, 2.2), (3.6, 2.2))):
        cyl(f"SM_Env_Col_{i}", 0.16, ROOM_H - 0.18, (cx, cy, ROOM_H * 0.5), "COL_Geo_Env", lib["concrete"], segs=16)
        cyl(f"SM_Env_ColBase_{i}", 0.22, 0.10, (cx, cy, 0.05), "COL_Geo_Env", lib["iron"], segs=12)
        cyl(f"SM_Env_ColCap_{i}", 0.20, 0.08, (cx, cy, ROOM_H - 0.14), "COL_Geo_Env", lib["iron"], segs=12)

    box("SM_Env_Sign_Kachalka", (3.4, 0.12, 0.55), (0.0, 4.92, 3.55), "COL_Geo_Env", lib["sign"])
    for i, (x, y) in enumerate(((-4, -2), (0, -2), (4, -2), (-4, 2), (0, 2), (4, 2))):
        cyl(f"SM_Env_Can_{i}", 0.18, 0.08, (x, y, ROOM_H - 0.08), "COL_Geo_Env", lib["iron"], segs=12)
        cyl(f"SM_Env_CanLens_{i}", 0.13, 0.02, (x, y, ROOM_H - 0.13), "COL_Geo_Env", lib["trim"], segs=10)

    # --- Reception south ---
    room_floor("SM_Env_Floor_Recep", 0.0, -7.55, 8.2, 5.1, mat_wood)
    room_ceil("SM_Env_Ceil_Recep", 0.0, -7.55, 8.2, 5.1, H_RECEP, mat_paint)
    wall_y("SM_Env_Recep_S", -10.1, -4.1, 4.1, H_RECEP, mat_paint, door_x=0.0)
    wall_x("SM_Env_Recep_W", -4.1, -10.1, -5.1, H_RECEP, mat_paint, door_y=-7.5)
    wall_x("SM_Env_Recep_E", 4.1, -10.1, -5.1, H_RECEP, mat_paint)
    flush_double_door("SM_Env_Recep_Door", -10.08, lib["wood"], lib["iron"], lib["chrome"])
    box("SM_Env_Recep_Sign", (1.6, 0.08, 0.32), (0.0, -9.96, 2.48), "COL_Geo_Env", lib["sign"])
    cyl("SM_Env_Can_Recep", 0.16, 0.07, (0.0, -7.5, H_RECEP - 0.08), "COL_Geo_Env", lib["iron"], segs=12)

    # WC west of reception
    mat_wc = mat("MAT_FloorWC", (0.18, 0.20, 0.22), 0.0, 0.55)
    room_floor("SM_Env_Floor_WC", -6.1, -7.55, 4.0, 5.1, mat_wc)
    room_ceil("SM_Env_Ceil_WC", -6.1, -7.55, 4.0, 5.1, H_RECEP, mat_paint)
    wall_x("SM_Env_WC_W", -8.1, -10.1, -5.1, H_RECEP, mat_paint)
    wall_y("SM_Env_WC_S", -10.1, -8.1, -4.1, H_RECEP, mat_paint)
    cyl("SM_Env_Can_WC", 0.14, 0.06, (-6.1, -7.5, H_RECEP - 0.08), "COL_Geo_Env", lib["iron"], segs=10)

    # --- Locker room west ---
    room_floor("SM_Env_Floor_Lock", -11.05, 0.0, 6.1, 8.2, mat_lock)
    room_ceil("SM_Env_Ceil_Lock", -11.05, 0.0, 6.1, 8.2, H_LOCK, mat_paint_c)
    wall_x("SM_Env_Lock_W", -14.1, -4.1, 4.1, H_LOCK, mat_paint_c)
    wall_y("SM_Env_Lock_S", -4.1, -14.1, -8.1, H_LOCK, mat_paint_c)
    wall_y("SM_Env_Lock_N", 4.1, -14.1, -8.1, H_LOCK, mat_paint_c, door_x=-13.05)
    cyl("SM_Env_Can_Lock", 0.16, 0.07, (-11.0, 0.0, H_LOCK - 0.08), "COL_Geo_Env", lib["iron"], segs=12)

    # --- Sauna north of lockers (enter through locker north door) ---
    cedar = mat("MAT_SaunaWood", (0.40, 0.24, 0.12), 0.0, 0.58)
    cedar_d = mat("MAT_SaunaWoodDark", (0.24, 0.13, 0.07), 0.0, 0.62)
    room_floor("SM_Env_Floor_Sauna", -12.00, 6.22, 4.40, 4.30, cedar_d)
    room_ceil("SM_Env_Ceil_Sauna", -12.00, 6.22, 4.40, 4.30, H_SAUNA, cedar)
    wall_x("SM_Env_Sauna_W", -14.20, 4.1, 8.35, H_SAUNA, cedar)
    wall_y("SM_Env_Sauna_N", 8.35, -14.20, -9.80, H_SAUNA, cedar)
    wall_x("SM_Env_Sauna_E", -9.80, 4.1, 8.35, H_SAUNA, cedar)
    # Wood jambs on the locker-side opening
    box("SM_Env_Sauna_JambL", (0.10, 0.18, 2.16), (-13.85, 4.10, 1.08), "COL_Geo_Env", cedar)
    box("SM_Env_Sauna_JambR", (0.10, 0.18, 2.16), (-12.25, 4.10, 1.08), "COL_Geo_Env", cedar)
    box("SM_Env_Sauna_Head", (1.72, 0.18, 0.12), (-13.05, 4.10, 2.20), "COL_Geo_Env", cedar)
    box("SM_Env_Sauna_Sign", (0.85, 0.06, 0.22), (-13.05, 3.98, 2.42), "COL_Geo_Env", lib["poster"])
    cyl("SM_Env_Can_Sauna", 0.12, 0.05, (-12.00, 6.22, H_SAUNA - 0.06), "COL_Geo_Env", lib["iron"], segs=10)

    # --- Cardio east ---
    room_floor("SM_Env_Floor_Cardio", 11.05, 0.0, 6.1, 8.2, mat_card)
    room_ceil("SM_Env_Ceil_Cardio", 11.05, 0.0, 6.1, 8.2, H_CARD, mat_paint_c)
    wall_x("SM_Env_Card_E", 14.1, -4.1, 4.1, H_CARD, mat_paint_c)
    wall_y("SM_Env_Card_S", -4.1, 8.1, 14.1, H_CARD, mat_paint_c)
    wall_y("SM_Env_Card_N", 4.1, 8.1, 14.1, H_CARD, mat_paint_c)
    for i, y in enumerate((-2.4, 0.0, 2.4)):
        box(f"SM_Env_CardWin_{i}", (0.06, 1.5, 1.3), (14.0, y, 1.9), "COL_Geo_Env", lib["glass"])
        box(f"SM_Env_CardWinF_{i}", (0.08, 1.65, 1.45), (14.05, y, 1.9), "COL_Geo_Env", lib["trim"])
    cyl("SM_Env_Can_Card", 0.16, 0.07, (11.0, 0.0, H_CARD - 0.08), "COL_Geo_Env", lib["iron"], segs=12)

    # --- Protein bar north ---
    room_floor("SM_Env_Floor_Bar", 0.0, 7.55, 10.2, 5.1, mat_bar)
    room_ceil("SM_Env_Ceil_Bar", 0.0, 7.55, 10.2, 5.1, H_BAR, lib["wall"])
    wall_y("SM_Env_Bar_N", 10.1, -5.1, 5.1, H_BAR, lib["wall"])
    wall_x("SM_Env_Bar_W", -5.1, 5.1, 10.1, H_BAR, lib["wall"])
    wall_x("SM_Env_Bar_E", 5.1, 5.1, 10.1, H_BAR, lib["wall"])
    box("SM_Env_Bar_Counter", (3.6, 0.62, 1.05), (0.0, 8.35, 0.52), "COL_Geo_Env", lib["wood"])
    box("SM_Env_Bar_Top", (3.7, 0.7, 0.06), (0.0, 8.35, 1.08), "COL_Geo_Env", lib["chrome"])
    cyl("SM_Env_Can_Bar", 0.16, 0.07, (0.0, 7.6, H_BAR - 0.08), "COL_Geo_Env", lib["iron"], segs=12)
    box("SM_Env_Bar_Sign", (2.2, 0.1, 0.45), (0.0, 10.0, 2.6), "COL_Geo_Env", lib["fridge"])
    # Shop entrance: open doorway, cream frame, no leaves, no mirror in the hole
    cream = mat("MAT_ShopFrame", (0.84, 0.80, 0.70), 0.05, 0.48)
    box("SM_Env_Shop_JambL", (0.10, 0.22, 2.18), (-0.86, 5.10, 1.09), "COL_Geo_Env", cream)
    box("SM_Env_Shop_JambR", (0.10, 0.22, 2.18), (0.86, 5.10, 1.09), "COL_Geo_Env", cream)
    box("SM_Env_Shop_Head", (1.76, 0.22, 0.12), (0.0, 5.10, 2.20), "COL_Geo_Env", cream)
    box("SM_Env_Shop_Sign", (1.35, 0.06, 0.28), (0.0, 4.96, 2.50), "COL_Geo_Env", lib["fridge"])
    box("SM_Env_Shop_Ledge", (1.10, 0.04, 0.06), (0.0, 4.95, 2.72), "COL_Geo_Env", cream)


def make_barbell(prefix, loc, col, lib, plate_r=0.225):
    parts = []
    bar = cyl(f"{prefix}_Bar", 0.016, 2.2, (loc[0], loc[1], loc[2]), col, lib["chrome"], rot=(0, math.radians(90), 0), segs=20)
    parts.append(bar)
    knurl = cyl(f"{prefix}_Knurl", 0.018, 0.42, loc, col, lib["iron"], rot=(0, math.radians(90), 0), segs=16)
    parts.append(knurl)
    for sx in (-0.88, 0.88):
        stack = (
            (0.00, plate_r, 0.045),
            (0.05, plate_r * 0.88, 0.035),
            (0.09, plate_r * 0.62, 0.032),
            (0.125, plate_r * 0.42, 0.028),
        )
        for ox, r, t in stack:
            px = loc[0] + sx + (ox if sx > 0 else -ox)
            p = cyl(f"{prefix}_Plate_{sx}_{ox}", r, t, (px, loc[1], loc[2]), col, lib["plate"], rot=(0, math.radians(90), 0), segs=28)
            parts.append(p)
            hub = cyl(f"{prefix}_Hub_{sx}_{ox}", 0.026, t + 0.004, (px, loc[1], loc[2]), col, lib["chrome"], rot=(0, math.radians(90), 0), segs=16)
            parts.append(hub)
        sleeve = cyl(f"{prefix}_Sleeve_{sx}", 0.028, 0.18, (loc[0] + sx * 1.05, loc[1], loc[2]), col, lib["chrome"], rot=(0, math.radians(90), 0), segs=16)
        colr = cyl(f"{prefix}_Collar_{sx}", 0.034, 0.04, (loc[0] + sx * 0.72, loc[1], loc[2]), col, lib["iron"], rot=(0, math.radians(90), 0), segs=16)
        parts += [sleeve, colr]
    return parts


def phase_stations(lib):
    leather = mat("MAT_Leather", (0.09, 0.09, 0.10), 0.0, 0.55)
    yellow = mat("MAT_Caution", (0.95, 0.74, 0.08), 0.08, 0.42)
    redpad = mat("MAT_GripRed", (0.62, 0.10, 0.12), 0.0, 0.5)
    bx, by = -5.5, -3.35
    parts = []
    parts.append(box("SM_Bench_Pad", (0.58, 1.28, 0.11), (bx, by - 0.05, 0.46), "COL_Geo_Props", leather))
    parts.append(box("SM_Bench_Back", (0.58, 0.38, 0.10), (bx, by + 0.62, 0.62), "COL_Geo_Props", leather))
    parts.append(box("SM_Bench_Rail", (0.12, 1.45, 0.06), (bx, by, 0.38), "COL_Geo_Props", lib["iron"]))
    parts.append(box("SM_Bench_LegA", (0.09, 0.09, 0.40), (bx, by - 0.55, 0.20), "COL_Geo_Props", lib["iron"]))
    parts.append(box("SM_Bench_LegB", (0.09, 0.09, 0.40), (bx, by + 0.50, 0.20), "COL_Geo_Props", lib["iron"]))
    parts.append(box("SM_Bench_Foot", (0.42, 0.14, 0.05), (bx, by - 0.55, 0.03), "COL_Geo_Props", lib["iron"]))
    parts.append(cyl("SM_Bench_UpL", 0.042, 1.22, (bx - 0.32, by + 0.58, 0.92), "COL_Geo_Props", lib["iron"], segs=12))
    parts.append(cyl("SM_Bench_UpR", 0.042, 1.22, (bx + 0.32, by + 0.58, 0.92), "COL_Geo_Props", lib["iron"], segs=12))
    parts.append(box("SM_Bench_Cross", (0.72, 0.07, 0.07), (bx, by + 0.58, 1.38), "COL_Geo_Props", lib["iron"]))
    parts.append(box("SM_Bench_HookL", (0.14, 0.05, 0.09), (bx - 0.32, by + 0.50, 1.28), "COL_Geo_Props", lib["chrome"]))
    parts.append(box("SM_Bench_HookR", (0.14, 0.05, 0.09), (bx + 0.32, by + 0.50, 1.28), "COL_Geo_Props", lib["chrome"]))
    parts.append(box("SM_Bench_Stripe", (0.62, 0.10, 0.03), (bx, by - 0.55, 0.42), "COL_Geo_Props", yellow))
    parts.append(box("SM_Bench_Tag", (0.22, 0.04, 0.10), (bx + 0.22, by - 0.55, 0.58), "COL_Geo_Props", lib["cyan_e"]))
    parts.append(box("SM_Bench_GripL", (0.05, 0.16, 0.05), (bx - 0.26, by - 0.62, 0.52), "COL_Geo_Props", lib["chrome"]))
    parts.append(box("SM_Bench_GripR", (0.05, 0.16, 0.05), (bx + 0.26, by - 0.62, 0.52), "COL_Geo_Props", lib["chrome"]))
    parts += make_barbell("SM_Bench", (bx, by + 0.55, 1.36), "COL_Geo_Props", lib)
    join_named("SM_Station_Bench", parts, "COL_Geo_Props")
    empty_station("EMP_Station_Bench", (bx, by - 0.35, 0.0), "bench", "Жим лёжа", "chest")

    # --- Squat rack (0, -3.6) ---
    sx, sy = 2.35, -3.35
    posts = []
    for px, py in ((-0.62, -0.48), (0.62, -0.48), (-0.62, 0.48), (0.62, 0.48)):
        posts.append(cyl(f"SM_Squat_Post_{px}_{py}", 0.048, 2.28, (sx + px, sy + py, 1.14), "COL_Geo_Props", lib["iron"], segs=12))
        posts.append(cyl(f"SM_Squat_Foot_{px}_{py}", 0.11, 0.06, (sx + px, sy + py, 0.03), "COL_Geo_Props", lib["iron"], segs=10))
        for zi, z in enumerate((0.70, 1.15, 1.60, 2.00)):
            posts.append(cyl(f"SM_Squat_Pin_{px}_{zi}", 0.014, 0.12, (sx + px, sy + py, z), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=8))
    for yoff, z in ((-0.48, 2.22), (0.48, 2.22), (-0.48, 0.10), (0.48, 0.10)):
        posts.append(box(f"SM_Squat_Cross_{yoff}_{z}", (1.36, 0.08, 0.08), (sx, sy + yoff, z), "COL_Geo_Props", lib["iron"]))
    posts.append(box("SM_Squat_SafetyL", (0.08, 0.95, 0.07), (sx - 0.55, sy, 0.74), "COL_Geo_Props", lib["chrome"]))
    posts.append(box("SM_Squat_SafetyR", (0.08, 0.95, 0.07), (sx + 0.55, sy, 0.74), "COL_Geo_Props", lib["chrome"]))
    posts.append(box("SM_Squat_JHookL", (0.16, 0.06, 0.10), (sx - 0.62, sy, 1.24), "COL_Geo_Props", lib["chrome"]))
    posts.append(box("SM_Squat_JHookR", (0.16, 0.06, 0.10), (sx + 0.62, sy, 1.24), "COL_Geo_Props", lib["chrome"]))
    posts.append(box("SM_Squat_Tag", (0.28, 0.05, 0.12), (sx, sy - 0.48, 2.08), "COL_Geo_Props", lib["mag_e"]))
    posts.append(box("SM_Squat_Stripe", (1.40, 0.06, 0.04), (sx, sy, 0.14), "COL_Geo_Props", yellow))
    posts += make_barbell("SM_Squat", (sx, sy, 1.30), "COL_Geo_Props", lib, plate_r=0.255)
    join_named("SM_Station_Squat", posts, "COL_Geo_Props")
    empty_station("EMP_Station_Squat", (sx, sy + 0.15, 0.0), "squat", "Присед", "legs")

    # --- Dumbbell rack (4.5, -3.2) ---
    dx, dy = 5.65, -3.35
    rack = []
    rack.append(box("SM_DB_Frame", (1.55, 0.48, 0.07), (dx, dy, 0.58), "COL_Geo_Props", lib["iron"]))
    rack.append(box("SM_DB_LegL", (0.08, 0.42, 0.58), (dx - 0.68, dy, 0.29), "COL_Geo_Props", lib["iron"]))
    rack.append(box("SM_DB_LegR", (0.08, 0.42, 0.58), (dx + 0.68, dy, 0.29), "COL_Geo_Props", lib["iron"]))
    rack.append(box("SM_DB_Shelf2", (1.55, 0.42, 0.06), (dx, dy, 0.30), "COL_Geo_Props", lib["iron"]))
    rack.append(box("SM_DB_Brace", (1.4, 0.05, 0.05), (dx, dy, 0.44), "COL_Geo_Props", lib["iron"]))
    for i, ox in enumerate((-0.52, -0.16, 0.20, 0.56)):
        for si, shelf_z in enumerate((0.66, 0.38)):
            rhead = 0.055 + i * 0.008
            hndl = cyl(f"SM_DB_H_{i}_{si}", 0.016, 0.30, (dx + ox, dy, shelf_z), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=14)
            l = cyl(f"SM_DB_L_{i}_{si}", rhead, 0.055, (dx + ox - 0.17, dy, shelf_z), "COL_Geo_Props", lib["plate"], rot=(0, math.radians(90), 0), segs=6)
            r = cyl(f"SM_DB_R_{i}_{si}", rhead, 0.055, (dx + ox + 0.17, dy, shelf_z), "COL_Geo_Props", lib["plate"], rot=(0, math.radians(90), 0), segs=6)
            rack += [hndl, l, r]
    rack.append(box("SM_DB_Tag", (0.36, 0.04, 0.10), (dx, dy - 0.22, 0.72), "COL_Geo_Props", lib["cyan_e"]))
    rack.append(box("SM_DB_Mat", (1.70, 0.70, 0.02), (dx, dy + 0.55, 0.015), "COL_Geo_Props", lib["rubber"]))
    join_named("SM_Station_Dumbbells", rack, "COL_Geo_Props")
    empty_station("EMP_Station_Dumbbells", (dx, dy + 0.7, 0.0), "dumbbell", "Гантели", "arms")

    # --- Pull-up (-4.5, 3.0) ---
    px, py = -5.5, 3.35
    pu = []
    pu.append(cyl("SM_PU_PostL", 0.055, 2.45, (px - 0.58, py, 1.22), "COL_Geo_Props", lib["iron"], segs=20))
    pu.append(cyl("SM_PU_PostR", 0.055, 2.45, (px + 0.58, py, 1.22), "COL_Geo_Props", lib["iron"], segs=20))
    pu.append(cyl("SM_PU_Bar", 0.022, 1.36, (px, py, 2.38), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=18))
    pu.append(cyl("SM_PU_GripL", 0.024, 0.18, (px - 0.28, py, 2.38), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=14))
    pu.append(cyl("SM_PU_GripR", 0.024, 0.18, (px + 0.28, py, 2.38), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=14))
    pu.append(box("SM_PU_BaseL", (0.34, 0.34, 0.08), (px - 0.58, py, 0.04), "COL_Geo_Props", lib["iron"]))
    pu.append(box("SM_PU_BaseR", (0.34, 0.34, 0.08), (px + 0.58, py, 0.04), "COL_Geo_Props", lib["iron"]))
    pu.append(box("SM_PU_CapL", (0.12, 0.12, 0.04), (px - 0.58, py, 2.46), "COL_Geo_Props", lib["chrome"]))
    pu.append(box("SM_PU_CapR", (0.12, 0.12, 0.04), (px + 0.58, py, 2.46), "COL_Geo_Props", lib["chrome"]))
    pu.append(box("SM_PU_Mat", (1.40, 0.70, 0.03), (px, py, 0.02), "COL_Geo_Props", lib["rubber"]))
    pu.append(box("SM_PU_Chalk", (0.16, 0.16, 0.08), (px + 0.72, py - 0.22, 0.08), "COL_Geo_Props", lib["concrete"]))
    pu.append(box("SM_PU_Tag", (0.22, 0.04, 0.10), (px, py + 0.08, 2.52), "COL_Geo_Props", lib["cyan_e"]))
    join_named("SM_Station_PullUp", pu, "COL_Geo_Props")
    empty_station("EMP_Station_PullUp", (px, py - 0.15, 0.0), "pullup", "Турник", "back")

    # --- Treadmill (4.5, 3.0) ---
    tx, ty = 11.2, 2.25
    tm = []
    tm.append(box("SM_TM_Base", (0.86, 1.85, 0.08), (tx, ty, 0.04), "COL_Geo_Props", lib["iron"]))
    tm.append(box("SM_TM_Deck", (0.78, 1.72, 0.12), (tx, ty, 0.18), "COL_Geo_Props", lib["iron"]))
    for si in range(9):
        tm.append(box(f"SM_TM_Slat_{si}", (0.52, 0.12, 0.025), (tx, ty - 0.62 + si * 0.155, 0.26), "COL_Geo_Props", lib["rubber"]))
    tm.append(box("SM_TM_PostL", (0.055, 0.055, 1.12), (tx - 0.32, ty + 0.82, 0.74), "COL_Geo_Props", lib["iron"]))
    tm.append(box("SM_TM_PostR", (0.055, 0.055, 1.12), (tx + 0.32, ty + 0.82, 0.74), "COL_Geo_Props", lib["iron"]))
    tm.append(cyl("SM_TM_RailL", 0.018, 0.55, (tx - 0.32, ty + 0.55, 1.18), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=12))
    tm.append(cyl("SM_TM_RailR", 0.018, 0.55, (tx + 0.32, ty + 0.55, 1.18), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=12))
    tm.append(box("SM_TM_Console", (0.72, 0.10, 0.38), (tx, ty + 0.88, 1.22), "COL_Geo_Props", lib["iron"]))
    tm.append(box("SM_TM_Screen", (0.46, 0.03, 0.24), (tx, ty + 0.94, 1.24), "COL_Geo_Props", lib["cyan_e"]))
    tm.append(box("SM_TM_Keys", (0.28, 0.04, 0.08), (tx, ty + 0.90, 1.08), "COL_Geo_Props", lib["trim"]))
    tm.append(box("SM_TM_Stop", (0.10, 0.06, 0.04), (tx + 0.22, ty + 0.90, 1.10), "COL_Geo_Props", redpad))
    tm.append(box("SM_TM_Stripe", (0.86, 0.08, 0.02), (tx, ty - 0.88, 0.10), "COL_Geo_Props", yellow))
    tm.append(box("SM_TM_Fan", (0.20, 0.08, 0.12), (tx, ty + 0.88, 1.42), "COL_Geo_Props", lib["trim"]))
    join_named("SM_Station_Treadmill", tm, "COL_Geo_Props")
    empty_station("EMP_Station_Treadmill", (tx, ty - 0.1, 0.0), "treadmill", "Дорожка", "cardio")

    # --- Lat pulldown west mid ---
    lx, ly = -6.35, 2.55
    lat = []
    lat.append(box("SM_Lat_Base", (0.85, 0.70, 0.08), (lx, ly, 0.04), "COL_Geo_Props", lib["iron"]))
    lat.append(box("SM_Lat_Col", (0.12, 0.12, 2.20), (lx - 0.18, ly + 0.12, 1.14), "COL_Geo_Props", lib["iron"]))
    lat.append(box("SM_Lat_Top", (0.70, 0.12, 0.10), (lx, ly + 0.12, 2.22), "COL_Geo_Props", lib["iron"]))
    lat.append(box("SM_Lat_Seat", (0.42, 0.42, 0.08), (lx + 0.12, ly - 0.12, 0.52), "COL_Geo_Props", leather))
    lat.append(box("SM_Lat_SeatPost", (0.08, 0.08, 0.48), (lx + 0.12, ly - 0.12, 0.26), "COL_Geo_Props", lib["iron"]))
    lat.append(box("SM_Lat_Thigh", (0.42, 0.10, 0.06), (lx + 0.12, ly - 0.12, 0.68), "COL_Geo_Props", leather))
    lat.append(cyl("SM_Lat_Bar", 0.016, 0.72, (lx + 0.05, ly - 0.08, 1.95), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=12))
    lat.append(cyl("SM_Lat_Cable", 0.008, 0.55, (lx - 0.05, ly + 0.12, 1.90), "COL_Geo_Props", lib["iron"], segs=8))
    for wi, wz in enumerate((0.35, 0.55, 0.75, 0.95, 1.15)):
        lat.append(box(f"SM_Lat_W_{wi}", (0.18, 0.08, 0.18), (lx - 0.18, ly + 0.28, wz), "COL_Geo_Props", lib["plate"]))
    lat.append(box("SM_Lat_Guide", (0.04, 0.04, 1.05), (lx - 0.06, ly + 0.28, 0.80), "COL_Geo_Props", lib["chrome"]))
    lat.append(box("SM_Lat_Screen", (0.22, 0.03, 0.14), (lx + 0.28, ly + 0.18, 1.55), "COL_Geo_Props", lib["cyan_e"]))
    lat.append(box("SM_Lat_Tag", (0.24, 0.04, 0.08), (lx + 0.12, ly - 0.28, 0.62), "COL_Geo_Props", yellow))
    join_named("SM_Station_Lat", lat, "COL_Geo_Props")
    empty_station("EMP_Station_Lat", (lx + 0.12, ly - 0.45, 0.0), "lat", "Тяга сверху", "back")

    # --- Exercise bike east mid ---
    kx, ky = 11.2, -2.25
    bk = []
    bk.append(box("SM_Bike_Base", (0.28, 0.85, 0.06), (kx, ky, 0.03), "COL_Geo_Props", lib["iron"]))
    bk.append(cyl("SM_Bike_WheelF", 0.22, 0.05, (kx, ky + 0.28, 0.24), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=16))
    bk.append(cyl("SM_Bike_WheelB", 0.18, 0.05, (kx, ky - 0.28, 0.20), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=16))
    bk.append(box("SM_Bike_Frame", (0.08, 0.62, 0.08), (kx, ky, 0.42), "COL_Geo_Props", lib["cyan_e"]))
    bk.append(box("SM_Bike_Seat", (0.22, 0.28, 0.07), (kx, ky - 0.18, 0.78), "COL_Geo_Props", leather))
    bk.append(cyl("SM_Bike_Post", 0.025, 0.40, (kx, ky - 0.18, 0.56), "COL_Geo_Props", lib["chrome"], segs=10))
    bk.append(box("SM_Bike_Console", (0.28, 0.08, 0.16), (kx, ky + 0.22, 1.05), "COL_Geo_Props", lib["iron"]))
    bk.append(box("SM_Bike_Screen", (0.22, 0.02, 0.12), (kx, ky + 0.27, 1.06), "COL_Geo_Props", lib["cyan_e"]))
    bk.append(cyl("SM_Bike_Bar", 0.016, 0.38, (kx, ky + 0.18, 0.92), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=10))
    bk.append(cyl("SM_Bike_PedL", 0.03, 0.12, (kx - 0.12, ky, 0.22), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=8))
    bk.append(cyl("SM_Bike_PedR", 0.03, 0.12, (kx + 0.12, ky, 0.22), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=8))
    bk.append(box("SM_Bike_Stripe", (0.30, 0.08, 0.03), (kx, ky, 0.10), "COL_Geo_Props", yellow))
    join_named("SM_Station_Bike", bk, "COL_Geo_Props")
    empty_station("EMP_Station_Bike", (kx, ky - 0.05, 0.0), "bike", "Велосипед", "cardio")

    # --- Dip station ---
    dipx, dipy = 2.35, 3.35
    dp = []
    dp.append(box("SM_Dip_Base", (1.05, 0.55, 0.07), (dipx, dipy, 0.035), "COL_Geo_Props", lib["iron"]))
    dp.append(cyl("SM_Dip_PL", 0.040, 1.25, (dipx - 0.32, dipy, 0.72), "COL_Geo_Props", lib["iron"], segs=12))
    dp.append(cyl("SM_Dip_PR", 0.040, 1.25, (dipx + 0.32, dipy, 0.72), "COL_Geo_Props", lib["iron"], segs=12))
    dp.append(cyl("SM_Dip_HL", 0.022, 0.42, (dipx - 0.32, dipy + 0.12, 1.28), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=12))
    dp.append(cyl("SM_Dip_HR", 0.022, 0.42, (dipx + 0.32, dipy + 0.12, 1.28), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=12))
    dp.append(box("SM_Dip_Top", (0.72, 0.08, 0.08), (dipx, dipy, 1.36), "COL_Geo_Props", lib["iron"]))
    dp.append(box("SM_Dip_Mat", (1.15, 0.85, 0.03), (dipx, dipy + 0.15, 0.02), "COL_Geo_Props", lib["rubber"]))
    dp.append(box("SM_Dip_Tag", (0.22, 0.04, 0.08), (dipx, dipy, 1.46), "COL_Geo_Props", lib["cyan_e"]))
    join_named("SM_Station_Dip", dp, "COL_Geo_Props")
    empty_station("EMP_Station_Dip", (dipx, dipy - 0.2, 0.0), "dip", "Брусья", "chest")

    # --- Kettlebells ---
    kbx, kby = 5.65, 3.35
    kb = []
    kb.append(box("SM_KB_Mat", (1.15, 0.70, 0.03), (kbx, kby, 0.016), "COL_Geo_Props", lib["rubber"]))
    kb.append(box("SM_KB_Rack", (1.05, 0.22, 0.08), (kbx, kby + 0.12, 0.18), "COL_Geo_Props", lib["iron"]))
    for i, ox in enumerate((-0.36, -0.12, 0.12, 0.36)):
        sc = 0.85 + i * 0.08
        body = uvsp(f"SM_KB_B_{i}", 0.09 * sc, (kbx + ox, kby, 0.14 * sc), "COL_Geo_Props", lib["plate"], segs=12)
        handle = cyl(f"SM_KB_H_{i}", 0.014, 0.12 * sc, (kbx + ox, kby, 0.26 * sc), "COL_Geo_Props", lib["chrome"], segs=8)
        kb += [body, handle]
    kb.append(box("SM_KB_Tag", (0.28, 0.04, 0.08), (kbx, kby + 0.22, 0.28), "COL_Geo_Props", yellow))
    join_named("SM_Station_Kettlebells", kb, "COL_Geo_Props")
    empty_station("EMP_Station_Kettlebells", (kbx, kby - 0.45, 0.0), "kettlebell", "Гири", "arms")

    # --- Leg press ---
    lpx, lpy = -2.15, 3.35
    lp = []
    lp.append(box("SM_LP_Base", (1.15, 1.55, 0.10), (lpx, lpy, 0.05), "COL_Geo_Props", lib["iron"]))
    lp.append(box("SM_LP_Seat", (0.55, 0.50, 0.10), (lpx, lpy - 0.42, 0.55), "COL_Geo_Props", leather))
    lp.append(box("SM_LP_Back", (0.55, 0.10, 0.55), (lpx, lpy - 0.62, 0.85), "COL_Geo_Props", leather))
    lp.append(box("SM_LP_RailL", (0.06, 1.20, 0.06), (lpx - 0.38, lpy + 0.15, 0.55), "COL_Geo_Props", lib["chrome"]))
    lp.append(box("SM_LP_RailR", (0.06, 1.20, 0.06), (lpx + 0.38, lpy + 0.15, 0.55), "COL_Geo_Props", lib["chrome"]))
    lp.append(box("SM_LP_Sled", (0.85, 0.12, 0.70), (lpx, lpy + 0.48, 0.72), "COL_Geo_Props", lib["iron"]))
    lp.append(box("SM_LP_Foot", (0.62, 0.08, 0.42), (lpx, lpy + 0.52, 0.78), "COL_Geo_Props", lib["rubber"]))
    for i, oz in enumerate((0.55, 0.72, 0.89)):
        lp.append(cyl(f"SM_LP_W_{i}", 0.11, 0.05, (lpx + 0.48, lpy + 0.48, oz), "COL_Geo_Props", lib["plate"], rot=(0, math.radians(90), 0), segs=12))
    lp.append(box("SM_LP_Tag", (0.30, 0.04, 0.10), (lpx, lpy - 0.62, 0.95), "COL_Geo_Props", lib["cyan_e"]))
    lp.append(box("SM_LP_Stripe", (1.15, 0.08, 0.03), (lpx, lpy, 0.12), "COL_Geo_Props", yellow))
    lp.append(box("SM_LP_HandleL", (0.04, 0.16, 0.04), (lpx - 0.28, lpy - 0.42, 0.68), "COL_Geo_Props", lib["chrome"]))
    lp.append(box("SM_LP_HandleR", (0.04, 0.16, 0.04), (lpx + 0.28, lpy - 0.42, 0.68), "COL_Geo_Props", lib["chrome"]))
    join_named("SM_Station_LegPress", lp, "COL_Geo_Props")
    empty_station("EMP_Station_LegPress", (lpx, lpy - 0.35, 0.0), "legpress", "Жим ногами", "legs")

    # --- Shoulder press ---
    spx, spy = -2.15, -3.35
    sp = []
    sp.append(box("SM_SP_Base", (0.85, 0.70, 0.08), (spx, spy, 0.04), "COL_Geo_Props", lib["iron"]))
    sp.append(box("SM_SP_Seat", (0.42, 0.42, 0.08), (spx, spy - 0.05, 0.52), "COL_Geo_Props", leather))
    sp.append(box("SM_SP_Back", (0.42, 0.08, 0.55), (spx, spy - 0.22, 0.85), "COL_Geo_Props", leather))
    sp.append(box("SM_SP_PostL", (0.08, 0.08, 1.35), (spx - 0.32, spy + 0.18, 0.82), "COL_Geo_Props", lib["iron"]))
    sp.append(box("SM_SP_PostR", (0.08, 0.08, 1.35), (spx + 0.32, spy + 0.18, 0.82), "COL_Geo_Props", lib["iron"]))
    sp.append(cyl("SM_SP_Bar", 0.018, 0.85, (spx, spy + 0.10, 1.28), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=12))
    sp.append(cyl("SM_SP_PL", 0.12, 0.04, (spx - 0.40, spy + 0.10, 1.28), "COL_Geo_Props", lib["plate"], rot=(0, math.radians(90), 0), segs=12))
    sp.append(cyl("SM_SP_PR", 0.12, 0.04, (spx + 0.40, spy + 0.10, 1.28), "COL_Geo_Props", lib["plate"], rot=(0, math.radians(90), 0), segs=12))
    sp.append(box("SM_SP_Tag", (0.26, 0.04, 0.08), (spx, spy - 0.22, 1.18), "COL_Geo_Props", yellow))
    sp.append(box("SM_SP_Pad", (0.85, 0.70, 0.02), (spx, spy, 0.09), "COL_Geo_Props", lib["rubber"]))
    join_named("SM_Station_Shoulder", sp, "COL_Geo_Props")
    empty_station("EMP_Station_Shoulder", (spx, spy + 0.05, 0.0), "shoulder", "Жим сидя", "chest")

    # --- Seated cable row ---
    srx, sry = 0.15, 3.35
    sr = []
    sr.append(box("SM_SR_Base", (0.70, 1.55, 0.08), (srx, sry, 0.04), "COL_Geo_Props", lib["iron"]))
    sr.append(box("SM_SR_Seat", (0.40, 0.38, 0.08), (srx, sry - 0.35, 0.42), "COL_Geo_Props", leather))
    sr.append(box("SM_SR_Foot", (0.50, 0.12, 0.18), (srx, sry + 0.35, 0.22), "COL_Geo_Props", lib["iron"]))
    sr.append(box("SM_SR_Col", (0.12, 0.12, 1.15), (srx, sry + 0.55, 0.70), "COL_Geo_Props", lib["iron"]))
    sr.append(cyl("SM_SR_Handle", 0.016, 0.38, (srx, sry + 0.05, 0.55), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=10))
    for i, wz in enumerate((0.40, 0.58, 0.76, 0.94)):
        sr.append(box(f"SM_SR_W_{i}", (0.16, 0.06, 0.16), (srx, sry + 0.62, wz), "COL_Geo_Props", lib["plate"]))
    sr.append(box("SM_SR_Screen", (0.18, 0.03, 0.12), (srx, sry + 0.55, 1.35), "COL_Geo_Props", lib["cyan_e"]))
    sr.append(box("SM_SR_Tag", (0.24, 0.04, 0.08), (srx, sry - 0.35, 0.52), "COL_Geo_Props", yellow))
    join_named("SM_Station_Row", sr, "COL_Geo_Props")
    empty_station("EMP_Station_Row", (srx, sry - 0.35, 0.0), "row", "Тяга сидя", "back")

    # --- Rowing machine (cardio) ---
    rwx, rwy = 11.2, 0.05
    rw = []
    rw.append(box("SM_RW_Rail", (0.22, 1.85, 0.08), (rwx, rwy, 0.12), "COL_Geo_Props", lib["iron"]))
    rw.append(box("SM_RW_Seat", (0.32, 0.28, 0.08), (rwx, rwy - 0.15, 0.32), "COL_Geo_Props", leather))
    rw.append(cyl("SM_RW_Wheel", 0.22, 0.08, (rwx, rwy + 0.72, 0.28), "COL_Geo_Props", lib["iron"], rot=(0, math.radians(90), 0), segs=16))
    rw.append(box("SM_RW_Foot", (0.38, 0.22, 0.06), (rwx, rwy + 0.42, 0.18), "COL_Geo_Props", lib["rubber"]))
    rw.append(cyl("SM_RW_Handle", 0.014, 0.42, (rwx, rwy + 0.20, 0.55), "COL_Geo_Props", lib["chrome"], rot=(0, math.radians(90), 0), segs=10))
    rw.append(box("SM_RW_Screen", (0.16, 0.03, 0.10), (rwx, rwy + 0.72, 0.52), "COL_Geo_Props", lib["cyan_e"]))
    rw.append(box("SM_RW_Stripe", (0.24, 0.10, 0.02), (rwx, rwy - 0.85, 0.16), "COL_Geo_Props", yellow))
    join_named("SM_Station_Rower", rw, "COL_Geo_Props")
    empty_station("EMP_Station_Rower", (rwx, rwy - 0.15, 0.0), "rower", "Гребля", "cardio")

    # --- Hyperextension bench ---
    hyx, hyy = 5.65, 0.05
    hy = []
    hy.append(box("SM_HY_Base", (0.55, 1.15, 0.08), (hyx, hyy, 0.04), "COL_Geo_Props", lib["iron"]))
    hy.append(box("SM_HY_Pad", (0.42, 0.38, 0.10), (hyx, hyy + 0.12, 0.72), "COL_Geo_Props", leather))
    hy.append(box("SM_HY_Ankle", (0.42, 0.10, 0.08), (hyx, hyy - 0.38, 0.38), "COL_Geo_Props", leather))
    hy.append(box("SM_HY_Post", (0.08, 0.08, 0.70), (hyx, hyy - 0.05, 0.40), "COL_Geo_Props", lib["iron"]))
    hy.append(box("SM_HY_Mat", (0.70, 1.30, 0.02), (hyx, hyy, 0.015), "COL_Geo_Props", lib["rubber"]))
    hy.append(box("SM_HY_Tag", (0.22, 0.04, 0.08), (hyx, hyy + 0.12, 0.84), "COL_Geo_Props", lib["cyan_e"]))
    join_named("SM_Station_Hyper", hy, "COL_Geo_Props")
    empty_station("EMP_Station_Hyper", (hyx, hyy + 0.35, 0.0), "hyper", "Гиперэкстензия", "back")

    # --- Battle ropes ---
    brx, bry = 13.15, 2.35
    br = []
    br.append(box("SM_BR_Post", (0.14, 0.14, 1.10), (brx + 0.45, bry, 0.55), "COL_Geo_Props", lib["iron"]))
    br.append(box("SM_BR_Base", (0.40, 0.40, 0.08), (brx + 0.45, bry, 0.04), "COL_Geo_Props", lib["iron"]))
    br.append(cyl("SM_BR_R0", 0.035, 1.6, (brx - 0.12, bry - 0.12, 0.08), "COL_Geo_Props", lib["tank"], rot=(0, math.radians(90), 0), segs=8))
    br.append(cyl("SM_BR_R1", 0.035, 1.6, (brx - 0.12, bry + 0.12, 0.08), "COL_Geo_Props", lib["tank"], rot=(0, math.radians(90), 0), segs=8))
    br.append(box("SM_BR_Mat", (1.80, 0.70, 0.03), (brx - 0.35, bry, 0.02), "COL_Geo_Props", lib["rubber"]))
    br.append(box("SM_BR_Tag", (0.22, 0.04, 0.08), (brx + 0.45, bry, 1.16), "COL_Geo_Props", yellow))
    join_named("SM_Station_Ropes", br, "COL_Geo_Props")
    empty_station("EMP_Station_Ropes", (brx - 0.55, bry, 0.0), "ropes", "Канаты", "arms")


def phase_dressing(lib):
    kenney_furn("kitchenFridgeLarge.glb", "SM_Dress_Fridge", (-3.35, 8.85, 0.0), "COL_Geo_Props", scale=2.15, rot=(0, 0, 0))
    empty_station("EMP_Station_Shop", (0.0, 7.55, 0.0), "shop", "Магазин", "shop")
    kenney_furn("stoolBar.glb", "SM_Dress_StoolL", (-1.05, 7.50, 0.0), "COL_Geo_Props")
    kenney_furn("stoolBar.glb", "SM_Dress_StoolR", (1.05, 7.50, 0.0), "COL_Geo_Props")

    # Water cooler
    wc = []
    wc.append(cyl("SM_WC_Body", 0.17, 0.72, (1.7, 8.75, 0.40), "COL_Geo_Props", lib["trim"], segs=20))
    wc.append(uvsp("SM_WC_Bottle", 0.175, (1.7, 8.75, 0.98), "COL_Geo_Props", lib["cyan_e"], scale=(1, 1, 1.35), segs=16))
    wc.append(cyl("SM_WC_Spout", 0.018, 0.08, (1.7, 8.55, 0.62), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=10))
    wc.append(box("SM_WC_Drip", (0.16, 0.12, 0.03), (1.7, 8.55, 0.50), "COL_Geo_Props", lib["iron"]))
    join_named("SM_Dress_Cooler", wc, "COL_Geo_Props")

    # Plate tree
    tree = []
    tree.append(cyl("SM_Tree_Pole", 0.03, 1.1, (6.2, 3.6, 0.55), "COL_Geo_Props", lib["chrome"], segs=8))
    tree.append(box("SM_Tree_Base", (0.35, 0.35, 0.06), (6.2, 3.6, 0.03), "COL_Geo_Props", lib["iron"]))
    for i, z in enumerate((0.25, 0.38, 0.50, 0.62)):
        tree.append(cyl(f"SM_Tree_P_{i}", 0.22 - i * 0.02, 0.04, (6.2, 3.6, z), "COL_Geo_Props", lib["plate"], segs=12))
    join_named("SM_Dress_PlateTree", tree, "COL_Geo_Props")

    # Speaker
    box("SM_Dress_Speaker", (0.25, 0.25, 0.4), (-7.3, 4.4, 2.6), "COL_Geo_Props", lib["iron"])

    # Clock on bar east wall (was floating in the shop doorway)
    cyl("SM_Dress_Clock", 0.22, 0.06, (4.95, 7.55, 2.45), "COL_Geo_Props", lib["trim"], rot=(0, math.radians(90), 0), segs=16)

    # Steel gym lockers along west wall
    lk = []
    steel = mat("MAT_LockerSteel", (0.58, 0.60, 0.63), 0.55, 0.38)
    steel_d = mat("MAT_LockerDoor", (0.50, 0.52, 0.55), 0.5, 0.42)
    plate = mat("MAT_LockerPlate", (0.90, 0.88, 0.78), 0.05, 0.5)
    for i in range(10):
        y = -2.48 + i * 0.60
        lk.append(box(f"SM_Lock_Body_{i}", (0.38, 0.56, 1.88), (-13.78, y, 1.00), "COL_Geo_Props", steel))
        lk.append(box(f"SM_Lock_Door_{i}", (0.03, 0.50, 1.70), (-13.58, y, 1.02), "COL_Geo_Props", steel_d))
        lk.append(box(f"SM_Lock_Num_{i}", (0.02, 0.10, 0.08), (-13.56, y, 1.55), "COL_Geo_Props", plate))
        lk.append(box(f"SM_Lock_H_{i}", (0.03, 0.035, 0.09), (-13.55, y + 0.18, 1.05), "COL_Geo_Props", lib["chrome"]))
        for vi, vz in enumerate((1.68, 1.74, 1.80)):
            lk.append(box(f"SM_Lock_V_{i}_{vi}", (0.02, 0.22, 0.018), (-13.56, y, vz), "COL_Geo_Props", lib["iron"]))
        lk.append(cyl(f"SM_Lock_LegA_{i}", 0.02, 0.08, (-13.90, y - 0.20, 0.04), "COL_Geo_Props", lib["iron"], segs=8))
        lk.append(cyl(f"SM_Lock_LegB_{i}", 0.02, 0.08, (-13.90, y + 0.20, 0.04), "COL_Geo_Props", lib["iron"], segs=8))
        lk.append(cyl(f"SM_Lock_LegC_{i}", 0.02, 0.08, (-13.66, y - 0.20, 0.04), "COL_Geo_Props", lib["iron"], segs=8))
        lk.append(cyl(f"SM_Lock_LegD_{i}", 0.02, 0.08, (-13.66, y + 0.20, 0.04), "COL_Geo_Props", lib["iron"], segs=8))
    join_named("SM_Dress_Lockers", lk, "COL_Geo_Props")

    # Changing stalls: laminate partitions, floor gap, ajar doors (not curtains)
    stall = mat("MAT_Stall", (0.86, 0.82, 0.74), 0.0, 0.55)
    alum = mat("MAT_StallEdge", (0.70, 0.72, 0.74), 0.65, 0.28)
    occ = mat("MAT_StallOcc", (0.22, 0.48, 0.30), 0.05, 0.5)
    booths = []
    y_back = -3.96
    depth = 1.12
    y_mid = y_back + depth * 0.5
    y_front = y_back + depth
    for i, cx in enumerate((-13.28, -12.18, -11.08)):
        if i == 0:
            booths.append(box(f"SM_Booth_SideL_{i}", (0.04, depth, 1.92), (cx - 0.52, y_mid, 1.10), "COL_Geo_Props", stall))
        booths.append(box(f"SM_Booth_SideR_{i}", (0.04, depth, 1.92), (cx + 0.52, y_mid, 1.10), "COL_Geo_Props", stall))
        booths.append(box(f"SM_Booth_Head_{i}", (1.08, 0.05, 0.10), (cx, y_front, 2.08), "COL_Geo_Props", alum))
        booths.append(cyl(f"SM_Booth_PostL_{i}", 0.025, 0.16, (cx - 0.52, y_front, 0.08), "COL_Geo_Props", alum, segs=8))
        booths.append(cyl(f"SM_Booth_PostR_{i}", 0.025, 0.16, (cx + 0.52, y_front, 0.08), "COL_Geo_Props", alum, segs=8))
        # Ajar door (gap at floor like a real stall)
        ang = math.radians(-22 if i != 1 else 18)
        booths.append(box(f"SM_Booth_Door_{i}", (0.62, 0.04, 1.72), (cx + 0.12, y_front + 0.12, 1.14), "COL_Geo_Props", stall, rot=(0, 0, ang)))
        booths.append(box(f"SM_Booth_Hinge_{i}", (0.04, 0.04, 1.70), (cx - 0.48, y_front, 1.14), "COL_Geo_Props", alum))
        booths.append(box(f"SM_Booth_Handle_{i}", (0.04, 0.03, 0.10), (cx + 0.28, y_front + 0.10, 1.15), "COL_Geo_Props", lib["chrome"]))
        booths.append(cyl(f"SM_Booth_Occ_{i}", 0.03, 0.02, (cx, y_front + 0.04, 1.95), "COL_Geo_Props", occ, rot=(math.radians(90), 0, 0), segs=10))
        booths.append(box(f"SM_Booth_Seat_{i}", (0.82, 0.30, 0.07), (cx, y_back + 0.28, 0.42), "COL_Geo_Props", lib["wood"]))
        booths.append(box(f"SM_Booth_SeatL_{i}", (0.06, 0.06, 0.40), (cx - 0.28, y_back + 0.28, 0.20), "COL_Geo_Props", lib["iron"]))
        booths.append(box(f"SM_Booth_SeatR_{i}", (0.06, 0.06, 0.40), (cx + 0.28, y_back + 0.28, 0.20), "COL_Geo_Props", lib["iron"]))
        booths.append(cyl(f"SM_Booth_Hook_{i}", 0.012, 0.08, (cx + 0.38, y_back + 0.10, 1.55), "COL_Geo_Props", lib["chrome"], rot=(math.radians(90), 0, 0), segs=8))
    join_named("SM_Dress_Booths", booths, "COL_Geo_Props")

    # Sit bench against locker-room north wall, east of the sauna door
    sb = []
    sb.append(box("SM_Sit_Pad", (1.45, 0.38, 0.09), (-10.45, 3.55, 0.42), "COL_Geo_Props", lib["pad"]))
    sb.append(box("SM_Sit_L", (0.08, 0.32, 0.40), (-11.05, 3.55, 0.20), "COL_Geo_Props", lib["iron"]))
    sb.append(box("SM_Sit_R", (0.08, 0.32, 0.40), (-9.85, 3.55, 0.20), "COL_Geo_Props", lib["iron"]))
    join_named("SM_Dress_SitBench", sb, "COL_Geo_Props")

    # Punching bag
    bag = []
    bag.append(cyl("SM_Bag_Body", 0.18, 1.15, (13.2, 0.0, 1.15), "COL_Geo_Props", lib["tank"], segs=16))
    bag.append(cyl("SM_Bag_Chain", 0.012, 0.55, (13.2, 0.0, 1.95), "COL_Geo_Props", lib["chrome"], segs=8))
    bag.append(box("SM_Bag_Mount", (0.25, 0.25, 0.08), (13.2, 0.0, 2.25), "COL_Geo_Props", lib["iron"]))
    join_named("SM_Dress_Bag", bag, "COL_Geo_Props")

    # Fan
    fan = []
    fan.append(cyl("SM_Fan_Hub", 0.08, 0.06, (0.0, 0.0, 3.85), "COL_Geo_Props", lib["chrome"], segs=12))
    fan.append(box("SM_Fan_B0", (0.9, 0.12, 0.03), (0.0, 0.0, 3.85), "COL_Geo_Props", lib["trim"]))
    fan.append(box("SM_Fan_B1", (0.12, 0.9, 0.03), (0.0, 0.0, 3.85), "COL_Geo_Props", lib["trim"]))
    join_named("SM_Dress_Fan", fan, "COL_Geo_Props")
    food("soda-can.glb", "SM_Dress_Soda", (-0.85, 8.18, 1.11), "COL_Geo_Props", 0.55)
    food("soda-bottle.glb", "SM_Dress_SodaBot", (-0.45, 8.18, 1.11), "COL_Geo_Props", 0.55)
    food("carton.glb", "SM_Dress_Protein", (0.0, 8.18, 1.11), "COL_Geo_Props", 0.55)
    food("banana.glb", "SM_Dress_Banana", (0.40, 8.18, 1.11), "COL_Geo_Props", 0.55)
    food("cup-coffee.glb", "SM_Dress_Coffee", (0.80, 8.18, 1.11), "COL_Geo_Props", 0.55)
    food("muffin.glb", "SM_Dress_Muffin", (1.15, 8.18, 1.11), "COL_Geo_Props", 0.55)

    gb = []
    gb.append(box("SM_GymBag", (0.55, 0.28, 0.28), (-11.6, 3.1, 0.16), "COL_Geo_Props", lib["mag_e"]))
    gb.append(box("SM_Chalk", (0.16, 0.16, 0.08), (4.9, -4.2, 0.05), "COL_Geo_Props", lib["concrete"]))
    join_named("SM_Dress_Clutter", gb, "COL_Geo_Props")

    # Shop TV on a stand against the west wall, screen into the room (+X)
    cab = kenney_furn(
        "cabinetTelevision.glb", "SM_Dress_TVCab",
        (-4.78, 6.90, 0.0), "COL_Geo_Props", scale=2.3, rot=(0, 0, math.radians(90)),
    )
    cab_top = 0.70
    if cab is not None:
        bpy.context.view_layer.update()
        cab_top = max((cab.matrix_world @ Vector(c)).z for c in cab.bound_box)
    kenney_furn(
        "televisionModern.glb", "SM_Dress_TV",
        (-4.78, 6.90, cab_top), "COL_Geo_Props", scale=1.8, rot=(0, 0, math.radians(90)),
    )

    # Second plate tree
    tree2 = []
    tree2.append(cyl("SM_Tree2_Pole", 0.03, 1.1, (-6.6, -2.4, 0.55), "COL_Geo_Props", lib["chrome"], segs=8))
    tree2.append(box("SM_Tree2_Base", (0.35, 0.35, 0.06), (-6.6, -2.4, 0.03), "COL_Geo_Props", lib["iron"]))
    for i, z in enumerate((0.22, 0.36, 0.50, 0.64, 0.78)):
        tree2.append(cyl(f"SM_Tree2_P_{i}", 0.24 - i * 0.018, 0.04, (-6.6, -2.4, z), "COL_Geo_Props", lib["plate"], segs=14))
    join_named("SM_Dress_PlateTree2", tree2, "COL_Geo_Props")

    # Reception: clear center aisle, desk on the east wall facing the walkway
    kenney_furn("desk.glb", "SM_Dress_Desk", (2.70, -7.60, 0.0), "COL_Geo_Props", rot=(0, 0, math.radians(90)))
    kenney_furn("chairDesk.glb", "SM_Dress_Chair", (3.45, -7.60, 0.0), "COL_Geo_Props", rot=(0, 0, math.radians(-90)))
    kenney_furn("computerScreen.glb", "SM_Dress_Screen", (2.90, -7.60, 0.83), "COL_Geo_Props", scale=2.0, rot=(0, 0, math.radians(90)))
    kenney_furn("computerKeyboard.glb", "SM_Dress_Keys", (3.10, -7.60, 0.83), "COL_Geo_Props", scale=2.0, rot=(0, 0, math.radians(90)))
    kenney_furn("lampRoundTable.glb", "SM_Dress_Lamp", (2.70, -8.20, 0.83), "COL_Geo_Props", scale=1.7)
    kenney_furn("plantSmall1.glb", "SM_Dress_PlantDesk", (2.45, -7.05, 0.83), "COL_Geo_Props", scale=2.2)
    kenney_furn("pottedPlant.glb", "SM_Dress_Plant", (3.30, -9.35, 0.0), "COL_Geo_Props", scale=2.3)
    kenney_furn("coatRackStanding.glb", "SM_Dress_Coat", (-3.40, -9.35, 0.0), "COL_Geo_Props", scale=2.4)
    kenney_furn("trashcan.glb", "SM_Dress_Trash", (3.35, -5.75, 0.0), "COL_Geo_Props", scale=2.2)
    kenney_furn("loungeChair.glb", "SM_Dress_WaitA", (-2.15, -6.70, 0.0), "COL_Geo_Props", scale=2.15, rot=(0, 0, math.radians(90)))
    kenney_furn("loungeChair.glb", "SM_Dress_WaitB", (-2.15, -8.40, 0.0), "COL_Geo_Props", scale=2.15, rot=(0, 0, math.radians(90)))
    kenney_furn("pottedPlant.glb", "SM_Dress_PlantShop", (4.15, 9.20, 0.0), "COL_Geo_Props", scale=2.0)

    # WC: two toilets + sink
    stall_m = mat("MAT_Stall", (0.86, 0.82, 0.74), 0.0, 0.55)
    alum = mat("MAT_StallEdge", (0.70, 0.72, 0.74), 0.65, 0.28)
    kenney_furn("toilet.glb", "SM_Dress_ToiletA", (-7.45, -8.95, 0.0), "COL_Geo_Props", scale=2.3, rot=(0, 0, math.radians(90)))
    kenney_furn("toilet.glb", "SM_Dress_ToiletB", (-7.45, -7.25, 0.0), "COL_Geo_Props", scale=2.3, rot=(0, 0, math.radians(90)))
    box("SM_Dress_WCDiv", (1.05, 0.04, 1.80), (-7.15, -8.10, 1.02), "COL_Geo_Props", stall_m)
    box("SM_Dress_WCSideA", (1.05, 0.04, 1.80), (-7.15, -9.55, 1.02), "COL_Geo_Props", stall_m)
    box("SM_Dress_WCSideB", (1.05, 0.04, 1.80), (-7.15, -6.65, 1.02), "COL_Geo_Props", stall_m)
    box("SM_Dress_WCHeadA", (1.05, 0.04, 0.08), (-7.15, -8.80, 1.95), "COL_Geo_Props", alum)
    box("SM_Dress_WCHeadB", (1.05, 0.04, 0.08), (-7.15, -7.40, 1.95), "COL_Geo_Props", alum)
    kenney_furn("bathroomSink.glb", "SM_Dress_Sink", (-5.35, -9.72, 0.0), "COL_Geo_Props", scale=2.2, rot=(0, 0, math.pi))
    # y puts the frame's back on the wall face (y=-10.0), not 0.1 m inside it.
    kenney_furn("bathroomMirror.glb", "SM_Dress_WCMirror", (-5.35, -9.8456, 1.20), "COL_Geo_Props", scale=2.0, rot=(0, 0, math.pi))

    extra = []
    extra.append(box("SM_Exting", (0.12, 0.12, 0.42), (-3.7, -6.6, 0.28), "COL_Geo_Props", lib["tank"]))
    for i, ox in enumerate((-0.28, 0.0, 0.28)):
        extra.append(uvsp(f"SM_Med_{i}", 0.09 + i * 0.01, (6.2, -3.6 + ox, 0.12), "COL_Geo_Props", lib["mag_e"] if i else lib["cyan_e"], segs=12))
    extra.append(cyl("SM_MatRoll0", 0.07, 0.55, (-6.3, 3.9, 0.08), "COL_Geo_Props", lib["fridge"], rot=(0, math.radians(90), 0), segs=12))
    extra.append(cyl("SM_MatRoll1", 0.07, 0.55, (-6.3, 3.65, 0.08), "COL_Geo_Props", lib["poster"], rot=(0, math.radians(90), 0), segs=12))
    extra.append(cyl("SM_Foam", 0.06, 0.38, (6.3, 3.9, 0.07), "COL_Geo_Props", lib["concrete"], rot=(0, math.radians(90), 0), segs=10))
    extra.append(cyl("SM_Rope", 0.03, 1.4, (6.4, -3.9, 0.04), "COL_Geo_Props", lib["wood"], rot=(0, math.radians(90), 0), segs=8))
    extra.append(box("SM_WallBar", (0.08, 1.6, 1.4), (-7.95, 3.4, 1.1), "COL_Geo_Props", lib["wood"]))
    extra.append(uvsp("SM_SpeedBag", 0.12, (13.2, 2.4, 1.55), "COL_Geo_Props", lib["tank"], scale=(1, 1, 1.3), segs=12))
    extra.append(cyl("SM_SpeedArm", 0.02, 0.35, (13.2, 2.4, 1.85), "COL_Geo_Props", lib["chrome"], segs=8))
    extra.append(box("SM_Crate", (0.4, 0.32, 0.28), (2.4, 8.9, 0.16), "COL_Geo_Props", lib["wood"]))
    extra.append(cyl("SM_Can0", 0.04, 0.12, (2.35, 8.9, 0.36), "COL_Geo_Props", lib["cyan_e"], segs=8))
    extra.append(cyl("SM_Can1", 0.04, 0.12, (2.5, 8.85, 0.36), "COL_Geo_Props", lib["fridge"], segs=8))
    extra.append(box("SM_WallRail", (1.8, 0.08, 0.10), (13.95, 0.0, 1.15), "COL_Geo_Props", lib["iron"]))
    extra.append(box("SM_ShoeRack", (0.7, 0.22, 0.45), (-9.55, 3.55, 0.25), "COL_Geo_Props", lib["iron"]))
    join_named("SM_Dress_Extra", extra, "COL_Geo_Props")
    # Hangs on the y=+4.0 wall face, so it faces -Y into the room. The WC mirror
    # sits on the opposite wall and is the one that needs the half turn, not this
    # one. y puts the frame's back on the wall rather than buried behind it.
    kenney_furn("bathroomMirror.glb", "SM_Dress_MirrorLock", (-10.45, 3.788, 0.85), "COL_Geo_Props", scale=2.8)
    dress_sauna(lib)


def dress_sauna(lib):
    """Wooden banya north of lockers: benches, stove, bucket."""
    cedar = mat("MAT_SaunaWood", (0.40, 0.24, 0.12), 0.0, 0.58)
    cedar_l = mat("MAT_SaunaBench", (0.50, 0.32, 0.16), 0.0, 0.52)
    iron = lib["iron"]
    chrome = lib["chrome"]
    ember = mat("MAT_SaunaEmber", (0.55, 0.22, 0.10), 0.1, 0.48)
    coal = mat("MAT_SaunaStone", (0.18, 0.16, 0.15), 0.05, 0.62)
    parts = []
    # Floor planks
    for i, x in enumerate((-13.85, -13.05, -12.25, -11.45, -10.65)):
        parts.append(box(f"SM_Sau_Plank_{i}", (0.72, 4.05, 0.03), (x, 6.22, 0.02), "COL_Geo_Props", cedar if i % 2 == 0 else cedar_l))
    # Interior slats
    for i, y in enumerate((4.55, 5.25, 5.95, 6.65, 7.35, 8.00)):
        parts.append(box(f"SM_Sau_SlatW_{i}", (0.03, 0.62, 2.28), (-14.05, y, 1.18), "COL_Geo_Props", cedar))
    for i, x in enumerate((-13.75, -12.95, -12.15, -11.35, -10.55)):
        parts.append(box(f"SM_Sau_SlatN_{i}", (0.70, 0.03, 2.28), (x, 8.20, 1.18), "COL_Geo_Props", cedar))
    for i, y in enumerate((4.55, 5.35, 6.15, 6.95, 7.75)):
        parts.append(box(f"SM_Sau_SlatE_{i}", (0.03, 0.68, 2.28), (-9.95, y, 1.18), "COL_Geo_Props", cedar))
    for i, x in enumerate((-13.90, -13.20, -12.40, -11.70, -11.00, -10.30)):
        parts.append(box(f"SM_Sau_Ceil_{i}", (0.62, 4.05, 0.03), (x, 6.22, H_SAUNA - 0.04), "COL_Geo_Props", cedar_l))
    # West benches (keep clear of the door at y=4.1)
    parts.append(box("SM_Sau_WLo", (0.54, 2.55, 0.08), (-13.70, 6.55, 0.44), "COL_Geo_Props", cedar_l))
    parts.append(box("SM_Sau_WHi", (0.54, 2.55, 0.08), (-13.70, 6.55, 0.94), "COL_Geo_Props", cedar_l))
    parts.append(box("SM_Sau_WLoF", (0.06, 2.55, 0.38), (-13.46, 6.55, 0.22), "COL_Geo_Props", cedar))
    parts.append(box("SM_Sau_WHiF", (0.06, 2.55, 0.48), (-13.46, 6.55, 0.68), "COL_Geo_Props", cedar))
    for y in (5.45, 6.55, 7.65):
        parts.append(box(f"SM_Sau_WLeg_{y}", (0.08, 0.08, 0.90), (-13.70, y, 0.46), "COL_Geo_Props", cedar))
    # North benches
    parts.append(box("SM_Sau_NLo", (2.70, 0.54, 0.08), (-12.35, 7.95, 0.44), "COL_Geo_Props", cedar_l))
    parts.append(box("SM_Sau_NHi", (2.70, 0.54, 0.08), (-12.35, 7.95, 0.94), "COL_Geo_Props", cedar_l))
    parts.append(box("SM_Sau_NLoF", (2.70, 0.06, 0.38), (-12.35, 7.71, 0.22), "COL_Geo_Props", cedar))
    parts.append(box("SM_Sau_NHiF", (2.70, 0.06, 0.48), (-12.35, 7.71, 0.68), "COL_Geo_Props", cedar))
    for x in (-13.45, -12.35, -11.25):
        parts.append(box(f"SM_Sau_NLeg_{x}", (0.08, 0.08, 0.90), (x, 7.95, 0.46), "COL_Geo_Props", cedar))
    # Heater / каменка, NE corner, wooden rail
    hx, hy = -10.45, 7.55
    parts.append(box("SM_Sau_Stove", (0.48, 0.48, 0.62), (hx, hy, 0.36), "COL_Geo_Props", iron))
    parts.append(box("SM_Sau_StoveTop", (0.52, 0.52, 0.05), (hx, hy, 0.70), "COL_Geo_Props", iron))
    parts.append(box("SM_Sau_StoveDoor", (0.22, 0.03, 0.28), (hx, hy - 0.26, 0.32), "COL_Geo_Props", chrome))
    parts.append(cyl("SM_Sau_Pipe", 0.045, 1.55, (hx + 0.14, hy + 0.14, 1.52), "COL_Geo_Props", iron, segs=10))
    parts.append(cyl("SM_Sau_PipeCap", 0.07, 0.04, (hx + 0.14, hy + 0.14, 2.30), "COL_Geo_Props", iron, segs=10))
    parts.append(box("SM_Sau_Glow", (0.18, 0.04, 0.16), (hx, hy - 0.27, 0.32), "COL_Geo_Props", ember))
    rng = (0.12, 0.18, 0.08, -0.10, 0.0, -0.16, 0.14, -0.14)
    for i, ox in enumerate(rng):
        oy = rng[(i + 3) % 8] * 0.7
        parts.append(uvsp(f"SM_Sau_Rock_{i}", 0.055 + (i % 3) * 0.012, (hx + ox, hy + oy, 0.82), "COL_Geo_Props", coal if i % 2 else ember, segs=10))
    parts.append(box("SM_Sau_RailA", (0.04, 0.85, 0.06), (hx - 0.42, hy - 0.10, 0.72), "COL_Geo_Props", cedar))
    parts.append(box("SM_Sau_RailB", (0.85, 0.04, 0.06), (hx - 0.10, hy - 0.42, 0.72), "COL_Geo_Props", cedar))
    parts.append(cyl("SM_Sau_PostA", 0.03, 0.72, (hx - 0.42, hy - 0.42, 0.38), "COL_Geo_Props", cedar, segs=8))
    parts.append(cyl("SM_Sau_PostB", 0.03, 0.72, (hx - 0.42, hy + 0.28, 0.38), "COL_Geo_Props", cedar, segs=8))
    parts.append(cyl("SM_Sau_PostC", 0.03, 0.72, (hx + 0.28, hy - 0.42, 0.38), "COL_Geo_Props", cedar, segs=8))
    # Bucket + ladle
    parts.append(cyl("SM_Sau_Bucket", 0.12, 0.22, (-11.15, 7.15, 0.16), "COL_Geo_Props", cedar, segs=14))
    parts.append(cyl("SM_Sau_Band", 0.125, 0.02, (-11.15, 7.15, 0.22), "COL_Geo_Props", iron, segs=12))
    parts.append(cyl("SM_Sau_Water", 0.10, 0.04, (-11.15, 7.15, 0.24), "COL_Geo_Props", lib["glass"], segs=12))
    parts.append(cyl("SM_Sau_LadleH", 0.012, 0.32, (-11.00, 7.05, 0.38), "COL_Geo_Props", cedar, rot=(0, math.radians(55), 0), segs=8))
    parts.append(cyl("SM_Sau_LadleC", 0.05, 0.03, (-10.86, 7.00, 0.28), "COL_Geo_Props", cedar, segs=10))
    # Thermometer
    parts.append(box("SM_Sau_Thermo", (0.05, 0.03, 0.28), (-9.92, 6.20, 1.55), "COL_Geo_Props", cedar_l))
    parts.append(cyl("SM_Sau_Mercury", 0.012, 0.18, (-9.90, 6.20, 1.50), "COL_Geo_Props", ember, segs=8))
    join_named("SM_Dress_Sauna", parts, "COL_Geo_Props")


def add_bone(arm, name, head, tail, parent=None, connect=False):
    b = arm.edit_bones.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    b.roll = 0.0
    if parent is not None:
        b.parent = arm.edit_bones[parent]
        b.use_connect = connect
    return b


def phase_hero(lib):
    parts = []
    pelvis = box("SK_H_Pelvis", (0.34, 0.20, 0.16), (0, 0, 0.98), "COL_Geo_Hero", lib["shorts"])
    torso = box("SK_H_Torso", (0.36, 0.20, 0.38), (0, 0, 1.24), "COL_Geo_Hero", lib["tank"])
    chest = box("SK_H_Chest", (0.46, 0.24, 0.20), (0, 0.03, 1.46), "COL_Geo_Hero", lib["tank"])
    pec_l = uvsp("SK_H_PecL", 0.09, (0.11, 0.10, 1.44), "COL_Geo_Hero", lib["tank"], scale=(1.15, 0.55, 0.85), segs=14)
    pec_r = uvsp("SK_H_PecR", 0.09, (-0.11, 0.10, 1.44), "COL_Geo_Hero", lib["tank"], scale=(1.15, 0.55, 0.85), segs=14)
    neck = cyl("SK_H_Neck", 0.055, 0.11, (0, 0.01, 1.58), "COL_Geo_Hero", lib["skin"], segs=14)
    head = uvsp("SK_H_Head", 0.125, (0, 0.02, 1.72), "COL_Geo_Hero", lib["skin"], segs=20)
    jaw = uvsp("SK_H_Jaw", 0.08, (0, 0.04, 1.64), "COL_Geo_Hero", lib["skin"], scale=(0.85, 0.7, 0.55), segs=12)
    hair = uvsp("SK_H_Hair", 0.13, (0, 0.0, 1.78), "COL_Geo_Hero", lib["hair"], scale=(1.02, 1.08, 0.72), segs=16)
    brow = box("SK_H_Brow", (0.16, 0.04, 0.03), (0, 0.12, 1.75), "COL_Geo_Hero", lib["hair"])
    parts += [pelvis, torso, chest, pec_l, pec_r, neck, head, jaw, hair, brow]
    for side, sx in (("L", 0.28), ("R", -0.28)):
        delt = uvsp(f"SK_H_Delt_{side}", 0.075, (sx, 0.02, 1.48), "COL_Geo_Hero", lib["skin"], segs=14)
        ua = cyl(f"SK_H_UpperArm_{side}", 0.062, 0.28, (sx, 0.0, 1.36), "COL_Geo_Hero", lib["skin"], segs=14)
        elbow = uvsp(f"SK_H_Elbow_{side}", 0.04, (sx, 0.0, 1.22), "COL_Geo_Hero", lib["skin"], segs=10)
        la = cyl(f"SK_H_LowerArm_{side}", 0.048, 0.26, (sx, 0.0, 1.10), "COL_Geo_Hero", lib["skin"], segs=14)
        hand = uvsp(f"SK_H_Hand_{side}", 0.045, (sx, 0.0, 0.94), "COL_Geo_Hero", lib["skin"], scale=(0.7, 0.5, 1.15), segs=10)
        ul = cyl(f"SK_H_UpperLeg_{side}", 0.078, 0.36, (sx * 0.42, 0.0, 0.72), "COL_Geo_Hero", lib["shorts"], segs=14)
        knee = uvsp(f"SK_H_Knee_{side}", 0.048, (sx * 0.42, 0.02, 0.52), "COL_Geo_Hero", lib["skin"], segs=10)
        ll = cyl(f"SK_H_LowerLeg_{side}", 0.052, 0.34, (sx * 0.42, 0.0, 0.34), "COL_Geo_Hero", lib["skin"], segs=14)
        calf = uvsp(f"SK_H_Calf_{side}", 0.055, (sx * 0.42, -0.04, 0.32), "COL_Geo_Hero", lib["skin"], scale=(0.9, 0.7, 1.3), segs=10)
        foot = box(f"SK_H_Foot_{side}", (0.10, 0.24, 0.075), (sx * 0.42, 0.05, 0.04), "COL_Geo_Hero", lib["shoe"])
        sole = box(f"SK_H_Sole_{side}", (0.11, 0.26, 0.02), (sx * 0.42, 0.05, 0.012), "COL_Geo_Hero", lib["rubber"])
        parts += [delt, ua, elbow, la, hand, ul, knee, ll, calf, foot, sole]

    hero = join_named("SK_Hero", parts, "COL_Geo_Hero", floor=True)
    hero.location = (0.0, 0.8, 0.0)

    # Armature at same place
    arm_data = bpy.data.armatures.new("ARM_Hero")
    arm_data.display_type = "OCTAHEDRAL"
    arm_obj = bpy.data.objects.new("ARM_Hero", arm_data)
    bpy.data.collections["COL_Geo_Hero"].objects.link(arm_obj)
    arm_obj.location = hero.location.copy()
    deselect_all()
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    add_bone(arm_data, "Root", (0, 0, 0.0), (0, 0, 0.12))
    add_bone(arm_data, "Hips", (0, 0, 0.90), (0, 0, 1.04), "Root")
    add_bone(arm_data, "Spine", (0, 0, 1.04), (0, 0, 1.22), "Hips", True)
    add_bone(arm_data, "Chest", (0, 0, 1.22), (0, 0, 1.48), "Spine", True)
    add_bone(arm_data, "Neck", (0, 0, 1.48), (0, 0, 1.58), "Chest", True)
    add_bone(arm_data, "Head", (0, 0, 1.58), (0, 0, 1.78), "Neck", True)
    add_bone(arm_data, "UpperArm_L", (0.22, 0, 1.46), (0.26, 0, 1.22), "Chest")
    add_bone(arm_data, "LowerArm_L", (0.26, 0, 1.22), (0.26, 0, 0.98), "UpperArm_L", True)
    add_bone(arm_data, "Hand_L", (0.26, 0, 0.98), (0.26, 0, 0.86), "LowerArm_L", True)
    add_bone(arm_data, "UpperArm_R", (-0.22, 0, 1.46), (-0.26, 0, 1.22), "Chest")
    add_bone(arm_data, "LowerArm_R", (-0.26, 0, 1.22), (-0.26, 0, 0.98), "UpperArm_R", True)
    add_bone(arm_data, "Hand_R", (-0.26, 0, 0.98), (-0.26, 0, 0.86), "LowerArm_R", True)
    add_bone(arm_data, "UpperLeg_L", (0.12, 0, 0.92), (0.12, 0, 0.52), "Hips")
    add_bone(arm_data, "LowerLeg_L", (0.12, 0, 0.52), (0.12, 0, 0.12), "UpperLeg_L", True)
    add_bone(arm_data, "Foot_L", (0.12, 0, 0.12), (0.12, 0.16, 0.02), "LowerLeg_L", True)
    add_bone(arm_data, "UpperLeg_R", (-0.12, 0, 0.92), (-0.12, 0, 0.52), "Hips")
    add_bone(arm_data, "LowerLeg_R", (-0.12, 0, 0.52), (-0.12, 0, 0.12), "UpperLeg_R", True)
    add_bone(arm_data, "Foot_R", (-0.12, 0, 0.12), (-0.12, 0.16, 0.02), "LowerLeg_R", True)
    bpy.ops.object.mode_set(mode="OBJECT")

    deselect_all()
    hero.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    hero.name = "SK_Hero"
    return arm_obj, hero


def ensure_action(arm_obj, name, frames):
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    act = bpy.data.actions.get(name)
    if act:
        bpy.data.actions.remove(act)
    act = bpy.data.actions.new(name)
    arm_obj.animation_data.action = act
    return act


def key_bone(pose_bone, frame, loc=None, rot=None, scale=None):
    pose_bone.rotation_mode = "XYZ"
    if loc is not None:
        pose_bone.location = loc
        pose_bone.keyframe_insert("location", frame=frame)
    if rot is not None:
        pose_bone.rotation_euler = rot
        pose_bone.keyframe_insert("rotation_euler", frame=frame)
    if scale is not None:
        pose_bone.scale = scale
        pose_bone.keyframe_insert("scale", frame=frame)


def reset_pose(arm_obj):
    for pb in arm_obj.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)


def phase_animation(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    deselect_all()
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode="POSE")
    pb = arm_obj.pose.bones

    def clip_idle():
        ensure_action(arm_obj, "AN_Idle", 60)
        reset_pose(arm_obj)
        for f, dz, arms in ((1, 0.0, 0.05), (30, 0.012, -0.04), (60, 0.0, 0.05)):
            key_bone(pb["Hips"], f, loc=(0, 0, dz))
            key_bone(pb["Chest"], f, rot=(arms * 0.2, 0, 0))
            key_bone(pb["UpperArm_L"], f, rot=(0, 0, 0.12 + arms))
            key_bone(pb["UpperArm_R"], f, rot=(0, 0, -0.12 - arms))

    def clip_walk():
        ensure_action(arm_obj, "AN_Walk", 24)
        reset_pose(arm_obj)
        for f, a in ((1, 0.45), (12, -0.45), (24, 0.45)):
            key_bone(pb["UpperLeg_L"], f, rot=(a, 0, 0))
            key_bone(pb["UpperLeg_R"], f, rot=(-a, 0, 0))
            key_bone(pb["LowerLeg_L"], f, rot=(-abs(a) * 0.4 if a > 0 else 0, 0, 0))
            key_bone(pb["LowerLeg_R"], f, rot=(-abs(a) * 0.4 if a < 0 else 0, 0, 0))
            key_bone(pb["UpperArm_L"], f, rot=(-a * 0.7, 0, 0.15))
            key_bone(pb["UpperArm_R"], f, rot=(a * 0.7, 0, -0.15))
            key_bone(pb["Hips"], f, loc=(0, 0, 0.02 if f in (1, 24) else 0.05))

    def clip_run():
        ensure_action(arm_obj, "AN_Run", 16)
        reset_pose(arm_obj)
        for f, a in ((1, 0.7), (8, -0.7), (16, 0.7)):
            key_bone(pb["UpperLeg_L"], f, rot=(a, 0, 0))
            key_bone(pb["UpperLeg_R"], f, rot=(-a, 0, 0))
            key_bone(pb["UpperArm_L"], f, rot=(-a * 0.9, 0, 0.2))
            key_bone(pb["UpperArm_R"], f, rot=(a * 0.9, 0, -0.2))
            key_bone(pb["Hips"], f, loc=(0, 0, 0.04), rot=(0.08, 0, 0))
            key_bone(pb["Chest"], f, rot=(0.1, 0, 0))

    def clip_bench():
        ensure_action(arm_obj, "AN_Bench", 30)
        reset_pose(arm_obj)
        # lie-ish: hips back, arms press
        for f, press in ((1, 0.15), (15, 1.05), (30, 0.15)):
            key_bone(pb["Hips"], f, rot=(-1.2, 0, 0), loc=(0, -0.05, -0.15))
            key_bone(pb["Spine"], f, rot=(-0.2, 0, 0))
            key_bone(pb["UpperArm_L"], f, rot=(0.2, 0, 1.4 - press * 0.15))
            key_bone(pb["UpperArm_R"], f, rot=(0.2, 0, -1.4 + press * 0.15))
            key_bone(pb["LowerArm_L"], f, rot=(0, 0, press * 0.1))
            key_bone(pb["LowerArm_R"], f, rot=(0, 0, -press * 0.1))

    def clip_squat():
        ensure_action(arm_obj, "AN_Squat", 36)
        reset_pose(arm_obj)
        for f, d in ((1, 0.0), (18, 1.0), (36, 0.0)):
            key_bone(pb["Hips"], f, loc=(0, 0.04 * d, -0.22 * d), rot=(0.35 * d, 0, 0))
            key_bone(pb["UpperLeg_L"], f, rot=(-1.1 * d, 0, 0.08))
            key_bone(pb["UpperLeg_R"], f, rot=(-1.1 * d, 0, -0.08))
            key_bone(pb["LowerLeg_L"], f, rot=(1.2 * d, 0, 0))
            key_bone(pb["LowerLeg_R"], f, rot=(1.2 * d, 0, 0))
            key_bone(pb["UpperArm_L"], f, rot=(0.8, 0, 0.9))
            key_bone(pb["UpperArm_R"], f, rot=(0.8, 0, -0.9))
            key_bone(pb["Chest"], f, rot=(0.15 * d, 0, 0))

    def clip_curl():
        ensure_action(arm_obj, "AN_Curl", 28)
        reset_pose(arm_obj)
        for f, c in ((1, 0.1), (14, 1.4), (28, 0.1)):
            key_bone(pb["UpperArm_L"], f, rot=(0.15, 0, 0.2))
            key_bone(pb["UpperArm_R"], f, rot=(0.15, 0, -0.2))
            key_bone(pb["LowerArm_L"], f, rot=(-c, 0, 0))
            key_bone(pb["LowerArm_R"], f, rot=(-c, 0, 0))
            key_bone(pb["Chest"], f, rot=(0.05 * c, 0, 0))

    def clip_pull():
        ensure_action(arm_obj, "AN_PullUp", 32)
        reset_pose(arm_obj)
        for f, u in ((1, 0.0), (16, 1.0), (32, 0.0)):
            key_bone(pb["Hips"], f, loc=(0, 0, 0.35 * u))
            key_bone(pb["UpperArm_L"], f, rot=(-2.2 + 0.6 * u, 0, 0.4))
            key_bone(pb["UpperArm_R"], f, rot=(-2.2 + 0.6 * u, 0, -0.4))
            key_bone(pb["LowerArm_L"], f, rot=(-1.0 * (1 - u), 0, 0))
            key_bone(pb["LowerArm_R"], f, rot=(-1.0 * (1 - u), 0, 0))
            key_bone(pb["Chest"], f, rot=(0.2 * u, 0, 0))

    clip_idle()
    clip_walk()
    clip_run()
    clip_bench()
    clip_squat()
    clip_curl()
    clip_pull()

    # NLA strips so glTF exports multiple clips
    if arm_obj.animation_data.nla_tracks:
        for t in list(arm_obj.animation_data.nla_tracks):
            arm_obj.animation_data.nla_tracks.remove(t)
    arm_obj.animation_data.action = None
    for name in ("AN_Idle", "AN_Walk", "AN_Run", "AN_Bench", "AN_Squat", "AN_Curl", "AN_PullUp"):
        act = bpy.data.actions.get(name)
        if act is None:
            continue
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = name
        start = int(act.frame_range[0])
        track.strips.new(name, start, act)

    bpy.ops.object.mode_set(mode="OBJECT")
    reset_pose(arm_obj)


def collider_copy(src, suffix, col="COL_Collision"):
    if src is None or src.type != "MESH":
        return None
    c = src.copy()
    c.data = src.data.copy()
    c.name = src.name + suffix
    c.display_type = "WIRE"
    bpy.data.collections[col].objects.link(c)
    # strip materials
    c.data.materials.clear()
    return c


def phase_collision():
    mapping = {
        "SM_Env_Floor_16x12": "-colonly",
        "SM_Env_Wall_North": "-colonly",
        "SM_Env_Wall_South": "-colonly",
        "SM_Env_Wall_East": "-colonly",
        "SM_Env_Wall_West": "-colonly",
        "SM_Station_Bench": "-convcolonly",
        "SM_Station_Squat": "-convcolonly",
        "SM_Station_Dumbbells": "-convcolonly",
        "SM_Station_PullUp": "-convcolonly",
        "SM_Station_Treadmill": "-convcolonly",
        "SM_Station_Lat": "-convcolonly",
        "SM_Station_Bike": "-convcolonly",
        "SM_Station_Dip": "-convcolonly",
        "SM_Station_Kettlebells": "-convcolonly",
        "SM_Dress_Fridge": "-convcolonly",
        "SM_Dress_Lockers": "-convcolonly",
        "SM_Dress_Booths": "-convcolonly",
    }
    for name, suf in mapping.items():
        obj = bpy.data.objects.get(name)
        collider_copy(obj, suf)


def phase_lookdev():
    # lights not exported
    def add_light(name, ltype, loc, energy, color, size=0.4):
        data = bpy.data.lights.new(name, ltype)
        data.energy = energy
        data.color = color
        if ltype == "AREA":
            data.size = size
        obj = bpy.data.objects.new(name, data)
        bpy.data.collections["COL_Lights"].objects.link(obj)
        obj.location = loc
        return obj

    add_light("LGT_Key", "AREA", (4.0, -6.0, 6.0), 250, (1.0, 0.96, 0.9), 3.0)
    add_light("LGT_NeonCyan", "POINT", (-4.5, 3.0, 3.2), 80, (0.3, 0.9, 1.0))
    add_light("LGT_NeonMag", "POINT", (4.5, -3.2, 3.0), 70, (1.0, 0.25, 0.6))
    add_light("LGT_Fill", "AREA", (-5.0, 4.0, 4.0), 80, (0.7, 0.8, 1.0), 2.0)

    cam_data = bpy.data.cameras.new("CAM_GameplayRef")
    cam_data.lens = 35
    cam = bpy.data.objects.new("CAM_GameplayRef", cam_data)
    bpy.data.collections["COL_Cameras"].objects.link(cam)
    cam.location = (6.5, -8.5, 4.2)
    cam.rotation_euler = (math.radians(62), 0, math.radians(38))
    bpy.context.scene.camera = cam


def set_viewport(azimuth_deg, elevation_deg, distance, target=(0, 0, 1.2)):
    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            r3d = area.spaces[0].region_3d
            az = math.radians(azimuth_deg)
            el = math.radians(elevation_deg)
            eye = Vector(
                (
                    target[0] + distance * math.cos(el) * math.cos(az),
                    target[1] + distance * math.cos(el) * math.sin(az),
                    target[2] + distance * math.sin(el),
                )
            )
            r3d.view_location = Vector(target)
            r3d.view_distance = distance
            direction = (Vector(target) - eye).normalized()
            r3d.view_rotation = direction.to_track_quat("-Z", "Y")
            r3d.view_perspective = "PERSP"
            area.spaces[0].shading.type = "MATERIAL"
            break


def select_collection_objects(col_name, extra=None):
    deselect_all()
    col = bpy.data.collections.get(col_name)
    if col is None:
        return
    for obj in col.objects:
        obj.select_set(True)
    if extra:
        for name in extra:
            o = bpy.data.objects.get(name)
            if o:
                o.select_set(True)


def export_glb(path, objects):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    deselect_all()
    for obj in objects:
        if obj is None:
            continue
        obj.hide_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
    kwargs = dict(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_nla_strips=False,
        export_texcoords=True,
        export_tangents=False,
        export_image_format="JPEG",
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_texcoords", None)
        kwargs.pop("export_tangents", None)
        kwargs.pop("export_yup", None)
        kwargs.pop("export_image_format", None)
        bpy.ops.export_scene.gltf(**kwargs)
    print("EXPORTED", path, "bytes", os.path.getsize(path) if os.path.exists(path) else 0)


def gather(col_name):
    col = bpy.data.collections.get(col_name)
    if col is None:
        return []
    return list(col.objects)


def phase_export():
    os.makedirs(EXPORT_DIR, exist_ok=True)
    os.makedirs(GODOT_MODELS, exist_ok=True)
    env = gather("COL_Geo_Env")
    stations = gather("COL_Geo_Props") + gather("COL_Stations")
    export_glb(os.path.join(EXPORT_DIR, "gym_env.glb"), env)
    export_glb(os.path.join(EXPORT_DIR, "gym_stations.glb"), stations)
    import shutil
    for fn in ("gym_env.glb", "gym_stations.glb"):
        src = os.path.join(EXPORT_DIR, fn)
        dst = os.path.join(GODOT_MODELS, fn)
        if os.path.exists(src):
            shutil.copy2(src, dst)
    for leftover in ("gym_env_colormap.png", "gym_stations_colormap.png", "sk_hero.glb"):
        p = os.path.join(GODOT_MODELS, leftover)
        if os.path.exists(p):
            os.remove(p)


def phase_report():
    total = 0
    lines = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        if obj.name.startswith("REF_"):
            continue
        t = tri_count(obj)
        total += t
        lines.append((t, obj.name))
    lines.sort(reverse=True)
    print("=== KACHALKA TRI REPORT ===")
    for t, n in lines[:40]:
        print(f"{t:6d}  {n}")
    print("TOTAL", total)
    unapplied = []
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        s = obj.scale
        if abs(s.x - 1) > 1e-4 or abs(s.y - 1) > 1e-4 or abs(s.z - 1) > 1e-4:
            unapplied.append(obj.name)
    print("UNAPPLIED_SCALE", unapplied)
    defaults = [o.name for o in bpy.data.objects if o.name.split(".")[0] in ("Cube", "Plane", "Cylinder", "Sphere", "Light", "Camera")]
    print("DEFAULT_NAMES", defaults)
    print("STATIONS", [o.name for o in gather("COL_Stations")])
    return total


def phase_save():
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("SAVED", BLEND_PATH)


def main():
    phase_scene()
    lib = make_materials()
    phase_reference(lib)
    phase_environment(lib)
    phase_stations(lib)
    phase_dressing(lib)
    phase_lookdev()
    set_viewport(40, 18, 16.0, (0, 0, 1.2))
    total = phase_report()
    phase_export()
    phase_save()
    print("BUILD_OK total_tris", total)


if __name__ == "__main__":
    main()
