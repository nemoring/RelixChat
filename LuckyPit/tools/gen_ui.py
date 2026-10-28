# -*- coding: utf-8 -*-
"""Backgrounds, machine body and UI sprites for 240x320."""
import math
import random
from pix import Pix, P, col, vgrad, RAMP
import motifs as M

W, H = 240, 320
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

# ------------------------------------------------------------ big letters
BIG = {
    'L': ['##...', '##...', '##...', '##...', '##...', '##...', '#####', '#####'],
    'U': ['##.##', '##.##', '##.##', '##.##', '##.##', '##.##', '#####', '.###.'],
    'C': ['.####', '#####', '##...', '##...', '##...', '##...', '#####', '.####'],
    'K': ['##.##', '##.##', '####.', '###..', '###..', '####.', '##.##', '##.##'],
    'Y': ['##.##', '##.##', '##.##', '.###.', '..#..', '..#..', '.###.', '.###.'],
    'P': ['####.', '#####', '##.##', '##.##', '#####', '####.', '##...', '##...'],
    'I': ['####', '.##.', '.##.', '.##.', '.##.', '.##.', '.##.', '####'],
    'T': ['#####', '#####', '.###.', '.###.', '.###.', '.###.', '.###.', '.###.'],
    ' ': ['..', '..', '..', '..', '..', '..', '..', '..'],
}


def big_text(p, text, x, y, scale, ramp='gold', outline='black', shadow=True):
    """Chunky gradient letters with outline, drawn into p."""
    tmp = Pix(len(text) * 6 * scale + 8, 8 * scale + 8)
    cx = 2
    for ch in text:
        g = BIG[ch]
        for j, row in enumerate(g):
            for i, c in enumerate(row):
                if c == '#':
                    band = j * 5 // 8
                    shade = RAMP[ramp][4 - min(3, band)] if j < 7 else RAMP[ramp][1]
                    if j == 0:
                        shade = RAMP[ramp][4]
                    tmp.rect(cx + i * scale, 2 + j * scale, scale, scale, shade)
        cx += (len(g[0]) + 1) * scale
    tmp.outline(outline)
    if shadow:
        tmp.drop_shadow((0, 0, 0, 255), 1, 2)
    p.paste(tmp, x - 2, y - 2)
    return cx


def wallpaper(p, x0, y0, w, h, base='maroon1', dark='maroon0', light='maroon2'):
    """Damask casino wallpaper with vertical pinstripes."""
    tile = [
        '................',
        '.......##.......',
        '......#..#......',
        '.....#.##.#.....',
        '....#.#..#.#....',
        '...#..#..#..#...',
        '..#...#..#...#..',
        '.#.##..##..##.#.',
        '..#...#..#...#..',
        '...#..#..#..#...',
        '....#.#..#.#....',
        '.....#.##.#.....',
        '......#..#......',
        '.......##.......',
        '................',
        '................',
    ]
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            c = base
            tx, ty = (x - x0) % 16, (y - y0) % 16
            if tile[ty][tx] == '#':
                c = dark
            if (x - x0) % 16 == 0:
                c = light if y % 2 == 0 else dark
            p.set(x, y, c)


def vignette(p, x0, y0, w, h, strength=1.0, dark='black'):
    cx, cy = x0 + w / 2, y0 + h / 2
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            dx = (x - cx) / (w / 2)
            dy = (y - cy) / (h / 2)
            d = (dx * dx + dy * dy) ** 0.5 * strength
            lvl = int((d - 0.78) * 16 * 2.0)
            if lvl > BAYER[y % 4][x % 4]:
                p.set(x, y, dark)


def bevel(p, x, y, w, h, light, dark):
    p.hline(x, x + w - 1, y, light)
    p.vline(x, y, y + h - 1, light)
    p.hline(x, x + w - 1, y + h - 1, dark)
    p.vline(x + w - 1, y, y + h - 1, dark)


