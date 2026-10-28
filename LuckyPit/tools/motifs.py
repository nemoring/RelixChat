# -*- coding: utf-8 -*-
"""Scalable pixel motifs for card illustrations.

Every motif is a function (s, ramp) -> Pix of size s x s.  Coordinates are
given in a 0..1 unit square and rasterised for the requested size, then the
result is shaded and outlined, so the same motif works at 18px and 10px.
"""
import math
from pix import Pix, P, RAMP, col


def U(s, v):
    return v * s


def poly(p, pts, ramp, base=2):
    s = p.w
    mk = p.mask_poly([(U(s, x), U(s, y)) for x, y in pts])
    p.shade_mask(mk, ramp, base=base)
    return mk


def circ(p, cx, cy, r, ramp, base=2, ry=None):
    s = p.w
    mk = p.mask_ellipse(U(s, cx), U(s, cy), max(0.8, U(s, r)), max(0.8, U(s, ry if ry else r)))
    p.shade_mask(mk, ramp, base=base)
    return mk


def ring(p, cx, cy, r1, r2, ramp, base=2):
    s = p.w
    mk = Pix.m_sub(p.mask_ellipse(U(s, cx), U(s, cy), U(s, r1), U(s, r1)),
                   p.mask_ellipse(U(s, cx), U(s, cy), U(s, r2), U(s, r2)))
    p.shade_mask(mk, ramp, base=base)
    return mk


def ln(p, x0, y0, x1, y1, c):
    s = p.w - 1
    p.line(int(round(x0 * s)), int(round(y0 * s)), int(round(x1 * s)), int(round(y1 * s)), c)


def dot(p, x, y, c):
    s = p.w - 1
    p.set(int(round(x * s)), int(round(y * s)), c)


def R(ramp, i):
    return RAMP[ramp][i]


def done(p):
    p.outline('black')
    return p


# ------------------------------------------------------------------ motifs
def m_cherry(s, rp='red'):
    p = Pix(s, s)
    ln(p, .30, .62, .55, .12, 'green1'); ln(p, .70, .64, .55, .12, 'green1')
    poly(p, [(.55, .12), (.80, .04), (.92, .12), (.70, .20)], 'green')
    circ(p, .30, .72, .21, rp); circ(p, .70, .74, .21, rp)
    dot(p, .23, .65, 'white'); dot(p, .63, .67, 'white')
    return done(p)


def m_lemon(s, rp='yellow'):
    p = Pix(s, s)
    poly(p, [(.08, .58), (.18, .32), (.42, .20), (.70, .22), (.90, .40), (.92, .60), (.75, .80), (.45, .86), (.20, .78)], rp)
    poly(p, [(.62, .22), (.75, .06), (.88, .10), (.76, .24)], 'green')
    dot(p, .25, .40, 'white'); dot(p, .30, .36, R(rp, 4))
    return done(p)


def m_horseshoe(s, rp='steel'):
    p = Pix(s, s)
    mk = Pix.m_sub(p.mask_ellipse(U(s, .5), U(s, .56), U(s, .42), U(s, .40)),
                   p.mask_ellipse(U(s, .5), U(s, .56), U(s, .22), U(s, .22)))
    mk = Pix.m_sub(mk, p.mask_poly([(U(s, .32), 0), (U(s, .68), 0), (U(s, .62), U(s, .56)), (U(s, .38), U(s, .56))]))
    p.shade_mask(mk, rp)
    for (x, y) in ((.18, .55), (.82, .55), (.28, .80), (.72, .80)):
        dot(p, x, y, 'black')
    return done(p)


def m_bell(s, rp='gold'):
    p = Pix(s, s)
    poly(p, [(.5, .10), (.70, .18), (.74, .45), (.92, .78), (.08, .78), (.26, .45), (.30, .18)], rp)
    circ(p, .5, .86, .09, 'steel')
    ln(p, .36, .25, .30, .62, R(rp, 4))
    return done(p)


