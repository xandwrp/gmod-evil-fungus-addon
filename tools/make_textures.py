"""Bakes the fungus's skin textures into materials/evil_fungus/ as VTFs.

u runs around a strand, v runs along it. Everything is built in frequency space or
on a wrapped grid, so both directions tile. Alpha is how wet each spot is, used as
the cubemap mask.

    python tools/make_textures.py
"""
import os
import struct

import numpy as np
from PIL import Image

SIZE = 512
SEED = 1998
GAIN = 1.35  # strands are tinted by vertex colour too, so the textures sit bright
OUT = os.path.join(os.path.dirname(__file__), "..", "materials", "evil_fungus")
PREVIEW = os.path.join(os.path.dirname(__file__), "..", "renders")

rng = np.random.default_rng(SEED)
fy, fx = np.meshgrid(np.fft.fftfreq(SIZE) * SIZE, np.fft.fftfreq(SIZE) * SIZE, indexing="ij")
Y, X = np.meshgrid(np.arange(SIZE) / SIZE, np.arange(SIZE) / SIZE, indexing="ij")


def norm(a):
    a = a - a.min()
    return a / max(a.max(), 1e-9)


def noise(freq, stretch_u=1.0, stretch_v=1.0, width=0.5):
    """Tiling band-passed noise around `freq` cycles per tile, squashed along u or v."""
    r = np.sqrt((fx * stretch_u) ** 2 + (fy * stretch_v) ** 2)
    band = np.exp(-((np.log(r + 1e-6) - np.log(freq)) ** 2) / (2 * width ** 2))
    band[0, 0] = 0
    white = rng.standard_normal((SIZE, SIZE))
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * band))
    return out / out.std()


def fbm(freq, octaves, gain=0.55, **kw):
    total, amp = np.zeros((SIZE, SIZE)), 1.0
    for i in range(octaves):
        total += noise(freq * 2 ** i, **kw) * amp
        amp *= gain
    return total / total.std()


