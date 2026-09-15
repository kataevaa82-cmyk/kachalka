# Production log

## 2026-08-30 — kickoff

- Target: 3D gym simulator for Yandex Games, Blender + Godot.
- Blender MCP connected: Blender 5.2.0 LTS, addon protocol 4.
- Default scene (Cube/Light/Camera) is **not** production — will be replaced.
- Docs written: brief, GDD, technical, art bible, pipeline, naming, Yandex.
- Next: scene setup → blockout → stations → hero → export → Godot gameplay.

## 2026-08-30 — Blender build v1

- Ran `blender/scripts/build_gym.py` on Blender 5.2 LTS via MCP.
- Scene: 16×12×4.2 m night gym, 2 m grid, 5 stations + shop fridge.
- Hero: SK_Hero 536 tris, ARM_Hero 18 bones, 7 NLA clips.
- **Tri total 7096** (includes collision copies; gameplay uses Godot boxes).
- GLB copied to `godot/assets/models/`.
- Viewport QA: interior camera at (5.4, −4.6, 2.55) — gym readable (pull-up, fridge, neon, lanes, hero).
- Note: glTF exporter stripped `-convcolonly` to `.001`. Collision moved to engine.
- Note: first screenshots were ceiling-on-outside; camera moved inside (documented).

## 2026-08-30 — Godot v1

- Project Godot 4.7 Compatibility, autoloads GameState + YandexSDK.
- Loop: walk → interact → timing set → muscle bone scale → shop / ads.
- Yandex: init mock, interstitial every 4 sets, rewarded energy, leaderboard `mass`, pause API.

## 2026-08-30 — Windows exe

- Preset `Windows Desktop`, x86_64, Compatibility, `embed_pck=true`.
- Export: `godot/export/windows/Kachalka.exe` (also copied to repo root `Kachalka.exe`).
- Single file, ~104 MB (release template + packed game). No separate `.pck`.

## 2026-08-30 — close reception entrance

- Reception south wall (Blender Y=-10.1 / Godot z=+10.1) had a 1.6 m exterior door into empty space. Player walked out of spawn and fell.
- Visual: closed double wood doors + handles fill the opening (`SM_Env_Recep_DoorL/R`). Interior doors stay open.
- Collision: solid `_wall_z(10.1, -4.1, 4.1)` plus a 1.8×2.2×0.36 door slab. Floor thickened to 0.5 m (top still y=0). Player `floor_snap_length` 0.4.
- Rebuild: Blender `BUILD_OK` 150414 tris, `gym_env.glb` 312932. Godot export 19:55:38 → `C:\kach\Kachalka.exe` (111686256 bytes).

## 2026-08-30 — shop door, booths, workout viz

- Shop north door was a bare hole. Now a storefront: chrome jambs, threshold, transom sign + green neon, glass leaves parked open inside the bar. Clock moved off the doorway onto the bar east wall; TV onto the west wall. Shop EMP sits in front of the counter (y=7.55), not in the opening.
- Locker room: removed floating `LockBench` pads. 10 lockers in a continuous west-wall bank. Three changing booths with partitions, curtain rods, seats and hooks along the south wall. Sit bench + mirror on the north wall.
- Workout: first-person arms + station-specific camera (bench looks up, squat drops, pull-up rises). Cyan ring + warm omni at the station. Hits flash the screen and punch FOV. Dim overlay dropped to 0.10 so the hall stays visible.
- Rebuild: Blender `BUILD_OK` 176914 tris. Export 20:11:21 → `C:\kach\Kachalka.exe` (112048960 bytes).

## 2026-08-30 — Kenney props, shop door, stalls, reception

