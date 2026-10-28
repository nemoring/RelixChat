# -*- coding: utf-8 -*-
"""Fails the build if any text shown in game uses a character missing from the pixel font."""
import re
import struct
import sys
import glob
import os

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.join(here, '..')
d = open(os.path.join(root, 'res', 'font.bin'), 'rb').read()
n = struct.unpack('>H', d[:2])[0]
have = set(chr(struct.unpack('>H', d[2 + i * 6:4 + i * 6])[0]) for i in range(n))
have |= {'\n'}
missing = {}
for f in glob.glob(os.path.join(root, 'src', 'luckypit', '*.java')):
    src = open(f, encoding='utf-8').read()
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', src):
        s = m.group(1).encode('utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8')
        for ch in s:
            if ch not in have:
                missing.setdefault(ch, set()).add(os.path.basename(f))
sys.path.insert(0, here)
import gen_cards
for c in gen_cards.CARDS:
    txt = c[0] + ' '.join(gen_cards.desc_of(*e) for e in c[3])
    for ch in txt:
        if ch not in have:
            missing.setdefault(ch, set()).add('card ' + c[0])
if missing:
    for ch, where in missing.items():
        print('missing glyph %r U+%04X used in %s' % (ch, ord(ch), ', '.join(sorted(where))[:120]))
    sys.exit(1)
print('glyphs ok: %d characters in font' % len(have))