def m_clover(s, rp='green'):
    p = Pix(s, s)
    for (cx, cy) in ((.5, .26), (.5, .66), (.30, .46), (.70, .46)):
        circ(p, cx, cy, .19, rp)
    ln(p, .55, .70, .72, .96, R(rp, 1))
    dot(p, .5, .46, R(rp, 0))
    dot(p, .42, .18, R(rp, 4))
    return done(p)


def m_star(s, rp='yellow'):
    p = Pix(s, s)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = .48 if i % 2 == 0 else .20
        pts.append((.5 + r * math.cos(a), .54 + r * math.sin(a)))
    poly(p, pts, rp)
    dot(p, .44, .40, 'white')
    return done(p)


def m_diamond(s, rp='cyan'):
    p = Pix(s, s)
    poly(p, [(.25, .14), (.75, .14), (.96, .40), (.5, .94), (.04, .40)], rp)
    ln(p, .06, .40, .94, .40, R(rp, 1))
    ln(p, .5, .14, .34, .40, R(rp, 1)); ln(p, .5, .14, .66, .40, R(rp, 1))
    ln(p, .34, .40, .5, .92, R(rp, 1)); ln(p, .66, .40, .5, .92, R(rp, 1))
    dot(p, .30, .24, 'white')
    return done(p)


def m_seven(s, rp='red'):
    p = Pix(s, s)
    poly(p, [(.12, .10), (.88, .10), (.88, .28), (.58, .92), (.32, .92), (.60, .30), (.12, .30)], rp)
    ln(p, .14, .12, .84, .12, R(rp, 4))
    return done(p)


def m_eye(s, rp='purple'):
    p = Pix(s, s)
    poly(p, [(.02, .5), (.25, .25), (.5, .18), (.75, .25), (.98, .5), (.75, .75), (.5, .82), (.25, .75)], 'bone')
    circ(p, .5, .5, .22, rp)
    circ(p, .5, .5, .09, ['black'] * 5)
    dot(p, .43, .42, 'white')
    return done(p)


def m_skull(s, rp='bone'):
    p = Pix(s, s)
    circ(p, .5, .42, .40, rp, ry=.36)
    poly(p, [(.28, .62), (.72, .62), (.70, .92), (.30, .92)], rp)
    circ(p, .33, .48, .11, ['black'] * 5); circ(p, .67, .48, .11, ['black'] * 5)
    dot(p, .5, .66, 'black')
    for x in (.38, .5, .62):
        ln(p, x, .78, x, .90, R(rp, 0))
    return done(p)


def m_coin(s, rp='gold'):
    p = Pix(s, s)
    circ(p, .5, .5, .44, rp)
    ring(p, .5, .5, .32, .24, [R(rp, 1)] * 2 + [R(rp, 1)] * 3)
    ln(p, .5, .32, .5, .68, R(rp, 4))
    return done(p)


def m_coins(s, rp='gold'):
    p = Pix(s, s)
    for i, y in enumerate((.82, .68, .54)):
        poly(p, [(.10, y - .08), (.90, y - .08), (.90, y + .08), (.10, y + .08)], rp)
        ln(p, .12, y - .08, .88, y - .08, R(rp, 4))
    circ(p, .5, .28, .22, rp, ry=.12)
    return done(p)


def m_bag(s, rp='brown'):
    p = Pix(s, s)
    circ(p, .5, .64, .38, rp, ry=.32)
    poly(p, [(.36, .14), (.64, .14), (.58, .34), (.42, .34)], rp)
    ln(p, .34, .34, .66, .34, 'gold2')
    poly(p, [(.44, .52), (.56, .52), (.56, .78), (.44, .78)], 'gold')
    return done(p)


def m_safe(s, rp='steel'):
    p = Pix(s, s)
    poly(p, [(.08, .12), (.92, .12), (.92, .90), (.08, .90)], rp)
    p.frame(int(U(s, .18)), int(U(s, .22)), int(U(s, .64)), int(U(s, .58)), R(rp, 0))
    circ(p, .5, .5, .14, 'gold')
    ln(p, .5, .40, .5, .60, 'gold0')
    return done(p)


