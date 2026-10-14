#!/usr/bin/env python3
"""Генерация иконок предметов, иконки приложения и Android-сплэша.
Запуск: python3 tools/gen_images.py (из корня проекта Godot)."""
import os
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "assets", "textures")
ICONS = os.path.join(TEX, "icons")
os.makedirs(ICONS, exist_ok=True)
TITLE_FONT = os.path.join(ROOT, "assets", "fonts", "RussoOne-Regular.ttf")
S = 128  # рисуем в 128 и уменьшаем до 64


def canvas():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def finish(img, name):
    img = img.resize((64, 64), Image.LANCZOS)
    img.save(os.path.join(ICONS, name + ".png"))


def outline_poly(d, pts, fill, w=5):
    d.polygon(pts, fill=fill, outline=(20, 20, 20, 255), width=w)


def log_icon(d):
    d.rounded_rectangle([14, 44, 112, 84], 18, fill=(150, 95, 50), outline=(40, 25, 10), width=5)
    d.ellipse([92, 44, 122, 84], fill=(220, 180, 120), outline=(40, 25, 10), width=5)
    d.ellipse([101, 56, 113, 72], outline=(150, 100, 60), width=3)
    d.rounded_rectangle([6, 76, 100, 112], 16, fill=(130, 80, 40), outline=(40, 25, 10), width=5)
    d.ellipse([84, 76, 114, 112], fill=(220, 180, 120), outline=(40, 25, 10), width=5)


def rock_icon(d, col=(140, 140, 150)):
    outline_poly(d, [(20, 96), (30, 52), (60, 30), (96, 40), (112, 78), (98, 104), (44, 108)], col)
    d.line([(60, 30), (64, 70), (98, 104)], fill=(90, 90, 100), width=4)
    d.line([(30, 52), (64, 70)], fill=(90, 90, 100), width=4)


def ingot_icon(d):
    outline_poly(d, [(16, 92), (34, 56), (106, 56), (116, 92)], (170, 180, 195))
    outline_poly(d, [(34, 56), (46, 40), (98, 40), (106, 56)], (210, 220, 235))


def scrap_icon(d):
    outline_poly(d, [(16, 100), (28, 60), (58, 70), (52, 104)], (130, 90, 60))
    d.ellipse([56, 30, 104, 78], fill=(150, 150, 160), outline=(30, 30, 30), width=5)
    d.ellipse([72, 46, 88, 62], fill=(60, 60, 70))
    outline_poly(d, [(60, 110), (70, 76), (112, 84), (106, 112)], (110, 110, 120))


def fabric_icon(d):
    outline_poly(d, [(20, 30), (108, 22), (100, 70), (112, 106), (24, 100), (32, 64)], (90, 140, 210))
    for y in (46, 66, 86):
        d.line([(30, y), (102, y - 6)], fill=(60, 100, 170), width=4)


def rope_icon(d):
    for i in range(3):
        r = 40 - i * 10
        d.ellipse([64 - r, 64 - r, 64 + r, 64 + r], outline=(200, 160, 90), width=9)
    d.line([(64, 64), (110, 112)], fill=(200, 160, 90), width=9)


def chip_icon(d):
    d.rounded_rectangle([28, 28, 100, 100], 8, fill=(40, 120, 70), outline=(15, 40, 20), width=5)
    for i in range(4):
        x = 38 + i * 16
        d.line([(x, 14), (x, 28)], fill=(220, 200, 90), width=5)
        d.line([(x, 100), (x, 114)], fill=(220, 200, 90), width=5)
        d.line([(14, x), (28, x)], fill=(220, 200, 90), width=5)
        d.line([(100, x), (114, x)], fill=(220, 200, 90), width=5)
    d.rectangle([48, 48, 80, 80], fill=(25, 25, 30))


def berries_icon(d):
    d.line([(64, 20), (64, 50)], fill=(60, 120, 40), width=5)
    outline_poly(d, [(64, 26), (96, 14), (88, 36)], (70, 160, 60), 3)
    for cx, cy in ((44, 64), (78, 60), (60, 92), (92, 92), (30, 96)):
        d.ellipse([cx - 17, cy - 17, cx + 17, cy + 17], fill=(200, 30, 60), outline=(60, 10, 20), width=4)
        d.ellipse([cx - 9, cy - 10, cx - 3, cy - 4], fill=(255, 200, 210))


