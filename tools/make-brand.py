#!/usr/bin/env python3
"""Builds the Wiflow icon set from the original artwork (rom/brand/wiflow-icon-source.png).

- wiflow-mark.png / wiflow-mark-256.png: the W-wifi mark alone, transparent
  background (sidebar tile, mobile top bar, login card)
- favicon.png, apple-touch-icon.png, /www/favicon.ico: the original artwork,
  square crop centred on the mark, rounded corners

usage: make-brand.py <rom/overlay dir>
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

overlay = sys.argv[1]
media = os.path.join(overlay, "www/luci-static/wiflow")
os.makedirs(media, exist_ok=True)
src_img = Image.open(os.path.join(os.path.dirname(__file__), "..", "rom/brand/wiflow-icon-source.png")).convert("RGB")

# --- mark on transparent background ---
# the mark is saturated or dark blue, the artwork background is near-white
src = np.asarray(src_img).astype(float)
sat = (src.max(2) - src.min(2)) / 255.0
alpha = np.maximum(np.clip((sat - 0.22) / 0.45, 0, 1), np.clip((205 - src.mean(2)) / 55, 0, 1))
box = np.zeros_like(alpha)
box[240:985, 140:1115] = 1          # mark area; the soft bubbles outside are dropped
alpha *= box
bg = np.array([250, 253, 255.0])
a3 = alpha[..., None]
col = np.clip(np.where(a3 > 0.01, (src - (1 - a3) * bg) / np.maximum(a3, 0.01), 0), 0, 255)
rgba = Image.fromarray(np.dstack([col, alpha * 255]).astype(np.uint8), "RGBA")
ys, xs = np.where(alpha > 0.5)
mark = rgba.crop((xs.min() - 6, ys.min() - 6, xs.max() + 7, ys.max() + 7))
side = max(mark.size)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(mark, ((side - mark.size[0]) // 2, (side - mark.size[1]) // 2), mark)
square.resize((96, 96), Image.LANCZOS).save(os.path.join(media, "wiflow-mark.png"), optimize=True)
square.resize((256, 256), Image.LANCZOS).save(os.path.join(media, "wiflow-mark-256.png"), optimize=True)

# --- rounded app icon from the original artwork ---
cx, cy, half = 627, 610, 560
art = src_img.crop((cx - half, cy - half, cx + half, cy + half))


def icon(size, radius=0.225):
    big = art.resize((size * 4, size * 4), Image.LANCZOS)
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, big.size[0] - 1, big.size[1] - 1),
                                           radius=int(big.size[0] * radius), fill=255)
    img = big.convert("RGBA")
    img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


icon(64).save(os.path.join(media, "favicon.png"), optimize=True)
icon(180).save(os.path.join(media, "apple-touch-icon.png"), optimize=True)
icon(256).save(os.path.join(overlay, "www/favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
print("brand assets written")
