#!/usr/bin/env python3
"""Regenerate every platform icon from assets/logo/logo.svg.   python3 scripts/make_icons.py
Needs:  pip install --user cairosvg pillow
"""
import io
import re
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SVG = (ROOT / "assets/logo/logo.svg").read_text()
CLAY = "#BC452B"
# the penguin spans roughly y 84..461, so scale around its middle; 0.78 keeps it inside Android's adaptive-icon
# safe zone and the web "maskable" safe zone
SAFE = '<g transform="translate(256 272) scale(0.78) translate(-256 -272)">'


def _penguin(svg: str) -> str:
    return re.search(r'<g id="penguin">.*</g>', svg, re.S).group(0)


def _wrap(inner: str, background: str = "") -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">{background}{SAFE}{inner}</g></svg>'


FULL = SVG
MASKABLE = _wrap(_penguin(SVG), f'<rect width="512" height="512" fill="{CLAY}"/>')  # full bleed: the OS masks it
FOREGROUND = _wrap(_penguin(SVG))  # transparent, for Android adaptive icons


def png(svg: str, size: int) -> Image.Image:
    data = cairosvg.svg2png(bytestring=svg.encode(), output_width=size, output_height=size)
    return Image.open(io.BytesIO(data)).convert("RGBA")


def save(svg: str, size: int, rel: str) -> None:
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    png(svg, size).save(path, optimize=True)
    print(f"{size:>4}px  {rel}")


# In-app logo, and the Linux window icon (loaded from the Flutter assets at runtime)
save(FULL, 512, "assets/logo/logo.png")
save(FULL, 256, "assets/logo/app_icon.png")

# Web
(ROOT / "web/favicon.svg").write_text(SVG)
save(FULL, 48, "web/favicon.png")
save(FULL, 192, "web/icons/Icon-192.png")
save(FULL, 512, "web/icons/Icon-512.png")
save(MASKABLE, 192, "web/icons/Icon-maskable-192.png")
save(MASKABLE, 512, "web/icons/Icon-maskable-512.png")

# Android: legacy launcher icons, plus adaptive foregrounds (108dp canvas) over a clay background colour
for density, launcher, adaptive in [("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216), ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)]:
    save(FULL, launcher, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png")
    save(FOREGROUND, adaptive, f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png")

# macOS
for size in (16, 32, 64, 128, 256, 512, 1024):
    save(FULL, size, f"macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png")

# Windows: one .ico holding several sizes
sizes = [16, 24, 32, 48, 64, 128, 256]
png(FULL, 256).save(ROOT / "windows/runner/resources/app_icon.ico", format="ICO", sizes=[(s, s) for s in sizes])
print("ico    windows/runner/resources/app_icon.ico", sizes)
