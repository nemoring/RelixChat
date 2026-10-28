import type { ClefKind, Note, Step } from './types';
import { STEPS } from './types';

const STEP_SEMITONES: Record<Step, number> = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };

export interface Pitch {
  step: Step;
  octave: number;
  alter: number;
}

/** MIDI note number (C4 = 60). */
export function midiOf(p: Pitch): number {
  return (p.octave + 1) * 12 + STEP_SEMITONES[p.step] + p.alter;
}

/** Diatonic index: octave * 7 + step index (C4 = 28). */
export function diatonicOf(p: { step: Step; octave: number }): number {
  return p.octave * 7 + STEPS.indexOf(p.step);
}

export function fromDiatonic(d: number): { step: Step; octave: number } {
  const octave = Math.floor(d / 7);
  return { step: STEPS[((d % 7) + 7) % 7], octave };
}

const SHARP_SPELLING: [Step, number][] = [
  ['C', 0], ['C', 1], ['D', 0], ['D', 1], ['E', 0], ['F', 0], ['F', 1], ['G', 0], ['G', 1], ['A', 0], ['A', 1], ['B', 0],
];
const FLAT_SPELLING: [Step, number][] = [
  ['C', 0], ['D', -1], ['D', 0], ['E', -1], ['E', 0], ['F', 0], ['G', -1], ['G', 0], ['A', -1], ['A', 0], ['B', -1], ['B', 0],
];

export function pitchFromMidi(midi: number, preferFlats: boolean): Pitch {
  const pc = ((midi % 12) + 12) % 12;
  const octave = Math.floor(midi / 12) - 1;
  const [step, alter] = (preferFlats ? FLAT_SPELLING : SHARP_SPELLING)[pc];
  return { step, octave, alter };
}

/** Order of sharps/flats in key signatures. */
const SHARP_ORDER: Step[] = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
const FLAT_ORDER: Step[] = ['B', 'E', 'A', 'D', 'G', 'C', 'F'];

/** Alteration implied by the key signature for a step. */
export function keyAlter(fifths: number, step: Step): number {
  if (fifths > 0) return SHARP_ORDER.slice(0, fifths).includes(step) ? 1 : 0;
  if (fifths < 0) return FLAT_ORDER.slice(0, -fifths).includes(step) ? -1 : 0;
  return 0;
}

export function keyName(fifths: number): string {
  const major = ['C♭', 'G♭', 'D♭', 'A♭', 'E♭', 'B♭', 'F', 'C', 'G', 'D', 'A', 'E', 'B', 'F♯', 'C♯'];
  const minor = ['a♭', 'e♭', 'b♭', 'f', 'c', 'g', 'd', 'a', 'e', 'b', 'f♯', 'c♯', 'g♯', 'd♯', 'a♯'];
  return `${major[fifths + 7]} / ${minor[fifths + 7]}`;
}

/** Diatonic index of the bottom staff line for a clef. */
export function clefBottomLine(clef: ClefKind): number {
  switch (clef) {
    case 'treble':
      return diatonicOf({ step: 'E', octave: 4 });
    case 'treble8vb':
      return diatonicOf({ step: 'E', octave: 3 });
    case 'bass':
      return diatonicOf({ step: 'G', octave: 2 });
    case 'alto':
      return diatonicOf({ step: 'F', octave: 3 });
    case 'tenor':
      return diatonicOf({ step: 'D', octave: 3 });
    case 'percussion':
      return diatonicOf({ step: 'E', octave: 4 });
  }
}

/** Middle-line pitch, used as the default reference for letter entry. */
export function clefMiddle(clef: ClefKind): number {
  return clefBottomLine(clef) + 4;
}

/** Chooses the octave of `step` closest to the reference diatonic position. */
export function nearestOctave(step: Step, refDiatonic: number): number {
  const si = STEPS.indexOf(step);
  let best = 4;
  let bestDist = Infinity;
  for (let oct = 0; oct <= 8; oct++) {
    const dist = Math.abs(oct * 7 + si - refDiatonic);
    if (dist < bestDist) {
      bestDist = dist;
      best = oct;
    }
  }
  return best;
}

export function samePitch(a: Pitch, b: Pitch): boolean {
  return a.step === b.step && a.octave === b.octave && a.alter === b.alter;
}

export function pitchName(p: Pitch): string {
  const acc: Record<number, string> = { [-2]: '𝄫', [-1]: '♭', 0: '', 1: '♯', 2: '𝄪' };
  return `${p.step}${acc[p.alter] ?? ''}${p.octave}`;
}

export function sortNotes(notes: Note[]): void {
  notes.sort((a, b) => midiOf(a) - midiOf(b) || diatonicOf(a) - diatonicOf(b));
}

export const MIDI_MIN = 12; // C0
export const MIDI_MAX = 120; // C9
