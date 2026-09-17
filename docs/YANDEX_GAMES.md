# Yandex Games — publish notes

Official requirements used for this project (HTML5).

> **Source caveat (11.09.2026):** the official page https://yandex.ru/dev/games/doc/ru/concepts/requirements
> was unreachable when this table was updated. Clause numbers (1.19.x, 1.6.1.8, 2.14) come from search
> snippets of that page and SDK docs, not from the full list. Re-check against the official page before
> submitting the draft.

## Hard requirements mapped

| Requirement | Our implementation |
|-------------|-------------------|
| SDK installed, init per docs (1.1, 1.19.1) | `godot/scripts/yandex/yandex_sdk.gd` + HTML shell `/sdk.js`, single `YaGames.init()` |
| LoadingAPI.ready (1.19.2) | Once per session, when the title menu is interactive |
| GameplayAPI start/stop (1.19.3) | Start in the hall; stop on pause menu, shop, ads, hidden tab. Only on state change, never stop before the first start |
| game_api_pause / resume (1.19.4) | Pause tree + mute + save; resume only if the player had not paused manually |
| Pause + mute when tab hidden | `visibilitychange` in the SDK bridge; SDK and tab reasons are combined, resume only when both are gone |
| Silent during ads | `Audio.hold_mute("ad")` around every `showFullscreenAdv` / `showRewardedVideo`; the same reason counter as the tab mute, so an ad inside a hidden tab cannot un-mute early |
| Sound and music can be turned off | Pause menu toggles, stored in the save (`sfx_on`, `music_on`) and therefore synced to the cloud |
| Play without login | `getPlayer({ scopes: false })`, local save always works |
| Desktop fill | stretch `canvas_items` + `expand` |
| Keyboard + mouse | WASD / mouse look (click to capture) / E / Space / Esc |
| Mobile touch | joystick + look pad + on-screen buttons, only on mobile and tablets |
| Desktop vs mobile detection | `ysdk.deviceInfo.type` (`GameState.is_touch()` → `YandexSDK.is_mobile_device()`). The touchscreen probe is only the guess before the SDK answers: a touch-capable laptop is a desktop player and must keep mouse look |
| Layout follows the window | HUD relayouts on `size_changed` and on `device_resolved`, so rotation and leaving fullscreen are handled |
| No keyboard hints on mobile | `GameState.is_touch()`; `hint_touch` in `stations.json`, key letters hidden, `E —` stripped |
| No page scroll / zoom / selection / long-tap menu (1.6.1.8) | Shell CSS `touch-action:none`, `user-select:none`, `-webkit-touch-callout:none`, `overscroll-behavior:none`; `contextmenu`, `selectstart`, `dragstart`, `wheel`, scroll keys blocked |
| Language auto-detect (2.14) | `scripts/autoload/loc.gd`: `?lang=` / browser language until the SDK answers, then `ysdk.environment.i18n.lang`; English table `data/i18n_en.json` (Russian source text is the key), cash shown as `$` in English |
| No broken glyphs | UI font Inter (`godot/assets/fonts`, SIL OFL); the default engine font had no ₽ → ► |
| File names ASCII, no spaces | Enforced |
| Uncompressed ≤ 100 MB | ~40 MB (wasm 39.5 MB + pck ~1 MB) |
| index.html at archive root | `godot/export/Kachalka_Yandex.zip` |
| No external links, no in-game generative AI | Pre-authored assets only |

## Console settings (not in code)

- Languages: **Russian + English**. The game picks the language from `ysdk.environment.i18n.lang` (2.14): ru/be/kk/uk/uz → Russian, anything else → English. The console needs an English name, description, cover and screenshots too (in-game English title: «KACHALKA»).
- Mobile orientation: **landscape** (the UI is laid out for 16:9; the platform shows its own "rotate" screen).
- Leaderboard: technical name `mass`, numeric, DESC. Code sends `int(mass * 10)`; the pause menu reads the top 10 back via `getEntries` and offers `auth.openAuthDialog()` to anonymous players (never automatically — an unprompted login dialog is a moderation finding).
- Age rating: **12+**. The shop sells a pre-workout supplement; nothing else in the build touches a rating trigger.
- Name in the console must match the in-game title: **Качалка: ещё один повтор** / **Kachalka: one more rep**.

## Store media (re-recorded 17.09.2026)

Prepared package: `marketing/yandex/preview.html`, `marketing/Kachalka_Yandex_Media.zip`.
Re-recorded from the current build with `marketing/source/capture_all.sh` (Godot 4.7.1,
Xvfb + Mesa software rasteriser on a headless box). The gameplay clips now carry the
game's own synthesised audio, which Movie Maker writes alongside the frames; the field
limits themselves were last checked against the Yandex docs on 11.09.2026 and were not
re-read for this pass.
Copy the exact per-language fields from `marketing/yandex/{ru,en}/texts.txt` or `metadata.json`.
The title scene and web shell use the new name; the internal Godot project name stays unchanged to preserve the existing save directory.
Media sizes and copy limits were checked against https://yandex.ru/dev/games/doc/ru/console/add-new-game/draft (the page was accessible during this media task).
See `marketing/yandex/README.md` for recording provenance and limitations.

## Export

1. Godot: Project → Export → **YandexGamesWeb**
2. Renderer Compatibility
3. Threads: **Off** (single-thread)
4. Custom HTML: `godot/export/yandex_shell.html`
5. Output: `godot/export/web/index.html`
6. Zip **contents** of `web/` (index.html at root of zip), upload draft

## Audio

Everything is synthesised at runtime into `AudioStreamWAV` (`scripts/autoload/audio.gd`).
No audio files ship, so there is no third-party audio licence and no bytes in the pck.
SFX are built at boot (~350 k samples); the two loops are built at 11 025 Hz one per
frame **after** the title screen has called `LoadingAPI.ready()`, so the platform
handshake is never held up by DSP. Loops are peak-normalised and seam-checked.

## Ads policy in-game

- Interstitial only between sets, after 4 completed sets (the SDK also enforces its own minimum interval)
- Never on first interaction
- Rewarded is optional energy, labelled «Смотреть рекламу: +60 энергии», gameplay available without it
- Game tree paused + gameplay stopped during ads
- Reward is granted on `onRewarded`, but gameplay resumes only after `onClose`
- Audio is muted for the whole ad and un-muted only when every mute reason is gone

## Checklist before draft submit

- [ ] Cold boot on Yandex Browser desktop
- [ ] Chrome Android + iOS Safari
- [ ] Pause when switching tabs
- [ ] Rewarded mock + real
- [ ] Save survives reload
- [ ] No WebGL banner
- [ ] Debug panel (`?debug-mode=16`): LoadingAPI / GameplayAPI events look correct
- [ ] **Pointer lock inside the Yandex iframe** — mouse look dies on desktop if the host frame does not allow it; test on the real draft, not locally
- [ ] Sound plays, and goes silent for the whole ad
- [ ] Sound/music toggles survive a reload
- [ ] Leaderboard opens; anonymous players see the sign-in button
- [ ] Touch laptop on desktop Yandex Browser still gets mouse look, not the joystick
