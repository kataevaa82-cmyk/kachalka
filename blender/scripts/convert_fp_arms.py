"""Convert WRAD CC0 FPS arms to Godot viewmodel GLB."""
import bpy
import math
import os
import shutil
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "blender", "vendor", "fp_arms", "wrad", "src", "arms.glb")
TEX = os.path.join(ROOT, "blender", "vendor", "fp_arms", "wrad", "src", "arm_albedo_pale.png")
OUT_GODOT = os.path.join(ROOT, "godot", "assets", "models", "fp_arms.glb")
OUT_BLEND = os.path.join(ROOT, "blender", "export", "fp_arms.glb")
LIC_SRC = os.path.join(ROOT, "blender", "vendor", "fp_arms", "wrad", "src", "LICENSE.txt")
LIC_DST = os.path.join(ROOT, "godot", "assets", "models", "fp_arms_LICENSE.txt")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

print("OBJECTS")
for o in bpy.data.objects:
    print(" ", o.name, o.type, "loc", tuple(round(v, 4) for v in o.location), "parent", o.parent.name if o.parent else None)
    if o.type == "MESH":
        bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
        xs = [v.x for v in bb]; ys = [v.y for v in bb]; zs = [v.z for v in bb]
        print("   verts", len(o.data.vertices), "bbox", (round(min(xs),3), round(min(ys),3), round(min(zs),3)), "->", (round(max(xs),3), round(max(ys),3), round(max(zs),3)))
        print("   mats", [s.name if s else None for s in o.data.materials])
    if o.type == "ARMATURE":
        print("   bones", [b.name for b in o.data.bones])

# Bind pale albedo if missing
if os.path.isfile(TEX):
    img = bpy.data.images.load(TEX)
    img.pack()
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        has_tex = False
        for l in nt.links:
            if l.to_socket == bsdf.inputs["Base Color"] and l.from_node.type == "TEX_IMAGE":
                has_tex = True
                l.from_node.image = img
        if not has_tex:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = img
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.48
        print("MAT", mat.name)

# Drop helper meshes (icosphere / head gizmo).
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.lower() != "arms_mesh":
        print("DELETE", o.name)
        bpy.data.objects.remove(o, do_unlink=True)

arm = bpy.data.objects.get("arms")
if arm is None:
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
arm.name = "FPArms"
# Author units are huge (~11 m wide). Shrink to camera viewmodel size.
arm.scale = (0.08, 0.08, 0.08)
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
print("SCALED", arm.name, "scale", tuple(arm.scale))
mesh = bpy.data.objects.get("arms_mesh")
if mesh:
    bb = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
    xs = [v.x for v in bb]; ys = [v.y for v in bb]; zs = [v.z for v in bb]
    print("MESH_BBOX", (round(min(xs), 3), round(min(ys), 3), round(min(zs), 3)), "->", (round(max(xs), 3), round(max(ys), 3), round(max(zs), 3)))

os.makedirs(os.path.dirname(OUT_GODOT), exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
kwargs = dict(
    filepath=OUT_GODOT,
    export_format="GLB",
    use_selection=True,
    export_apply=True,
    export_yup=True,
    export_cameras=False,
    export_lights=False,
    export_animations=True,
    export_skins=True,
    export_morph=False,
    export_extras=True,
    export_image_format="AUTO",
)
try:
    bpy.ops.export_scene.gltf(**kwargs)
except TypeError:
    kwargs.pop("export_yup", None)
    kwargs.pop("export_extras", None)
    bpy.ops.export_scene.gltf(**kwargs)

shutil.copy2(OUT_GODOT, OUT_BLEND)
if os.path.isfile(LIC_SRC):
    shutil.copy2(LIC_SRC, LIC_DST)
print("EXPORTED", OUT_GODOT, os.path.getsize(OUT_GODOT))
