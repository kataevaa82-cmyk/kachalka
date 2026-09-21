# Custom Godot web export template

`godot/export_presets.cfg` points the **YandexGamesWeb** preset at
`web_nothreads_release.zip` in this folder instead of the stock template.

## Why

The stock Godot 4.7.1 web release template is a 37.7 MiB wasm. The game itself
is 0.7 MiB, so the engine is ~98% of what a player downloads. The only
lever on that is compiling the engine without the parts this game never
touches.

| | wasm | template zip (≈ what transfers, gzipped) |
|---|---|---|
| stock 4.7.1 | 37.68 MiB | 9.77 MiB |
| this build | 31.70 MiB | 8.09 MiB (−17%) |

## What was removed

Verified unused by grepping the shipped scripts (`godot/scripts`,
`godot/scenes`) — `godot/tools` is excluded from the export and does not count:

- **Networking** — enet, multiplayer, webrtc, websocket, upnp, jsonrpc. The
  Yandex SDK is reached through `JavaScriptBridge`, not Godot's networking.
- **Audio codecs** — ogg, vorbis, mp3, theora, interactive_music. Every sound
  is synthesised into an `AudioStreamWAV` at runtime; the project ships no
  audio files at all.
- **XR** — openxr, webxr, mobile_vr.
- **3D extras** — csg, gridmap, navigation_2d/3d, vhacd, raycast,
  lightmapper_rd, xatlas_unwrap, meshoptimizer, noise.
- **Import-time codecs** — bmp, dds, hdr, jpg, ktx, tga, tinyexr, bcdec, betsy,
  astcenc, cvtt, etcpak, basis_universal. These run in the editor when
  importing, never in the exported build.
- **Editor-only** — visual_shader, msdfgen, fbx, glslang, objectdb_profiler.
- **Other** — zip, regex, camera, and `deprecated=no`.

The gltf removal needed a code change to go with it:

- **gltf** — `scripts/gym/gltf_runtime.gd` has a fallback that parses a `.glb`
  at runtime when the import cache is missing. That never happens in an
  exported build, where the import remap always resolves. The fallback now
  reaches the classes through `ClassDB.instantiate` so the script still parses
  with the module absent, and simply returns null there.

## What was tried and put back

**text_server_adv → text_server_fb.** The advanced text server is the single
biggest thing left in the build: HarfBuzz, ICU and Graphite, plus a 4.7 MB ICU
data blob, for complex shaping and bidi a Russian/English game has no use for.
Dropping it took the template to 7.25 MiB.

It also made every string in the game disappear — Latin as well as Cyrillic.
Inter is a variable font and the UI asks for weight 600, which only the
advanced server can interpolate. Pinning the weight into the file did not help
either: the before and after screenshots came back byte-identical. The
fallback server is not a drop-in here, so `text_server_adv` stays.

The weight is pinned anyway (see `tools/subset_font.py`) because it is smaller
and one less thing resolved at runtime. Anyone retrying the fallback server
should start by rendering a label in a plain non-variable font.

## Rebuilding

Needed after a Godot version bump, or to change the module set. Takes roughly
40 minutes on 4 cores.

```sh
pip install scons
git clone --depth 1 --branch 4.7.1-stable https://github.com/godotengine/godot.git
git clone --depth 1 https://github.com/emscripten-core/emsdk.git
cd emsdk && ./emsdk install latest && ./emsdk activate latest && source ./emsdk_env.sh && cd -
cd godot && bash ../tools/godot-web-template/build.sh
```

`build.sh` carries the full flag list. Copy
`bin/godot.web.template_release.wasm32.nothreads.zip` over
`web_nothreads_release.zip` here, then re-run the checks below.

## Going back to the stock template

Set `custom_template/release=""` in the `[preset.1.options]` block of
`godot/export_presets.cfg`. Nothing else depends on this build — the game runs
on the stock template unchanged, it just downloads more.

## Verifying a new build

All three must pass before shipping one:

```sh
godot --headless --path godot res://tools/smoke_scene.tscn     # SMOKE_PASS
godot --headless --path godot --export-release "YandexGamesWeb" export/web/index.html
node tools/browser_smoke.mjs                                   # real Chrome, mock Yandex SDK
# SHOT=/tmp/gym.png node tools/browser_smoke.mjs  — same run, but saves a frame
```

The browser run is the one that matters here: it is the only check that
exercises the custom wasm rather than the editor binary, and it covers canvas
rendering, `LoadingAPI.ready`, `GameplayAPI` start/stop across SDK pause and
tab visibility, and the page-level CSS rules Yandex requires.