def mushroom_icon(d):
    d.rounded_rectangle([50, 60, 78, 110], 10, fill=(240, 230, 210), outline=(40, 30, 20), width=5)
    d.pieslice([16, 20, 112, 100], 180, 360, fill=(200, 60, 40), outline=(40, 20, 10), width=5)
    for cx, cy in ((44, 44), (70, 34), (90, 50)):
        d.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=(255, 255, 255))


def meat_icon(d, cooked):
    col = (150, 75, 40) if cooked else (220, 80, 90)
    d.ellipse([18, 26, 96, 96], fill=col, outline=(50, 20, 10), width=5)
    d.ellipse([34, 42, 70, 74], fill=(240, 220, 200) if not cooked else (190, 120, 70))
    d.line([(84, 84), (112, 112)], fill=(240, 235, 220), width=12)
    d.ellipse([100, 100, 122, 122], fill=(240, 235, 220), outline=(60, 60, 60), width=3)


def bottle_icon(d, col):
    d.rounded_rectangle([50, 10, 78, 30], 4, fill=(60, 60, 200), outline=(20, 20, 20), width=4)
    d.rounded_rectangle([54, 26, 74, 44], 4, fill=(200, 230, 255), outline=(20, 20, 20), width=4)
    d.rounded_rectangle([34, 40, 94, 118], 18, fill=(210, 235, 255, 200), outline=(20, 20, 20), width=5)
    d.rounded_rectangle([40, 66, 88, 112], 14, fill=col)


def can_icon(d):
    d.rounded_rectangle([30, 28, 98, 108], 10, fill=(170, 170, 180), outline=(30, 30, 30), width=5)
    d.rectangle([32, 48, 96, 88], fill=(180, 40, 40))
    d.text((40, 54), "ТУШ", fill=(255, 230, 120), font=ImageFont.truetype(TITLE_FONT, 22))


def sandwich_icon(d):
    outline_poly(d, [(14, 76), (64, 40), (114, 76), (64, 104)], (230, 190, 120))
    d.line([(20, 70), (64, 44), (108, 70)], fill=(90, 180, 70), width=7)
    d.line([(22, 66), (64, 38), (106, 66)], fill=(220, 90, 80), width=6)
    outline_poly(d, [(14, 64), (64, 28), (114, 64), (64, 92)], (240, 200, 130))


def pryanik_icon(d):
    d.rounded_rectangle([18, 26, 110, 102], 26, fill=(160, 90, 40), outline=(60, 30, 10), width=5)
    d.rounded_rectangle([30, 38, 98, 90], 18, outline=(240, 220, 180), width=4)
    d.text((44, 46), "ТУЛА", fill=(250, 235, 200), font=ImageFont.truetype(TITLE_FONT, 18))


def tool_icon(d, head):
    d.line([(30, 110), (90, 30)], fill=(140, 90, 50), width=12)
    d.line([(30, 110), (90, 30)], fill=(40, 25, 10), width=2)
    if head == "axe":
        outline_poly(d, [(70, 22), (110, 28), (112, 64), (84, 50)], (150, 150, 160))
    elif head == "pick":
        outline_poly(d, [(50, 26), (90, 22), (118, 50), (92, 38), (60, 40)], (150, 150, 160))
    else:
        outline_poly(d, [(86, 34), (110, 10), (100, 46)], (170, 170, 180))
    d.line([(78, 44), (96, 32)], fill=(200, 160, 90), width=6)


def bandage_icon(d):
    d.rounded_rectangle([18, 40, 110, 88], 16, fill=(245, 245, 240), outline=(60, 60, 60), width=5)
    d.rectangle([56, 48, 72, 80], fill=(220, 40, 40))
    d.rectangle([48, 56, 80, 72], fill=(220, 40, 40))


