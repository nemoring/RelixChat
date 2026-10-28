# -*- coding: utf-8 -*-
"""Regenerates every resource of Lucky Pit into ../res (and Op.java)."""
import os
import sys
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import gen_symbols, gen_font, gen_cards, gen_ui, gen_sound

res = os.path.join(here, '..', 'res')
src = os.path.join(here, '..', 'src', 'luckypit')
os.makedirs(res, exist_ok=True)
gen_symbols.build(res)
print('font glyphs', gen_font.build(res))
print('cards', gen_cards.build(res, src))
gen_ui.build(res)
gen_sound.build(res)
print('done')
