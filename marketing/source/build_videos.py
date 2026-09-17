"""Encode the in-engine recordings and an original, synthesized trailer soundtrack.

The gameplay clip keeps the audio Godot recorded with the frames. The trailer gets
a separate promo loop built here, so captions and music can be paced for the store
card. No third-party music or generated gameplay frames are used. Requires ffmpeg.
Run from any directory after capture.gd has recorded both languages.
"""
from pathlib import Path
import array
import math
import shutil
import subprocess
import wave

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "_work"
OUT = ROOT / "yandex"
RATE = 44100
DURATION = 24


def make_soundtrack():
    # Original minimal 120 BPM electronic loop: kick, hi-hat and a muted bass ostinato.
    # Deterministic oscillators only, without copyrighted recordings or samples.
    data = array.array("h")
    notes = [55.0, 55.0, 65.4064, 73.4162, 55.0, 55.0, 82.4069, 73.4162]
    noise_state = 1234567
    for i in range(RATE * DURATION):
        t = i / RATE
        b = t % 0.5
        h = t % 0.25
        note = notes[int(t / 0.5) % len(notes)]
        kick = 0.42 * math.exp(-b * 20) * math.sin(2 * math.pi * (49 * b + 8 * (1 - math.exp(-b * 35))))
        bass = 0.13 * math.exp(-b * 6) * (math.sin(2 * math.pi * note * t) + 0.22 * math.sin(4 * math.pi * note * t))
        noise_state = (1664525 * noise_state + 1013904223) & 0xffffffff
        noise = noise_state / 2147483648 - 1
        hat = noise * 0.052 * math.exp(-h * 90)
        fade = min(1, t / 0.08, max(0, (DURATION - t) / 0.65))
        val = int(max(-0.94, min(0.94, (kick + bass + hat) * fade)) * 32767)
        data.extend([val, val])
    path = ROOT / "source" / "original_soundtrack.wav"
    with wave.open(str(path), "wb") as wav:
        wav.setparams((2, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(data.tobytes())
    return path


# Arial Bold on Windows; Liberation Sans Bold is the metric-compatible stand-in
# elsewhere, and DejaVu is the fallback. All three cover Cyrillic.
CAPTION_FONTS = [
    "C:/Windows/Fonts/arialbd.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
]


def caption_font():
    for candidate in CAPTION_FONTS:
        if Path(candidate).exists():
            return candidate
    raise SystemExit("No bold Cyrillic font found for captions; add one to CAPTION_FONTS.")


def run(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *map(str, args)], cwd=WORK, check=True)


def main():
    soundtrack = make_soundtrack()
    shutil.copyfile(caption_font(), WORK / "font.ttf")
    captions = {
        "ru": ["Поймай идеальный повтор", "15 тренажёров. Найди свой ритм.", "Позже: Кузница титанов. Темп выше.", "6 уровней. Как далеко дойдёшь?", "Качалка: ещё один повтор"],
        "en": ["Time your perfect rep", "15 stations. Find your rhythm.", "Later: Titan Forge. Faster timing.", "6 tiers. How far will you go?", "Kachalka: one more rep"],
    }
    intervals = [(0, 7), (7, 12), (12, 19), (19, 21.5), (21.5, 24)]
    for lang in ["ru", "en"]:
        source = WORK / f"gameplay_{lang}.avi"
        dest = OUT / lang
        codec = ["-c:v", "libx264", "-preset", "fast", "-crf", "19", "-pix_fmt", "yuv420p", "-color_range", "tv", "-r", "30", "-movflags", "+faststart", "-t", "24"]
        color_conversion = "scale=in_range=pc:out_range=tv,format=yuv420p"
        # The gameplay clip keeps the engine's own recording: Movie Maker writes the
        # game's synthesised music and SFX straight into the AVI, so the store video
        # sounds like the build does.
        run(["-i", source, "-map", "0:v:0", "-map", "0:a:0", "-vf", color_conversion,
             *codec, "-c:a", "aac", "-b:a", "160k", "-ac", "2", dest / "gameplay_24s.mp4"])
        filters = [color_conversion, "drawbox=x=0:y=655:w=iw:h=65:color=0x080d14@0.9:t=fill"]
        for i, (caption, (start, end)) in enumerate(zip(captions[lang], intervals)):
            filename = f"caption_{lang}_{i}.txt"
            (WORK / filename).write_text(caption, encoding="utf-8")
            filters.append(f"drawtext=fontfile=font.ttf:textfile={filename}:fontcolor=0xfff4db:fontsize=30:x=(w-tw)/2:y=672:enable='gte(t,{start})*lt(t,{end})'")
        run(["-i", source, "-i", soundtrack, "-map", "0:v:0", "-map", "1:a:0", "-vf", ",".join(filters), *codec, "-c:a", "aac", "-b:a", "160k", dest / "trailer_24s.mp4"])
        print(f"Encoded {lang}: gameplay and trailer")


if __name__ == "__main__":
    main()
