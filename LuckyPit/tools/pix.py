# -*- coding: utf-8 -*-
"""Tiny pixel-art toolkit used to author every Lucky Pit texture.

All drawing is aliased (no smoothing): shapes are rasterised on an integer
grid, then shaded with a fixed light direction (top-left) and outlined.
"""
from PIL import Image, ImageDraw

# ---------------------------------------------------------------- palette
P = {
    'clear': (0, 0, 0, 0),
    'black': (11, 7, 8), 'vdark': (24, 12, 14),
    'maroon0': (40, 10, 16), 'maroon1': (62, 16, 24), 'maroon2': (92, 24, 34),
    'red0': (126, 28, 36), 'red1': (176, 38, 44), 'red2': (222, 70, 58), 'red3': (250, 128, 104),
    'brown0': (34, 20, 14), 'brown1': (58, 36, 22), 'brown2': (86, 54, 32), 'brown3': (120, 78, 44),
    'gold0': (92, 62, 22), 'gold1': (150, 108, 40), 'gold2': (206, 160, 66), 'gold3': (240, 210, 130),
    'gold4': (255, 240, 196),
    'cream0': (170, 150, 116), 'cream1': (214, 196, 158), 'cream2': (240, 226, 192), 'white': (255, 248, 232),
    'gray0': (36, 32, 34), 'gray1': (68, 62, 64), 'gray2': (110, 102, 104), 'gray3': (160, 150, 150),
    'steel0': (48, 46, 52), 'steel1': (88, 86, 94), 'steel2': (140, 138, 146), 'steel3': (200, 198, 204),
    'green0': (18, 50, 26), 'green1': (34, 96, 40), 'green2': (70, 150, 60), 'green3': (140, 206, 96),
    'yellow0': (150, 120, 20), 'yellow1': (214, 182, 40), 'yellow2': (246, 222, 80), 'yellow3': (255, 246, 160),
    'blue0': (18, 26, 66), 'blue1': (34, 60, 130), 'blue2': (60, 110, 196), 'blue3': (130, 180, 240),
    'cyan0': (20, 70, 96), 'cyan1': (40, 140, 180), 'cyan2': (100, 210, 236), 'cyan3': (200, 246, 255),
    'purple0': (40, 16, 56), 'purple1': (86, 36, 112), 'purple2': (140, 70, 176), 'purple3': (200, 140, 230),
    'orange0': (120, 50, 14), 'orange1': (190, 92, 26), 'orange2': (240, 146, 50), 'orange3': (255, 200, 120),
    'pink1': (190, 70, 110), 'pink2': (236, 120, 156),
    'blood0': (70, 0, 8), 'blood1': (130, 6, 18), 'blood2': (190, 20, 30),
}

# colour ramps: dark -> light, used for shading
RAMP = {
    'red': ['blood0', 'red0', 'red1', 'red2', 'red3'],
    'gold': ['gold0', 'gold1', 'gold2', 'gold3', 'gold4'],
    'yellow': ['yellow0', 'yellow1', 'yellow2', 'yellow3', 'white'],
    'green': ['green0', 'green1', 'green2', 'green3', 'cream2'],
    'cyan': ['cyan0', 'cyan1', 'cyan2', 'cyan3', 'white'],
    'blue': ['blue0', 'blue1', 'blue2', 'blue3', 'cyan3'],
    'purple': ['purple0', 'purple1', 'purple2', 'purple3', 'white'],
    'steel': ['steel0', 'steel1', 'steel2', 'steel3', 'white'],
    'bone': ['cream0', 'cream0', 'cream1', 'cream2', 'white'],
    'brown': ['brown0', 'brown1', 'brown2', 'brown3', 'gold2'],
    'orange': ['orange0', 'orange1', 'orange2', 'orange3', 'gold4'],
    'maroon': ['maroon0', 'maroon1', 'maroon2', 'red0', 'red1'],
    'gray': ['gray0', 'gray1', 'gray2', 'gray3', 'cream1'],
    'pink': ['red0', 'pink1', 'pink2', 'red3', 'white'],
    'blood': ['black', 'blood0', 'blood1', 'blood2', 'red2'],
}


def col(c):
    if isinstance(c, str):
        c = P[c]
    if len(c) == 3:
        c = c + (255,)
    return c


