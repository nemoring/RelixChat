import { describe, it, expect } from 'vitest';
import { createPianoScore } from '../src/model/factory';
import * as E from '../src/model/edit';
import { frac, ZERO, eq } from '../src/model/fraction';
import { eventLen } from '../src/model/duration';
import { getStaff, measureLen, staffCount, voiceLength, clefAt } from '../src/model/query';
import { perform, unroll } from '../src/playback/perform';
import { scoreToMei } from '../src/engrave/mei';
import { serializeProject, parseProject } from '../src/model/serialize';
import { edit, loadVerovio } from './helpers';
import type { ChordEvent, Score, Step } from '../src/model/types';

const P = (step: Step, octave: number, alter = 0) => ({ step, octave, alter });
const chord = (...notes: ReturnType<typeof P>[]) => ({ type: 'chord' as const, notes });

function full(score: Score) {
  for (let s = 0; s < staffCount(score); s++)
    getStaff(score, s).measures.forEach((sm, m) => sm.voices.forEach((v) => v.length && expect(eq(voiceLength(v), measureLen(score, m))).toBe(true)));
}

describe('tuplets', () => {
  it('creates a triplet and edits inside it in written values', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => {
      const r = E.createTuplet(d, 0, 0, 0, ZERO, frac(1, 4), 3);
      expect(typeof r).toBe('object');
      E.writeAt(d, 0, 0, 0, ZERO, frac(1, 8), chord(P('C', 5)));
      E.writeAt(d, 0, 0, 0, frac(1, 12), frac(1, 8), chord(P('D', 5)));
      E.writeAt(d, 0, 0, 0, frac(1, 6), frac(1, 8), chord(P('E', 5)));
    });
    const v = getStaff(s, 0).measures[0].voices[0];
    expect(v.slice(0, 3).map((e) => (e as ChordEvent).notes?.[0].step)).toEqual(['C', 'D', 'E']);
    expect(v.slice(0, 3).every((e) => e.tuplet?.num === 3 && e.tuplet?.den === 2)).toBe(true);
    expect(eq(eventLen(v[0]), frac(1, 12))).toBe(true);
    full(s);
    const p = perform(s);
    expect(p.notes.map((n) => Math.round(n.start * 1000))).toEqual([0, 200, 400]); // 100 bpm: quarter = 0.6 s
  });

  it('removes a whole tuplet when it is overwritten from outside', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => {
      E.createTuplet(d, 0, 0, 0, frac(1, 4), frac(1, 4), 3);
      E.writeAt(d, 0, 0, 0, ZERO, frac(1, 2), chord(P('C', 5)));
    });
    const v = getStaff(s, 0).measures[0].voices[0];
    expect(v.some((e) => e.tuplet)).toBe(false);
    full(s);
  });

  it('keeps quintuplets through re-barring', () => {
    let s = createPianoScore({ measures: 2 });
    s = edit(s, (d) => {
      E.createTuplet(d, 0, 0, 0, ZERO, frac(1, 4), 5);
      E.writeAt(d, 0, 0, 0, ZERO, frac(1, 16), chord(P('G', 5)));
      E.setTimeSig(d, 0, { count: 3, unit: 4 });
    });
    const v = getStaff(s, 0).measures[0].voices[0];
    expect(v.filter((e) => e.tuplet?.num === 5).length).toBe(5);
    full(s);
  });
});