def m_key(s, rp='gold'):
    p = Pix(s, s)
    ring(p, .28, .30, .22, .10, rp)
    poly(p, [(.40, .42), (.48, .36), (.94, .82), (.86, .90)], rp)
    poly(p, [(.70, .72), (.78, .64), (.86, .72), (.78, .80)], rp)
    return done(p)


def m_hourglass(s, rp='gold'):
    p = Pix(s, s)
    poly(p, [(.18, .06), (.82, .06), (.82, .14), (.18, .14)], 'brown')
    poly(p, [(.18, .86), (.82, .86), (.82, .94), (.18, .94)], 'brown')
    poly(p, [(.24, .14), (.76, .14), (.54, .50), (.76, .86), (.24, .86), (.46, .50)], 'cyan', base=3)
    poly(p, [(.36, .28), (.64, .28), (.5, .46)], rp)
    poly(p, [(.30, .86), (.70, .86), (.5, .64)], rp)
    return done(p)


def m_clock(s, rp='gold'):
    p = Pix(s, s)
    circ(p, .5, .52, .44, rp)
    circ(p, .5, .52, .34, 'bone', base=3)
    ln(p, .5, .52, .5, .26, 'black'); ln(p, .5, .52, .70, .58, 'black')
    dot(p, .5, .52, 'red1')
    poly(p, [(.42, .02), (.58, .02), (.58, .08), (.42, .08)], rp)
    return done(p)


def m_dice(s, rp='bone'):
    p = Pix(s, s)
    poly(p, [(.10, .26), (.62, .10), (.92, .34), (.88, .80), (.40, .94), (.08, .72)], rp)
    ln(p, .10, .27, .44, .46, R(rp, 0)); ln(p, .44, .46, .92, .35, R(rp, 0)); ln(p, .44, .46, .40, .93, R(rp, 0))
    for (x, y) in ((.36, .24), (.56, .20), (.24, .55), (.28, .74), (.66, .58), (.78, .74)):
        dot(p, x, y, 'red1')
    return done(p)


def m_card(s, rp='bone'):
    p = Pix(s, s)
    poly(p, [(.18, .06), (.82, .06), (.82, .94), (.18, .94)], rp, base=3)
    p.frame(int(U(s, .18)), int(U(s, .06)), int(U(s, .64)) + 1, int(U(s, .88)) + 1, 'cream0')
    poly(p, [(.5, .30), (.66, .50), (.5, .70), (.34, .50)], 'red')
    dot(p, .26, .14, 'red1'); dot(p, .74, .86, 'red1')
    return done(p)


def m_crown(s, rp='gold'):
    p = Pix(s, s)
    poly(p, [(.06, .30), (.28, .52), (.5, .18), (.72, .52), (.94, .30), (.86, .80), (.14, .80)], rp)
    poly(p, [(.14, .74), (.86, .74), (.86, .86), (.14, .86)], rp, base=1)
    circ(p, .5, .58, .07, 'red'); circ(p, .27, .66, .05, 'cyan'); circ(p, .73, .66, .05, 'cyan')
    return done(p)


def m_heart(s, rp='red'):
    p = Pix(s, s)
    circ(p, .32, .36, .22, rp); circ(p, .68, .36, .22, rp)
    poly(p, [(.11, .42), (.89, .42), (.5, .90)], rp)
    dot(p, .26, .28, 'white')
    return done(p)


def m_flame(s, rp='orange'):
    p = Pix(s, s)
    poly(p, [(.5, .02), (.70, .30), (.86, .52), (.82, .80), (.60, .96), (.40, .96), (.18, .80), (.16, .52), (.34, .40), (.40, .20)], rp, base=2)
    poly(p, [(.5, .40), (.64, .62), (.60, .88), (.40, .88), (.36, .64)], 'yellow', base=3)
    return done(p)


