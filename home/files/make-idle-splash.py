#!/usr/bin/env python3
"""Render the "Stremio is paused" screen shown while the idle backstop holds it off.

Kept as a generator rather than a checked-in PNG so the wording can be changed
without a binary round-trip, and so the image can be rebuilt if it is lost.

Sized to the panel's native 1920x1080 rather than the 1536x864 logical desktop:
imv scales to fit the output, and rendering at native resolution keeps the text
crisp instead of being upscaled from the 125% logical size.

Text is deliberately large — this is read from a sofa, not a desk.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG = (18, 16, 42)          # matches Stremio's dark navy so the handover is not jarring
FG = (255, 255, 255)
MUTED = (138, 134, 184)
ACCENT = (124, 92, 255)

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/.local/share/kiosk-idle.png")

FONT_DIRS = [
    "/usr/share/fonts/truetype/dejavu",
    "/usr/share/fonts/truetype/liberation",
    "/usr/share/fonts/truetype/noto",
]


def font(bold, size):
    names = (["DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf"] if bold
             else ["DejaVuSans.ttf", "LiberationSans-Regular.ttf"])
    for d in FONT_DIRS:
        for n in names:
            p = os.path.join(d, n)
            if os.path.exists(p):
                return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def centre(draw, y, text, f, fill):
    box = draw.textbbox((0, 0), text, font=f)
    draw.text(((W - (box[2] - box[0])) / 2, y), text, font=f, fill=fill)
    return box[3] - box[1]


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

# A soft accent bar rather than a logo — nothing to misrepresent, and it reads
# as deliberate rather than as a crashed screen.
d.rounded_rectangle([(W / 2 - 90, 300), (W / 2 + 90, 308)], radius=4, fill=ACCENT)

centre(d, 380, "Stremio is paused", font(True, 96), FG)
centre(d, 530, "Press any button on the remote to start it", font(False, 52), FG)
centre(d, 640, "Paused automatically to save power while the TV was off",
       font(False, 34), MUTED)
centre(d, 950, "midz HTPC", font(False, 26), (70, 66, 110))

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT)
print(f"wrote {OUT} ({W}x{H})")
