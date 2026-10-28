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

export type Articulation = 'staccato' | 'staccatissimo' | 'tenuto' | 'accent' | 'marcato';
export const ARTICULATIONS: Articulation[] = ['staccato', 'staccatissimo', 'tenuto', 'accent', 'marcato'];

export type Ornament = 'trill' | 'mordent' | 'invertedMordent' | 'turn' | 'invertedTurn';
export const ORNAMENTS: Ornament[] = ['trill', 'mordent', 'invertedMordent', 'turn', 'invertedTurn'];

export type Dynamic = 'ppp' | 'pp' | 'p' | 'mp' | 'mf' | 'f' | 'ff' | 'fff' | 'sf' | 'sfz' | 'fp' | 'rfz';
export const DYNAMICS: Dynamic[] = ['ppp', 'pp', 'p', 'mp', 'mf', 'f', 'ff', 'fff', 'sf', 'sfz', 'fp', 'rfz'];

/** Rhythmic group: `num` notes in the time of `den` (triplet = 3:2, quintuplet = 5:4). */
export interface Tuplet {
  /** Shared by all members of one group. */
  id: string;
  num: number;
  den: number;
}

interface EventBase {
  id: string;
  dur: Duration;
  tuplet?: Tuplet;
  fermata?: boolean;
}

export interface ChordEvent extends EventBase {
  type: 'chord';
  /** One or more notes sounding together (sorted low → high). */
  notes: Note[];
  artics?: Articulation[];
  ornament?: Ornament;
  /** Grace note: takes no metric time and belongs to the following event. */
  grace?: 'acciaccatura' | 'appoggiatura';
  /** Dynamic marking starting at this event (applies to the whole part). */
  dynamic?: Dynamic;
  /** Cross-staff notation: drawn on the staff `staffShift` below (+1) / above (-1). */
  staffShift?: number;
  stem?: 'up' | 'down';
  /** Manual beaming: start a new beam, join with the previous event, or no beam. */
  beam?: 'break' | 'join' | 'none';
  /** Melody line this event belongs to (see Score.lines). */
  line?: string;
}

export interface RestEvent extends EventBase {
  type: 'rest';
}

export type VoiceEvent = ChordEvent | RestEvent;

export const MAX_VOICES = 4;

export interface StaffMeasure {
  /** Index = voice number - 1. An empty array means the voice is unused in this measure. */
  voices: VoiceEvent[][];
  /** Clef change at the start of this measure. */
  clef?: ClefKind;
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

export type JumpKind = 'DC' | 'DCalFine' | 'DCalCoda' | 'DS' | 'DSalFine' | 'DSalCoda';
export type MarkerKind = 'segno' | 'coda' | 'fine' | 'toCoda';

export interface MeasureInfo {
  id: string;
  /** Time signature change starting at this measure (always set on measure 1). */
  timeSig?: TimeSig;
  /** Key signature change (circle of fifths: -7 … +7) starting at this measure. */
  keySig?: number;
  /** Tempo change at the start of this measure. */
  tempo?: Tempo;
  /** Start repeat barline. */
  repeatStart?: boolean;
  /** End repeat barline; the value is how many times the section is played (2 = one repeat). */
  repeatEnd?: number;
  /** Volta (1st/2nd ending) bracket over this measure; consecutive measures with the same id form one bracket. */
  volta?: { id: string; numbers: number[] };
  /** Navigation marker in this measure. */
  marker?: MarkerKind;
  /** Jump instruction at the end of this measure. */
  jump?: JumpKind;
  /** Right barline style (repeat barlines take precedence). */
  barline?: 'double' | 'final';
  /** Start of a movement / section of the work. */
  section?: { title: string; newPage: boolean };
  /** Rehearsal mark text (A, B, …). */
  rehearsal?: string;
  /** Forced system or page break before this measure. */
  breakBefore?: 'system' | 'page';
}

export type SpannerType = 'slur' | 'cresc' | 'dim' | 'pedal' | 'ottava';

/** Line-like markings anchored to a start and an end event. */
export interface Spanner {
  id: string;
  type: SpannerType;
  /** Event id where the spanner starts (inclusive). */
  start: string;
  /** Event id where the spanner ends (inclusive). */
  end: string;
  /** Octave line: +8/+15 above (8va/15ma), -8/-15 below (8vb/15mb). */
  ottava?: number;
}

/** A melodic line that may wander between hands, voices and staves. */
export interface MelodyLine {
  id: string;
  name: string;
  color: string;
}

export interface Bookmark {
  id: string;
  name: string;
  measure: number;
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
  /** Fixed number of measures per system (0 = automatic). */
  measuresPerSystem: number;
  /** Minimal space between staves / systems (Verovio units, defaults 12 / 6). */
  staffSpacing: number;
  systemSpacing: number;
  showPageNumbers: boolean;
  showHeader: boolean;
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
  spanners: Spanner[];
  lines: MelodyLine[];
  bookmarks: Bookmark[];
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
