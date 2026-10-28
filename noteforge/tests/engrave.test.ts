import { describe, it, expect, beforeAll } from 'vitest';
import { createPianoScore } from '../src/model/factory';
import { writeAt, setKeySig, setTimeSig } from '../src/model/edit';
import { frac, ZERO } from '../src/model/fraction';
import { scoreToMei } from '../src/engrave/mei';
import { verovioOptions } from '../src/engrave/layout';
import { edit, loadVerovio } from './helpers';
import type { VerovioToolkit } from 'verovio/esm';

let tk: VerovioToolkit;
beforeAll(async () => {
  tk = await loadVerovio();
}, 60000);

function sample() {
  return edit(createPianoScore({ title: 'Тест', composer: 'Автор', measures: 4 }), (d) => {
    // Melody handed from the right hand (C5 → B4) to the left hand (A4 → G4).
    writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { type: 'chord', notes: [{ step: 'C', octave: 5, alter: 0 }] });
    writeAt(d, 0, 0, 0, frac(1, 4), frac(1, 4), { type: 'chord', notes: [{ step: 'B', octave: 4, alter: 0 }] });
    writeAt(d, 1, 0, 0, frac(1, 2), frac(1, 4), { type: 'chord', notes: [{ step: 'A', octave: 4, alter: 0 }] });
    writeAt(d, 1, 0, 0, frac(3, 4), frac(1, 4), { type: 'chord', notes: [{ step: 'G', octave: 4, alter: 0 }] });
    // F# twice in one measure: only the first gets a printed sharp.
    writeAt(d, 0, 1, 0, ZERO, frac(1, 8), { type: 'chord', notes: [{ step: 'F', octave: 5, alter: 1 }] });
    writeAt(d, 0, 1, 0, frac(1, 8), frac(1, 8), { type: 'chord', notes: [{ step: 'F', octave: 5, alter: 1 }] });
    // Tie across the barline.
    writeAt(d, 0, 1, 0, frac(3, 4), frac(1, 2), { type: 'chord', notes: [{ step: 'E', octave: 5, alter: 0 }] });
    setKeySig(d, 3, -3);
    setTimeSig(d, 3, { count: 6, unit: 8 });
  });
}

describe('MEI export + Verovio engraving', () => {
  it('produces MEI that Verovio lays out without errors', () => {
    const { mei, index } = scoreToMei(sample());
    tk.setOptions(verovioOptions(createPianoScore().layout, 'page'));
    expect(tk.loadData(mei)).toBeTruthy();
    expect(tk.getPageCount()).toBe(1);
    expect(tk.getLog()).toBe('');
    const svg = tk.renderToSVG(1);
    // Every model note is present in the SVG under its own id.
    for (const [id, ref] of index) if (ref.kind === 'note') expect(svg).toContain(`id="${id}"`);
  });

  it('prints accidentals only where needed and beams eighths', () => {
    const { mei } = scoreToMei(sample());
    const m2 = mei.slice(mei.indexOf('n="2"'), mei.indexOf('n="3"'));
    expect((m2.match(/accid="s"/g) ?? []).length).toBe(1);
    expect((m2.match(/accid.ges="s"/g) ?? []).length).toBe(1);
    expect(m2).toContain('<beam>');
    expect(mei).toContain('<tie ');
    expect(mei).toContain('<keySig sig="3f"/>');
    expect(mei).toContain('<meterSig count="6" unit="8"/>');
  });

  it('renders long scores across many pages', () => {
    const s = createPianoScore({ measures: 400 });
    tk.setOptions(verovioOptions(s.layout, 'page'));
    expect(tk.loadData(scoreToMei(s).mei)).toBeTruthy();
    expect(tk.getPageCount()).toBeGreaterThan(5);
  });
});
