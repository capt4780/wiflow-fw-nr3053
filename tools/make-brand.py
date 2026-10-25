#!/usr/bin/env python3
"""Builds the Wiflow brand assets from the one original logo
(rom/brand/wiflow-logo-source.png: mark + "Wiflow" wordmark, transparent PNG).

The logo pixels are never changed: only the empty transparent margin is
trimmed and the image resized.
- wiflow-logo.png: gate/login page, sidebar, mobile top bar
- favicon.png, apple-touch-icon.png, /www/favicon.ico: the Wiflow app icon
  (rom/brand/wiflow-icon-source.png, square artwork), only resized

usage: make-brand.py <rom/overlay dir>
"""
import os
import sys

from PIL import Image

overlay = sys.argv[1]
media = os.path.join(overlay, "www/luci-static/wiflow")
os.makedirs(media, exist_ok=True)
logo = Image.open(os.path.join(os.path.dirname(__file__), "..", "rom/brand/wiflow-logo-source.png")).convert("RGBA")
logo = logo.crop(logo.getchannel("A").getbbox())
logo.resize((480, round(logo.height * 480 / logo.width)), Image.LANCZOS).save(os.path.join(media, "wiflow-logo.png"), optimize=True)

icon = Image.open(os.path.join(os.path.dirname(__file__), "..", "rom/brand/wiflow-icon-source.png")).convert("RGB")
icon.resize((64, 64), Image.LANCZOS).save(os.path.join(media, "favicon.png"), optimize=True)
icon.resize((180, 180), Image.LANCZOS).save(os.path.join(media, "apple-touch-icon.png"), optimize=True)
icon.resize((256, 256), Image.LANCZOS).save(os.path.join(overlay, "www/favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
print("brand assets written")