def map_icon(d):
    outline_poly(d, [(14, 26), (48, 16), (80, 28), (114, 18), (114, 102), (80, 112), (48, 100), (14, 110)], (230, 210, 150))
    d.line([(48, 16), (48, 100)], fill=(150, 130, 90), width=3)
    d.line([(80, 28), (80, 112)], fill=(150, 130, 90), width=3)
    d.line([(24, 80), (46, 56), (70, 70), (98, 40)], fill=(200, 50, 40), width=5)
    d.line([(90, 32), (106, 48)], fill=(200, 50, 40), width=5)
    d.line([(106, 32), (90, 48)], fill=(200, 50, 40), width=5)


def antenna_icon(d):
    d.line([(64, 116), (64, 30)], fill=(170, 170, 180), width=8)
    for i, y in enumerate((40, 60, 80)):
        w = 40 - i * 8
        d.line([(64 - w, y), (64 + w, y)], fill=(170, 170, 180), width=6)
    d.ellipse([56, 18, 72, 34], fill=(230, 60, 60))


def lamp_icon(d):
    d.ellipse([34, 14, 94, 84], fill=(255, 200, 120, 220), outline=(40, 40, 40), width=5)
    d.line([(52, 50), (64, 34), (76, 50)], fill=(255, 120, 30), width=4)
    d.rectangle([44, 80, 84, 110], fill=(60, 60, 60), outline=(20, 20, 20), width=4)
    for x in (52, 64, 76):
        d.line([(x, 110), (x, 122)], fill=(200, 200, 200), width=4)


def coil_icon(d):
    d.rounded_rectangle([40, 14, 88, 114], 6, fill=(80, 60, 50), outline=(20, 20, 20), width=4)
    for y in range(24, 106, 10):
        d.line([(34, y), (94, y + 4)], fill=(210, 120, 50), width=6)


def ufo_part_icon(d):
    outline_poly(d, [(16, 70), (40, 40), (100, 34), (118, 60), (96, 96), (30, 100)], (170, 190, 200))
    d.text((40, 52), "ТЦК", fill=(220, 40, 40), font=ImageFont.truetype(TITLE_FONT, 24))
    d.line([(60, 96), (70, 116)], fill=(80, 255, 140), width=4)