def blur(a, sigma):
    g = np.exp(-(fx ** 2 + fy ** 2) * (2 * np.pi ** 2) * (sigma / SIZE) ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def warp(a, du, dv):
    """Samples a at (u + du, v + dv), du and dv in pixels, wrapping."""
    xi = (np.arange(SIZE)[None, :] + du) % SIZE
    yi = (np.arange(SIZE)[:, None] + dv) % SIZE
    x0, y0 = np.floor(xi).astype(int), np.floor(yi).astype(int)
    tx, ty = xi - x0, yi - y0
    x1, y1 = (x0 + 1) % SIZE, (y0 + 1) % SIZE
    top = a[y0, x0] * (1 - tx) + a[y0, x1] * tx
    bot = a[y1, x0] * (1 - tx) + a[y1, x1] * tx
    return top * (1 - ty) + bot * ty


def hexes(cells):
    """Distance to the nearest wall of a hex grid with `cells` columns per tile, 0 at walls."""
    w = 1.0 / cells
    h = w * np.sqrt(3) / 2
    rows = max(2, int(round(1.0 / h / 2)) * 2)
    h = 1.0 / rows
    pts = []
    for r in range(rows):
        for c in range(cells):
            pts.append(((c + (0.5 if r % 2 else 0)) / cells, r * h))
    pts = np.array(pts) + rng.uniform(-0.18, 0.18, (len(pts), 2)) * [w, h]
    d1 = np.full((SIZE, SIZE), 9.0)
    d2 = np.full((SIZE, SIZE), 9.0)
    for px, py in pts:
        dx = (X - px + 0.5) % 1 - 0.5
        dy = (Y - py + 0.5) % 1 - 0.5
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        d1 = np.where(closer, d, d1)
    return norm(np.clip(d2 - d1, 0, w * 0.5))


def tint(gray, *stops):
    """Maps 0..1 through a list of (at, (r, g, b)) colour stops."""
    at = np.array([s[0] for s in stops])
    rgb = np.array([s[1] for s in stops], dtype=float) / 255
    return np.stack([np.interp(gray, at, rgb[:, c]) for c in range(3)], -1)


def flesh():
    """Tentacle skin: deep rings of wrinkles around it, a few veins down it, bruised and greasy."""
    wob_u = fbm(3, 2) * 8
    rings = 6
    phase = Y * rings + fbm(2, 2) * 0.22 + np.sin(2 * np.pi * X) * 0.08
    ridge = np.abs(np.sin(np.pi * phase)) ** 0.6
    small = np.abs(np.sin(np.pi * (Y * rings * 3 + fbm(3, 2) * 0.5))) ** 0.8
    small_amt = np.clip(norm(fbm(2, 2)) * 1.4 - 0.3, 0, 1)
    fine = fbm(28, 2, stretch_u=5.0)
    height = ridge * 0.7 + small * small_amt * 0.18 + fine * 0.025 + fbm(8, 2) * 0.05

    veins = 1 - np.abs(warp(fbm(4, 2, stretch_v=7.0), wob_u, 0))
    veins = np.clip((veins - 0.86) / 0.14, 0, 1) ** 1.3
    height += veins * 0.25

    cavity = norm(np.clip(height - blur(height, 12), -0.45, 0.45))
    slope = np.roll(height, -2, 0) - np.roll(height, 2, 0)
    relief = np.clip(0.5 - slope * 2.2, 0, 1)
    bruise = norm(fbm(3, 3))
    mottle = norm(fbm(12, 2))
    smudge = np.clip(fbm(5, 3) * 0.5 - 0.2, 0, 1)
    grain = fbm(110, 1)

    base = tint(bruise,
                (0.0, (200, 186, 180)),
                (0.45, (176, 154, 156)),
                (0.75, (148, 112, 124)),
                (1.0, (110, 76, 94)))
    sick = tint(mottle, (0.0, (255, 255, 255)), (0.7, (255, 255, 255)), (1.0, (275, 265, 220)))
    col = base * sick
    col *= (0.35 + 0.55 * cavity + 0.3 * relief)[..., None]
    col = col * (1 - veins[..., None] * 0.5) + veins[..., None] * np.array([96, 70, 110]) / 255 * 0.5
    col *= (1 - smudge * 0.45 + grain * 0.035)[..., None]

    streaks = np.clip(fbm(5, 3, stretch_v=4.0) * 0.4 + 0.5, 0, 1)
    wet = np.clip(ridge * 0.55 + relief * 0.35 + veins * 0.3 + streaks * 0.35 - smudge * 0.7 - 0.25, 0.06, 1)
    return col, wet


def fiber():
    """The mat: hyphae bundled along the strand, crossed now and then, grimy and only damp."""
    wob = fbm(4, 3) * 5
    strands = np.zeros((SIZE, SIZE))
    for freq, amp in ((10, 0.5), (22, 0.35), (46, 0.2)):
        r = 1 - np.abs(warp(noise(freq, stretch_v=12.0, width=0.35), wob, 0))
        strands += np.clip((r - 0.55) / 0.45, 0, 1) ** 2 * amp
    cross = 1 - np.abs(warp(noise(9, stretch_u=7.0, width=0.4), 0, wob))
    cross = np.clip((cross - 0.9) / 0.1, 0, 1) * 0.25
    cells = hexes(12)
    cells = np.clip(cells * 3, 0, 1)
    height = strands + cross + cells * 0.12 + fbm(30, 2) * 0.03

    cavity = norm(np.clip(height - blur(height, 6), -0.5, 0.5))
    dirt = norm(fbm(3, 3))
    grime = np.clip(fbm(6, 3) * 0.5 - 0.15, 0, 1)
    grain = fbm(110, 1)

    base = tint(dirt,
                (0.0, (206, 196, 176)),
                (0.5, (180, 166, 140)),
                (1.0, (138, 120, 100)))
    col = base * (0.5 + 0.6 * cavity)[..., None]
    col *= (0.86 + 0.14 * cells)[..., None]
    col *= (1 - grime * 0.5 + grain * 0.04)[..., None]

    beads = np.clip((fbm(18, 2) - 1.6) / 0.6, 0, 1)
    wet = np.clip(cavity * 0.35 + beads * 0.8 - grime * 0.4, 0.03, 0.75)
    return col, wet


def dxt1_solid(rgb):
    """A 16x16 DXT1 thumbnail, one flat colour per block."""
    small = np.asarray(Image.fromarray(rgb).resize((4, 4), Image.BOX)).astype(int)
    out = bytearray()
    for by in range(4):
        for bx in range(4):
            r, g, b = small[by, bx]
            c = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            out += struct.pack("<HHI", c, c, 0)
    return bytes(out)


def write_vtf(path, rgba, mip=None):
    img = Image.fromarray(rgba, "RGBA")
    mips = [img]
    while mips[-1].width > 1:
        w = mips[-1].width // 2
        mips.append(img.resize((w, w), Image.LANCZOS))
    if mip:
        mips = [mip(m) for m in mips]

    flags = 0x0010 | 0x2000  # anisotropic, eight-bit alpha
    linear = (rgba[..., :3].astype(float) / 255) ** 2.2
    refl = linear.reshape(-1, 3).mean(0)
    header = struct.pack(
        "<4s2IIHHIHH4x3f4xfIBIBBH",
        b"VTF\0", 7, 2, 80, rgba.shape[1], rgba.shape[0], flags, 1, 0,
        *refl, 1.0, 12, len(mips), 13, 16, 16, 1)
    header += b"\0" * (80 - len(header))

    with open(path, "wb") as f:
        f.write(header)
        f.write(dxt1_solid(rgba[..., :3]))
        for m in reversed(mips):
            a = np.asarray(m)
            f.write(a[..., [2, 1, 0, 3]].tobytes())


def save(name, col, wet):
    rgb = (np.clip(col, 0, 1) * 255 + 0.5).astype(np.uint8)
    a = (np.clip(wet, 0, 1) * 255 + 0.5).astype(np.uint8)
    rgba = np.dstack([rgb, a])
    os.makedirs(OUT, exist_ok=True)
    write_vtf(os.path.join(OUT, name + ".vtf"), rgba)
    os.makedirs(PREVIEW, exist_ok=True)
    tiled = np.tile(rgb, (2, 2, 1))
    Image.fromarray(np.hstack([tiled, np.tile(np.dstack([a] * 3), (2, 2, 1))])).save(
        os.path.join(PREVIEW, name + "_preview.png"))
    print(name, "mean", rgb.reshape(-1, 3).mean(0).round(), "wet", round(a.mean() / 255, 2))


if __name__ == "__main__":
    for name, make in (("flesh", flesh), ("fiber", fiber)):
        col, wet = make()
        save(name, col * GAIN, wet)