def m_moon(s, rp='bone'):
    p = Pix(s, s)
    mk = Pix.m_sub(p.mask_ellipse(U(s, .46), U(s, .5), U(s, .42), U(s, .42)),
                   p.mask_ellipse(U(s, .66), U(s, .40), U(s, .34), U(s, .34)))
    p.shade_mask(mk, rp)
    return done(p)


def m_sun(s, rp='orange'):
    p = Pix(s, s)
    for i in range(8):
        a = i * math.pi / 4
        poly(p, [(.5 + .48 * math.cos(a), .5 + .48 * math.sin(a)),
                 (.5 + .26 * math.cos(a + .35), .5 + .26 * math.sin(a + .35)),
                 (.5 + .26 * math.cos(a - .35), .5 + .26 * math.sin(a - .35))], 'yellow')
    circ(p, .5, .5, .28, rp)
    return done(p)


def m_potion(s, rp='purple'):
    p = Pix(s, s)
    circ(p, .5, .66, .32, rp)
    poly(p, [(.40, .14), (.60, .14), (.60, .40), (.40, .40)], 'cyan', base=3)
    poly(p, [(.36, .06), (.64, .06), (.64, .14), (.36, .14)], 'brown')
    dot(p, .38, .56, 'white')
    return done(p)


def m_knife(s, rp='steel'):
    p = Pix(s, s)
    poly(p, [(.92, .06), (.96, .10), (.42, .62), (.34, .54)], rp, base=3)
    poly(p, [(.26, .52), (.48, .74), (.42, .80), (.20, .58)], 'gold')
    poly(p, [(.34, .70), (.40, .76), (.12, .98), (.04, .92)], 'brown')
    return done(p)


def m_scroll(s, rp='bone'):
    p = Pix(s, s)
    poly(p, [(.18, .14), (.82, .14), (.82, .86), (.18, .86)], rp, base=3)
    circ(p, .5, .10, .40, 'cream0' and rp, ry=.06)
    circ(p, .5, .90, .40, rp, ry=.06)
    for y in (.30, .42, .54):
        ln(p, .28, y, .72, y, 'brown1')
    circ(p, .62, .72, .09, 'blood')
    return done(p)


def m_book(s, rp='maroon'):
    p = Pix(s, s)
    poly(p, [(.14, .10), (.84, .10), (.84, .90), (.14, .90)], rp, base=3)
    poly(p, [(.84, .14), (.92, .16), (.92, .92), (.84, .90)], 'bone')
    poly(p, [(.40, .36), (.60, .36), (.60, .56), (.40, .56)], 'gold')
    ln(p, .20, .10, .20, .90, R(rp, 0))
    return done(p)


def m_candle(s, rp='bone'):
    p = Pix(s, s)
    poly(p, [(.34, .40), (.66, .40), (.66, .92), (.34, .92)], rp)
    poly(p, [(.5, .06), (.62, .24), (.5, .36), (.38, .24)], 'orange', base=3)
    ln(p, .5, .36, .5, .40, 'black')
    poly(p, [(.22, .88), (.78, .88), (.78, .96), (.22, .96)], 'gold')
    return done(p)


def m_mirror(s, rp='gold'):
    p = Pix(s, s)
    circ(p, .5, .44, .38, rp, ry=.42)
    circ(p, .5, .44, .28, 'cyan', base=3, ry=.32)
    ln(p, .38, .26, .30, .44, 'white')
    poly(p, [(.44, .84), (.56, .84), (.56, .98), (.44, .98)], rp)
    return done(p)


def m_mask(s, rp='bone'):
    p = Pix(s, s)
    poly(p, [(.06, .30), (.94, .30), (.88, .62), (.62, .74), (.5, .64), (.38, .74), (.12, .62)], rp)
    circ(p, .30, .46, .10, ['black'] * 5, ry=.07)
    circ(p, .70, .46, .10, ['black'] * 5, ry=.07)
    ln(p, .06, .30, .02, .18, 'red1')
    return done(p)