- Shop entrance black slab was dark glass + iron shopfront (alpha reads black in Compatibility). Replaced with cream jambs and Kenney Building Kit doors parked open. Green sign stays.
- Reception box clutter (scale disc, trophy case, sandwich board, blob plant, fake desk) replaced with Kenney Furniture Kit CC0: desk, office chair, monitor, keyboard, laptop, lamp, potted plants, coat rack, trash, waiting chairs.
- Changing booths rebuilt as laminate stalls with floor gap, ajar doors, hooks, occupancy dots — not dark curtains.
- Lockers are steel gym lockers (vents, number plates, legs).
- Assets: `blender/vendor/kenney_furniture` + `kenney_building` (CC0, Kenney.nl).
- Blender `BUILD_OK` 221280 tris. Export 20:27:34 → `godot/export/windows/Kachalka.exe` and `C:\kach\Kachalka_new.exe` (root `Kachalka.exe` was locked by a running process).

## 2026-08-30 — quest board

- 3 live gym tasks always on the HUD (жим, комбо, чистый сет, круговая, кардио, гири, турник, касса…). 30+ templates in `data/quests.json`, scaled by mass/unlocks.
- Rewards: cash + energy. Every 5th quest: «герой дня» bonus.
- Workout hint shows the related task. Shop visit counts. Completing a task immediately rolls a new one.
- Export 20:36:42, no script errors → `C:\kach\Kachalka_new.exe`.

## 2026-08-30 — layout, doors, WC

- Screenshots showed: north-wall mirror covering the shop door (black rectangle); Kenney `door-rotate` leaves not filling the reception opening and sticking 0.8 m into the room; desk on the spawn aisle.
- Shop: mirror split left/right of the doorway. Open cream frame, no door leaves. You can see the bar and stools through it.
- Reception south: flush wood double doors filling 1.6×2.15. Desk moved to the east wall, chairs west, center aisle free.
- WC west of reception (door in west wall): two Kenney toilets in stalls + sink and mirror.
- Export 21:40:54 → `godot/export/windows/Kachalka.exe` and `C:\kach\Kachalka_layout.exe`.

## 2026-08-30 — orientations, shop TV, white posters

- Kenney glTF stayed in quaternion mode so `rotation_euler` was ignored; import now forces XYZ. Toilet bowl is local +Y (tank −Y); sit/screen/cabinet front are local −Y.
- Chair faces the desk (rotZ −90). Waiting chairs face the aisle. Toilets: tank to west wall, bowl into the stall (rotZ −90).
- Shop TV no longer floats: Kenney cabinet against the west wall, TV sitting on it, screen into the room.
- Removed wall posters, non-reflective north-wall mirrors, and gray wall pads that read as blank white posters.
- Export 22:30:45 → `godot/export/windows/Kachalka.exe`, `C:\kach\Kachalka.exe`, `Kachalka_new.exe`, `Kachalka_layout.exe` (112667536 bytes).

## 2026-09-01 — full audit, five new levels, Yandex hardening

- Added five real progression stages after the starter hall: Районный зал, Железный цех, Неоновая лига, Арена чемпионов, Кузница титанов. Thresholds: 70 / 82 / 96 / 112 / 128 kg.
- Each level has a visual theme plus period/window/cash/gain modifiers. HUD and a 3D hall sign show the active stage.
- Added automated progression simulation: all levels unlock strictly 1→6; level 6 is reachable at 128.86 kg using only currently unlocked stations.
- Fixed save migration, cloud/local reconciliation, prop quests, clean-set streaks, repeated gear purchase, gloves forgiveness and ad counter persistence.
- Fixed Yandex lifecycle: persistent JavaScript callbacks, queued Loading/Gameplay calls, cloud player cache, leaderboard availability check and pause/resume preservation.
- Rewarded ads now wait for `onClose` before gameplay resumes; both ad types use a 180 s safety timeout instead of incorrectly resuming after 8–10 s.
- Web preset and custom shell restored. Generated export folders are excluded from PCK; removed a 141 MB temporary Chrome profile that had been scanned as project content.
- Validation: Godot smoke PASS, 15 stations + 11 props reachable, browser SDK contract PASS, Blender 226 objects / 205 meshes / 91 materials / 0 missing images.
