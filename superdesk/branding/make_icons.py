"""Generate all super远程桌面 icons (Windows, tray, Flutter assets, Android) from one design.

Design (1024 grid): blue gradient rounded square, white monitor with stand, white mouse
pointer on the screen. Pure geometry, so the PNG/ICO renders and the SVG match exactly.

Usage: python superdesk/branding/make_icons.py      (run from anywhere; needs Pillow)
"""
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
C1, C2 = (0x2F, 0x6B, 0xFF), (0x00, 0xC2, 0xE8)  # gradient top-left -> bottom-right
SS = 4  # supersampling factor for anti-aliasing

# --- geometry on a 1024 grid --------------------------------------------------
BG_R = 224
MON = (192, 250, 832, 690)        # monitor outer rect
MON_R = 60
SCREEN = (252, 310, 772, 630)     # screen cut-out
SCREEN_R = 18
NECK = (462, 690, 562, 770)
BASE = (342, 762, 682, 822)
BASE_R = 30
POINTER = [(468, 366), (468, 594), (522, 544), (562, 628), (604, 608),
           (564, 526), (636, 526)]


def gradient(size):
    """Diagonal gradient C1 (top-left) -> C2 (bottom-right)."""
    idx = np.arange(size)
    t = (idx[:, None] + idx[None, :]) / (2 * (size - 1))
    c1, c2 = np.array(C1, dtype=float), np.array(C2, dtype=float)
    arr = (c1 + (c2 - c1) * t[..., None]).round().astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def s(v, k):
    return [round(c * k) for c in v] if isinstance(v, tuple) else round(v * k)


def glyph_mask(size):
    """White parts (monitor frame, stand, pointer) as an L mask at `size`."""
    k = size / 1024
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle(s(MON, k), s(MON_R, k), fill=255)
    d.rounded_rectangle(s(SCREEN, k), s(SCREEN_R, k), fill=0)
    d.rectangle(s(NECK, k), fill=255)
    d.rounded_rectangle(s(BASE, k), s(BASE_R, k), fill=255)
    d.polygon([(x * k, y * k) for x, y in POINTER], fill=255)
    return m


def render(size, background=True, rounded=True, scale=1.0, white_only=False):
    """Render the icon. scale<1 shrinks the glyph around the centre (Android safe zone)."""
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if background:
        bg = gradient(big).convert("RGBA")
        bm = Image.new("L", (big, big), 0)
        if rounded:
            ImageDraw.Draw(bm).rounded_rectangle((0, 0, big - 1, big - 1), round(BG_R * big / 1024), fill=255)
        else:
            bm.paste(255, (0, 0, big, big))
        img.paste(bg, (0, 0), bm)
    gs = round(big * scale)
    gm = glyph_mask(gs)
    off = (big - gs) // 2
    white = Image.new("RGBA", (gs, gs), (255, 255, 255, 255))
    if white_only or background:
        img.paste(white, (off, off), gm)
    else:
        img.paste(Image.new("RGBA", (gs, gs), C1 + (255,)), (off, off), gm)
    return img.resize((size, size), Image.LANCZOS)


def save_png(img, *rel):
    path = os.path.join(ROOT, *rel)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


def save_ico(*rel):
    path = os.path.join(ROOT, *rel)
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    imgs = [render(n) for n in sizes]
    imgs[-1].save(path, format="ICO", sizes=[(n, n) for n in sizes], append_images=imgs[:-1])
    print("wrote", os.path.relpath(path, ROOT))


def svg():
    def rr(r, rad):
        x1, y1, x2, y2 = r
        return f'<rect x="{x1}" y="{y1}" width="{x2 - x1}" height="{y2 - y1}" rx="{rad}"/>'
    pts = " ".join(f"{x},{y}" for x, y in POINTER)
    x1, y1, x2, y2 = SCREEN
    # Screen cut-out drawn in the background gradient, on top of the white frame.
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="#{C1[0]:02x}{C1[1]:02x}{C1[2]:02x}"/>
<stop offset="1" stop-color="#{C2[0]:02x}{C2[1]:02x}{C2[2]:02x}"/>
</linearGradient>
<linearGradient id="gs" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1024" y2="1024">
<stop offset="0" stop-color="#{C1[0]:02x}{C1[1]:02x}{C1[2]:02x}"/>
<stop offset="1" stop-color="#{C2[0]:02x}{C2[1]:02x}{C2[2]:02x}"/>
</linearGradient></defs>
<rect width="1024" height="1024" rx="{BG_R}" fill="url(#g)"/>
<g fill="#fff">{rr(MON, MON_R)}{rr(NECK, 0)}{rr(BASE, BASE_R)}</g>
<rect x="{x1}" y="{y1}" width="{x2 - x1}" height="{y2 - y1}" rx="{SCREEN_R}" fill="url(#gs)"/>
<polygon fill="#fff" points="{pts}"/>
</svg>
'''


def main():
    # Windows / desktop
    save_ico("res", "icon.ico")
    save_ico("res", "tray-icon.ico")
    save_ico("flutter", "windows", "runner", "resources", "app_icon.ico")
    save_png(render(1024), "res", "icon.png")
    for n, name in [(32, "32x32.png"), (64, "64x64.png"), (128, "128x128.png"), (256, "128x128@2x.png")]:
        save_png(render(n), "res", name)
    # Flutter in-app logo (loadIcon prefers assets/icon.png, falls back to icon.svg)
    save_png(render(256), "flutter", "assets", "icon.png")
    with open(os.path.join(ROOT, "flutter", "assets", "icon.svg"), "w", encoding="utf-8", newline="\n") as f:
        f.write(svg())
    print("wrote flutter/assets/icon.svg")
    # Android launcher icons
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    res = ("flutter", "android", "app", "src", "main", "res")
    for d, k in dens.items():
        legacy = round(48 * k)
        save_png(render(legacy), *res, f"mipmap-{d}", "ic_launcher.png")
        save_png(render(legacy), *res, f"mipmap-{d}", "ic_launcher_round.png")
        # Adaptive foreground: 108dp canvas, glyph kept inside the 66dp safe zone.
        save_png(render(round(108 * k), background=False, scale=0.8), *res, f"mipmap-{d}", "ic_launcher_foreground.png")
        # Notification icon: white silhouette only.
        save_png(render(round(24 * k), background=False, white_only=True, scale=1.15), *res, f"mipmap-{d}", "ic_stat_logo.png")


if __name__ == "__main__":
    main()
