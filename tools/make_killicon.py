"""Draws the fungus's kill icon into materials/killicons/ as a white silhouette, tinted in game.

A sleeper's head in profile, eyes shut and chin up, with everything below it gone to strands
that come apart from the neck down and spread out into the mat. Drawn large and shrunk, so the
thin strands stay soft.

    python tools/make_killicon.py
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw

HEIGHT = 48
SS = 8  # supersampling
W, H = 140, 72  # working canvas, in icon pixels before the crop
SEED = 4
TILT = -12  # degrees the head is tipped back
GROUND = 58
ROOTS = 5
R_ROOT = 1.25
R_TIP = 0.5
REACH = 14  # how far a root runs before it first forks
SHORTER = 0.85  # each fork's run against the one before
TAPER = 0.7
KINK = 0.18
STEP = 0.7
PITCH = 0.5  # how squashed the ground is, looked down on
OUT = os.path.join(os.path.dirname(__file__), "..", "materials", "killicons", "evil_fungus.png")
PREVIEW = os.path.join(os.path.dirname(__file__), "..", "renders", "killicon_preview.png")

rand = random.Random(SEED)

# The head outline, facing left: crown, round the back, down the nape, then up the front of the
# throat, chin, mouth, nose and brow.
PROFILE = [
    (33, 6), (43, 8), (50, 15), (52.5, 24), (50, 33), (46, 38.5), (45, 44), (45.5, 48),
    (29, 48), (27.5, 45.5), (22.5, 44.5), (18.8, 42.2), (18.4, 39.6), (17.2, 38.4), (17.6, 37),
    (16.4, 35.8), (16.8, 34.6), (16, 33.4), (16.4, 31.6), (12.6, 29.6), (13.6, 27.4), (17.2, 22.6),
    (18.2, 19.2), (19.4, 14), (24, 8.4),
]
PIVOT = (34, 30)
SHIFT = 36  # room on the left for the roots under the chin
EYE = [(19.6, 23.4), (21.6, 24.6), (23.8, 24.4)]
EAR = [(39.2, 25), (41.6, 23.8), (43, 27), (41.4, 30.6), (39.6, 31)]


def layer():
    im = Image.new("L", (W * SS, H * SS), 0)
    return im, ImageDraw.Draw(im)


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


def curve(p0, p1, p2, n=24):
    return [(p0[0] * (1 - t) ** 2 + p1[0] * 2 * t * (1 - t) + p2[0] * t * t,
             p0[1] * (1 - t) ** 2 + p1[1] * 2 * t * (1 - t) + p2[1] * t * t) for t in (i / n for i in range(n + 1))]


def spline(points, closed=False, n=8):
    """Catmull-Rom through points."""
    if closed:
        pts = points[-1:] + points + points[:2]
    else:
        pts = points[:1] + points + points[-1:]
    out = []
    for i in range(1, len(pts) - 2):
        p0, p1, p2, p3 = pts[i - 1:i + 3]
        for s in range(n):
            t = s / n
            out.append(tuple(0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t * t
                                    + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * t ** 3) for k in (0, 1)))
    return out if closed else out + [points[-1]]


def tilt(points):
    a = math.radians(TILT)
    c, s = math.cos(a), math.sin(a)
    return [(SHIFT + PIVOT[0] + (x - PIVOT[0]) * c - (y - PIVOT[1]) * s, PIVOT[1] + (x - PIVOT[0]) * s + (y - PIVOT[1]) * c)
            for x, y in points]


def ground(x, d):
    """Screen position of a spot on the ground, d coming toward the viewer, looked down on a little."""
    return x, GROUND + d * PITCH


def spread(draw, x, d, heading, r, length=None):
    """A root across the ground: a kinked run that forks in two, thinner each time, until it's a hair."""
    pts = [ground(x, d)]
    length = length or REACH
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
        if rand.random() < 0.9:
            spread(draw, x, d, heading + turn * rand.uniform(0.3, 0.7), r * rand.uniform(0.88, 1.0),
                   length * SHORTER * rand.uniform(0.8, 1.2))


head, hd = layer()
hd.polygon([(x * SS, y * SS) for x, y in spline(tilt(PROFILE), closed=True)], fill=255)

cuts, cd = layer()
stroke(cd, spline(tilt(EYE)), 0.7, 0.55)
stroke(cd, spline(tilt(EAR)), 0.6, 0.45)

# Below the neck it's all roots, flaring out into the mat.
NECK = [(29, 49), (45.5, 47)]
(ax, ay), (bx, by) = tilt(NECK)
hd.polygon([(ax * SS, ay * SS), (bx * SS, by * SS), (bx * SS, H * SS), (0, H * SS), (0, ay * SS)], fill=0)
head = ImageChops.subtract(head, cuts)
roots, rd = layer()
for i in range(ROOTS):
    f = (i + 0.5) / ROOTS
    x, y = ax + (bx - ax) * f, ay + (by - ay) * f - 1.5
    # Out behind them, or forward under the chin, and some toward or away from the viewer.
    heading = (0 if f > 0.35 else math.pi) + rand.uniform(-0.6, 0.6)
    d = math.sin(heading) * 2
    gx, gy = ground(x + math.cos(heading) * 5, d)
    stroke(rd, curve((x, y), (x, gy), (gx, gy)), R_ROOT * 1.15, R_ROOT)
    spread(rd, x + math.cos(heading) * 5, d, heading, R_ROOT)
full = ImageChops.lighter(head, roots)
if os.environ.get("DEBUG"):
    full.resize((W * 4, H * 4), Image.LANCZOS).save(PREVIEW.replace(".png", "_full.png"))
alpha = full.resize((W, H), Image.LANCZOS)
alpha = alpha.crop(alpha.getbbox())
alpha = alpha.resize((round(alpha.width * HEIGHT / alpha.height), HEIGHT), Image.LANCZOS)
icon = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
icon.putalpha(alpha)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
icon.save(OUT, optimize=True)
print("materials/killicons/evil_fungus.png  %dx%d" % icon.size)

if os.path.isdir(os.path.dirname(PREVIEW)):
    tint = Image.new("RGBA", icon.size, (235, 175, 180, 255))
    tint.putalpha(alpha)
    bg = Image.new("RGBA", (icon.width + 16, icon.height + 16), (24, 24, 24, 255))
    bg.alpha_composite(tint, (8, 8))
    big = bg.resize((bg.width * 5, bg.height * 5), Image.NEAREST)
    sheet = Image.new("RGBA", (big.width, big.height + bg.height + 8), (24, 24, 24, 255))
    sheet.alpha_composite(big)
    sheet.alpha_composite(bg, (0, big.height + 4))
    sheet.save(PREVIEW)
