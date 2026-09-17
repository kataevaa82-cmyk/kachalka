# Production Brief: КАЧАЛКА

**Date:** 2026-08-30  
**Engine:** Godot 4.7.1 (GL Compatibility / WebGL 2.0)  
**DCC:** Blender 5.2.0 LTS via MCP  
**Target store:** Яндекс Игры (HTML5)  
**Scale law:** 1 Blender Unit = 1 metre = 1 Godot unit  

## Type

Full 3D session: environment kit + hero character + interactable stations + set dressing.

## Target

| Item | Value |
|------|--------|
| Platform | Desktop + mobile browsers (Yandex Games) |
| Renderer | `gl_compatibility` only (Godot 4 web cannot use Forward+/Mobile) |
| Package budget | < 100 MB uncompressed (store hard limit) |
| Soft budget | < 25 MB exported zip, first paint < 8 s on 4G |
| Session length | 2–8 minutes, return loop via energy + ads |

## Style

Stylized **low-poly** gym, readable silhouettes, saturated night-gym palette (charcoal rubber, chrome, neon cyan/magenta, tank-top red). Vertex-color / solid PBR, no micro-bevels, no subdivision.

## Poly / texture budgets

| Asset | Tris | Texture |
|-------|------|---------|
| FP arms (`fp_arms.glb`) | 1 500–3 000 | solid PBR, no maps |
| Gym shell (floor/walls/ceiling) | 2 000–4 000 | solid + vertex color |
| Station (each) | 200–800 | solid PBR |
| Set dressing prop | 50–300 | solid PBR |
| **Scene total** | **< 25 000** | no atlas > 512 |

## Export

- Format: **GLB**
- +Y up, modifiers applied, extras on
- Collision as Godot suffix meshes (`-convcolonly`, `-colonly`)
- Pivot: hero at feet; props at floor contact; modular walls on 2 m grid
- Animations: NLA clips `AN_Idle`, `AN_Walk`, `AN_Bench`, `AN_Squat`, `AN_Curl`, `AN_PullUp`, `AN_Run`

## Pivot / animation

- Hero: origin at ground between heels, facing −Y in Blender (GLTF → Godot −Z)
- Stations: origin on floor, interaction empty `EMP_Station_*` at stand point
- Animation: skeletal, 30 fps, looping clips, no root motion except Walk/Run in-place

## Active skills (pipeline order)

1. **blender-director** — brief, budgets, naming, validation
2. **lowpoly-style** — silhouette, poly caps, flat shading language
3. **genre-card-party-idle** — readable stations as “3D icons”, UI stage camera
4. **environment-artist** — 2 m interior grid, modular shell, set dressing
5. **blender-modeler** — collections, origins, cleanup
6. **prop-artist** — bench, rack, dumbbells, treadmill, fridge
7. **character-artist** — stylized hero, joint loops, muscle-scale bones
8. **rigging / animation** — humanoid bones, workout clips
9. **collision-proxy** — boxes/convex, Godot suffixes
10. **asset-optimization** — tri count, draw-call count (material slots)
11. **godot-export** — GLB, extras, import verify
12. **qa-review** — screenshots + engine import

## Pipeline phases

- [x] Reference & Planning (this brief + GDD + tech + art bible)
- [x] Blockout & Silhouette
- [x] Modeling
- [x] Cleanup & Topology
- [x] UVs (smart project, engine-legal)
- [x] Materials (Principled BSDF only)
- [x] Hero rig + clips
- [x] Collision proxies (engine boxes; GLB suffixes not trusted)
- [x] Optimization (7096 tris << 25k)
- [x] Export & Godot runtime GLB load
- [x] Gameplay / Yandex SDK
- [x] Validation report (`docs/EXPORT_PACKAGE.md`)

## MCP execution plan

1. Units metric, collections `COL_*`, scale ref 1.75 m
2. Gym shell on 2 m grid (16 × 12 × 4.2 m)
3. Fifteen stations + shop + dressing
4. First-person arms (`fp_arms.glb`, WRAD CC0)
5. Collision + station empties
6. Viewport QA screenshots (front, side, top, gameplay camera)
7. Export `gym_env.glb`, `gym_stations.glb`
8. Copy into `godot/assets/models/`
