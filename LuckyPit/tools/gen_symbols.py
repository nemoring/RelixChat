# -*- coding: utf-8 -*-
"""Reel symbol textures (36x36), plus a motion-blurred strip for fast spin."""
import math
from pix import Pix, P, col

S = 36


def _finish(p, outline='black'):
    p.outline(outline)
    return p


def cherry():
    p = Pix(S, S)
    # stems
    stem = ['green1', 'green2']
    pts1 = [(11, 24), (12, 20), (14, 15), (17, 10), (20, 6), (22, 4)]
    pts2 = [(25, 25), (24, 20), (23, 15), (22, 10), (22, 4)]
    for pts in (pts1, pts2):
        for (a, b) in zip(pts, pts[1:]):
            p.line(a[0], a[1], b[0], b[1], 'green1')
            p.line(a[0] + 1, a[1], b[0] + 1, b[1], 'green2')
    # leaf
    leaf = p.mask_poly([(22, 5), (27, 2), (33, 3), (30, 8), (24, 8)])
    p.shade_mask(leaf, 'green')
    p.line(23, 6, 31, 4, 'green1')
    # fruits
    for (cx, cy) in ((11, 27), (25, 27)):
        mk = p.mask_ellipse(cx, cy, 7.4, 7.0)
        p.shade_mask(mk, 'red', base=2)
        p.set(cx - 3, cy - 3, 'white')
        p.set(cx - 4, cy - 2, 'red3')
        p.set(cx - 3, cy - 2, 'red3')
        p.set(cx - 2, cy - 4, 'red3')
        p.set(cx, cy - 6, 'blood0')
    return _finish(p)


def lemon():
    p = Pix(S, S)
    mk = p.mask_poly([(4, 21), (6, 14), (11, 9), (18, 7), (25, 8), (30, 12),
                      (33, 18), (32, 24), (27, 29), (19, 31), (11, 30), (6, 27)])
    tip1 = p.mask_ellipse(3.5, 22.5, 2.2, 2.2)
    tip2 = p.mask_ellipse(33.5, 15.5, 2.0, 2.4)
    mk = Pix.m_or(Pix.m_or(mk, tip1), tip2)
    p.shade_mask(mk, 'yellow', base=2)
    # pores
    for (x, y) in ((12, 14), (17, 12), (23, 13), (14, 20), (20, 18), (26, 19), (18, 25), (24, 25), (10, 24)):
        p.set(x, y, 'yellow1')
    for (x, y) in ((9, 12), (10, 11), (11, 11), (8, 13)):
        p.set(x, y, 'white')
    # leaf
    leaf = p.mask_poly([(25, 7), (27, 2), (32, 1), (31, 5), (28, 8)])
    p.shade_mask(leaf, 'green')
    p.line(26, 6, 31, 2, 'green1')
    return _finish(p, 'black')


def horseshoe():
    p = Pix(S, S)
    outer = p.mask_ellipse(18, 16, 14, 14)
    inner = p.mask_ellipse(18, 16, 7.5, 8)
    cut = p.mask_poly([(10, 21), (26, 21), (26, 36), (10, 36)])
    ring = Pix.m_sub(outer, inner)
    ring = Pix.m_sub(ring, cut)
    legs = Pix.m_or(p.mask_poly([(4, 14), (11, 14), (12, 32), (4, 32)]),
                    p.mask_poly([(25, 14), (32, 14), (32, 32), (24, 32)]))
    legs = Pix.m_sub(legs, Pix.m_or(inner, p.mask_poly([(0, 0), (36, 0), (36, 13), (0, 13)])))
    shape = Pix.m_or(ring, legs)
    p.shade_mask(shape, 'steel', base=2)
    # gold rim line
    for y in range(p.h):
        for x in range(p.w):
            if shape[y][x] and not shape[y - 1][x] if y > 0 else False:
                pass
    # nail holes
    for (x, y) in ((7, 20), (7, 26), (28, 20), (28, 26), (10, 9), (25, 9), (18, 5)):
        p.set(x, y, 'black')
        p.set(x + 1, y, 'steel0')
    # toe caps
    p.rect(4, 31, 8, 2, 'gold2')
    p.rect(24, 31, 8, 2, 'gold2')
    p.hline(4, 11, 31, 'gold3')
    p.hline(24, 31, 31, 'gold3')
    p.img = p.img.transpose(1)  # flip vertically: open end up, the lucky way
    p.px = p.img.load()
    return _finish(p)


