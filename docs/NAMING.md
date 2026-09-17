# Naming conventions — КАЧАЛКА

Follows Blender Director prefixes. No spaces, no Cyrillic in file or object names.

## Collections

| Prefix | Use |
|--------|-----|
| `COL_Kachalka` | Root |
| `COL_Reference` | Scale dummy, not exported |
| `COL_Geo_Env` | Shell: floor, walls, ceiling, windows |
| `COL_Geo_Props` | Stations + dressing |
| `COL_Geo_Hero` | Skinned mesh + armature |
| `COL_Collision` | Proxy meshes with Godot suffixes |
| `COL_Stations` | Interaction empties |
| `COL_Lights` | Lookdev only, **not** exported |
| `COL_Cameras` | Lookdev / screenshot, **not** exported |
| `COL_Export` | Instances of export sets |

## Objects

| Prefix | Meaning | Example |
|--------|---------|---------|
| `SM_` | Static mesh | `SM_Env_Floor_16x12` |
| `SK_` | Skinned mesh | `SK_Hero` |
| `ARM_` | Armature | `ARM_Hero` |
| `EMP_` | Empty / socket | `EMP_Station_Bench` |
| `UCX_` | Collision proxy (authoring) | `UCX_SM_Bench-convcolonly` |
| `MAT_` | Material | `MAT_RubberFloor` |
| `LGT_` | Light | `LGT_Neon_Key` |
| `CAM_` | Camera | `CAM_GameplayRef` |
| `REF_` | Non-export reference | `REF_Human_175cm` |
| `AN_` | Action / NLA clip | `AN_Walk` |

## Godot collision suffixes (on the object name, before export)

| Suffix | Godot import |
|--------|----------------|
| `-colonly` | Trimesh collider, mesh hidden |
| `-convcolonly` | Convex collider, mesh hidden |
| `-col` | Visual + trimesh |
| `-convcol` | Visual + convex |

## Files

```
blender/kachalka_gym.blend
blender/export/gym_env.glb
blender/export/gym_stations.glb
godot/assets/models/*.glb
```

## Bone names (ASCII, underscore)

`Root Hips Spine Chest Neck Head`
`UpperArm_L LowerArm_L Hand_L` (+ `_R`)
`UpperLeg_L LowerLeg_L Foot_L` (+ `_R`)
