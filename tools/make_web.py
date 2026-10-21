import math
import os

import numpy as np
from PIL import Image, ImageDraw

from make_textures import OUT, PREVIEW, write_vtf

TILE = 256
VARIANTS = 2
SUPER = 4
POINTS = 40
RIM = 8
LINKS = 3
WIDTH = (2.5, 6)
SEGMENTS = 8
BOW = 0.15
SEED = 1999


def web(rng):
    size = TILE * SUPER
    img = Image.new("LA", (size, size), (0, 0))
    draw = ImageDraw.Draw(img)
    pts = []
    for i in range(POINTS + RIM):
        r = 0.49 if i >= POINTS else math.sqrt(rng.random()) * 0.42
        a = rng.random() * math.tau
        pts.append((0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r))
    seen = set()
    for i, (x0, y0) in enumerate(pts):
        near = sorted((((x0 - x1) ** 2 + (y0 - y1) ** 2, j) for j, (x1, y1) in enumerate(pts[:POINTS]) if j != i))
        for _, j in near[:1 if i >= POINTS else LINKS]:
            key = (min(i, j), max(i, j))
            if key in seen:
                continue
            seen.add(key)
            x1, y1 = pts[j]
            dx, dy = x1 - x0, y1 - y0
            bow = (rng.random() - 0.5) * 2 * BOW
            shade = int(200 + 55 * rng.random())
            width = (WIDTH[0] + (WIDTH[1] - WIDTH[0]) * rng.random()) * SUPER
            line = []
            for s in range(SEGMENTS + 1):
                k = s / SEGMENTS
                lift = 4 * k * (1 - k) * bow
                line.append(((x0 + dx * k - dy * lift) * size, (y0 + dy * k + dx * lift) * size))
            for s in range(SEGMENTS):
                w = max(1, round(width * (1 - 0.3 * (s + 0.5) / SEGMENTS)))
                draw.line([line[s], line[s + 1]], fill=(shade, 255), width=w)
                draw.ellipse([line[s + 1][0] - w / 2, line[s + 1][1] - w / 2, line[s + 1][0] + w / 2, line[s + 1][1] + w / 2], fill=(shade, 255))
    return np.asarray(img.resize((TILE, TILE), Image.LANCZOS))


def keep(m):
    a = np.asarray(m).copy()
    alpha = a[..., 3].astype(float) / 255
    if alpha.max() > 0:
        cover = keep.cover
        cut = np.quantile(alpha, 1 - cover) if cover < 1 else alpha.min()
        if cut > 0:
            alpha = np.clip(alpha * (0.5 / cut), 0, 1)
    a[..., 3] = (alpha * 255 + 0.5).astype(np.uint8)
    return Image.fromarray(a, "RGBA")


if __name__ == "__main__":
    rng = np.random.default_rng(SEED)
    atlas = np.zeros((TILE * VARIANTS, TILE * VARIANTS, 4), np.uint8)
    for v in range(VARIANTS * VARIANTS):
        tile = web(rng)
        ox, oy = (v % VARIANTS) * TILE, (v // VARIANTS) * TILE
        atlas[oy:oy + TILE, ox:ox + TILE, :3] = tile[..., :1]
        atlas[oy:oy + TILE, ox:ox + TILE, 3] = tile[..., 1]
    keep.cover = (atlas[..., 3] >= 128).mean()
    write_vtf(os.path.join(OUT, "web.vtf"), atlas, keep)
    os.makedirs(PREVIEW, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(os.path.join(PREVIEW, "web_preview.png"))
    print("web cover", round(keep.cover, 3))