def bell():
    p = Pix(S, S)
    body = p.mask_poly([(18, 3), (24, 5), (26, 10), (27, 17), (29, 23), (33, 27), (33, 29),
                        (3, 29), (3, 27), (7, 23), (9, 17), (10, 10), (12, 5)])
    p.shade_mask(body, 'gold', base=2)
    # rim band
    p.hline(3, 33, 27, 'gold1')
    p.hline(4, 32, 26, 'gold3')
    p.hline(3, 33, 29, 'gold0')
    # highlight stripe
    for y in range(8, 24):
        x = 13 - (y - 8) // 5
        p.set(x, y, 'gold4')
        p.set(x + 1, y, 'gold3')
    # top loop
    loop = Pix.m_sub(p.mask_ellipse(18, 3, 3.2, 3.2), p.mask_ellipse(18, 3, 1.4, 1.4))
    p.shade_mask(loop, 'gold')
    # clapper
    cl = p.mask_ellipse(18, 31.5, 3.2, 2.8)
    p.shade_mask(cl, 'steel', base=2)
    # engraved band
    for x in range(10, 27, 3):
        p.set(x, 19, 'gold1')
    return _finish(p)


def clover():
    p = Pix(S, S)
    mk = p.mask_new()
    # four heart-shaped leaves made of two circles each
    leaves = [((14, 9), (22, 9)), ((14, 27), (22, 27)), ((9, 14), (9, 22)), ((27, 14), (27, 22))]
    centers = []
    for (a, b) in [((13, 9), (19, 7)), ((17, 7), (23, 9))]:
        pass
    leaf_parts = [
        [(14, 8.5), (18.5, 6.5), (16.5, 12)],   # top leaf (lobes)
    ]
    L = []
    # top
    L.append(p.mask_ellipse(14.5, 8.5, 4.6, 4.6)); L.append(p.mask_ellipse(21.5, 8.5, 4.6, 4.6))
    L.append(p.mask_poly([(10.5, 10), (25.5, 10), (18, 17)]))
    # bottom
    L.append(p.mask_ellipse(14.5, 25.5, 4.6, 4.6)); L.append(p.mask_ellipse(21.5, 25.5, 4.6, 4.6))
    L.append(p.mask_poly([(10.5, 24), (25.5, 24), (18, 17)]))
    # left
    L.append(p.mask_ellipse(9.5, 13.5, 4.6, 4.6)); L.append(p.mask_ellipse(9.5, 20.5, 4.6, 4.6))
    L.append(p.mask_poly([(11, 9.5), (11, 24.5), (18, 17)]))
    # right
    L.append(p.mask_ellipse(26.5, 13.5, 4.6, 4.6)); L.append(p.mask_ellipse(26.5, 20.5, 4.6, 4.6))
    L.append(p.mask_poly([(25, 9.5), (25, 24.5), (18, 17)]))
    for m in L:
        mk = Pix.m_or(mk, m)
    p.shade_mask(mk, 'green', base=2)
    # vein lines (dark cross)
    for i in range(0, 8):
        p.set(18 - i, 17 - i, 'green1')
        p.set(18 + i, 17 - i, 'green1')
        p.set(18 - i, 17 + i, 'green1')
        p.set(18 + i, 17 + i, 'green1')
    # shiny spots
    for (x, y) in ((12, 6), (13, 6), (12, 7), (7, 12), (7, 11)):
        p.set(x, y, 'cream2')
    # stem
    for i in range(0, 9):
        p.set(20 + i // 2 + (1 if i > 5 else 0), 25 + i, 'green1')
        p.set(21 + i // 2 + (1 if i > 5 else 0), 25 + i, 'green2')
    return _finish(p)


def star():
    p = Pix(S, S)
    cx, cy = 18, 19
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 16.5 if i % 2 == 0 else 7.2
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    mk = p.mask_poly(pts)
    p.shade_mask(mk, 'yellow', base=2)
    # facets: darker on lower-right halves of each arm
    for i in range(0, 10, 2):
        a = -math.pi / 2 + i * math.pi / 5
        tx, ty = cx + 16 * math.cos(a), cy + 16 * math.sin(a)
        steps = 14
        for s in range(steps):
            x = int(round(cx + (tx - cx) * s / steps))
            y = int(round(cy + (ty - cy) * s / steps))
            if mk[y][x]:
                p.set(x, y, 'gold2')
    for (x, y) in ((16, 13), (17, 12), (15, 15)):
        p.set(x, y, 'white')
    p.set(cx, cy, 'yellow3')
    return _finish(p, 'black')


def diamond():
    p = Pix(S, S)
    top = [(9, 6), (27, 6), (34, 14), (18, 33), (2, 14)]
    mk = p.mask_poly(top)
    p.shade_mask(mk, 'cyan', base=2)
    # crown/pavilion separation
    p.hline(3, 33, 14, 'cyan1')
    p.hline(4, 32, 13, 'cyan3')
    # facet lines
    for (a, b) in (((9, 6), (13, 13)), ((27, 6), (23, 13)), ((18, 6), (13, 13)), ((18, 6), (23, 13)),
                   ((13, 14), (18, 32)), ((23, 14), (18, 32)), ((3, 14), (18, 32)), ((33, 14), (18, 32))):
        p.line(a[0], a[1], b[0], b[1], 'cyan1')
    # bright facets
    for y in range(7, 13):
        for x in range(10, 18):
            if mk[y][x] and (x + y) % 3 == 0:
                p.set(x, y, 'cyan3')
    for (x, y) in ((11, 8), (12, 8), (11, 9), (7, 12), (14, 18), (15, 20)):
        p.set(x, y, 'white')
    return _finish(p, 'black')


def seven():
    p = Pix(S, S)
    # bold "7" polygon
    shape = p.mask_poly([(5, 4), (31, 4), (31, 10), (21, 32), (12, 32), (21, 11), (5, 11)])
    serif = p.mask_poly([(5, 4), (9, 4), (9, 14), (5, 14)])
    mk = Pix.m_or(shape, serif)
    # gold inner rim: draw gold mask, then red inset
    p.shade_mask(mk, 'gold', base=2)
    inner = [[False] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            if mk[y][x] and all(0 <= x + dx < S and 0 <= y + dy < S and mk[y + dy][x + dx]
                                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2))):
                inner[y][x] = True
    p.shade_mask(inner, 'red', base=2)
    for (x, y) in ((8, 6), (9, 6), (10, 6), (11, 6), (8, 7)):
        p.set(x, y, 'red3')
    for y in range(13, 30):
        x = 21 - (y - 13) // 2
        p.set(x, y, 'red2')
    p.drop_shadow(col('black'), 2, 2)
    return _finish(p)


def eye():
    p = Pix(S, S)
    # rays (wild aura)
    for i in range(12):
        a = i * math.pi / 6
        for r in range(13, 17):
            x = int(round(18 + r * math.cos(a)))
            y = int(round(18 + r * math.sin(a) * 0.9))
            p.set(x, y, 'purple2' if r < 16 else 'purple1')
    alm = p.mask_from_draw(lambda d: (d.chord([2, 7, 34, 35], 200, 340, fill=255),
                                       d.chord([2, 1, 34, 29], 20, 160, fill=255)))
    p.shade_mask(alm, 'bone', base=2)
    iris = p.mask_ellipse(18, 18, 6.5, 6.5)
    iris = Pix.m_and(iris, alm)
    p.shade_mask(iris, 'purple', base=2)
    pup = p.mask_ellipse(18, 18, 2.4, 4.2)
    p.fill_mask(pup, 'black')
    p.set(15, 15, 'white'); p.set(16, 15, 'white'); p.set(15, 16, 'white')
    # lids
    for x in range(4, 33):
        for y in range(S):
            if alm[y][x]:
                p.set(x, y, 'gold2')
                break
    return _finish(p)


def skull():
    p = Pix(S, S)
    head = p.mask_ellipse(18, 15, 13, 12)
    jaw = p.mask_poly([(10, 22), (26, 22), (25, 31), (11, 31)])
    mk = Pix.m_or(head, jaw)
    p.shade_mask(mk, 'bone', base=2)
    for (cx, cy) in ((12.5, 17), (23.5, 17)):
        e = p.mask_ellipse(cx, cy, 4, 4.4)
        p.fill_mask(e, 'black')
    p.set(12, 17, 'red2'); p.set(23, 17, 'red2')
    nose = p.mask_poly([(18, 21), (16, 25), (20, 25)])
    p.fill_mask(nose, 'vdark')
    for x in range(12, 25, 3):
        p.vline(x, 27, 31, 'cream0')
    p.hline(11, 25, 27, 'cream0')
    # cracks
    p.line(18, 4, 20, 8, 'cream0'); p.line(20, 8, 19, 11, 'cream0')
    p.set(9, 9, 'white'); p.set(10, 8, 'white'); p.set(9, 10, 'cream2')
    return _finish(p)


SYMBOLS = [cherry, lemon, horseshoe, bell, clover, star, diamond, seven, eye, skull]


def build(outdir):
    sheet = Pix(S * len(SYMBOLS), S)
    blur = Pix(S * len(SYMBOLS), S)
    singles = []
    for i, fn in enumerate(SYMBOLS):
        s = fn()
        singles.append(s)
        sheet.paste(s, i * S, 0)
        # vertical motion blur: average of shifted copies, alpha-thresholded
        for y in range(S):
            for x in range(S):
                acc = [0, 0, 0]; n = 0
                for k in range(-3, 4):
                    q = s.get(x, y + k)
                    if q[3] > 0:
                        acc[0] += q[0]; acc[1] += q[1]; acc[2] += q[2]; n += 1
                if n >= 3:
                    blur.set(i * S + x, y, (acc[0] // n, acc[1] // n, acc[2] // n, 255))
    sheet.save(outdir + '/sym.png')
    blur.save(outdir + '/symb.png')
    return singles


if __name__ == '__main__':
    import sys
    s = build(sys.argv[1] if len(sys.argv) > 1 else '.')
