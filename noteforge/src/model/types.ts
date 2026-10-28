/**
 * NoteForge music model.
 *
 * The model is the single source of truth: engraving (MEI → Verovio), playback,
 * MIDI/MusicXML export and the .nfg project file are all derived from it.
 *
 * Time is measured in whole notes as exact rationals (see fraction.ts), so a
 * quarter note is 1/4 and a dotted eighth is 3/16.
 *
 * Structure:
 *   Score
 *    ├─ measures: MeasureInfo[]        global bar data (time/key signature changes)
 *    └─ parts: Part[]
 *         └─ staves: Staff[]
 *              └─ measures: StaffMeasure[]   (parallel to Score.measures)
 *                   └─ voices: VoiceEvent[][] (up to 4 independent voices)
 *
 * Invariant: every non-empty voice exactly fills its measure (rests are explicit
 * events). Voice 1 (index 0) is never empty.
 */

export type Step = 'C' | 'D' | 'E' | 'F' | 'G' | 'A' | 'B';
export const STEPS: Step[] = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

/** Note value denominator: 1 = whole, 2 = half, … 64 = sixty-fourth. */
export type DurBase = 1 | 2 | 4 | 8 | 16 | 32 | 64;
export const DUR_BASES: DurBase[] = [1, 2, 4, 8, 16, 32, 64];

export interface Duration {
  base: DurBase;
  /** Augmentation dots, 0–3. */
  dots: number;
}

export interface Note {
  id: string;
  step: Step;
  octave: number;
  /** Chromatic alteration in semitones: -2 (double flat) … +2 (double sharp). */
  alter: number;
  /** Tied to the note of the same pitch in the next event of the same voice. */
  tie?: boolean;
}

export interface ChordEvent {
  id: string;
  type: 'chord';
  dur: Duration;
  /** One or more notes sounding together (sorted low → high). */
  notes: Note[];
}

export interface RestEvent {
  id: string;
  type: 'rest';
  dur: Duration;
}

export type VoiceEvent = ChordEvent | RestEvent;

export const MAX_VOICES = 4;

export interface StaffMeasure {
  /** Index = voice number - 1. An empty array means the voice is unused in this measure. */
  voices: VoiceEvent[][];
}

export type ClefKind = 'treble' | 'bass' | 'alto' | 'tenor' | 'treble8vb' | 'percussion';

export interface Staff {
  id: string;
  /** Initial clef of the staff. */
  clef: ClefKind;
  measures: StaffMeasure[];
}

export interface Part {
  id: string;
  name: string;
  abbreviation: string;
  /** General MIDI program (0 = Acoustic Grand Piano). */
  program: number;
  staves: Staff[];
}

export interface TimeSig {
  count: number;
  unit: number;
  /** Display as C / ¢ symbol where applicable. */
  symbol?: 'common' | 'cut';
}

export interface MeasureInfo {
  id: string;
  /** Time signature change starting at this measure (always set on measure 1). */
  timeSig?: TimeSig;
  /** Key signature change (circle of fifths: -7 … +7) starting at this measure. */
  keySig?: number;
}

export interface ScoreMeta {
  title: string;
  subtitle: string;
  composer: string;
  arranger: string;
  lyricist: string;
  copyright: string;
}

export type PageSize = 'A4' | 'A3' | 'Letter';

export interface PageLayout {
  size: PageSize;
  orientation: 'portrait' | 'landscape';
  /** Margins in millimetres. */
  margins: { top: number; bottom: number; left: number; right: number };
  /** Engraving scale in percent (staff size). */
  staffScale: number;
}

export interface Tempo {
  bpm: number;
  /** Beat unit denominator (4 = quarter). */
  beatUnit: number;
  beatDots: number;
  /** Optional verbal marking, e.g. "Allegro". */
  text: string;
}

export interface Score {
  meta: ScoreMeta;
  tempo: Tempo;
  layout: PageLayout;
  measures: MeasureInfo[];
  parts: Part[];
}

/** File envelope of a .nfg project. */
export interface ProjectFile {
  format: 'noteforge';
  formatVersion: number;
  app: string;
  savedAt: string;
  score: Score;
}

export const FORMAT_VERSION = 1;
