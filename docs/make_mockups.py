#!/usr/bin/env python3
"""Generate the README mockup assets from raw screenshots.

Wraps each raw 1080x2340 screenshot in a clean modern phone bezel (rounded
screen, thin near-black frame, soft drop shadow) and composes a fanned,
overlapping "hero" image from three of them. Also emits individually framed
phones for the screenshot row.

Run:  python docs/make_mockups.py
Deps: Pillow  (python -m pip install Pillow)

Re-run whenever the screenshots change. Output -> docs/screenshots/generated/.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

SRC = os.path.join(os.path.dirname(__file__), "screenshots")
OUT = os.path.join(SRC, "generated")
os.makedirs(OUT, exist_ok=True)

BEZEL = (18, 18, 20, 255)      # near-black frame
RIM   = (70, 70, 78, 255)      # subtle outer rim so the phone reads on dark bg
ACCENT = (108, 99, 255)        # Moongate purple (#6C63FF) - unused stage tint hook

BACKDROP = (245, 245, 247, 255)  # Apple-style light grey (#F5F5F7); None = transparent
STAGE_RADIUS = 0.045             # rounded-corner fraction of min dim; 0 = square corners


def frame_phone(name, screen_w):
    """Return an upright RGBA framed phone built from screenshots/<name>."""
    shot = Image.open(os.path.join(SRC, name)).convert("RGBA")
    sw = screen_w
    sh = round(sw * shot.height / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)

    bezel = max(2, round(sw * 0.030))
    screen_r = round(sw * 0.085)
    outer_r = screen_r + bezel

    W, H = sw + 2 * bezel, sh + 2 * bezel
    phone = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(phone)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=outer_r, fill=BEZEL,
                        outline=RIM, width=max(1, round(sw * 0.004)))

    # Round the screenshot's corners and seat it inside the bezel.
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1],
                                           radius=screen_r, fill=255)
    phone.paste(shot, (bezel, bezel), mask)
    return phone


def with_shadow(phone, blur=None, alpha=155, off=None):
    """Composite a soft drop shadow under an (already rotated) phone RGBA."""
    W, H = phone.size
    blur = blur or round(W * 0.06)
    off = off or (round(W * 0.015), round(W * 0.08))
    pad = blur * 3 + max(abs(off[0]), abs(off[1]))
    canvas = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))

    sil = Image.new("RGBA", phone.size, (0, 0, 0, 0))
    sil.putalpha(phone.split()[3].point(lambda a: alpha if a > 0 else 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow.paste(sil, (pad + off[0], pad + off[1]), sil)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(phone, (pad, pad))
    return canvas


def trim(img, margin=40):
    bbox = img.getbbox()
    if not bbox:
        return img
    img = img.crop(bbox)
    out = Image.new("RGBA", (img.width + 2 * margin, img.height + 2 * margin),
                    (0, 0, 0, 0))
    out.alpha_composite(img, (margin, margin))
    return out


def add_backdrop(fg, color, radius_frac=STAGE_RADIUS):
    """Composite the phones over a solid (optionally rounded) colour stage."""
    if color is None:
        return fg
    bg = Image.new("RGBA", fg.size, color)
    if radius_frac > 0:
        r = round(min(fg.size) * radius_frac)
        mask = Image.new("L", fg.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, fg.width - 1, fg.height - 1], radius=r, fill=255)
        bg.putalpha(mask)
    return Image.alpha_composite(bg, fg)


def build_hero():
    center_w = 560
    side_w = round(center_w * 0.86)

    center = frame_phone("dashboard.png", center_w)
    left = frame_phone("printer-mainsail.png", side_w).rotate(8, expand=True,
                                                              resample=Image.BICUBIC)
    right = frame_phone("gcode-viewer.png", side_w).rotate(-8, expand=True,
                                                           resample=Image.BICUBIC)

    Wc, Hc = center.size
    canvas = Image.new("RGBA", (Wc * 3, round(Hc * 1.7)), (0, 0, 0, 0))
    cx, cy = canvas.width // 2, canvas.height // 2

    dx = round(Wc * 0.66)
    dy = round(Hc * 0.05)

    def place(layer, ccx, ccy):
        s = with_shadow(layer)
        canvas.alpha_composite(s, (ccx - s.width // 2, ccy - s.height // 2))

    place(left, cx - dx, cy + dy)
    place(right, cx + dx, cy + dy)
    place(center, cx, cy)

    hero = trim(canvas, margin=120)
    hero = add_backdrop(hero, BACKDROP)
    hero.save(os.path.join(OUT, "hero.png"))
    print("hero.png", hero.size)


def build_row():
    # The README screenshot gallery. gcode-viewer.png also appears (fanned,
    # partly obscured) in the hero - it's featured again here standalone so the
    # print-from-stored-gcodes flow gets a clear, unobstructed showcase.
    for name in ["pairing.png", "drawer.png", "icon-guide.png", "custom-theme.png",
                 "gcode-viewer.png", "console.png", "file-system.png",
                 "config-editor.png"]:
        phone = with_shadow(frame_phone(name, 460), alpha=90)
        phone = trim(phone, margin=10)
        phone.save(os.path.join(OUT, "framed-" + name))
        print("framed-" + name, phone.size)


if __name__ == "__main__":
    build_hero()
    build_row()
