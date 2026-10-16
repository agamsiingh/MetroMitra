"""Derive Android launcher icons + splash logo from app/assets/brand/logo.jpg.

Run from repo root: python tools/brand/make_icons.py   (needs Pillow)
Outputs are committed; re-run only when the logo changes.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "app/assets/brand/logo.jpg"
RES = ROOT / "app/android/app/src/main/res"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
WHITE = (255, 255, 255)

logo = Image.open(SRC).convert("RGB")


def square(size: int, content: float) -> Image.Image:
    """Logo scaled to `content` of the canvas, centred on white."""
    canvas = Image.new("RGB", (size, size), WHITE)
    inner = round(size * content)
    scaled = logo.resize((inner, inner), Image.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(scaled, (offset, offset))
    return canvas


for name, scale in DENSITIES.items():
    folder = RES / f"mipmap-{name}"
    folder.mkdir(parents=True, exist_ok=True)
    # Legacy launcher icon: 48dp, logo nearly full-bleed.
    square(round(48 * scale), 0.96).save(folder / "ic_launcher.png")
    # Adaptive foreground: 108dp canvas, content inside the 66dp safe zone.
    fg = Image.new("RGBA", (round(108 * scale),) * 2, (0, 0, 0, 0))
    inner = round(108 * scale * 0.78)
    scaled = logo.resize((inner, inner), Image.LANCZOS).convert("RGBA")
    off = (fg.width - inner) // 2
    fg.paste(scaled, (off, off))
    fg.save(folder / "ic_launcher_foreground.png")

anydpi = RES / "mipmap-anydpi-v26"
anydpi.mkdir(exist_ok=True)
(anydpi / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    "</adaptive-icon>\n"
)
values = RES / "values"
values.mkdir(exist_ok=True)
(values / "colors.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
    '    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n'
)
print("icons written")

# Pre-Flutter launch screen logo (Android < 12; 12+ uses the adaptive icon).
nodpi = RES / "drawable-nodpi"
nodpi.mkdir(exist_ok=True)
logo.resize((480, 480), Image.LANCZOS).save(nodpi / "splash_logo.png")
