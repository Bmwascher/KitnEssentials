"""Build the Forever mark beside the settings window's title: a white infinity
that the accent color tints at runtime.

Language, in UI units at the display size:
  display     32 x 16, curve center line 28 wide; the texture is 4x this
  curve       x = cos t (1 + Q sin^2 t), y = sin 2t (1 + K cos 2t), aspect 2.4833
  stroke      1.9 at rest, thickening to 2.8 from 78 percent of the arc length,
              through the right extreme, to 5 percent, where it ends round
  detail      nothing thinner than the stroke: no stars and no second color

Run from the repo root: python -I dev/media/build_forever_mark.py   (needs NumPy, Pillow)
"""
import math, os
import numpy as np
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "Media", "GUITextures", "ForeverMark.png")

DISPLAY_W, DISPLAY_H, INK_W = 32, 16, 28
TEXEL, SUPERSAMPLE = 4, 16
ASPECT, K, Q = 2.4833, -0.25, -0.1
RING, HEAD = 1.9, 2.8
COMET_START, COMET_SPAN = 78, 27

t = np.linspace(0, 2 * math.pi, 12000, endpoint=False)
x = np.cos(t) * (1 + Q * np.sin(t) ** 2)
y = np.sin(2 * t) * (1 + K * np.cos(2 * t))
x, y = np.r_[x, x[0]] / np.abs(x).max(), np.r_[y, y[0]] / np.abs(y).max() / ASPECT
arc = np.r_[0, np.cumsum(np.hypot(np.diff(x), np.diff(y)))]

percent = np.linspace(0, 100, 5000, endpoint=False)
at = percent / 100 * arc[-1]
px, py = np.interp(at, arc, x), np.interp(at, arc, y)

scale = TEXEL * SUPERSAMPLE
canvas = Image.new("L", (DISPLAY_W * scale, DISPLAY_H * scale), 0)
draw = ImageDraw.Draw(canvas)
for p, a, b in zip(percent, px, py):
    along = (p - COMET_START) % 100
    width = RING + (HEAD - RING) * along / COMET_SPAN if along <= COMET_SPAN else RING
    r = width / 2 * scale
    cx = (DISPLAY_W / 2 + INK_W / 2 * a) * scale
    cy = (DISPLAY_H / 2 + INK_W / 2 * b) * scale
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)

alpha = canvas.resize((DISPLAY_W * TEXEL, DISPLAY_H * TEXEL), Image.BOX)
white = Image.new("L", alpha.size, 255)
Image.merge("RGBA", (white, white, white, alpha)).save(OUT, optimize=True)