describe('grace notes and marks', () => {
  it('grace notes take no time and are played before the beat note', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => {
      const r = E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), chord(P('C', 5)));
      E.addGrace(d, 0, 0, 0, r.firstId, 'acciaccatura');
    });
    full(s);
    const v = getStaff(s, 0).measures[0].voices[0];
    expect((v[0] as ChordEvent).grace).toBe('acciaccatura');
    const p = perform(s);
    expect(p.notes.length).toBe(2);
    expect(p.notes[0].end - p.notes[0].start).toBeLessThan(0.1);
  });

  it('articulations, dynamics and hairpins change velocity and length', () => {
    let s = createPianoScore({ measures: 2 });
    s = edit(s, (d) => {
      const a = E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { ...chord(P('C', 5)), attrs: { dynamic: 'p', artics: ['staccato'] } });
      E.writeAt(d, 0, 0, 0, frac(1, 4), frac(1, 4), chord(P('D', 5)));
      E.writeAt(d, 0, 0, 0, frac(1, 2), frac(1, 4), chord(P('E', 5)));
      const z = E.writeAt(d, 0, 0, 0, frac(3, 4), frac(1, 4), chord(P('F', 5)));
      E.addSpanner(d, 'cresc', a.firstId, z.firstId);
      E.writeAt(d, 0, 1, 0, ZERO, frac(1, 4), { ...chord(P('G', 5)), attrs: { dynamic: 'ff', artics: ['accent'] } });
    });
    const p = perform(s);
    const [c, dn, e, f, g] = p.notes;
    expect(c.vel).toBe(48);
    expect(c.end - c.start).toBeCloseTo(0.3);
    expect(dn.vel).toBeGreaterThan(c.vel);
    expect(e.vel).toBeGreaterThan(dn.vel);
    expect(f.vel).toBeGreaterThan(e.vel);
    expect(g.vel).toBe(124);
  });

  it('fermata holds the music, the sustain pedal extends notes', () => {
    let s = createPianoScore({ measures: 2, bpm: 60 });
    s = edit(s, (d) => {
      E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { ...chord(P('C', 5)), attrs: { fermata: true } });
      const a = E.writeAt(d, 1, 0, 0, ZERO, frac(1, 4), chord(P('C', 3)));
      const b = E.writeAt(d, 1, 0, 0, frac(3, 4), frac(1, 4), chord(P('G', 2)));
      E.addSpanner(d, 'pedal', a.firstId, b.firstId);
    });
    const p = perform(s);
    expect(p.measures[0].end).toBeCloseTo(5); // 4 beats + 1 extra beat of fermata
    const lowC = p.notes.find((n) => n.key === 48)!;
    expect(lowC.end).toBeCloseTo(5); // held by the pedal to the end of the bar
  });

  it('trills alternate with the upper neighbour in the key', () => {
    let s = createPianoScore({ measures: 1, keySig: 2 });
    s = edit(s, (d) => void E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { ...chord(P('E', 5)), attrs: { ornament: 'trill' } }));
    const keys = perform(s).notes.map((n) => n.key);
    expect(keys.slice(0, 4)).toEqual([76, 78, 76, 78]); // E5 – F#5 in D major
  });
});

describe('form: repeats, voltas and jumps', () => {
  it('plays repeats with first and second endings', () => {
    const s = edit(createPianoScore({ measures: 5 }), (d) => {
      E.setRepeatStart(d, 1, true);
      E.setVolta(d, 2, 2, [1]);
      E.setRepeatEnd(d, 2, 2);
      E.setVolta(d, 3, 3, [2]);
    });
    expect(unroll(s)).toEqual([0, 1, 2, 1, 3, 4]);
  });

  it('handles D.C. al Fine and D.S. al Coda', () => {
    const dc = edit(createPianoScore({ measures: 4 }), (d) => {
      E.setMarker(d, 1, 'fine');
      E.setJump(d, 3, 'DCalFine');
    });
    expect(unroll(dc)).toEqual([0, 1, 2, 3, 0, 1]);
    const ds = edit(createPianoScore({ measures: 6 }), (d) => {
      E.setMarker(d, 1, 'segno');
      E.setMarker(d, 2, 'toCoda');
      E.setJump(d, 3, 'DSalCoda');
      E.setMarker(d, 4, 'coda');
    });
    expect(unroll(ds)).toEqual([0, 1, 2, 3, 1, 2, 4, 5]);
  });

  it('applies tempo changes from their measure on', () => {
    const s = edit(createPianoScore({ measures: 2, bpm: 60 }), (d) => E.setMeasureTempo(d, 1, { bpm: 120, beatUnit: 4, beatDots: 0, text: '' }));
    const p = perform(s);
    expect(p.measures[0].end).toBeCloseTo(4);
    expect(p.measures[1].end).toBeCloseTo(6);
  });
});

