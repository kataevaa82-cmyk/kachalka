#!/usr/bin/env python3
"""Cut Inter down to the glyphs this game can actually draw.

The full face is 2937 glyphs and 343 KB — most of the project's download that
is not the engine — while the game only ever renders Latin, Cyrillic and a
handful of symbols. Subsetting takes it to ~48 KB.

Re-run this after adding text in a new script, alphabet or symbol, otherwise
the new characters render as empty boxes:

    python3 tools/subset_font.py

It reads the pristine face from tools/fonts/Inter.full.woff2 and writes
godot/assets/fonts/Inter.woff2. Inter is SIL OFL with no Reserved Font Name, so
subsetting and keeping the name is permitted.
"""
import glob
import json
import pathlib
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
GODOT = ROOT / "godot"
# The pristine face lives outside the Godot project on purpose: anything under
# godot/ gets imported and shipped, and 343 KB of unused glyphs is the thing
# this script exists to avoid.
SRC = ROOT / "tools/fonts/Inter.full.woff2"
DST = GODOT / "assets/fonts/Inter.woff2"

# Anything a format string, a quest line or the smoke test's glyph guard can
# put on screen but that no literal in the repo spells out.
EXTRA = (
    "".join(chr(c) for c in range(0x20, 0x7F))          # Basic Latin
    + "".join(chr(c) for c in range(0x0410, 0x0450))    # А-я
    + "ЁёЇїІіЄєҐґ"                                      # other Cyrillic the SDK may hand us
    + "₽$€—–…«»„“”‘’·•→←►◄▲▼✓✕×°±№%‰@©®™"
    + "    "
)


def _strings():
    for path in sorted(glob.glob(str(GODOT / "data/*.json"))):
        def walk(o):
            if isinstance(o, str):
                yield o
            elif isinstance(o, dict):
                for k, v in o.items():
                    yield k
                    yield from walk(v)
            elif isinstance(o, list):
                for v in o:
                    yield from walk(v)
        yield from walk(json.load(open(path, encoding="utf-8")))

    # Comments are not rendered, so only quoted literals count.
    globs = ["scripts/**/*.gd", "scenes/**/*.tscn"]
    for g in globs:
        for path in sorted(glob.glob(str(GODOT / g), recursive=True)):
            src = pathlib.Path(path).read_text(encoding="utf-8")
            for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', src):
                yield m.group(1)


def main():
    if not SRC.exists():
        sys.exit("missing %s — keep the unsubsetted face next to the subset one" % SRC)
    text = EXTRA + "".join(_strings())
    font = TTFont(SRC)
    before = len(font.getGlyphOrder())
    opts = subset.Options()
    opts.layout_features = ["kern", "liga", "calt", "locl", "ccmp"]
    opts.drop_tables += ["DSIG"]
    opts.notdef_outline = True
    s = subset.Subsetter(options=opts)
    s.populate(text=text)
    s.subset(font)
    font.flavor = "woff2"
    font.save(DST)
    print("glyphs %d -> %d, %d KB -> %d KB" % (
        before, len(TTFont(DST).getGlyphOrder()),
        SRC.stat().st_size // 1024, DST.stat().st_size // 1024))


if __name__ == "__main__":
    main()