def gold_frame(p, x, y, w, h, thick=3):
    ramp = ['gold0', 'gold1', 'gold2', 'gold3']
    p.frame(x, y, w, h, 'black')
    for t in range(1, thick + 1):
        c = ramp[min(3, t)]
        bevel(p, x + t, y + t, w - 2 * t, h - 2 * t, ramp[3] if t == 1 else c, ramp[0] if t == 1 else ramp[1])
    p.frame(x + thick + 1, y + thick + 1, w - 2 * thick - 2, h - 2 * thick - 2, 'black')


def steel_frame(p, x, y, w, h):
    p.frame(x, y, w, h, 'black')
    bevel(p, x + 1, y + 1, w - 2, h - 2, 'steel3', 'steel0')
    bevel(p, x + 2, y + 2, w - 4, h - 4, 'steel2', 'steel1')
    p.frame(x + 3, y + 3, w - 6, h - 6, 'black')


def rivet(p, x, y):
    p.set(x, y, 'gold3'); p.set(x + 1, y, 'gold2'); p.set(x, y + 1, 'gold2'); p.set(x + 1, y + 1, 'gold0')


def softbar(p):
    for y in range(304, 320):
        for x in range(W):
            p.set(x, y, 'black' if (y > 306 or (x + y) % 2) else 'vdark')
    p.hline(0, W - 1, 303, 'gold1')
    p.hline(0, W - 1, 302, 'gold0')


def plank(p, x0, y0, w, h, ramp=('brown0', 'brown1', 'brown2', 'brown3')):
    rnd = random.Random(x0 * 31 + y0)
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            n = (math.sin((x + rnd.random() * 0.3) * 0.31 + y * 0.9) + math.sin(x * 0.07 + y * 2.1)) * 0.5
            c = ramp[1] if n < 0.2 else ramp[2]
            if n > 0.75:
                c = ramp[3]
            if n < -0.7:
                c = ramp[0]
            p.set(x, y, c)
    p.hline(x0, x0 + w - 1, y0, ramp[3])
    p.hline(x0, x0 + w - 1, y0 + h - 1, ramp[0])


# ------------------------------------------------------------ machine bg
REEL_X = [36, 86, 136]
REEL_Y = 64
REEL_W = 46
CELL_H = 42


