#!/usr/bin/env python3
"""Builds the Wiflow icon set from the original artwork (rom/brand/wiflow-icon-source.png).

Every icon is the whole original file, only resized and given rounded corners
(no cropping, no background removal, no colour change):
- wiflow-mark.png (96 px) / wiflow-mark-256.png: sidebar tile, mobile top bar, login card
- favicon.png, apple-touch-icon.png, /www/favicon.ico

usage: make-brand.py <rom/overlay dir>
"""
import os
import sys

from PIL import Image, ImageDraw

overlay = sys.argv[1]
media = os.path.join(overlay, "www/luci-static/wiflow")
os.makedirs(media, exist_ok=True)
src = Image.open(os.path.join(os.path.dirname(__file__), "..", "rom/brand/wiflow-icon-source.png")).convert("RGB")


def icon(size, radius=0.225):
    big = src.resize((size * 4, size * 4), Image.LANCZOS)
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big.size[0] - 1, big.size[1] - 1),
                                           radius=int(big.size[0] * radius), fill=255)
    img = big.convert("RGBA")
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


icon(96).save(os.path.join(media, "wiflow-mark.png"), optimize=True)
icon(256).save(os.path.join(media, "wiflow-mark-256.png"), optimize=True)
icon(64).save(os.path.join(media, "favicon.png"), optimize=True)
icon(180).save(os.path.join(media, "apple-touch-icon.png"), optimize=True)
icon(256).save(os.path.join(overlay, "www/favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
print("brand assets written")
