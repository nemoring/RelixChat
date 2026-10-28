import type { ChordEvent, Note, RestEvent, Score, StaffMeasure, TimeSig, Duration } from './types';
import type { Frac } from './fraction';
import { ZERO } from './fraction';
import { decomposeAligned, fracToDuration } from './duration';
import { newId } from './ids';
import type { Pitch } from './pitch';

export function makeRest(dur: Duration): RestEvent {
  return { id: newId('r'), type: 'rest', dur: { ...dur } };
}

export function makeNote(p: Pitch, tie = false): Note {
  const n: Note = { id: newId('n'), step: p.step, octave: p.octave, alter: p.alter };
  if (tie) n.tie = true;
  return n;
}

export function makeChord(dur: Duration, pitches: (Pitch & { tie?: boolean })[]): ChordEvent {
  return { id: newId('c'), type: 'chord', dur: { ...dur }, notes: pitches.map((p) => makeNote(p, !!p.tie)) };
}

/** Rests filling [start, start+len) of a measure, aligned to beat values. */
export function restsFor(start: Frac, len: Frac): RestEvent[] {
  return decomposeAligned(start, len).map(makeRest);
}

/** Rests for a whole measure: one (dotted) rest when possible, aligned rests otherwise. */
export function measureRests(len: Frac): RestEvent[] {
  const single = fracToDuration(len, 2);
  return single ? [makeRest(single)] : restsFor(ZERO, len);
}

export function emptyStaffMeasure(len: Frac): StaffMeasure {
  return { voices: [measureRests(len), [], [], []] };
}

export interface NewScoreOptions {
  title?: string;
  composer?: string;
  timeSig?: TimeSig;
  keySig?: number;
  measures?: number;
  bpm?: number;
}

/** A new two-staff piano score filled with rests. */
export function createPianoScore(opts: NewScoreOptions = {}): Score {
  const ts = opts.timeSig ?? { count: 4, unit: 4 };
  const count = Math.max(1, opts.measures ?? 16);
  const len = { n: ts.count, d: ts.unit };
  const measures = Array.from({ length: count }, (_, i) =>
    i === 0 ? { id: newId('m'), timeSig: { ...ts }, keySig: opts.keySig ?? 0 } : { id: newId('m') },
  );
  const staff = (clef: 'treble' | 'bass') => ({
    id: newId('s'),
    clef,
    measures: Array.from({ length: count }, () => emptyStaffMeasure(len)),
  });
  return {
    meta: {
      title: opts.title ?? 'Без названия',
      subtitle: '',
      composer: opts.composer ?? '',
      arranger: '',
      lyricist: '',
      copyright: '',
    },
    tempo: { bpm: opts.bpm ?? 100, beatUnit: 4, beatDots: 0, text: '' },
    layout: {
      size: 'A4',
      orientation: 'portrait',
      margins: { top: 15, bottom: 15, left: 15, right: 15 },
      staffScale: 100,
    },
    measures,
    parts: [
      {
        id: newId('p'),
        name: 'Фортепиано',
        abbreviation: 'Фп.',
        program: 0,
        staves: [staff('treble'), staff('bass')],
      },
    ],
  };
}