def m_cat(s, rp='gray'):
    p = Pix(s, s)
    circ(p, .5, .56, .38, rp, ry=.34)
    poly(p, [(.14, .40), (.20, .06), (.42, .26)], rp)
    poly(p, [(.86, .40), (.80, .06), (.58, .26)], rp)
    circ(p, .34, .52, .08, 'yellow', base=3); circ(p, .66, .52, .08, 'yellow', base=3)
    dot(p, .34, .52, 'black'); dot(p, .66, .52, 'black')
    dot(p, .5, .68, 'pink2')
    return done(p)


def m_raven(s, rp='purple'):
    p = Pix(s, s)
    circ(p, .48, .58, .34, ['black', 'vdark', 'gray0', 'purple0', 'purple1'], ry=.28)
    circ(p, .70, .32, .18, ['black', 'vdark', 'gray0', 'purple0', 'purple1'])
    poly(p, [(.84, .28), (.98, .34), (.84, .38)], 'gold')
    dot(p, .72, .28, 'red2')
    poly(p, [(.14, .60), (.02, .86), (.30, .74)], ['black', 'vdark', 'gray0', 'purple0', 'purple1'])
    return done(p)


def m_gear(s, rp='steel'):
    p = Pix(s, s)
    for i in range(8):
        a = i * math.pi / 4
        cx, cy = .5 + .38 * math.cos(a), .5 + .38 * math.sin(a)
        circ(p, cx, cy, .10, rp)
    circ(p, .5, .5, .36, rp)
    circ(p, .5, .5, .12, ['black'] * 5)
    return done(p)


def m_bolt(s, rp='yellow'):
    p = Pix(s, s)
    poly(p, [(.60, .02), (.20, .56), (.46, .56), (.34, .98), (.82, .38), (.54, .38), (.72, .02)], rp)
    return done(p)


def m_chain(s, rp='steel'):
    p = Pix(s, s)
    for i, (cx, cy) in enumerate(((.24, .24), (.5, .5), (.76, .76))):
        ring(p, cx, cy, .20, .10, rp)
    return done(p)


def m_goblet(s, rp='gold'):
    p = Pix(s, s)
    circ(p, .5, .26, .36, rp, ry=.24)
    poly(p, [(.14, .10), (.86, .10), (.86, .24), (.14, .24)], 'blood', base=3)
    poly(p, [(.44, .48), (.56, .48), (.56, .80), (.44, .80)], rp)
    poly(p, [(.24, .82), (.76, .82), (.76, .94), (.24, .94)], rp)
    return done(p)


def m_spiral(s, rp='purple'):
    p = Pix(s, s)
    circ(p, .5, .5, .46, rp, base=1)
    for t in range(0, 200):
        a = t * 0.12
        r = .02 + t * .0021
        dot(p, .5 + r * math.cos(a), .5 + r * math.sin(a), R(rp, 4))
    return done(p)


def m_paw(s, rp='bone'):
    p = Pix(s, s)
    circ(p, .5, .64, .26, rp, ry=.22)
    for (cx, cy) in ((.22, .36), (.40, .20), (.60, .20), (.78, .36)):
        circ(p, cx, cy, .11, rp)
    return done(p)


def m_ladybug(s, rp='red'):
    p = Pix(s, s)
    circ(p, .5, .58, .40, rp)
    circ(p, .5, .20, .18, ['black', 'vdark', 'gray0', 'gray1', 'gray2'])
    ln(p, .5, .26, .5, .96, 'black')
    for (x, y) in ((.30, .48), (.70, .48), (.32, .74), (.68, .74)):
        circ(p, x, y, .07, ['black'] * 5)
    return done(p)


def m_drop(s, rp='blood'):
    p = Pix(s, s)
    poly(p, [(.5, .02), (.76, .46), (.5, .50), (.24, .46)], rp)
    circ(p, .5, .64, .30, rp)
    dot(p, .40, .58, 'red3')
    return done(p)


