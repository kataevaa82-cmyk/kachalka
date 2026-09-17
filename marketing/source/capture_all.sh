#!/usr/bin/env bash
# Recreate the native recordings without touching the player's saves.
#
# Linux/macOS counterpart of capture_all.ps1. Records 24 s of real gameplay per
# language with Godot Movie Maker, grabs the desktop and mobile screenshots, then
# encodes and validates the store media.
#
#   GODOT=/path/to/godot ./marketing/source/capture_all.sh
#
# On a headless box it wraps Godot in Xvfb with Mesa's software rasteriser, so it
# works on CI without a GPU. Set XVFB=0 to run against a real display instead.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
marketing_root="$(dirname "$here")"
repo_root="$(dirname "$marketing_root")"
stage="$marketing_root/_work/capture_game"
game="$repo_root/godot"

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || { echo "Godot not found. Set GODOT=/path/to/godot" >&2; exit 2; }
command -v ffmpeg >/dev/null 2>&1 || { echo "ffmpeg not found." >&2; exit 2; }

XVFB="${XVFB:-1}"
run_godot() {
  if [[ "$XVFB" == "1" ]]; then
    LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
      xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" "$@"
  else
    "$GODOT" "$@"
  fi
}

# --- stage a disposable copy -------------------------------------------------
rm -rf "$stage"
mkdir -p "$stage"
for item in project.godot icon.svg assets data scripts scenes; do
  cp -r "$game/$item" "$stage/"
done
# Reuse the main project's import cache: without it the staged copy cannot load the
# imported GLB resources and falls back to parsing them at runtime.
if [[ -d "$game/.godot/imported" ]]; then
  mkdir -p "$stage/.godot"
  cp -r "$game/.godot/imported" "$stage/.godot/"
  for f in global_script_class_cache.cfg uid_cache.bin; do
    [[ -e "$game/.godot/$f" ]] && cp "$game/.godot/$f" "$stage/.godot/"
  done
fi
cp "$here/capture.gd" "$here/capture.tscn" "$stage/"

# A different project name means a different user:// directory, so a capture run
# can never read or overwrite a real player's save.
python3 - "$stage" <<'PY'
import pathlib, sys
stage = pathlib.Path(sys.argv[1])

project = stage / "project.godot"
text = project.read_text(encoding="utf-8")
assert 'config/name="КАЧАЛКА"' in text, "project name not found — capture would share the player's save dir"
project.write_text(text.replace('config/name="КАЧАЛКА"', 'config/name="KachalkaMarketingCapture"'), encoding="utf-8")

# Every run starts from a clean state instead of whatever the last one left.
state = stage / "scripts/autoload/game_state.gd"
text = state.read_text(encoding="utf-8")
assert "\tload_game()" in text, "load_game() call not found — capture would inherit a save"
state.write_text(text.replace("\tload_game()", "\t# Fresh capture state.", 1), encoding="utf-8")
print("staged")
PY

# --- record gameplay ---------------------------------------------------------
mkdir -p "$marketing_root/_work"
for lang in ru en; do
  movie="$marketing_root/_work/gameplay_$lang.avi"
  rm -f "$movie"
  echo "recording gameplay_$lang.avi"
  run_godot --path "$stage" --rendering-driver opengl3 --resolution 1280x720 \
    --disable-vsync --fixed-fps 30 --write-movie "$movie" \
    res://capture.tscn -- "$lang" "out=$marketing_root/yandex"
  [[ -s "$movie" ]] || { echo "Recording produced nothing: $lang" >&2; exit 1; }
done

# --- mobile screenshots ------------------------------------------------------
# capture.gd forces ysdk.deviceInfo's answer itself; nothing to patch here.
for lang in ru en; do
  echo "capturing mobile screenshots ($lang)"
  run_godot --path "$stage" --rendering-driver opengl3 --resolution 1280x720 \
    --disable-vsync --fixed-fps 30 \
    res://capture.tscn -- "$lang" mobile "out=$marketing_root/yandex"
done

python3 "$here/build_videos.py"
python3 "$here/build_preview.py"
python3 "$here/validate_media.py"
