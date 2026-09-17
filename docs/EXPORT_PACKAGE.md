# Export package — КАЧАЛКА v1.0.0

**Date:** 2026-08-30  
**Format:** GLB  
**Scale:** 1 Blender unit = 1 metre  
**Forward after glTF:** −Z (Godot)  
**Up:** +Y  

## Files

| File | Role | Approx size |
|------|------|-------------|
| `godot/assets/models/gym_env.glb` | Shell, lanes, neon, mirrors | 330 KB |
| `godot/assets/models/gym_stations.glb` | Machines, dressing, `EMP_Station_*` | 1428 KB |
| `godot/assets/models/fp_arms.glb` | First-person arms (WRAD, CC0) | 446 KB |

The game is first-person only. There is no third-person hero model: an earlier
`sk_hero.glb` was never built, and the code that loaded it has been removed.

## Import notes (Godot 4.7)

- Renderer: Compatibility
- Do not apply extra scale
- Collision in GLB (`-convcolonly`) is **not** used: glTF exporter renamed dashed suffixes. Engine colliders are authored in `gym_world.gd::_build_collision`
- Station detection: nodes whose name starts with `EMP_Station`
- The first-person view is posed from code (`player.gd`), not from animation clips

## Validation (Blender build)

- Total authored tris **7096** (budget 25 000) — PASS
- Unapplied scale: none — PASS
- Default names Cube/Plane: none — PASS
- Sixteen station empties present (15 machines + shop) — PASS
- Eye height 1.62 m, capsule r=0.28 h=1.7 — PASS

## Rebuild

`blender/scripts/build_gym.py` via MCP or Blender `--background --python`.
