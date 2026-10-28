import { describe, it, expect } from 'vitest';
import { createPianoScore } from '../src/model/factory';
import { writeAt, setEventDuration, deleteEvent, deleteNote, addPitchToEvent, insertMeasures, deleteMeasures, appendMeasures, setTimeSig, copyRange, pasteClip, voiceFillsMeasure } from '../src/model/edit';
import { frac, ZERO, eq } from '../src/model/fraction';
import { durToFrac, decomposeAligned, fracToDuration } from '../src/model/duration';
import { measureLen, getStaff, staffCount, timeSigAt } from '../src/model/query';
import { serializeProject, parseProject } from '../src/model/serialize';
import { edit } from './helpers';
import type { Score, ChordEvent } from '../src/model/types';
import type { Pitch } from '../src/model/pitch';

const C5: Pitch = { step: 'C', octave: 5, alter: 0 };
const B4: Pitch = { step: 'B', octave: 4, alter: 0 };
const chord = (...p: Pitch[]) => ({ type: 'chord' as const, notes: p });

function assertInvariant(score: Score) {
  for (let s = 0; s < staffCount(score); s++) {
    const st = getStaff(score, s);
    expect(st.measures.length).toBe(score.measures.length);
    st.measures.forEach((sm, m) => {
      expect(sm.voices[0].length).toBeGreaterThan(0);
      sm.voices.forEach((v) => expect(voiceFillsMeasure(v, measureLen(score, m))).toBe(true));
    });
  }
}

describe('durations', () => {
  it('computes dotted values', () => {
    expect(durToFrac({ base: 4, dots: 1 })).toEqual(frac(3, 8));
    expect(durToFrac({ base: 8, dots: 2 })).toEqual(frac(7, 32));
    expect(fracToDuration(frac(3, 4))).toEqual({ base: 2, dots: 1 });
    expect(fracToDuration(frac(5, 8))).toBeNull();
  });
  it('decomposes rests on beat boundaries', () => {
    expect(decomposeAligned(frac(1, 4), frac(3, 4)).map((d) => d.base)).toEqual([4, 2]);
    expect(decomposeAligned(frac(1, 8), frac(7, 8)).map((d) => d.base)).toEqual([8, 4, 2]);
  });
});

describe('note entry (overwrite semantics)', () => {
  it('writes notes over rests and keeps measures full', () => {
    let s = createPianoScore({ measures: 2 });
    s = edit(s, (d) => {
      writeAt(d, 0, 0, 0, ZERO, frac(1, 4), chord(C5));
      writeAt(d, 0, 0, 0, frac(1, 4), frac(1, 8), chord(B4));
    });
    const v = getStaff(s, 0).measures[0].voices[0];
    expect(v[0].type).toBe('chord');
    expect(v[1].type).toBe('chord');
    expect(v[1].dur).toEqual({ base: 8, dots: 0 });
    assertInvariant(s);
  });

  it('splits notes across the barline with a tie', () => {
    let s = createPianoScore({ measures: 2 });
    s = edit(s, (d) => {
      writeAt(d, 0, 0, 0, frac(3, 4), frac(1, 2), chord(C5));
    });
    const m0 = getStaff(s, 0).measures[0].voices[0];
    const m1 = getStaff(s, 0).measures[1].voices[0];
    const last = m0[m0.length - 1] as ChordEvent;
    expect(last.type).toBe('chord');
    expect(last.notes[0].tie).toBe(true);
    expect(m1[0].type).toBe('chord');
    expect((m1[0] as ChordEvent).notes[0].tie).toBeUndefined();
    assertInvariant(s);
  });

  it('appends measures when writing past the end', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => {
      writeAt(d, 1, 0, 0, frac(1, 2), frac(1, 1), chord({ step: 'C', octave: 3, alter: 0 }));
    });
    expect(s.measures.length).toBe(2);
    assertInvariant(s);
  });

  it('changes durations, padding with rests or overwriting', () => {
    let s = createPianoScore({ measures: 2 });
    let id = '';
    s = edit(s, (d) => {
      id = writeAt(d, 0, 0, 0, ZERO, frac(1, 2), chord(C5)).firstId;
    });
    s = edit(s, (d) => void setEventDuration(d, 0, 0, 0, id, { base: 8, dots: 0 }));
    expect(getStaff(s, 0).measures[0].voices[0][0].dur).toEqual({ base: 8, dots: 0 });
    assertInvariant(s);
    s = edit(s, (d) => void setEventDuration(d, 0, 0, 0, id, { base: 1, dots: 1 }));
    expect(getStaff(s, 0).measures[0].voices[0][0].id).toBe(id);
    expect(getStaff(s, 0).measures[1].voices[0][0].type).toBe('chord');
    assertInvariant(s);
  });

  it('builds chords and deletes notes', () => {
    let s = createPianoScore({ measures: 1 });
    let id = '';
    s = edit(s, (d) => {
      id = writeAt(d, 0, 0, 0, ZERO, frac(1, 4), chord(C5)).firstId;
      addPitchToEvent(d, 0, 0, 0, id, { step: 'E', octave: 5, alter: 0 });
      addPitchToEvent(d, 0, 0, 0, id, { step: 'G', octave: 4, alter: 0 });
    });
    const ev = getStaff(s, 0).measures[0].voices[0][0] as ChordEvent;
    expect(ev.notes.map((n) => n.step + n.octave)).toEqual(['G4', 'C5', 'E5']);
    s = edit(s, (d) => void deleteNote(d, 0, 0, 0, id, ev.notes[0].id));
    expect((getStaff(s, 0).measures[0].voices[0][0] as ChordEvent).notes.length).toBe(2);
    s = edit(s, (d) => void deleteEvent(d, 0, 0, 0, id));
    expect(getStaff(s, 0).measures[0].voices[0][0].type).toBe('rest');
    assertInvariant(s);
  });

  it('supports independent secondary voices', () => {
    let s = createPianoScore({ measures: 1 });
    s = edit(s, (d) => void writeAt(d, 0, 0, 1, frac(1, 4), frac(1, 4), chord({ step: 'E', octave: 4, alter: 0 })));
    const v2 = getStaff(s, 0).measures[0].voices[1];
    expect(v2.map((e) => e.type)).toEqual(['rest', 'chord', 'rest']);
    assertInvariant(s);
  });
});

