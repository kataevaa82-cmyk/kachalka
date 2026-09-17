# Asset Pipeline — КАЧАЛКА

## Law

1. **Author in Blender, play in Godot.** Geometry never starts in the engine.
2. **1 BU = 1 m.** Scale reference `REF_Human_175cm` stays in every `.blend`.
3. **Collections first.** No object in Scene Collection dump.
4. **Name before you model.** Default `Cube` is a pipeline error.
5. **Origin = contact.** Feet / floor / wall grid.
6. **Apply scale** before weights, collision, export.
7. **Principled BSDF only.** No Shader-to-RGB, no custom groups at export.
8. **Collision ≠ render.** Godot suffix meshes, convex preferred.
9. **Export GLB.** Copy to `godot/assets/models/`. Godot import is the QA gate.
10. **Document the change** in `docs/production/PRODUCTION_LOG.md`.

## Rebuild

```text
Blender MCP: execute blender/scripts/build_gym.py
# or headless
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background --python blender/scripts/build_gym.py
```

Script is idempotent: clears `COL_Kachalka` contents and rebuilds.

## Phases inside `build_gym.py`

| Phase | Output |
|-------|--------|
| scene | units, collections, world, ref human |
| materials | MAT_* library |
| environment | 16×12 shell, mirrors, neon sign, mats |
| stations | 15 machines + shop, EMP_Station_* |
| dressing | fridge, cooler, posters, plates |
| collision | *-colonly / *-convcolonly |
| export | 2 GLB + copy to Godot |
| report | tri counts printed |

## Import in Godot

GLB files live in `godot/assets/models/`. The game loads them at **runtime** via `GLTFDocument` (`scripts/gym/gltf_runtime.gd`) so the project runs without an editor `.import` cache (required for headless CI and Yandex web). Opening the project in the Godot editor will also generate `.import` files; both paths are valid.

1. Copy GLB into `godot/assets/models/` (the Blender script already does this)
2. Play `scenes/boot/title.tscn` → `scenes/gym/gym.tscn`
3. Measure hero in editor (~1.72 m plus hair)
4. Confirm station empties `EMP_Station_*` appear under `StationsMount`

## Validation gate (must all pass)

- [ ] Tri total < 25 000
- [ ] No unapplied scale on export objects
- [ ] No objects named Cube/Plane/Cylinder
- [ ] Hero origin at z=0 (Blender), feet on floor
- [ ] Station empties present
- [ ] GLB opens in Godot without pink materials
- [ ] Walk clip loops
- [ ] Convex colliders keep player out of benches
