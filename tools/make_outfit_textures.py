"""Draws the tileable cloth / leather / metal textures used by the generated
outfits (tools/build_hero.py). Run: python3 tools/make_outfit_textures.py"""
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parent / "textures"
OUT.mkdir(exist_ok=True)
rng = np.random.default_rng(3)
N = 512


def noise(scale, octaves=5, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((N, N))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(scale / 2 ** o))
        g = r.random((N // s + 1, N // s + 1))
        g = np.pad(g, ((0, 1), (0, 1)), mode="wrap")  # tileable
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((N + s, N + s), Image.BICUBIC)
        out += amp * np.asarray(img, float)[:N, :N] / 255
        tot += amp
        amp *= 0.5
    return out / tot


def save(name, rgb):
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(OUT / f"{name}.png")


def normal_from_height(h, strength=2.0):
    dx = np.roll(h, -1, 1) - np.roll(h, 1, 1)
    dy = np.roll(h, -1, 0) - np.roll(h, 1, 0)
    n = np.dstack([-dx * strength, -dy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return (n * 0.5 + 0.5) * 255


def tint(gray, col):
    return gray[..., None] * np.array(col)[None, None, :]


# chain mail: rows of interlocking rings
yy, xx = np.mgrid[0:N, 0:N].astype(float)
cell = 16
h = np.zeros((N, N))
for row in range(-1, N // (cell // 2) + 2):
    cy = row * cell / 2
    off = (row % 2) * cell / 2
    for col in range(-1, N // cell + 2):
        cx = col * cell + off
        d = np.hypot((xx - cx) / 1.0, (yy - cy) / 0.8)
        ring = np.clip(1 - np.abs(d - cell * 0.42) / 2.2, 0, 1)
        h = np.maximum(h, ring)
h = np.roll(h, 0, 0)
alb = 60 + 150 * h + noise(64, seed=1) * 30
save("chain_albedo", tint(alb / 255, (210, 214, 222)))
save("chain_normal", normal_from_height(h, 3.0))
Image.fromarray((np.clip(1 - h * 0.6, 0.2, 1) * 255).astype(np.uint8)).save(OUT / "chain_rough.png")

# leather: mottled with creases
n1 = noise(48, seed=2)
n2 = noise(8, seed=3)
creases = np.clip(1 - np.abs(noise(96, 3, seed=4) - 0.5) * 12, 0, 1)
g = 0.55 + (n1 - 0.5) * 0.5 + (n2 - 0.5) * 0.15 - creases * 0.18
save("leather_albedo", tint(g, (120, 78, 46)))
save("leather_normal", normal_from_height(n2 * 0.6 - creases * 0.8, 2.0))

# linen / wool weave
wx = (np.sin(xx * 2 * math.pi / 4) * 0.5 + 0.5)
wy = (np.sin(yy * 2 * math.pi / 4) * 0.5 + 0.5)
weave = np.where(((xx // 4 + yy // 4) % 2) == 0, wx, wy)
g = 0.75 + (weave - 0.5) * 0.18 + (noise(64, seed=5) - 0.5) * 0.15
save("cloth_albedo", tint(g, (255, 255, 255)))
save("cloth_normal", normal_from_height(weave * 0.6, 1.5))

# brushed steel with light scratches
streak = np.asarray(Image.fromarray((rng.random((N, N)) * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(0)).resize((N, N)), float) / 255
streak = np.asarray(Image.fromarray((rng.random((N, 8)) * 255).astype(np.uint8)).resize((N, N), Image.BILINEAR), float).T / 255
g = 0.72 + (streak - 0.5) * 0.12 + (noise(96, seed=6) - 0.5) * 0.16
save("steel_albedo", tint(g, (210, 214, 220)))
save("steel_normal", normal_from_height(streak * 0.3 + noise(16, seed=7) * 0.2, 1.0))
print("textures written to", OUT)