describe('measures and signatures', () => {
  it('inserts and deletes measures on all staves', () => {
    let s = createPianoScore({ measures: 4 });
    s = edit(s, (d) => {
      insertMeasures(d, 2, 3);
      appendMeasures(d, 1);
    });
    expect(s.measures.length).toBe(8);
    assertInvariant(s);
    s = edit(s, (d) => void deleteMeasures(d, 0, 2));
    expect(s.measures.length).toBe(5);
    expect(s.measures[0].timeSig).toBeDefined();
    assertInvariant(s);
  });

  it('re-bars music when the time signature changes', () => {
    let s = createPianoScore({ measures: 2 });
    s = edit(s, (d) => {
      for (let i = 0; i < 8; i++) writeAt(d, 0, Math.floor(i / 4), 0, frac(i % 4, 4), frac(1, 4), chord({ step: 'C', octave: 4 + (i % 2), alter: 0 }));
    });
    s = edit(s, (d) => setTimeSig(d, 0, { count: 3, unit: 4 }));
    expect(s.measures.length).toBe(3);
    expect(timeSigAt(s, 2)).toEqual({ count: 3, unit: 4 });
    const notes = getStaff(s, 0).measures.flatMap((m) => m.voices[0]).filter((e) => e.type === 'chord');
    expect(notes.length).toBe(8);
    assertInvariant(s);
  });

  it('copies and pastes measures', () => {
    let s = createPianoScore({ measures: 4 });
    s = edit(s, (d) => {
      writeAt(d, 0, 0, 0, ZERO, frac(3, 8), chord(C5));
      writeAt(d, 1, 0, 0, ZERO, frac(1, 2), chord({ step: 'C', octave: 3, alter: 0 }));
    });
    const clip = copyRange(s, 0, 1, 0, 0);
    s = edit(s, (d) => void pasteClip(d, clip, 0, 3));
    const pasted = getStaff(s, 0).measures[3].voices[0][0];
    expect(pasted.type).toBe('chord');
    expect(eq(durToFrac(pasted.dur), frac(3, 8))).toBe(true);
    expect(getStaff(s, 1).measures[3].voices[0][0].type).toBe('chord');
    assertInvariant(s);
  });
});

describe('project files', () => {
  it('round-trips through .nfg serialization', () => {
    let s = createPianoScore({ title: 'Соната', measures: 3 });
    s = edit(s, (d) => {
      writeAt(d, 0, 0, 0, ZERO, frac(1, 4), chord({ step: 'F', octave: 5, alter: 1 }));
    });
    const loaded = parseProject(serializeProject(s));
    expect(loaded.errors).toEqual([]);
    expect(loaded.repaired).toEqual([]);
    expect(loaded.score).toEqual(s);
  });

  it('rejects foreign or corrupt files', () => {
    expect(parseProject('not json').score).toBeNull();
    expect(parseProject('{"format":"other"}').score).toBeNull();
  });

  it('repairs measures with wrong total duration', () => {
    const s = createPianoScore({ measures: 1 });
    const broken = structuredClone(s);
    broken.parts[0].staves[0].measures[0].voices[0] = [{ id: 'rx1', type: 'rest', dur: { base: 4, dots: 0 } }];
    const res = parseProject(JSON.stringify({ format: 'noteforge', formatVersion: 1, app: 'x', savedAt: '', score: broken }));
    expect(res.score).not.toBeNull();
    expect(res.repaired.length).toBeGreaterThan(0);
    assertInvariant(res.score!);
  });
});