def m_wheel(s, rp='gold'):
    p = Pix(s, s)
    circ(p, .5, .5, .46, rp)
    circ(p, .5, .5, .36, 'maroon', base=3)
    for i in range(8):
        a = i * math.pi / 4
        ln(p, .5, .5, .5 + .36 * math.cos(a), .5 + .36 * math.sin(a), R(rp, 3) if i % 2 else 'red2')
    circ(p, .5, .5, .08, rp)
    poly(p, [(.44, .0), (.56, .0), (.5, .12)], 'bone')
    return done(p)


def m_prism(s, rp='cyan'):
    p = Pix(s, s)
    poly(p, [(.5, .06), (.94, .88), (.06, .88)], rp, base=3)
    ln(p, .5, .06, .5, .88, R(rp, 1))
    ln(p, .0, .50, .30, .50, 'white')
    for i, c in enumerate(('red2', 'yellow2', 'green3', 'blue3')):
        ln(p, .68, .48 + i * .05, 1.0, .40 + i * .14, c)
    return done(p)


def m_bars(s, rp='gold'):
    p = Pix(s, s)
    poly(p, [(.10, .62), (.46, .62), (.42, .86), (.06, .86)], rp)
    poly(p, [(.54, .62), (.90, .62), (.94, .86), (.58, .86)], rp)
    poly(p, [(.32, .34), (.68, .34), (.72, .58), (.28, .58)], rp)
    return done(p)


def m_lock(s, rp='gold'):
    p = Pix(s, s)
    ring(p, .5, .38, .28, .16, 'steel')
    poly(p, [(.16, .40), (.84, .40), (.84, .92), (.16, .92)], rp)
    circ(p, .5, .62, .07, ['black'] * 5)
    ln(p, .5, .62, .5, .78, 'black')
    return done(p)


def m_scales(s, rp='gold'):
    p = Pix(s, s)
    ln(p, .5, .10, .5, .86, R(rp, 1)); ln(p, .12, .24, .88, .24, R(rp, 2))
    poly(p, [(.30, .86), (.70, .86), (.70, .94), (.30, .94)], rp)
    circ(p, .20, .54, .16, rp, ry=.08); circ(p, .80, .46, .16, rp, ry=.08)
    ln(p, .12, .24, .06, .52, R(rp, 1)); ln(p, .12, .24, .34, .52, R(rp, 1))
    ln(p, .88, .24, .66, .44, R(rp, 1)); ln(p, .88, .24, .94, .44, R(rp, 1))
    return done(p)


def m_rose(s, rp='red'):
    p = Pix(s, s)
    ln(p, .5, .56, .46, .98, 'green1')
    poly(p, [(.46, .74), (.20, .64), (.30, .80)], 'green')
    circ(p, .5, .34, .30, rp)
    ln(p, .36, .30, .5, .22, R(rp, 0)); ln(p, .5, .22, .64, .36, R(rp, 0)); ln(p, .64, .36, .46, .44, R(rp, 0))
    return done(p)


def m_orb(s, rp='purple'):
    p = Pix(s, s)
    circ(p, .5, .44, .38, rp, base=2)
    circ(p, .40, .34, .10, 'cyan', base=4)
    poly(p, [(.22, .80), (.78, .80), (.86, .96), (.14, .96)], 'brown')
    return done(p)


def m_bat(s, rp='gray'):
    p = Pix(s, s)
    poly(p, [(.02, .30), (.20, .44), (.36, .40), (.5, .60), (.64, .40), (.80, .44), (.98, .30), (.86, .70),
             (.70, .60), (.5, .80), (.30, .60), (.14, .70)], rp, base=1)
    circ(p, .5, .48, .12, rp)
    dot(p, .46, .46, 'red2'); dot(p, .54, .46, 'red2')
    return done(p)


def m_tower(s, rp='brown'):
    p = Pix(s, s)
    poly(p, [(.30, .30), (.70, .30), (.74, .96), (.26, .96)], rp)
    poly(p, [(.22, .20), (.78, .20), (.78, .32), (.22, .32)], rp)
    poly(p, [(.5, .0), (.80, .20), (.20, .20)], 'maroon')
    circ(p, .5, .52, .10, 'gold')
    return done(p)


