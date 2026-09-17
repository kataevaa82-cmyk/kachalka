"""Validate final assets against the recorded Yandex Games submission limits."""
from pathlib import Path
import datetime
import json
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1] / "yandex"
# checked_on is when the limits below were last read off the Yandex docs page;
# generated_on is when these files were produced. They are not the same claim.
report = {"checked_on": "2026-09-11", "generated_on": datetime.date.today().isoformat(),
          "source": "https://yandex.ru/dev/games/doc/ru/console/add-new-game/draft",
          "images": [], "videos": [], "text_lengths": {}}


def check_png(path, size):
    data = path.read_bytes()[:29]
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    assert (width, height) == size, (path, width, height)
    assert (depth, color) == (8, 2), (path, "expected 24-bit RGB PNG", depth, color)
    report["images"].append({"file": path.relative_to(ROOT).as_posix(), "width": width, "height": height, "format": "RGB PNG 24-bit", "bytes": path.stat().st_size})


check_png(ROOT / "icon_512.png", (512, 512))
for lang in ["ru", "en"]:
    folder = ROOT / lang
    meta = json.loads((folder / "metadata.json").read_text(encoding="utf-8"))
    limits = {"name": (1, 50), "short_description": (1, 70), "seo_description": (50, 160), "description": (100, 1000), "how_to_play": (100, 1000), "keywords": (1, 100)}
    report["text_lengths"][lang] = {}
    for key, (low, high) in limits.items():
        length = len(meta[key])
        assert low <= length <= high, (lang, key, length)
        report["text_lengths"][lang][key] = {"length": length, "min": low, "max": high}
    assert meta["keywords"] == meta["keywords"].lower()
    assert len(meta["categories"]) <= 2
    check_png(folder / "cover_800x470.png", (800, 470))
    for device in ["desktop", "mobile"]:
        files = sorted((folder / f"screenshots_{device}").glob("*.png"))
        assert len(files) >= 2, (lang, device, "at least two screenshots required")
        for path in files:
            check_png(path, (1280, 720))
    for stem in ["gameplay", "trailer"]:
        path = folder / f"{stem}_24s.mp4"
        raw = subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)], text=True)
        probe = json.loads(raw)
        video = next(s for s in probe["streams"] if s["codec_type"] == "video")
        duration = float(probe["format"]["duration"])
        assert video["codec_name"] == "h264" and video["pix_fmt"] == "yuv420p"
        assert (video["width"], video["height"]) == (1280, 720)
        assert video["r_frame_rate"] == "30/1"
        assert abs(duration - 24) < 0.1 and duration <= 28
        assert path.stat().st_size < 100_000_000
        audio = [s["codec_name"] for s in probe["streams"] if s["codec_type"] == "audio"]
        # Both clips carry sound now: the gameplay one the engine's own recording,
        # the trailer its promo loop.
        assert audio == ["aac"], (path, audio)
        report["videos"].append({"file": path.relative_to(ROOT).as_posix(), "width": 1280, "height": 720, "fps": 30, "codec": "h264", "pixel_format": "yuv420p", "duration_seconds": duration, "audio": audio, "bytes": path.stat().st_size})
report["status"] = "PASS"
(ROOT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"PASS: {len(report['images'])} PNGs, {len(report['videos'])} MP4s, RU/EN text limits")