describe('cross-staff, clefs, transposition, lines', () => {
  it('moves notes to the other staff for display only', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => {
      const r = E.writeAt(d, 0, 0, 0, ZERO, frac(1, 8), chord(P('C', 4)));
      const ev = getStaff(d, 0).measures[0].voices[0].find((e) => e.id === r.firstId) as ChordEvent;
      E.shiftStaff(d, 0, ev, 1);
    });
    expect(scoreToMei(s).mei).toMatch(/staff="2"/);
    expect(perform(s).notes[0].staff).toBe(0);
  });

  it('changes clef mid-score', () => {
    const s = edit(createPianoScore({ measures: 3 }), (d) => E.setClef(d, 1, 'treble', 2));
    expect(clefAt(s, 1, 1)).toBe('bass');
    expect(clefAt(s, 1, 2)).toBe('treble');
  });

  it('transposes with correct spelling and key signature', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => {
      E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), chord(P('E', 4), P('G', 4), P('B', 4)));
      E.transposeRange(d, [0, 1], 0, 0, { steps: 1, semitones: 2 }, true); // major second up
    });
    const ev = getStaff(s, 0).measures[0].voices[0][0] as ChordEvent;
    expect(ev.notes.map((n) => `${n.step}${n.alter === 1 ? '#' : ''}${n.octave}`)).toEqual(['F#4', 'A4', 'C#5']);
    expect(s.measures[0].keySig).toBe(2);
  });

  it('round-trips all stage-3 data through .nfg', () => {
    let s = createPianoScore({ measures: 3 });
    s = edit(s, (d) => {
      const a = E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { ...chord(P('C', 5)), attrs: { line: d.lines[0].id, dynamic: 'mf', ornament: 'turn' } });
      E.createTuplet(d, 0, 1, 0, ZERO, frac(1, 2), 3);
      E.addSpanner(d, 'slur', a.firstId, a.firstId);
      E.setRepeatEnd(d, 2, 3);
      E.setClef(d, 1, 'treble', 1);
    });
    const r = parseProject(serializeProject(s));
    expect(r.errors).toEqual([]);
    expect(r.repaired).toEqual([]);
    expect(r.score).toEqual(s);
  });

  it('engraves everything without Verovio warnings', async () => {
    const tk = await loadVerovio();
    let s = createPianoScore({ measures: 4 });
    s = edit(s, (d) => {
      const a = E.writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { ...chord(P('C', 5)), attrs: { dynamic: 'p', artics: ['tenuto'], fermata: true } });
      const b = E.writeAt(d, 0, 0, 0, frac(1, 4), frac(1, 4), { ...chord(P('E', 5), P('G', 5)), attrs: { ornament: 'trill', stem: 'down' } });
      E.addGrace(d, 0, 0, 0, b.firstId, 'appoggiatura');
      E.addSpanner(d, 'slur', a.firstId, b.firstId);
      E.addSpanner(d, 'dim', a.firstId, b.firstId);
      E.addSpanner(d, 'ottava', a.firstId, b.firstId, 15);
      E.addSpanner(d, 'pedal', a.firstId, b.firstId);
      E.createTuplet(d, 0, 1, 0, ZERO, frac(1, 2), 3);
      E.setVolta(d, 2, 2, [1, 2]);
      E.setRepeatEnd(d, 2, 3);
      E.setMarker(d, 3, 'coda');
      E.setJump(d, 3, 'DS');
      d.measures[1].rehearsal = 'A';
      d.measures[2].section = { title: 'II. Andante', newPage: false };
    });
    expect(tk.loadData(scoreToMei(s).mei)).toBeTruthy();
    expect(tk.getLog()).toBe('');
  });
});
