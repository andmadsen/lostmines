"""Generates the fantasy UI skin textures in res://ui/skin.

Run:  python3 tools/make_ui_skin.py
Everything is drawn from code (no third-party art), so it can be re-made or
recoloured at any time.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "ui" / "skin"
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(7)

GOLD_HI = np.array([246, 221, 150])
GOLD = np.array([196, 155, 72])
GOLD_LO = np.array([92, 64, 26])


def noise(w, h, scale, octaves=4):
    """Smooth value noise in 0..1."""
    out = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale / (2 ** o)))
        g = rng.random((h // s + 2, w // s + 2))
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w + 2 * s, h + 2 * s), Image.BICUBIC)
        out += amp * np.asarray(img, dtype=float)[s:s + h, s:s + w] / 255.0
        tot += amp
        amp *= 0.5
    return out / tot


def leather(w, h, base=(38, 27, 19), var=22):
    n = noise(w, h, 24)
    fine = rng.random((h, w))
    v = (n - 0.5) * var * 2 + (fine - 0.5) * 6
    rgb = np.clip(np.array(base)[None, None, :] + v[..., None] * np.array([1.0, 0.8, 0.6]), 0, 255)
    return rgb


def gold_band(t):
    """Colour across a bevelled band, t in 0..1 (0 = outer edge)."""
    k = 0.5 - 0.5 * math.cos(t * math.pi * 2)  # bright in the middle
    c = GOLD_LO + (GOLD - GOLD_LO) * min(1, t * 3)
    return c + (GOLD_HI - c) * k * 0.8


def frame(w, h, border=7, inner_dark=2, alpha_center=None, base=None, corner=True, radius=0):
    img = np.zeros((h, w, 4))
    img[..., :3] = leather(w, h) if base is None else base
    img[..., 3] = 255
    yy, xx = np.mgrid[0:h, 0:w]
    d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)).astype(float)
    if radius:
        # rounded corners
        for cx, cy in [(radius, radius), (w - 1 - radius, radius), (radius, h - 1 - radius), (w - 1 - radius, h - 1 - radius)]:
            m = ((xx < radius) if cx == radius else (xx > w - 1 - radius)) & ((yy < radius) if cy == radius else (yy > h - 1 - radius))
            dd = radius - np.hypot(xx - cx, yy - cy)
            d = np.where(m, np.minimum(d, dd), d)
        img[..., 3] = np.where(d < 0, 0, img[..., 3])
    band = (d >= 0) & (d < border)
    t = np.clip(d / border, 0, 1)
    for c in range(3):
        col = np.vectorize(lambda tt: gold_band(tt)[c])(t)
        img[..., c] = np.where(band, col, img[..., c])
    dark = (d >= border) & (d < border + inner_dark)
    img[..., :3] = np.where(dark[..., None], img[..., :3] * 0.25, img[..., :3])
    # inner shadow
    sh = (d >= border + inner_dark) & (d < border + inner_dark + 8)
    f = np.clip((d - border - inner_dark) / 8, 0, 1)
    img[..., :3] = np.where(sh[..., None], img[..., :3] * (0.55 + 0.45 * f[..., None]), img[..., :3])
    if alpha_center is not None:
        inside = d >= border + inner_dark
        img[..., 3] = np.where(inside, alpha_center, img[..., 3])
    out = Image.fromarray(img.clip(0, 255).astype(np.uint8), "RGBA")
    if corner:
        dr = ImageDraw.Draw(out)
        r = border + 3
        for cx, cy in [(r, r), (w - 1 - r, r), (r, h - 1 - r), (w - 1 - r, h - 1 - r)]:
            dr.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=tuple(GOLD_LO) + (255,))
            rr = r - 2
            dr.polygon([(cx, cy - rr), (cx + rr, cy), (cx, cy + rr), (cx - rr, cy)], fill=tuple(GOLD) + (255,))
            dr.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=tuple(GOLD_HI) + (255,))
    return out


# big panels (9-patch, margin 20)
frame(128, 128, border=6).save(OUT / "panel.png")
# portrait frame: transparent window
frame(128, 128, border=6, alpha_center=0).save(OUT / "frame.png")
# action slot: bronze square, recessed dark centre
slot_base = leather(64, 64, base=(18, 13, 10), var=8)
frame(64, 64, border=4, base=slot_base, corner=False, radius=6).save(OUT / "slot.png")
# hovered / active slot: brighter rim
hi = frame(64, 64, border=4, base=leather(64, 64, base=(44, 32, 18), var=8), corner=False, radius=6)
hi.save(OUT / "slot_hover.png")
act = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
glow = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(glow)
d.rounded_rectangle([1, 1, 62, 62], radius=7, outline=(255, 214, 110, 255), width=4)
glow = glow.filter(ImageFilter.GaussianBlur(1.5))
act = Image.alpha_composite(frame(64, 64, border=4, base=leather(64, 64, base=(60, 40, 16), var=10), corner=False, radius=6), glow)
act.save(OUT / "slot_active.png")
# HP bar frame + fills
frame(64, 16, border=2, inner_dark=1, base=leather(64, 16, base=(12, 8, 6), var=4), corner=False).save(OUT / "bar_bg.png")


def fill(col):
    h = 16
    img = np.zeros((h, 64, 4))
    for y in range(h):
        k = 1.25 - abs(y - h * 0.35) / h * 1.4
        img[y, :, :3] = np.clip(np.array(col) * k, 0, 255)
    img[..., 3] = 255
    return Image.fromarray(img.astype(np.uint8), "RGBA")


fill((70, 160, 60)).save(OUT / "bar_green.png")
fill((190, 50, 35)).save(OUT / "bar_red.png")
fill((200, 170, 70)).save(OUT / "bar_gold.png")

# divider ornament for the bar
w, h = 256, 12
orn = Image.new("RGBA", (w, h), (0, 0, 0, 0))
d = ImageDraw.Draw(orn)
d.line([(8, h // 2), (w - 8, h // 2)], fill=tuple(GOLD) + (255,), width=2)
d.polygon([(w // 2, 0), (w // 2 + 8, h // 2), (w // 2, h - 1), (w // 2 - 8, h // 2)], fill=tuple(GOLD_HI) + (255,))
for x in (8, w - 8):
    d.ellipse([x - 3, h // 2 - 3, x + 3, h // 2 + 3], fill=tuple(GOLD) + (255,))
orn.save(OUT / "divider.png")
print("UI skin written to", OUT)