class Pix:
    """An RGBA pixel canvas with helpers."""

    def __init__(self, w, h, bg='clear'):
        self.w, self.h = w, h
        self.img = Image.new('RGBA', (w, h), col(bg))
        self.px = self.img.load()

    # -- basic access
    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def set(self, x, y, c):
        if self.inside(x, y):
            self.px[x, y] = col(c)

    def get(self, x, y):
        if self.inside(x, y):
            return self.px[x, y]
        return (0, 0, 0, 0)

    def opaque(self, x, y):
        return self.inside(x, y) and self.px[x, y][3] > 0

    def rect(self, x, y, w, h, c):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.set(i, j, c)

    def frame(self, x, y, w, h, c):
        for i in range(x, x + w):
            self.set(i, y, c)
            self.set(i, y + h - 1, c)
        for j in range(y, y + h):
            self.set(x, j, c)
            self.set(x + w - 1, j, c)

    def hline(self, x0, x1, y, c):
        for i in range(min(x0, x1), max(x0, x1) + 1):
            self.set(i, y, c)

    def vline(self, x, y0, y1, c):
        for j in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, j, c)

    def line(self, x0, y0, x1, y1, c):
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def paste(self, other, x, y):
        for j in range(other.h):
            for i in range(other.w):
                p = other.px[i, j]
                if p[3] > 0:
                    self.set(x + i, y + j, p)

    def save(self, path):
        self.img.save(path, optimize=True)

    # -- masks
    def mask_new(self):
        return [[False] * self.w for _ in range(self.h)]

    def mask_from_draw(self, fn):
        """fn(draw) draws on an L image; returns boolean mask."""
        m = Image.new('L', (self.w, self.h), 0)
        d = ImageDraw.Draw(m)
        fn(d)
        mp = m.load()
        return [[mp[x, y] > 127 for x in range(self.w)] for y in range(self.h)]

    def mask_ellipse(self, cx, cy, rx, ry):
        mk = self.mask_new()
        for y in range(self.h):
            for x in range(self.w):
                dx = (x + 0.5 - cx) / rx
                dy = (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0:
                    mk[y][x] = True
        return mk

    def mask_poly(self, pts):
        return self.mask_from_draw(lambda d: d.polygon(pts, fill=255))

    @staticmethod
    def m_or(a, b):
        return [[a[y][x] or b[y][x] for x in range(len(a[0]))] for y in range(len(a))]

    @staticmethod
    def m_sub(a, b):
        return [[a[y][x] and not b[y][x] for x in range(len(a[0]))] for y in range(len(a))]

    @staticmethod
    def m_and(a, b):
        return [[a[y][x] and b[y][x] for x in range(len(a[0]))] for y in range(len(a))]

    def fill_mask(self, mk, c):
        for y in range(self.h):
            for x in range(self.w):
                if mk[y][x]:
                    self.set(x, y, c)

    def shade_mask(self, mk, ramp, light=(-1, -1), shine=True, base=2):
        """Fill mask with ramp-shaded colour: lit edge toward `light`."""
        r = [col(c) for c in RAMP[ramp]] if isinstance(ramp, str) else [col(c) for c in ramp]
        lx, ly = light
        h, w = self.h, self.w

        def m(x, y):
            return 0 <= x < w and 0 <= y < h and mk[y][x]
        for y in range(h):
            for x in range(w):
                if not mk[y][x]:
                    continue
                c = base
                if not m(x + lx, y + ly):
                    c = base + 1
                elif not m(x + 2 * lx, y + 2 * ly) and shine:
                    c = base + (1 if base + 1 < len(r) - 1 else 0)
                if not m(x - lx, y - ly):
                    c = base - 1
                elif not m(x - 2 * lx, y - 2 * ly):
                    c = max(base - 1, 0) if c == base else c
                c = max(0, min(len(r) - 1, c))
                self.set(x, y, r[c])
        return r

    def outline(self, c='black', diag=False):
        """Draw outline around all opaque pixels (outside)."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.opaque(x, y):
                    continue
                nb = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if diag:
                    nb += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
                for dx, dy in nb:
                    if self.opaque(x + dx, y + dy):
                        add.append((x, y))
                        break
        for x, y in add:
            self.set(x, y, c)

    def drop_shadow(self, c=(0, 0, 0, 110), dx=1, dy=1):
        src = [(x, y) for y in range(self.h) for x in range(self.w) if self.opaque(x, y)]
        sh = set((x + dx, y + dy) for x, y in src)
        for (x, y) in sh:
            if self.inside(x, y) and not self.opaque(x, y):
                self.px[x, y] = col(c)

    def recolor(self, mapping):
        for y in range(self.h):
            for x in range(self.w):
                p = self.px[x, y]
                for a, b in mapping.items():
                    if p[:3] == col(a)[:3] and p[3] > 0:
                        self.px[x, y] = col(b)

    def scaled(self, k):
        out = Pix(self.w * k, self.h * k)
        out.img = self.img.resize((self.w * k, self.h * k), Image.NEAREST)
        out.px = out.img.load()
        return out

    def flip_h(self):
        out = Pix(self.w, self.h)
        out.img = self.img.transpose(Image.FLIP_LEFT_RIGHT)
        out.px = out.img.load()
        return out


def dither(p, x0, y0, w, h, c1, c2, pattern='checker'):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            if pattern == 'checker':
                use2 = (x + y) % 2 == 0
            elif pattern == 'sparse':
                use2 = (x % 2 == 0 and y % 2 == 0)
            elif pattern == 'lines':
                use2 = y % 2 == 0
            else:
                use2 = False
            p.set(x, y, c2 if use2 else c1)


def vgrad(p, x0, y0, w, h, ramp_names):
    """Vertical banded gradient with ordered dither between bands."""
    n = len(ramp_names)
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(h):
        t = y * (n - 1) / max(1, h - 1)
        i = int(t)
        f = t - i
        for x in range(w):
            k = i
            if i < n - 1 and f * 16 > bayer[y % 4][x % 4]:
                k = i + 1
            p.set(x0 + x, y0 + y, ramp_names[k])
