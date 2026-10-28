import { describe, it, expect } from 'vitest';
import { produce } from 'immer';
import { createPianoScore } from '../src/model/factory';
import * as E from '../src/model/edit';
import { frac, ZERO } from '../src/model/fraction';
import { checkScore, fixIssues } from '../src/model/check';
import { changedMeasures, pageMetaOf } from '../src/engrave/fastLayout';
import { scoreToMei } from '../src/engrave/mei';
import { verovioOptions } from '../src/engrave/layout';
import { edit, loadVerovio } from './helpers';

describe('measure checker', () => {
  it('finds wrong measure lengths, dangling ties and range problems, and fixes them', () => {
    let s = createPianoScore({ measures: 3 });
    s = edit(s, (d) => {
      E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { type: 'chord', notes: [{ step: 'C', octave: 5, alter: 0, tie: true }] });
      E.writeAt(d, 1, 1, 0, ZERO, frac(1, 4), { type: 'chord', notes: [{ step: 'C', octave: 0, alter: 0 }] });
      d.parts[0].staves[0].measures[2].voices[0][0].dur = { base: 2, dots: 0 }; // break the invariant on purpose
    });
    const issues = checkScore(s);
    expect(issues.some((i) => i.kind === 'underfull' && i.measure === 2)).toBe(true);
    expect(issues.some((i) => i.kind === 'tie' && i.measure === 0)).toBe(true);
    expect(issues.some((i) => i.kind === 'range' && i.measure === 1)).toBe(true);
    const fixed = produce(s, (d) => void fixIssues(d, issues));
    expect(checkScore(fixed).filter((i) => i.severity === 'error' || i.kind === 'tie')).toEqual([]);
  });
});

describe('fast partial re-layout', () => {
  it('detects which measures changed and when a full layout is required', () => {
    const s = createPianoScore({ measures: 10 });
    const notes = edit(s, (d) => void E.writeAt(d, 0, 5, 0, ZERO, frac(1, 4), { type: 'chord', notes: [{ step: 'C', octave: 5, alter: 0 }] }));
    expect([...changedMeasures(s, notes)!].sort((a, b) => a - b)).toEqual([4, 5, 6]);
    expect(changedMeasures(s, edit(s, (d) => E.setKeySig(d, 3, 2)))).toBeNull();
    expect(changedMeasures(s, edit(s, (d) => E.appendMeasures(d, 1)))).toBeNull();
  });

  it('reads measure ranges and system starts from an engraved page', async () => {
    const tk = await loadVerovio();
    const s = createPianoScore({ measures: 40 });
    tk.setOptions(verovioOptions(s.layout, 'page'));
    tk.loadData(scoreToMei(s).mei);
    const meta = pageMetaOf(tk.renderToSVG(1))!;
    expect(meta.first).toBe(0);
    expect(meta.systems[0]).toBe(0);
    expect(meta.systems.length).toBeGreaterThan(2);
    expect(meta.last).toBeGreaterThan(meta.systems[meta.systems.length - 1]);
    // A partial page with the same breaks lays out as exactly one page.
    tk.setOptions({ ...verovioOptions(s.layout, 'page'), breaks: 'encoded' });
    tk.loadData(scoreToMei(s, { from: meta.first, to: meta.last, systemBreaks: meta.systems.slice(1), partial: true }).mei);
    expect(tk.getPageCount()).toBe(1);
    expect(pageMetaOf(tk.renderToSVG(1))!.systems).toEqual(meta.systems);
  });
});
