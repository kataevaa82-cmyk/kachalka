# Export package — КАЧАЛКА v1.0.0

**Date:** 2026-08-30  
**Format:** GLB  
**Scale:** 1 Blender unit = 1 metre  
**Forward after glTF:** −Z (Godot)  
**Up:** +Y  

## Files

| File | Role | Approx size |
|------|------|-------------|
| `godot/assets/models/gym_env.glb` | Shell, lanes, neon, mirrors | ~45 KB |
| `godot/assets/models/gym_stations.glb` | Machines, dressing, `EMP_Station_*` | ~280 KB |
| `godot/assets/models/sk_hero.glb` | SK_Hero + ARM_Hero + AN_* clips | ~130 KB |

## Import notes (Godot 4.7)

- Renderer: Compatibility
- Do not apply extra scale
- Collision in GLB (`-convcolonly`) is **not** used: glTF exporter renamed dashed suffixes. Engine colliders are authored in `gym_world.gd::_build_collision`
- Station detection: nodes whose name starts with `EMP_Station`
- Hero clips: `AN_Idle AN_Walk AN_Run AN_Bench AN_Squat AN_Curl AN_PullUp`

## Validation (Blender build)

- Total authored tris **7096** (budget 25 000) — PASS
- Unapplied scale: none — PASS
- Default names Cube/Plane: none — PASS
- Six station empties present — PASS
- Hero height ~1.72–1.95 m (hair) — PASS
- `mesh.validate()` run on SK_Hero before last export — PASS

## Rebuild

`blender/scripts/build_gym.py` via MCP or Blender `--background --python`.
