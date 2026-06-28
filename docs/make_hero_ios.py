#!/usr/bin/env python3
"""Generate the iOS-launch hero (docs/screenshots/generated/hero-ios.png).

Re-skins the multi-printer Android dashboard as a black iPhone (Dynamic Island
with camera lens, iOS status bar, home indicator), centred between the two
black Android phones, under a "Now on iPhone and Android" headline with drawn
Apple and Android badges. Reuses the bezel/shadow helpers in make_mockups.py
and reads only the repo's own screenshots, so it is fully reproducible.

Run:  python docs/make_hero_ios.py
Deps: Pillow

Staged for the iOS App Store launch. The live README image is hero.png; swap
to this (and add the App Store link) once the iPhone app is approved.
"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageChops
import make_mockups as mm

HERE = os.path.dirname(__file__)
SRC = mm.SRC
DASH = os.path.join(SRC, "dashboard.png")
OUT = os.path.join(SRC, "generated", "hero-ios.png")

BACKDROP = (245, 245, 247, 255)
INK = (22, 22, 27, 255)
SUB = (93, 93, 102, 255)

_FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
]


def font(size):
    for p in _FONT_CANDIDATES:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def apple_logo(size, color=(20, 20, 24, 255)):
    """A drawn black Apple silhouette: two-lobe body, right-side bite, angled leaf."""
    N = size * 4
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    for cxf in (0.34, 0.66):
        cx, cyb, r = N * cxf, N * 0.62, N * 0.31
        d.ellipse([cx - r, cyb - r, cx + r, cyb + r], fill=255)
    d.rectangle([N * 0.34, N * 0.62, N * 0.66, N * 0.93], fill=255)
    d.ellipse([N * 0.80, N * 0.40, N * 1.14, N * 0.74], fill=0)
    leaf = Image.new("L", (N, N), 0)
    ImageDraw.Draw(leaf).ellipse([N * 0.49, N * 0.05, N * 0.65, N * 0.33], fill=255)
    leaf = leaf.rotate(-35, center=(N * 0.54, N * 0.30))
    m = ImageChops.lighter(m, leaf)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", (size, size), color), (0, 0), m)
    return out


def android_head(draw, x, y, s):
    g = (61, 220, 132, 255)
    draw.pieslice([x, y, x + s, y + s], 180, 360, fill=g)
    aw = max(3, int(s * 0.06))
    draw.line([(x + s * 0.30, y + s * 0.05), (x + s * 0.20, y - s * 0.12)], fill=g, width=aw)
    draw.line([(x + s * 0.70, y + s * 0.05), (x + s * 0.80, y - s * 0.12)], fill=g, width=aw)
    er = s * 0.06
    for ex in (0.34, 0.66):
        cxx, cyy = x + s * ex, y + s * 0.30
        draw.ellipse([cxx - er, cyy - er, cxx + er, cyy + er], fill=(255, 255, 255, 255))


def iphone_screen(path, top_cut=72, bot_cut=94):
    """Crop the Android system bars off a dashboard shot and add iPhone chrome."""
    shot = Image.open(path).convert("RGBA")
    W, H = shot.size
    content = shot.crop((0, top_cut, W, H - bot_cut))
    ch = content.height
    bg = content.getpixel((28, 28))
    top_h, bot_h = 150, 58
    screen = Image.new("RGBA", (W, top_h + ch + bot_h), bg)
    screen.paste(content, (0, top_h))
    d = ImageDraw.Draw(screen)

    iw, ih = int(W * 0.33), int(W * 0.099)
    ix, iy = (W - iw) // 2, 34
    cy = iy + ih / 2
    d.rounded_rectangle([ix, iy, ix + iw, iy + ih], radius=ih // 2, fill=(0, 0, 0, 255))

    lx, ly, lr = ix + iw - ih * 0.60, cy, ih * 0.30
    d.ellipse([lx - lr, ly - lr, lx + lr, ly + lr], fill=(6, 6, 10, 255))
    d.ellipse([lx - lr * 0.62, ly - lr * 0.62, lx + lr * 0.62, ly + lr * 0.62], fill=(16, 17, 26, 255))
    gr = lr * 0.34
    d.ellipse([lx - gr + lr * 0.22, ly - gr - lr * 0.12, lx + gr + lr * 0.22, ly + gr - lr * 0.12], fill=(78, 86, 158, 210))

    f = font(42)
    d.text((78, cy), "9:41", font=f, fill=(255, 255, 255, 255), anchor="lm")

    bw, bh = 54, 26
    bx, by = W - 78 - bw, cy - bh / 2
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=7, outline=(255, 255, 255, 210), width=3)
    d.rounded_rectangle([bx + 4, by + 4, bx + 4 + int((bw - 8) * 0.8), by + bh - 4], radius=4, fill=(255, 255, 255, 235))
    d.rounded_rectangle([bx + bw + 2, by + 8, bx + bw + 7, by + bh - 8], radius=2, fill=(255, 255, 255, 210))

    wx, wy = bx - 52, cy + 8
    for r, wd in ((26, 5), (17, 5), (8, 5)):
        d.arc([wx - r, wy - r, wx + r, wy + r], 213, 327, fill=(255, 255, 255, 220), width=wd)
    d.ellipse([wx - 4, wy - 4, wx + 4, wy + 4], fill=(255, 255, 255, 235))

    hw, hh = int(W * 0.36), 14
    hx = (W - hw) // 2
    hy = top_h + ch + (bot_h - hh) // 2
    d.rounded_rectangle([hx, hy, hx + hw, hy + hh], radius=hh // 2, fill=(236, 236, 240, 235))
    return screen


def frame_image(img, screen_w, bezel, rim):
    sw = screen_w
    sh = round(sw * img.height / img.width)
    shot = img.resize((sw, sh), Image.LANCZOS)
    bz = max(2, round(sw * 0.028))
    sr = round(sw * 0.090)
    outer = sr + bz
    W, H = sw + 2 * bz, sh + 2 * bz
    phone = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(phone)
    d.rounded_rectangle([0, 0, W - 1, H - 1], radius=outer, fill=bezel,
                        outline=rim, width=max(1, round(sw * 0.004)))
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=sr, fill=255)
    phone.paste(shot, (bz, bz), mask)
    return phone


def build_phones():
    center_w = 520
    side_w = round(center_w * 0.86)
    center = frame_image(iphone_screen(DASH), center_w, mm.BEZEL, mm.RIM)
    left = mm.frame_phone("printer-mainsail.png", side_w).rotate(8, expand=True, resample=Image.BICUBIC)
    right = mm.frame_phone("gcode-viewer.png", side_w).rotate(-8, expand=True, resample=Image.BICUBIC)
    Wc, Hc = center.size
    canvas = Image.new("RGBA", (Wc * 3, round(Hc * 1.7)), (0, 0, 0, 0))
    cx, cy = canvas.width // 2, canvas.height // 2
    dx, dy = round(Wc * 0.66), round(Hc * 0.05)

    def place(layer, ccx, ccy):
        s = mm.with_shadow(layer)
        canvas.alpha_composite(s, (ccx - s.width // 2, ccy - s.height // 2))

    place(left, cx - dx, cy + dy)
    place(right, cx + dx, cy + dy)
    place(center, cx, cy)
    return mm.trim(canvas, margin=60)


def build_hero_ios():
    phones = build_phones()
    Wp, Hp = phones.size
    TOP = 360
    final = Image.new("RGBA", (Wp, TOP + Hp), BACKDROP)
    final.alpha_composite(phones, (0, TOP))
    d = ImageDraw.Draw(final)
    mid = Wp // 2

    hl, sf, pf = font(76), font(34), font(38)

    head = "Now on iPhone and Android"
    w = d.textlength(head, font=hl)
    d.text((mid - w / 2, 96), head, font=hl, fill=INK, stroke_width=1, stroke_fill=INK)

    subt = "One app for your whole printer fleet, anywhere"
    w = d.textlength(subt, font=sf)
    d.text((mid - w / 2, 210), subt, font=sf, fill=SUB)

    lab1, lab2 = "iPhone", "Android"
    padx, gap, ph, icon = 36, 16, 92, 50
    w1 = padx + icon + gap + d.textlength(lab1, font=pf) + padx
    w2 = padx + icon + gap + d.textlength(lab2, font=pf) + padx
    space = 28
    x = mid - (w1 + space + w2) / 2
    y = 286

    def pill(px, pw):
        d.rounded_rectangle([px, y, px + pw, y + ph], radius=ph // 2,
                            fill=(255, 255, 255, 255), outline=(216, 216, 222, 255), width=2)

    pill(x, w1)
    final.alpha_composite(apple_logo(icon), (int(x + padx), int(y + ph / 2 - icon / 2)))
    d.text((x + padx + icon + gap, y + ph / 2), lab1, font=pf, fill=INK, anchor="lm")

    x2 = x + w1 + space
    pill(x2, w2)
    android_head(d, x2 + padx, y + ph * 0.30, icon)
    d.text((x2 + padx + icon + gap, y + ph / 2), lab2, font=pf, fill=INK, anchor="lm")

    r = round(min(final.size) * 0.03)
    mask = Image.new("L", final.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, final.width - 1, final.height - 1], radius=r, fill=255)
    out = Image.new("RGBA", final.size, (0, 0, 0, 0))
    out.paste(final, (0, 0), mask)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out.save(OUT)
    print("hero-ios.png", out.size)


if __name__ == "__main__":
    build_hero_ios()