def bg_game():
    p = Pix(W, H, 'black')
    wallpaper(p, 0, 0, W, H)
    vignette(p, 0, 0, W, H, 1.1)
    # ---- HUD plate
    for y in range(0, 30):
        for x in range(W):
            p.set(x, y, 'brown0' if (y < 28) else 'black')
    plank(p, 0, 0, W, 28, ('vdark', 'brown0', 'brown1', 'brown2'))
    p.hline(0, W - 1, 28, 'gold2'); p.hline(0, W - 1, 29, 'gold0')
    for x in (3, 233):
        rivet(p, x, 4); rivet(p, x, 21)
    # dark insets for numbers
    for (x, w) in ((4, 76), (82, 52), (136, 100)):
        p.rect(x, 3, w, 12, 'black')
        p.frame(x - 1, 2, w + 2, 14, 'brown0')
        p.hline(x, x + w - 1, 15, 'brown2')
    # ---- cabinet body
    bx, by, bw, bh = 6, 33, 208, 207
    # shadow
    p.rect(bx + 3, by + 3, bw, bh, (8, 4, 6))
    for y in range(by, by + bh):
        for x in range(bx, bx + bw):
            t = (x - bx) / bw
            c = 'red0'
            if t < 0.06: c = 'red1'
            elif t > 0.9: c = 'maroon2'
            if (x - bx) % 6 == 0 and 0.06 < t < 0.9 and (y % 3 == 0):
                c = 'maroon2'
            p.set(x, y, c)
    gold_frame(p, bx, by, bw, bh, 3)
    # corner cuts
    for (cx, cy) in ((bx, by), (bx + bw - 1, by), (bx, by + bh - 1), (bx + bw - 1, by + bh - 1)):
        p.set(cx, cy, (8, 4, 6))
    # ---- marquee
    mx, my, mw, mh = 16, 38, 188, 22
    p.rect(mx, my, mw, mh, 'black')
    gold_frame(p, mx - 2, my - 2, mw + 4, mh + 4, 2)
    for y in range(my, my + mh):
        for x in range(mx, mx + mw):
            if (x + y) % 2 == 0 and y < my + mh // 2:
                p.set(x, y, 'vdark')
    big_text(p, 'LUCKY PIT', 48, 42, 2, 'gold')
    # lamp sockets above/below marquee
    for i in range(12):
        x = 22 + i * 16
        p.rect(x, 33, 6, 3, 'gold0')
    # ---- reel window
    wx0, wy0 = 28, 60
    ww, wh = 166, CELL_H * 3 + 8
    steel_frame(p, wx0, wy0, ww, wh)
    # window back and reel strips (cylinder shading)
    p.rect(wx0 + 4, wy0 + 4, ww - 8, wh - 8, 'black')
    for rx in REEL_X:
        for y in range(REEL_Y, REEL_Y + CELL_H * 3):
            t = (y - REEL_Y) / (CELL_H * 3)
            d = abs(t - 0.5) * 2  # 0 center .. 1 edge
            for x in range(rx, rx + REEL_W):
                lv = d * 16
                c = 'cream2'
                if lv > 9 + BAYER[y % 4][x % 4] * 0.4: c = 'cream1'
                if lv > 13 + BAYER[y % 4][x % 4] * 0.2: c = 'cream0'
                if d > 0.93: c = 'gray2'
                if x == rx or x == rx + REEL_W - 1:
                    c = 'cream0' if d < 0.9 else 'gray1'
                p.set(x, y, c)
    # separators between reels
    for sx in (REEL_X[1] - 4, REEL_X[2] - 4):
        for y in range(REEL_Y, REEL_Y + CELL_H * 3):
            p.hline(sx, sx + 3, y, 'steel1')
            p.set(sx + 1, y, 'steel2')
            p.set(sx + 3, y, 'steel0')
    # payline tabs
    for i, y in enumerate((REEL_Y + 21, REEL_Y + 63, REEL_Y + 105)):
        for side, x in ((0, 18), (1, 196)):
            p.rect(x, y - 5, 10, 11, 'black')
            p.rect(x + 1, y - 4, 8, 9, 'gold1')
            p.hline(x + 1, x + 8, y - 4, 'gold3')
            p.hline(x + 1, x + 8, y + 4, 'gold0')
    # ---- control panel
    cy0 = 196
    p.rect(14, cy0, 192, 38, 'black')
    for y in range(cy0 + 1, cy0 + 37):
        for x in range(15, 205):
            p.set(x, y, 'gray0' if (x // 2 + y) % 3 else 'gray1')
    bevel(p, 14, cy0, 192, 38, 'steel2', 'steel0')
    # LCD
    p.rect(36, cy0 + 4, 148, 18, 'black')
    for y in range(cy0 + 5, cy0 + 21):
        for x in range(37, 183):
            p.set(x, y, (20, 30, 14) if (x + y) % 2 else (16, 24, 12))
    bevel(p, 35, cy0 + 3, 150, 20, 'gray0', 'steel2')
    # buttons
    for i, (x, rp) in enumerate(((40, 'red'), (78, 'gold'), (116, 'gold'), (154, 'green'))):
        p.rect(x - 1, cy0 + 25, 28, 10, 'black')
        for y in range(cy0 + 26, cy0 + 34):
            for xx in range(x, x + 26):
                lv = 3 if y < cy0 + 28 else (2 if y < cy0 + 32 else 1)
                p.set(xx, y, RAMP[rp][lv])
    # coin slot
    p.rect(22, cy0 + 8, 8, 12, 'black'); p.vline(25, cy0 + 10, cy0 + 17, 'steel2')
    p.rect(190, cy0 + 8, 8, 12, 'black'); p.vline(193, cy0 + 10, cy0 + 17, 'steel2')
    # ---- lever mount
    lx = 214
    p.rect(lx, 128, 22, 34, 'black')
    for y in range(129, 161):
        for x in range(lx + 1, lx + 21):
            p.set(x, y, RAMP['steel'][3 if x < lx + 4 else (1 if x > lx + 17 else 2)])
    rivet(p, lx + 3, 132); rivet(p, lx + 3, 155); rivet(p, lx + 16, 132); rivet(p, lx + 16, 155)
    p.rect(lx + 8, 136, 6, 18, 'black')
    # ---- card shelf
    sy = 244
    p.rect(0, sy - 2, W, 58, 'black')
    for y in range(sy, sy + 54):
        for x in range(W):
            p.set(x, y, 'green0' if (x + y) % 2 else (14, 40, 20))
    plank(p, 0, sy - 3, W, 4)
    plank(p, 0, sy + 52, W, 6)
    for i in range(8):
        x = 4 + i * 29
        p.rect(x, sy + 6, 28, 28, (8, 26, 12))
        p.frame(x, sy + 6, 28, 28, 'black')
    softbar(p)
    return p


def lever_frames():
    """4 frames of the lever arm (24x110): 0 = up, 3 = fully pulled."""
    out = Pix(24 * 4, 110)
    for f in range(4):
        ox = f * 24
        top = 6 + f * 26  # knob y
        pivot = 145 - 64  # local pivot at y ~ 81 (screen 145)
        # arm from pivot to knob
        for y in range(min(top + 6, pivot), pivot + 1):
            for x in range(ox + 10, ox + 14):
                p_c = 'steel3' if x == ox + 10 else ('steel2' if x < ox + 13 else 'steel0')
                out.set(x, y, p_c)
        if top + 6 > pivot:
            # pulled below pivot
            for y in range(pivot, top + 6):
                for x in range(ox + 10, ox + 14):
                    out.set(x, y, 'steel2')
        ball = M.circ
        tmp = Pix(16, 16)
        mk = tmp.mask_ellipse(8, 8, 7, 7)
        tmp.shade_mask(mk, 'red')
        tmp.set(5, 4, 'white'); tmp.set(6, 4, 'red3'); tmp.set(5, 5, 'red3')
        tmp.outline('black')
        out.paste(tmp, ox + 4, top - 4)
        out.outline('black') if False else None
    # outline arms
    o2 = Pix(out.w, out.h)
    o2.paste(out, 0, 0)
    o2.outline('black')
    return o2


# ------------------------------------------------------------ menu bg
def curtain(p, x0, w, flip=False):
    for x in range(x0, x0 + w):
        lx = (x - x0) if not flip else (x0 + w - 1 - x)
        phase = (lx % 12) / 12.0
        v = math.sin(phase * math.pi * 2)
        for y in range(0, H):
            sway = math.sin(y * 0.02 + lx * 0.1) * 0.3
            vv = v + sway
            c = 'red0'
            if vv > 0.5: c = 'red1'
            if vv > 0.85: c = 'red2'
            if vv < -0.4: c = 'maroon2'
            if vv < -0.8: c = 'maroon1'
            p.set(x, y, c)
    # tie-back
    tx = x0 + (w - 14 if not flip else 0)


def bg_menu():
    p = Pix(W, H, 'black')
    # back wall gradient with spotlight
    for y in range(H):
        for x in range(W):
            dx, dy = (x - 120) / 120, (y - 150) / 170
            d = (dx * dx + dy * dy) ** 0.5
            lvl = int(d * 16 * 1.6)
            c = 'maroon1'
            if lvl > 8 + BAYER[y % 4][x % 4] * 0.5: c = 'maroon0'
            if lvl > 16 + BAYER[y % 4][x % 4] * 0.5: c = 'vdark'
            if lvl > 24 + BAYER[y % 4][x % 4]: c = 'black'
            p.set(x, y, c)
    # spotlight cone
    for y in range(0, 250):
        half = 12 + y * 0.42
        for x in range(int(120 - half), int(120 + half)):
            if 0 <= x < W and (x + y) % 2 == 0:
                q = p.get(x, y)
                if q[:3] == P['maroon0']: p.set(x, y, 'maroon1')
                elif q[:3] == P['vdark']: p.set(x, y, 'maroon0')
    # floor (checker in perspective)
    for y in range(250, H):
        t = (y - 250) / 70
        for x in range(W):
            u = (x - 120) / (1 + t * 3)
            cell = (int(u / 8) + int((y - 250) / (3 + t * 6))) % 2
            c = 'gray0' if cell else 'black'
            if (x + y) % 2 and cell: c = 'gray1' if t > 0.5 else 'gray0'
            p.set(x, y, c)
    p.hline(0, W - 1, 250, 'gold0')
    # curtains
    curtain(p, 0, 34)
    curtain(p, W - 34, 34, True)
    # valance top
    for x in range(W):
        for y in range(0, 16 + int(3 * math.sin(x * 0.26))):
            c = 'red1' if y < 4 else ('red0' if (x // 3) % 2 else 'maroon2')
            p.set(x, y, c)
        p.set(x, 16 + int(3 * math.sin(x * 0.26)), 'gold2')
        p.set(x, 17 + int(3 * math.sin(x * 0.26)), 'gold0')
    for x in range(4, W, 12):
        yb = 18 + int(3 * math.sin(x * 0.26))
        p.vline(x, yb, yb + 4, 'gold2'); p.set(x, yb + 5, 'gold3')
    # marquee lights border around center stage
    # logo plaque
    big_text(p, 'LUCKY', 56, 34, 4, 'gold')
    big_text(p, 'PIT', 88, 72, 4, 'red')
    # small slot machine silhouette glow at stage
    for i, sx in enumerate((70, 106, 142)):
        pass
    vignette(p, 0, 0, W, H, 0.9)
    softbar(p)
    return p


# ------------------------------------------------------------ room bg
def bg_room():
    p = Pix(W, H, 'black')
    wallpaper(p, 0, 0, W, H, 'maroon0', 'vdark', 'maroon1')
    vignette(p, 0, 0, W, H, 1.0)
    # header ribbon area
    p.rect(0, 0, W, 24, 'black')
    for x in range(W):
        for y in range(1, 22):
            p.set(x, y, 'brown0' if (x + y) % 2 else 'vdark')
    p.hline(0, W - 1, 22, 'gold2'); p.hline(0, W - 1, 23, 'gold0')
    p.hline(0, W - 1, 0, 'gold0')
    # central panel
    x, y, w, h = 4, 28, 232, 272
    p.rect(x, y, w, h, (16, 8, 10))
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if (xx + yy) % 2 == 0:
                p.set(xx, yy, (22, 11, 13))
    gold_frame(p, x - 2, y - 2, w + 4, h + 4, 2)
    for (cx, cy) in ((x, y), (x + w - 2, y), (x, y + h - 2), (x + w - 2, y + h - 2)):
        rivet(p, cx, cy)
    softbar(p)
    return p


def bg_shop():
    p = Pix(W, H, 'black')
    # wood panelling
    for i in range(0, H, 20):
        plank(p, 0, i, W, 20, ('vdark', 'brown0', 'brown1', 'brown2'))
    for x in range(0, W, 40):
        p.vline(x, 0, H, 'black')
        p.vline(x + 1, 0, H, 'brown2')
    vignette(p, 0, 0, W, H, 1.0)
    # header
    p.rect(0, 0, W, 24, 'black')
    for x in range(W):
        for y in range(1, 22):
            p.set(x, y, 'green0' if (x + y) % 2 else 'black')
    p.hline(0, W - 1, 22, 'gold2'); p.hline(0, W - 1, 23, 'gold0')
    # felt table for cards
    x, y, w, h = 4, 46, 232, 140
    p.rect(x, y, w, h, 'green0')
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if (xx * 3 + yy * 5) % 7 == 0:
                p.set(xx, yy, (14, 40, 20))
            if (xx + yy) % 2 == 0 and (yy < y + 6 or yy > y + h - 7 or xx < x + 6 or xx > x + w - 7):
                p.set(xx, yy, 'black')
    gold_frame(p, x - 2, y - 2, w + 4, h + 4, 2)
    # info panel
    x, y, w, h = 4, 192, 232, 108
    p.rect(x, y, w, h, (16, 8, 10))
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if (xx + yy) % 2 == 0:
                p.set(xx, yy, (22, 11, 13))
    gold_frame(p, x - 2, y - 2, w + 4, h + 4, 2)
    softbar(p)
    return p


def bg_lose():
    p = Pix(W, H, 'black')
    rnd = random.Random(5)
    cx, cy = 120, 210
    for y in range(H):
        for x in range(W):
            dx, dy = (x - cx) / 130.0, (y - cy) / 70.0
            d = (dx * dx + dy * dy) ** 0.5
            ring = int(d * 9)
            c = ['black', 'black', 'blood0', 'blood0', 'blood1', 'blood0', 'maroon0', 'vdark', 'black', 'black'][min(9, ring)]
            if (x + y) % 2 and ring in (3, 5):
                c = 'blood1' if ring == 3 else 'maroon0'
            if d < 0.22:
                c = 'black'
            p.set(x, y, c)
    # glow streaks rising
    for i in range(40):
        x = rnd.randint(30, 210)
        y0 = rnd.randint(120, 260)
        for k in range(rnd.randint(4, 12)):
            p.set(x, y0 - k * 2, 'red1' if k < 3 else 'blood1')
    # chains from top
    for x in (30, 210):
        for y in range(0, 140, 6):
            p.frame(x - 2, y, 5, 7, 'steel1')
            p.set(x, y + 3, 'black')
    # skulls around the rim
    for (x, y) in ((40, 230), (180, 236), (90, 270), (150, 262), (60, 180)):
        s = M.m_skull(12)
        p.paste(s, x, y)
    vignette(p, 0, 0, W, H, 1.0)
    softbar(p)
    return p


def bg_win():
    p = Pix(W, H, 'black')
    cx, cy = 120, 120
    for y in range(H):
        for x in range(W):
            a = math.atan2(y - cy, x - cx)
            ray = int((a + math.pi) / (2 * math.pi) * 24) % 2
            dx, dy = (x - cx) / 160, (y - cy) / 160
            d = (dx * dx + dy * dy) ** 0.5
            base = 'gold0' if ray else 'brown0'
            if d < 0.35:
                base = 'gold1' if ray else 'gold0'
            if d < 0.18:
                base = 'gold2'
            if d > 0.9 and (x + y) % 2:
                base = 'vdark'
            p.set(x, y, base)
    # coin pile at bottom
    rnd = random.Random(9)
    coin = M.m_coin(12)
    for i in range(70):
        x = rnd.randint(-6, 234)
        y = 300 - int(36 * math.exp(-((x - 120) / 70.0) ** 2)) + rnd.randint(-4, 18)
        p.paste(coin, x, y)
    vignette(p, 0, 0, W, H, 0.8)
    softbar(p)
    return p


# ------------------------------------------------------------ sprites
def icons():
    """12x12 icons: coin, token, debt, spin, card, lock, star, clock, check, cross, arrowL, arrowR, skull, bell."""
    names = []
    out = Pix(12 * 14, 12)

    def put(i, pp):
        out.paste(pp, i * 12, 0)
    put(0, M.m_coin(12))
    t = Pix(12, 12)
    M.poly(t, [(.5, .02), (.95, .5), (.5, .98), (.05, .5)], 'cyan')
    M.poly(t, [(.5, .25), (.72, .5), (.5, .75), (.28, .5)], 'blue', base=3)
    t.outline('black'); put(1, t)
    put(2, M.m_contract(12))
    s = Pix(12, 12)
    M.ring(s, .5, .5, .46, .22, 'gold')
    M.poly(s, [(.62, .0), (.98, .18), (.62, .38)], 'gold')
    s.outline('black'); put(3, s)
    put(4, M.m_card(12))
    put(5, M.m_lock(12))
    put(6, M.m_star(12))
    put(7, M.m_clock(12))
    c = Pix(12, 12)
    for (x, y) in ((1, 6), (2, 7), (3, 8), (4, 9), (5, 8), (6, 7), (7, 6), (8, 5), (9, 4), (10, 3)):
        c.rect(x, y, 2, 2, 'green3')
    c.outline('black'); put(8, c)
    x_ = Pix(12, 12)
    for i in range(2, 10):
        x_.rect(i, i, 2, 2, 'red2'); x_.rect(11 - i - 1, i, 2, 2, 'red2')
    x_.outline('black'); put(9, x_)
    a = Pix(12, 12)
    M.poly(a, [(.75, .1), (.75, .9), (.2, .5)], 'gold'); a.outline('black'); put(10, a)
    put(11, a.flip_h())
    put(12, M.m_skull(12))
    put(13, M.m_bell(12))
    return out


def coin_anim():
    """6 frames 8x8 spinning coin."""
    out = Pix(8 * 6, 8)
    widths = [4, 3, 2, 1, 2, 3]
    for f, wd in enumerate(widths):
        t = Pix(8, 8)
        mk = t.mask_ellipse(4, 4, max(0.6, wd), 3.6)
        t.shade_mask(mk, 'gold')
        t.outline('gold0')
        out.paste(t, f * 8, 0)
    return out


def lamps():
    """Lamp bulbs 6x6: gold off/on, red off/on, white flash."""
    out = Pix(6 * 5, 6)
    specs = [('gold0', 'gold1', None), ('gold2', 'gold4', 'white'), ('blood0', 'red0', None),
             ('red1', 'red3', 'white'), ('cream1', 'white', 'white')]
    for i, (a, b, hl) in enumerate(specs):
        t = Pix(6, 6)
        mk = t.mask_ellipse(3, 3, 2.9, 2.9)
        t.fill_mask(mk, a)
        mk2 = t.mask_ellipse(2.6, 2.6, 1.6, 1.6)
        t.fill_mask(mk2, b)
        if hl:
            t.set(2, 2, hl)
        out.paste(t, i * 6, 0)
    return out


def buttons():
    """Menu button 168x20: normal and selected stacked."""
    out = Pix(168, 40)
    for k in range(2):
        y0 = k * 20
        out.rect(0, y0, 168, 20, 'black')
        for y in range(y0 + 1, y0 + 19):
            for x in range(1, 167):
                t = (y - y0) / 20
                if k == 0:
                    c = 'brown1' if t < 0.5 else 'brown0'
                    if (x + y) % 2 and t > 0.5: c = 'vdark'
                else:
                    c = 'red1' if t < 0.45 else 'red0'
                    if t < 0.15: c = 'red2'
                    if (x + y) % 2 and t > 0.6: c = 'maroon2'
                out.set(x, y, c)
        fr = ('gold1', 'gold0') if k == 0 else ('gold4', 'gold2')
        bevel(out, 1, y0 + 1, 166, 18, fr[0], fr[1])
        for (x, y) in ((0, y0), (167, y0), (0, y0 + 19), (167, y0 + 19)):
            out.set(x, y, (0, 0, 0, 0))
        # side gems
        for x in (5, 159):
            gem = Pix(5, 5)
            mk = gem.mask_poly([(2.5, 0), (5, 2.5), (2.5, 5), (0, 2.5)])
            gem.shade_mask(mk, 'cyan' if k else 'gold')
            out.paste(gem, x, y0 + 7)
    return out


def panel():
    """9-slice dialog panel 24x24 (corners 8)."""
    p = Pix(24, 24)
    p.rect(0, 0, 24, 24, (20, 10, 12))
    for y in range(24):
        for x in range(24):
            if (x + y) % 2 == 0:
                p.set(x, y, (28, 14, 16))
    gold_frame(p, 0, 0, 24, 24, 2)
    rivet(p, 3, 3); rivet(p, 19, 3); rivet(p, 3, 19); rivet(p, 19, 19)
    return p


def banner():
    """Heading ribbon 200x18."""
    p = Pix(200, 18)
    for y in range(18):
        for x in range(200):
            inset = 0
            if x < 8:
                inset = abs(9 - y) * 8 // 9 > x
            elif x > 191:
                inset = abs(9 - y) * 8 // 9 > 199 - x
            if inset:
                continue
            c = 'red1' if y < 6 else ('red0' if y < 13 else 'maroon2')
            if y == 1: c = 'red2'
            p.set(x, y, c)
    p.hline(10, 189, 0, 'gold3'); p.hline(10, 189, 17, 'gold0')
    p.outline('black')
    return p


def glint():
    """Glass glare: diagonal translucent streaks, 40x134."""
    p = Pix(40, 134)
    for y in range(134):
        for x in range(40):
            u = x + y * 0.35
            if 6 < u % 60 < 12:
                p.px[x, y] = (255, 255, 255, 46)
            elif 15 < u % 60 < 17:
                p.px[x, y] = (255, 255, 255, 30)
    return p


def frames_extra():
    """Empty slot and locked slot 28x28 plus selection cursor 32x32."""
    out = Pix(28 * 2, 28)
    out.frame(0, 0, 28, 28, 'black')
    out.frame(1, 1, 26, 26, 'green1')
    for y in range(2, 26):
        for x in range(2, 26):
            out.set(x, y, 'green0' if (x + y) % 2 else (12, 34, 18))
    out.frame(28, 0, 28, 28, 'black')
    for y in range(1, 27):
        for x in range(29, 55):
            out.set(x, y, 'gray0' if (x + y) % 2 else 'vdark')
    lk = M.m_lock(14)
    out.paste(lk, 35, 7)
    cur = Pix(32, 32)
    for i in range(8):
        for (x, y) in ((i, 0), (0, i), (31 - i, 0), (31, i), (i, 31), (0, 31 - i), (31 - i, 31), (31, 31 - i)):
            cur.set(x, y, 'gold4')
            cur.set(x + (1 if x == 0 else (-1 if x == 31 else 0)), y + (1 if y == 0 else (-1 if y == 31 else 0)), 'gold2')
    return out, cur


def app_icon():
    p = Pix(46, 46)
    for y in range(46):
        for x in range(46):
            dx, dy = x - 22.5, y - 22.5
            r = (dx * dx + dy * dy) ** 0.5
            if r < 22:
                c = 'red0' if r > 18 else ('maroon1' if (x + y) % 2 else 'maroon2')
                if 18 <= r < 19.5:
                    c = 'gold2'
                p.set(x, y, c)
    s = M.m_seven(30, 'red')
    p.paste(s, 8, 6)
    c = M.m_clover(14)
    p.paste(c, 28, 28)
    p.outline('black')
    return p


def build(outdir):
    app_icon().save(outdir + '/icon.png')
    bg_game().save(outdir + '/bg_game.png')
    bg_menu().save(outdir + '/bg_menu.png')
    bg_room().save(outdir + '/bg_room.png')
    bg_shop().save(outdir + '/bg_shop.png')
    bg_lose().save(outdir + '/bg_lose.png')
    bg_win().save(outdir + '/bg_win.png')
    lever_frames().save(outdir + '/lever.png')
    icons().save(outdir + '/icons.png')
    coin_anim().save(outdir + '/coin.png')
    lamps().save(outdir + '/lamps.png')
    buttons().save(outdir + '/button.png')
    panel().save(outdir + '/panel.png')
    banner().save(outdir + '/banner.png')
    glint().save(outdir + '/glint.png')
    fx, cur = frames_extra()
    fx.save(outdir + '/slots.png')
    cur.save(outdir + '/cursor.png')


if __name__ == '__main__':
    import sys
    build(sys.argv[1] if len(sys.argv) > 1 else '.')