def piece_icon(d, kind):
    wood = (170, 120, 70)
    if kind == "foundation":
        outline_poly(d, [(10, 80), (64, 56), (118, 80), (64, 104)], wood)
        outline_poly(d, [(10, 80), (64, 104), (64, 116), (10, 92)], (130, 90, 50))
        outline_poly(d, [(64, 104), (118, 80), (118, 92), (64, 116)], (110, 75, 40))
    elif kind == "wall":
        d.rectangle([20, 20, 108, 108], fill=wood, outline=(40, 25, 10), width=5)
        for y in (42, 64, 86):
            d.line([(20, y), (108, y)], fill=(120, 80, 40), width=4)
    elif kind == "roof":
        outline_poly(d, [(8, 84), (64, 24), (120, 84)], (160, 70, 50))
        d.rectangle([24, 84, 104, 108], fill=wood, outline=(40, 25, 10), width=5)
    elif kind == "door":
        d.rectangle([20, 14, 108, 114], fill=wood, outline=(40, 25, 10), width=5)
        d.rectangle([42, 40, 86, 114], fill=(110, 70, 35), outline=(40, 25, 10), width=4)
        d.ellipse([74, 76, 82, 84], fill=(230, 200, 80))
    elif kind == "window":
        d.rectangle([20, 14, 108, 114], fill=wood, outline=(40, 25, 10), width=5)
        d.rectangle([40, 34, 88, 82], fill=(170, 220, 255), outline=(40, 25, 10), width=5)
        d.line([(64, 34), (64, 82)], fill=(40, 25, 10), width=4)
    elif kind == "campfire":
        d.line([(24, 108), (104, 88)], fill=(120, 75, 40), width=12)
        d.line([(24, 88), (104, 108)], fill=(120, 75, 40), width=12)
        outline_poly(d, [(40, 96), (50, 54), (64, 18), (78, 54), (88, 96)], (255, 140, 30), 4)
        outline_poly(d, [(52, 96), (58, 70), (64, 48), (70, 70), (76, 96)], (255, 230, 90), 3)
    elif kind == "crate":
        d.rectangle([18, 30, 110, 110], fill=wood, outline=(40, 25, 10), width=5)
        d.line([(18, 30), (110, 110)], fill=(120, 80, 40), width=6)
        d.line([(110, 30), (18, 110)], fill=(120, 80, 40), width=6)
    elif kind == "bed":
        d.rectangle([10, 60, 118, 96], fill=(120, 80, 50), outline=(40, 25, 10), width=5)
        d.rectangle([18, 52, 112, 72], fill=(90, 130, 210), outline=(30, 40, 80), width=4)
        d.rounded_rectangle([14, 44, 44, 66], 8, fill=(245, 245, 245), outline=(80, 80, 80), width=3)
        d.line([(16, 96), (16, 112)], fill=(40, 25, 10), width=6)
        d.line([(112, 96), (112, 112)], fill=(40, 25, 10), width=6)
    elif kind == "workbench":
        d.rectangle([10, 46, 118, 62], fill=wood, outline=(40, 25, 10), width=5)
        d.line([(22, 62), (22, 112)], fill=(110, 70, 35), width=10)
        d.line([(106, 62), (106, 112)], fill=(110, 70, 35), width=10)
        d.line([(40, 44), (80, 18)], fill=(150, 150, 160), width=8)
    elif kind == "furnace":
        d.rounded_rectangle([20, 20, 108, 112], 14, fill=(130, 130, 140), outline=(30, 30, 30), width=5)
        d.rounded_rectangle([40, 60, 88, 100], 10, fill=(40, 20, 10))
        d.pieslice([46, 66, 82, 110], 180, 360, fill=(255, 120, 30))
    elif kind == "fence":
        for x in (24, 54, 84, 110):
            outline_poly(d, [(x - 10, 112), (x - 10, 36), (x, 22), (x + 10, 36), (x + 10, 112)], wood, 3)
        d.rectangle([8, 54, 120, 64], fill=(130, 90, 50))
        d.rectangle([8, 86, 120, 96], fill=(130, 90, 50))
    elif kind == "tower":
        d.line([(30, 118), (48, 40)], fill=(120, 80, 40), width=8)
        d.line([(98, 118), (80, 40)], fill=(120, 80, 40), width=8)
        d.line([(36, 90), (92, 90)], fill=(120, 80, 40), width=6)
        d.rectangle([30, 26, 98, 44], fill=wood, outline=(40, 25, 10), width=4)
        outline_poly(d, [(26, 26), (64, 6), (102, 26)], (160, 70, 50), 4)
    elif kind == "bunker":
        d.pieslice([10, 40, 118, 150], 180, 360, fill=(100, 110, 100), outline=(30, 30, 30), width=5)
        d.rectangle([48, 70, 80, 96], fill=(30, 30, 30))
        d.rectangle([8, 94, 120, 104], fill=(80, 70, 60))
    elif kind == "demolish":
        d.line([(24, 24), (104, 104)], fill=(230, 60, 60), width=16)
        d.line([(104, 24), (24, 104)], fill=(230, 60, 60), width=16)


ITEMS = {
    "wood": log_icon,
    "stone": lambda d: rock_icon(d),
    "metal": ingot_icon,
    "scrap": scrap_icon,
    "fabric": fabric_icon,
    "rope": rope_icon,
    "electronics": chip_icon,
    "berries": berries_icon,
    "mushroom": mushroom_icon,
    "meat_raw": lambda d: meat_icon(d, False),
    "meat_cooked": lambda d: meat_icon(d, True),
    "water_dirty": lambda d: bottle_icon(d, (120, 140, 90)),
    "water_clean": lambda d: bottle_icon(d, (90, 170, 255)),
    "canned": can_icon,
    "sandwich": sandwich_icon,
    "pryanik": pryanik_icon,
    "axe": lambda d: tool_icon(d, "axe"),
    "pickaxe": lambda d: tool_icon(d, "pick"),
    "spear": lambda d: tool_icon(d, "spear"),
    "bandage": bandage_icon,
    "map": map_icon,
    "antenna": antenna_icon,
    "radio_lamp": lamp_icon,
    "coil": coil_icon,
    "ufo_part": ufo_part_icon,
}
PIECES = ["foundation", "wall", "roof", "door", "window", "campfire", "crate", "bed", "workbench", "furnace", "fence", "tower", "bunker", "demolish"]