def m_pickaxe(s, rp='steel'):
    p = Pix(s, s)
    poly(p, [(.06, .30), (.40, .08), (.94, .20), (.60, .22), (.12, .40)], rp)
    poly(p, [(.48, .16), (.56, .16), (.38, .98), (.30, .98)], 'brown')
    return done(p)


def m_tear(s, rp='cyan'):
    return m_drop(s, rp)


def m_anchor(s, rp='steel'):
    p = Pix(s, s)
    ring(p, .5, .14, .12, .05, rp)
    poly(p, [(.45, .24), (.55, .24), (.55, .88), (.45, .88)], rp)
    poly(p, [(.24, .36), (.76, .36), (.76, .44), (.24, .44)], rp)
    mk = Pix.m_sub(p.mask_ellipse(U(s, .5), U(s, .6), U(s, .42), U(s, .36)),
                   p.mask_ellipse(U(s, .5), U(s, .56), U(s, .32), U(s, .30)))
    mk = Pix.m_sub(mk, p.mask_poly([(0, 0), (s, 0), (s, U(s, .62)), (0, U(s, .62))]))
    p.shade_mask(mk, rp)
    return done(p)


def m_tophat(s, rp='gray'):
    p = Pix(s, s)
    poly(p, [(.26, .10), (.74, .10), (.74, .72), (.26, .72)], ['black', 'vdark', 'gray0', 'gray1', 'gray2'])
    poly(p, [(.26, .56), (.74, .56), (.74, .66), (.26, .66)], 'red')
    poly(p, [(.04, .72), (.96, .72), (.96, .84), (.04, .84)], ['black', 'vdark', 'gray0', 'gray1', 'gray2'])
    return done(p)


def m_lever(s, rp='red'):
    p = Pix(s, s)
    poly(p, [(.10, .70), (.60, .70), (.60, .96), (.10, .96)], 'steel')
    poly(p, [(.38, .76), (.46, .70), (.86, .18), (.80, .12)], 'steel')
    circ(p, .82, .14, .14, rp)
    return done(p)


def m_ticket(s, rp='orange'):
    p = Pix(s, s)
    poly(p, [(.04, .26), (.96, .26), (.96, .74), (.04, .74)], rp, base=3)
    circ(p, .04, .5, .08, ['clear'] * 5)
    for y in (.36, .5, .64):
        dot(p, .70, y, R(rp, 0))
    poly(p, [(.20, .40), (.50, .40), (.50, .60), (.20, .60)], 'red')
    return done(p)


def m_contract(s, rp='bone'):
    p = m_scroll(s, rp)
    return p


MOTIFS = {k[2:]: v for k, v in globals().items() if k.startswith('m_')}

# --------------------------------------------------------- micro digits 3x5
DIG3 = {
    '0': '###/#.#/#.#/#.#/###', '1': '.#./##./.#./.#./###', '2': '###/..#/###/#../###',
    '3': '###/..#/.##/..#/###', '4': '#.#/#.#/###/..#/..#', '5': '###/#../###/..#/###',
    '6': '###/#../###/#.#/###', '7': '###/..#/.#./.#./.#.', '8': '###/#.#/###/#.#/###',
    '9': '###/#.#/###/..#/###', '+': '.../.#./###/.#./...', 'x': '.../#.#/.#./#.#/...',
    '%': '#.#/..#/.#./#../#.#', '-': '.../.../###/.../...', '?': '###/..#/.##/.../.#.',
    '$': '.#./###/##./.##/###',
}


def badge(p, text, x, y, fg='gold3', bg='black'):
    """Draw small 3x5 text with a dark backing plate."""
    w = len(text) * 4 + 1
    p.rect(x, y, w, 7, bg)
    cx = x + 1
    for ch in text:
        g = DIG3.get(ch, DIG3['?'])
        for j, row in enumerate(g.split('/')):
            for i, c in enumerate(row):
                if c == '#':
                    p.set(cx + i, y + 1 + j, fg)
        cx += 4
    return w
