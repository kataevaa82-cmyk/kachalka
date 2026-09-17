# Technical Design — КАЧАЛКА

## Stack

| Layer | Choice | Why |
|-------|--------|-----|
| DCC | Blender 5.2 LTS | MCP production, GLB exporter |
| Engine | Godot 4.7.1 | HTML5, GDScript, GLTF first-class |
| Renderer | Compatibility / WebGL 2.0 | Only web path in Godot 4 |
| Physics | Godot Jolt/default 3D, CharacterBody3D | Simple capsule + static convex |
| UI | Control / theme | Touch + keyboard |
| Platform | Yandex Games JS SDK via `JavaScriptBridge` | Store requirement |

## Directory law

```
kach/
  docs/                 design + pipeline (source of truth)
  blender/              .blend, scripts, export GLB, screenshots
  godot/                runnable game
    assets/models/      imported GLB only (no .blend)
    scenes/             tscn by domain
    scripts/            gd by domain
    data/               json tables
  tools/                helpers
```

Godot never authors geometry. Blender never owns gameplay numbers.

## Coordinate / scale

| App | Up | Forward (character) | Unit |
|-----|----|---------------------|------|
| Blender | +Z | −Y | 1 m |
| glTF | +Y | −Z | 1 m |
| Godot | +Y | −Z | 1 m |

Export: `export_yup=True`, `export_apply=True`. After import, hero height must measure **1.72 ± 0.03 m**. Bench pad height **~0.45 m**.

## Scene graph (Godot)

```
Title (Control)             scenes/boot/title.tscn
Game (Node3D)               scenes/gym/gym.tscn
  EnvMount                  gym_env.glb loaded at runtime
  StationsMount             gym_stations.glb, EMP_Station_* empties
  Props                     built in code by gym_world.gd
  Player (CharacterBody3D)  scenes/player/player.tscn
    CollisionShape3D          capsule r=0.28 h=1.7
    Head/Camera3D             first person, eye height 1.62 m
      FPView                  fp_arms.glb, posed from code
  CanvasLayer HUD           hud.gd — vitals, prompt, pause, leaderboard, credits
  CanvasLayer Workout       workout_overlay.gd — the 15 minigames
  CanvasLayer Shop          shop_panel.gd
```

Autoloads, in order: `Loc`, `GameState`, `YandexSDK`, `Audio`. Audio is last because
it only touches `AudioServer` in `_ready`; the other three are readable by then.

## Movement

- `CharacterBody3D`, max speed 3.4 m/s, accel 18, gravity 9.8
- Camera: third-person, distance 4.2 m, height 1.7 m, mouse 0.12, touch 0.18
- Floor snap 0.2 m
- Interaction: Area3D on `EMP_Station_*`, nearest in 1.6 m

## Workout state machine

`Idle → Prompt → SetActive → Recover → Idle`

`SetActive` disables locomotion, parents hero to station pose empty, plays clip, drives timing HUD.

## Data tables

`godot/data/stations.json`, `shop.json` — designers edit numbers, not scripts.

## Performance budget (web)

| Metric | Budget |
|--------|--------|
| Tris on screen | < 30 k |
| Materials / draw calls | < 40 |
| Realtime lights | 1 directional + 2 omni (neon), no shadows on mobile |
| Texture RAM | < 8 MB (mostly unused in v1) |
| Scripts | no per-frame `find_child` |
| Threads | **single-thread** web export (SharedArrayBuffer policy) |

## Save schema v3

```json
{
  "v": 3,
  "chest": 0,
  "arms": 0,
  "back": 0,
  "legs": 0,
  "cardio": 0,
	"energy": 100,
	"fatigue": 0,
	"hygiene": 100,
	"recovery": 80,
	"money": 0,
	"inv": {},
	"total_reps": 0,
	"combo_best": 0,
	"sets_since_ad": 0,
	"active_quests": [],
	"quests_done": 0,
	"quest_seen": {},
	"saved_at": 0
}
```

Legacy v1 nested `stats` saves are migrated. Local and Yandex cloud saves are reconciled by `saved_at`, with progress rank as fallback for timestamp-less legacy data.

## Yandex SDK surface

| API | When |
|-----|------|
| `YaGames.init` | Boot, before gameplay_start |
| `features.LoadingAPI.ready` | When the title menu becomes interactive |
| `gameplay.start/stop` | Enter/leave gym, pause |
| `adv.showFullscreenAdv` | After 4 sets |
| `adv.showRewardedVideo` | Energy/protein |
| `getPlayer` + `setData/getData` | Cloud save |
| `isAvailableMethod` + `leaderboards.setScore('mass', int)` | After each completed set |
| `on('game_api_pause/resume')` | Pause tree + mute |

Mock path in editor: local JSON, fake ads succeed in 0.4 s.

## Risk register

| Risk | Mitigation |
|------|------------|
| WebGL 2 Safari | Compatibility renderer, no clustered lights |
| Autoplay audio | start silent, unmute on first gesture |
| Godot web size | no C#, strip unused modules, no large audio |
| MCP disconnect | `blender/scripts/build_gym.py` rerunnable headless |
| Bone name mismatch | documented in NAMING.md, assert on import |