def make_icons():
    for name, fn in ITEMS.items():
        img = canvas()
        fn(ImageDraw.Draw(img))
        finish(img, name)
    for p in PIECES:
        img = canvas()
        piece_icon(ImageDraw.Draw(img), p)
        finish(img, "build_" + p)
    print("icons:", len(ITEMS) + len(PIECES))


def make_app_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = size / 192.0
    d.rounded_rectangle([0, 0, size - 1, size - 1], int(40 * k), fill=(255, 130, 30))
    face(d, size / 2, size * 0.56, size * 0.3)
    return img


def face(d, cx, cy, r):
    # Голова Котакбаса в шапке с кошачьими ушами
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(245, 205, 165), outline=(30, 20, 10), width=max(2, int(r * 0.06)))
    d.pieslice([cx - r * 1.05, cy - r * 1.15, cx + r * 1.05, cy + r * 0.5], 180, 360, fill=(40, 40, 50))
    d.polygon([(cx - r * 0.95, cy - r * 0.55), (cx - r * 0.8, cy - r * 1.45), (cx - r * 0.25, cy - r * 0.95)], fill=(40, 40, 50))
    d.polygon([(cx + r * 0.95, cy - r * 0.55), (cx + r * 0.8, cy - r * 1.45), (cx + r * 0.25, cy - r * 0.95)], fill=(40, 40, 50))
    d.polygon([(cx - r * 0.8, cy - r * 0.7), (cx - r * 0.74, cy - r * 1.2), (cx - r * 0.42, cy - r * 0.9)], fill=(255, 150, 170))
    d.polygon([(cx + r * 0.8, cy - r * 0.7), (cx + r * 0.74, cy - r * 1.2), (cx + r * 0.42, cy - r * 0.9)], fill=(255, 150, 170))
    for sx in (-1, 1):
        ex = cx + sx * r * 0.38
        d.ellipse([ex - r * 0.2, cy - r * 0.05, ex + r * 0.2, cy + r * 0.38], fill=(255, 255, 255), outline=(30, 20, 10), width=max(1, int(r * 0.04)))
        d.ellipse([ex - r * 0.08 + sx * r * 0.05, cy + r * 0.1, ex + r * 0.08 + sx * r * 0.05, cy + r * 0.28], fill=(20, 20, 20))
    d.arc([cx - r * 0.35, cy + r * 0.35, cx + r * 0.35, cy + r * 0.8], 20, 160, fill=(80, 20, 20), width=max(2, int(r * 0.07)))


def make_launcher():
    make_app_icon(192).save(os.path.join(TEX, "icon.png"))
    make_app_icon(192).save(os.path.join(TEX, "launcher_192.png"))
    fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    face(ImageDraw.Draw(fg), 216, 236, 105)
    fg.save(os.path.join(TEX, "launcher_fg_432.png"))
    bg = Image.new("RGBA", (432, 432), (255, 130, 30, 255))
    bg.save(os.path.join(TEX, "launcher_bg_432.png"))
    mono = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    md = ImageDraw.Draw(mono)
    md.ellipse([116, 136, 316, 336], fill=(255, 255, 255, 255))
    mono.save(os.path.join(TEX, "launcher_mono_432.png"))


def make_splash():
    # Сплэш Android согласован с заставкой студии: чёрный фон, тусклая надпись.
    w, h = 800, 220
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([150, 30, 650, 190], fill=(255, 120, 30, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(TITLE_FONT, 64)
    text = "Kotakbas Studio"
    tw = d.textlength(text, font=f)
    d.text(((w - tw) / 2, 70), text, font=f, fill=(90, 80, 70, 255))
    img.save(os.path.join(TEX, "boot_splash.png"))


if __name__ == "__main__":
    make_icons()
    make_launcher()
    make_splash()
