"""Turns the thumbnail render into workshop/thumbnail.jpg: darkened toward the corners and shrunk
to the 512 square the workshop wants.

    python tools/finish_thumbnail.py renders
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

SIZE = 512
VIGNETTE = 0.45  # how dark the corners go
FALLOFF = 1.8
SHARPEN = (1.2, 60, 2)  # unsharp mask radius, percent, threshold, after shrinking
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

im = Image.open(os.path.join(sys.argv[1], "thumbnail.png")).convert("RGB")
a = np.asarray(im).astype(np.float32) / 255
h, w = a.shape[:2]
y, x = np.mgrid[0:h, 0:w]
d = np.sqrt(((x - w / 2) / (w / 2)) ** 2 + ((y - h / 2) / (h / 2)) ** 2) / np.sqrt(2)
a *= (1 - VIGNETTE * d ** FALLOFF)[..., None]
im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
im = im.resize((SIZE, SIZE), Image.LANCZOS).filter(ImageFilter.UnsharpMask(*SHARPEN))

out = os.path.join(ROOT, "workshop", "thumbnail.jpg")
os.makedirs(os.path.dirname(out), exist_ok=True)
im.save(out, quality=92, optimize=True)
print("workshop/thumbnail.jpg  %dx%d  %d KB" % (im.width, im.height, os.path.getsize(out) // 1024))
