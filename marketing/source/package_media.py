"""Create the hand-off archive only after all final media pass validation."""
from pathlib import Path
import json
import subprocess
import sys
import zipfile

root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(root / "source" / "validate_media.py")], check=True)
archive = root / "Kachalka_Yandex_Media.zip"
with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for path in sorted((root / "yandex").rglob("*")):
        if path.is_file():
            z.write(path, path.relative_to(root / "yandex").as_posix())
    for path in sorted((root / "source").glob("*")):
        if path.is_file():
            z.write(path, "source/" + path.name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert "preview.html" in z.namelist()
    assert "ru/trailer_24s.mp4" in z.namelist()
    assert "en/trailer_24s.mp4" in z.namelist()
    assert json.loads(z.read("validation.json"))["status"] == "PASS"
    print(f"Archive verified: {len(z.namelist())} files, {archive.stat().st_size / 1024 / 1024:.1f} MiB")
print(archive)
