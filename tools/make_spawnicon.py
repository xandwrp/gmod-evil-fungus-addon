"""Draws the fungus's spawn menu icon into materials/entities/ as a pale silhouette on a dark tile.

Same tile as the Evil Crawling Thing's icons (its tools/finish_assets.py), so the suite reads as one
set: a swollen mound of body sat on the ground, roots spreading out into the mat either side, and a
few fine fibers up off it, feeling around. Drawn large and shrunk, so the thin strands stay soft.

    python tools/make_spawnicon.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

# The suite's tile. Keep in step with the crawler's tools/finish_assets.py.
SIZE = 128
INK = (226, 219, 207)
BG_IN = (42, 38, 41)
BG_OUT = (12, 11, 12)
BOX = (112, 84)  # most room the creature gets
FLOOR = 104  # where whatever's on the ground stands
CEILING = 24  # where whatever's on the ceiling hangs from

SS = 8
W, H = 160, 130  # working canvas, in drawing units
SEED = 11
GROUND = 110
PITCH = 0.45
ROOTS = 8
R_ROOT = 2.2
R_TIP = 0.55
REACH = 9
SHORTER = 0.8
TAPER = 0.72
KINK = 0.2
STEP = 0.8
FIBERS = 7
FIBER_LENGTH = 46
R_FIBER = 2.2
CURL = 0.35
OUT = os.path.join(os.path.dirname(__file__), "..", "materials", "entities", "evil_fungus.png")
PREVIEW = os.path.join(os.path.dirname(__file__), "..", "renders", "spawnicon_preview.png")

rand = random.Random(SEED)


def dot(draw, x, y, r):
    draw.ellipse(((x - r) * SS, (y - r) * SS, (x + r) * SS, (y + r) * SS), fill=255)


def stroke(draw, points, r0, r1):
    """A tube through points, tapering from r0 to r1, as overlapping discs."""
    total = sum(math.dist(a, b) for a, b in zip(points, points[1:])) or 1
    run = 0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        n = max(1, int(seg * 4))
        for i in range(n + 1):
            f = (run + seg * i / n) / total
            dot(draw, a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n, r0 + (r1 - r0) * f)
        run += seg


def ground(x, d):
    """Screen position of a spot on the ground, d coming toward the viewer, looked down on a little."""
    return x, GROUND + d * PITCH


def spread(draw, x, d, heading, r, length):
    """A root across the ground: a kinked run that forks in two, thinner each time, until it's a hair."""
    pts = [ground(x, d)]
    for _ in range(int(length / STEP)):
        heading += rand.uniform(-KINK, KINK)
        x += math.cos(heading) * STEP
        d += math.sin(heading) * STEP
        pts.append(ground(x, d))
    stroke(draw, pts, r, r * TAPER)
    r *= TAPER
    if r < R_TIP:
        return
    for turn in (-1, 1):
        if rand.random() < 0.85:
            spread(draw, x, d, heading + turn * rand.uniform(0.3, 0.7), r * rand.uniform(0.85, 1.0),
                   length * SHORTER * rand.uniform(0.8, 1.2))


def fiber(draw, x, y, lean, length, r):
    """A tendril up off the body, leaning out and hooking over further the higher it gets."""
    pts, a = [(x, y)], -math.pi / 2 + lean
    n = int(length / STEP)
    for i in range(n):
        a += lean * CURL * (i / n) ** 2 + rand.uniform(-0.05, 0.05)
        x, y = x + math.cos(a) * STEP, y + math.sin(a) * STEP
        pts.append((x, y))
    stroke(draw, pts, r, r * 0.3)


def creature():
    im = Image.new("L", (W * SS, H * SS), 0)
    draw = ImageDraw.Draw(im)
    cx = W / 2
    # The mound: a few swollen lobes, the biggest in the middle.
    lobes = [(0, 0, 15, 13), (-12, 3, 10, 8.5), (13, 2.5, 10.5, 9), (-5, -8, 8, 7), (7, -7, 7.5, 7), (-21, 6, 5.5, 4.5),
             (22, 5.5, 6, 5)]
    for dx, dy, rx, ry in lobes:
        x, y = cx + dx, GROUND - ry * 0.6 + dy
        draw.ellipse(((x - rx) * SS, (y - ry) * SS, (x + rx) * SS, (y + ry) * SS), fill=255)
    # Flat underneath where it sits.
    draw.rectangle(((cx - 24) * SS, (GROUND - 2) * SS, (cx + 24) * SS, (GROUND + 1.5) * SS), fill=255)
    # Out into the mat both ways, a few toward and away from the viewer.
    for i in range(ROOTS):
        side = -1 if i % 2 == 0 else 1
        heading = (math.pi if side < 0 else 0) + rand.uniform(-0.55, 0.55)
        x = cx + side * rand.uniform(14, 23)
        d = rand.uniform(-2, 2)
        spread(draw, x, d, heading, R_ROOT * rand.uniform(0.8, 1.1), REACH * rand.uniform(0.9, 1.3))
    for i in range(FIBERS):
        f = (i + 0.5) / FIBERS
        x = cx - 16 + 32 * f
        top = GROUND - 19 + abs(f - 0.5) ** 2 * 40
        tall = 1 - abs(f - 0.5) * 1.1
        fiber(draw, x, top + 4, (f - 0.5) * 1.3 + rand.uniform(-0.12, 0.12), FIBER_LENGTH * (0.55 + 0.45 * tall) * rand.uniform(0.9, 1.1),
              R_FIBER * rand.uniform(0.85, 1.1))
    return im


def tile(alpha, hanging=False):
    """The suite's icon: the silhouette fitted into the box, stood on the floor or hung from the ceiling."""
    alpha = alpha.crop(alpha.getbbox())
    k = min(BOX[0] / alpha.width, BOX[1] / alpha.height)
    alpha = alpha.resize((max(1, round(alpha.width * k)), max(1, round(alpha.height * k))), Image.LANCZOS)
    if hanging:
        alpha = alpha.transpose(Image.FLIP_TOP_BOTTOM)
    y = CEILING if hanging else FLOOR - alpha.height
    yy, xx = SIZE / 2, SIZE / 2
    bg = Image.new("RGB", (SIZE, SIZE))
    px = bg.load()
    for j in range(SIZE):
        for i in range(SIZE):
            t = min(1, math.hypot(i - xx, j - yy) / (SIZE * 0.72))
            t = t * t
            px[i, j] = tuple(round(a + (b - a) * t) for a, b in zip(BG_IN, BG_OUT))
    ink = Image.new("RGB", alpha.size, INK)
    bg.paste(ink, ((SIZE - alpha.width) // 2, y), alpha)
    return bg


if __name__ == "__main__":
    icon = tile(creature().resize((W * 2, H * 2), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.3)))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    icon.save(OUT, optimize=True)
    print("materials/entities/evil_fungus.png  %dx%d" % icon.size)
    if os.path.isdir(os.path.dirname(PREVIEW)):
        icon.resize((SIZE * 3, SIZE * 3), Image.LANCZOS).save(PREVIEW)
