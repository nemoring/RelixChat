/**
 * MusicXML (partwise) import → NoteForge model.
 *
 * Supported: parts with several staves, up to 4 voices per staff (MusicXML
 * voices are mapped by their home staff), chords, rests, dots, ties, tuplets
 * (time-modification), grace notes, cross-staff notes, slurs, articulations,
 * fermatas, ornaments, dynamics, wedges, pedal, octave shifts, key/time/clef
 * changes, repeats, endings, segno/coda/fine/D.C./D.S., tempo, rehearsal
 * marks, note colours (→ melody lines) and pickup measures. Anything else is
 * skipped and reported in `warnings`.
 */
import type { ChordEvent, ClefKind, Duration, DurBase, Dynamic, JumpKind, MeasureInfo, Note, Ornament, Part, Score, Spanner, Staff, Step, TimeSig, Tuplet, VoiceEvent, Articulation } from '../model/types';
import { DYNAMICS, MAX_VOICES } from '../model/types';
import { Frac, frac, add, sub, lt, le, cmp, ZERO, toNumber, mul } from '../model/fraction';
import { durToFrac, eventLen, fracToDuration, measureLength } from '../model/duration';
import { createPianoScore, restsFor, measureRests } from '../model/factory';
import { newId } from '../model/ids';
import { validateScore } from '../model/serialize';
import { parseXml, child, children, text, num, type XmlNode } from './xml';

const TYPES: Record<string, number> = { whole: 1, half: 2, quarter: 4, eighth: 8, '16th': 16, '32nd': 32, '64th': 64 };
const ARTIC: Record<string, Articulation> = { staccato: 'staccato', staccatissimo: 'staccatissimo', spiccato: 'staccatissimo', tenuto: 'tenuto', accent: 'accent', 'strong-accent': 'marcato' };
const ORN: Record<string, Ornament> = { 'trill-mark': 'trill', mordent: 'mordent', 'inverted-mordent': 'invertedMordent', turn: 'turn', 'inverted-turn': 'invertedTurn', 'delayed-turn': 'turn' };

interface XNote {
  staff: number;
  voice: string;
  start: number;
  dur: number;
  grace?: 'acciaccatura' | 'appoggiatura';
  chord: boolean;
  rest: boolean;
  measureRest: boolean;
  pitch?: { step: Step; octave: number; alter: number };
  type?: number;
  dots: number;
  tm?: { act: number; norm: number };
  tieStart: boolean;
  slurs: { type: string; num: string }[];
  tupletStart: boolean;
  tupletStop: boolean;
  artics: Articulation[];
  ornament?: Ornament;
  fermata: boolean;
  stem?: 'up' | 'down';
  color?: string;
}

interface XDir {
  staff: number;
  pos: number;
  kind: 'dynamic' | 'wedge' | 'pedal' | 'octave';
  value: string;
  num: string;
  size?: number;
}

interface XMeasure {
  divisions: number;
  time?: TimeSig;
  key?: number;
  clefs: Map<number, ClefKind>;
  notes: XNote[];
  dirs: XDir[];
  length: number;
  info: Partial<MeasureInfo>;
  ending?: { numbers: number[]; start: boolean };
  tempo?: { bpm: number; text: string; beatUnit: number; beatDots: number };
}

export interface ImportResult {
  score: Score;
  warnings: string[];
}

function clefOf(sign: string, line: number, oct: number): ClefKind {
  if (sign === 'F') return 'bass';
  if (sign === 'C') return line === 4 ? 'tenor' : 'alto';
  if (sign === 'percussion') return 'percussion';
  return oct === -1 ? 'treble8vb' : 'treble';
}

export function musicXmlToScore(xml: string): ImportResult {
  const warnings: string[] = [];
  const warn = (w: string) => {
    if (!warnings.includes(w)) warnings.push(w);
  };
  const doc = parseXml(xml);
  if (child(doc, 'score-timewise')) throw new Error('Формат score-timewise не поддерживается — сохраните MusicXML как partwise.');
  const root = child(doc, 'score-partwise');
  if (!root) throw new Error('Это не файл MusicXML (нет score-partwise).');

  const base = createPianoScore({ measures: 1 });
  base.meta.title = text(child(root, 'work'), 'work-title') || text(root, 'movement-title') || 'Импорт MusicXML';
  const ident = child(root, 'identification');
  for (const c of children(ident, 'creator')) {
    const t = c.attrs.type;
    if (t === 'composer') base.meta.composer = text(c);
    else if (t === 'lyricist' || t === 'poet') base.meta.lyricist = text(c);
    else if (t === 'arranger') base.meta.arranger = text(c);
  }
  base.meta.copyright = text(ident, 'rights');
  for (const cr of children(root, 'credit')) if (text(cr, 'credit-type') === 'subtitle') base.meta.subtitle = text(cr, 'credit-words');
  base.lines = [];

  // Part list.
  const partInfo = new Map<string, { name: string; abbr: string; program: number }>();
  for (const sp of children(child(root, 'part-list'), 'score-part')) {
    const prog = num(child(sp, 'midi-instrument'), 'midi-program', 1) - 1;
    partInfo.set(sp.attrs.id, { name: text(sp, 'part-name') || 'Партия', abbr: text(sp, 'part-abbreviation'), program: Math.max(0, Math.min(127, prog)) });
  }

  const parts = children(root, 'part');
  if (!parts.length) throw new Error('В MusicXML нет партий.');
  const parsed = parts.map((p) => parsePart(p, warn));
  const nMeasures = Math.max(...parsed.map((p) => p.measures.length));

  // Global measure data from the first part.
  const first = parsed[0];
  const measures: MeasureInfo[] = [];
  let ts: TimeSig = { count: 4, unit: 4 };
  for (let m = 0; m < nMeasures; m++) {
    const xm = first.measures[m];
    const mi: MeasureInfo = { id: newId('m'), ...(xm?.info ?? {}) };
    if (xm?.time) {
      ts = xm.time;
      mi.timeSig = { ...ts };
    }
    if (xm?.key !== undefined) mi.keySig = xm.key;
    if (xm?.tempo) {
      if (m === 0) base.tempo = { ...xm.tempo };
      else mi.tempo = { ...xm.tempo };
    }
    measures.push(mi);
  }
  // The final barline of the last measure is implicit in NoteForge.
  if (measures[nMeasures - 1].barline === 'final') delete measures[nMeasures - 1].barline;
  if (!measures[0].timeSig) measures[0].timeSig = { count: 4, unit: 4 };
  if (measures[0].keySig === undefined) measures[0].keySig = 0;
  // Pickup (anacrusis): a short first measure gets its own time signature.
  const firstLen = first.measures[0] ? first.measures[0].length / (first.measures[0].divisions * 4) : 0;
  const nominal = toNumber(measureLength(measures[0].timeSig!));
  if (firstLen > 0 && firstLen < nominal - 1e-9 && nMeasures > 1) {
    const pick = fracToSig(firstLen);
    if (pick) {
      if (!measures[1].timeSig) measures[1].timeSig = { ...measures[0].timeSig! };
      measures[0].timeSig = pick;
      warn('Затакт импортирован как отдельный такт со своим размером.');
    }
  }
  // Volta ids: consecutive measures of one ending share an id.
  let openVolta: { id: string; numbers: number[] } | null = null;
  for (let m = 0; m < nMeasures; m++) {
    const e = first.measures[m]?.ending;
    if (e?.start) openVolta = { id: newId('v'), numbers: e.numbers };
    if (openVolta) measures[m].volta = { ...openVolta, numbers: [...openVolta.numbers] };
    if (first.measures[m]?.info && (first.measures[m] as XMeasure & { endingStop?: boolean }).endingStop) openVolta = null;
  }

  const score: Score = { ...base, measures, parts: [], spanners: [], lines: [], bookmarks: [] };
  const sigs: TimeSig[] = [];
  let cur = measures[0].timeSig!;
  for (const mi of measures) {
    if (mi.timeSig) cur = mi.timeSig;
    sigs.push(cur);
  }

  const colorLines = new Map<string, string>();
  parsed.forEach((pd, pi) => {
    const info = partInfo.get(parts[pi].attrs.id) ?? { name: 'Партия', abbr: '', program: 0 };
    const staves: Staff[] = Array.from({ length: pd.staves }, (_, k) => ({ id: newId('s'), clef: pd.initialClefs.get(k + 1) ?? (k === 1 ? 'bass' : 'treble'), measures: [] }));
    const slurOpen = new Map<string, string>();
    const spanOpen = new Map<string, { type: Spanner['type']; start: string; ottava?: number }>();
    for (let m = 0; m < nMeasures; m++) {
      const xm = pd.measures[m];
      const mlen = measureLength(sigs[m]);
      const toF = (d: number) => frac(Math.round(d), (xm?.divisions ?? 1) * 4);
      const smeasures = staves.map(() => ({ voices: [[], [], [], []] as VoiceEvent[][], clef: undefined as ClefKind | undefined }));
      if (xm) {
        for (const [st, clef] of xm.clefs) if (m > 0 && smeasures[st - 1]) smeasures[st - 1].clef = clef;
        // Map MusicXML voices to (home staff, voice slot).
        const homes = new Map<string, number>();
        for (const n of xm.notes) if (!homes.has(n.voice)) homes.set(n.voice, n.staff);
        const slots = new Map<string, number>();
        const used = staves.map(() => 0);
        for (const [v, st] of homes) {
          const k = Math.min(staves.length, Math.max(1, st)) - 1;
          if (used[k] >= MAX_VOICES) {
            warn('Больше 4 голосов на нотоносце: лишние голоса пропущены.');
            continue;
          }
          slots.set(v, used[k]++);
        }
        // Build events per voice.
        for (const [v, slot] of slots) {
          const k = Math.min(staves.length, Math.max(1, homes.get(v)!)) - 1;
          const notes = xm.notes.filter((n) => n.voice === v);
          const built = buildVoice(notes, k + 1, toF, mlen, warn, colorLines);
          smeasures[k].voices[slot] = built.events;
          for (const s of built.slurs) {
            if (s.type === 'start') slurOpen.set(s.num, s.eventId);
            else if (s.type === 'stop' && slurOpen.has(s.num)) {
              score.spanners.push({ id: newId('sp'), type: 'slur', start: slurOpen.get(s.num)!, end: s.eventId });
              slurOpen.delete(s.num);
            }
          }
        }
        // Directions → events.
        for (const d of xm.dirs) {
          const k = Math.min(staves.length, Math.max(1, d.staff)) - 1;
          const t = toF(d.pos);
          const startEv = eventAtOrAfter(smeasures[k].voices, t);
          // A stop at the very start of a measure closes on the previous measure's last event.
          const prevVoices = m > 0 ? staves[k].measures[m - 1]?.voices : undefined;
          const endEv = cmp(t, ZERO) === 0 && prevVoices ? eventBefore(prevVoices, measureLength(sigs[m - 1])) : eventBefore(smeasures[k].voices, t);
          if (d.kind === 'dynamic') {
            if (startEv && startEv.type === 'chord') startEv.dynamic = d.value as Dynamic;
            else warn('Часть обозначений динамики не привязана к нотам.');
          } else {
            const key = `${d.kind}:${d.num}`;
            if (d.value === 'stop' || d.value === 'change') {
              const open = spanOpen.get(key);
              if (open && endEv) score.spanners.push({ id: newId('sp'), type: open.type, start: open.start, end: endEv.id, ...(open.ottava ? { ottava: open.ottava } : {}) });
              spanOpen.delete(key);
              if (d.value === 'change' && startEv) spanOpen.set(key, { type: 'pedal', start: startEv.id });
            } else if (startEv) {
              const type: Spanner['type'] = d.kind === 'wedge' ? (d.value === 'crescendo' ? 'cresc' : 'dim') : d.kind === 'pedal' ? 'pedal' : 'ottava';
              const ottava = d.kind === 'octave' ? (d.value === 'down' ? (d.size === 15 ? 15 : 8) : d.size === 15 ? -15 : -8) : undefined;
              spanOpen.set(key, { type, start: startEv.id, ottava });
            }
          }
        }
      }
      staves.forEach((st, k) => {
        const sm = smeasures[k];
        if (!sm.voices[0].length) sm.voices[0] = measureRests(mlen);
        st.measures.push({ voices: sm.voices, ...(sm.clef ? { clef: sm.clef } : {}) });
      });
    }
    const part: Part = { id: newId('p'), name: info.name, abbreviation: info.abbr, program: info.program, staves };
    score.parts.push(part);
  });
  // Melody lines from note colours.
  let i = 0;
  for (const [color, id] of colorLines) score.lines.push({ id, name: `Мелодия ${++i}`, color });
  if (!score.lines.length) score.lines.push({ id: newId('l'), name: 'Мелодия', color: '#d6336c' });

  const res = validateScore(score);
  if (!res.score) throw new Error(res.errors.join('\n'));
  for (const r of res.repaired) warn(r);
  return { score: res.score, warnings };
}

function fracToSig(len: number): TimeSig | null {
  for (const unit of [4, 8, 16, 2]) {
    const count = len * unit;
    if (Math.abs(count - Math.round(count)) < 1e-9 && Math.round(count) >= 1) return { count: Math.round(count), unit };
  }
  return null;
}

function parsePart(p: XmlNode, warn: (w: string) => void) {
  const measures: (XMeasure & { endingStop?: boolean })[] = [];
  let divisions = 1;
  let staves = 1;
  const initialClefs = new Map<number, ClefKind>();
  for (const [mIdx, mx] of children(p, 'measure').entries()) {
    const xm: XMeasure & { endingStop?: boolean } = { divisions, clefs: new Map(), notes: [], dirs: [], length: 0, info: {} };
    let pos = 0;
    let lastStart = 0;
    for (const el of mx.children) {
      switch (el.name) {
        case 'attributes': {
          const dv = num(el, 'divisions', 0);
          if (dv > 0) {
            if (xm.notes.length) warn('Смена divisions внутри такта не поддерживается.');
            divisions = dv;
            xm.divisions = dv;
          }
          const st = num(el, 'staves', 0);
          if (st > 0) staves = Math.min(4, st);
          const key = child(el, 'key');
          if (key && child(key, 'fifths')) xm.key = Math.max(-7, Math.min(7, num(key, 'fifths')));
          const time = child(el, 'time');
          if (time && child(time, 'beats')) {
            const beats = text(time, 'beats').split('+').reduce((a, b) => a + Number(b), 0);
            const unit = num(time, 'beat-type', 4);
            if (beats >= 1 && [1, 2, 4, 8, 16, 32].includes(unit)) xm.time = { count: beats, unit, ...(time.attrs.symbol === 'common' || time.attrs.symbol === 'cut' ? { symbol: time.attrs.symbol as 'common' | 'cut' } : {}) };
          }
          for (const c of children(el, 'clef')) {
            const no = Number(c.attrs.number ?? 1);
            const kind = clefOf(text(c, 'sign'), num(c, 'line', 2), num(c, 'clef-octave-change', 0));
            if (mIdx === 0 && pos === 0) initialClefs.set(no, kind);
            else {
              if (pos > 0) warn('Смена ключа внутри такта перенесена на начало такта.');
              xm.clefs.set(no, kind);
            }
          }
          break;
        }
        case 'backup':
          pos = Math.max(0, pos - num(el, 'duration'));
          break;
        case 'forward':
          pos += num(el, 'duration');
          xm.length = Math.max(xm.length, pos);
          break;
        case 'direction':
          parseDirection(el, pos, xm);
          break;
        case 'sound': {
          const tempo = Number(el.attrs.tempo);
          if (tempo > 0 && !xm.tempo) xm.tempo = { bpm: Math.round(tempo), beatUnit: 4, beatDots: 0, text: '' };
          break;
        }
        case 'barline': {
          const rep = child(el, 'repeat');
          if (rep?.attrs.direction === 'forward') xm.info.repeatStart = true;
          if (rep?.attrs.direction === 'backward') xm.info.repeatEnd = Math.max(2, Number(rep.attrs.times ?? 2) || 2);
          const style = text(el, 'bar-style');
          if (!rep && el.attrs.location !== 'left') {
            if (style === 'light-light') xm.info.barline = 'double';
            else if (style === 'light-heavy') xm.info.barline = 'final';
          }
          const ending = child(el, 'ending');
          if (ending) {
            if (ending.attrs.type === 'start') xm.ending = { numbers: (ending.attrs.number ?? '1').split(/[^0-9]+/).map(Number).filter((n) => n > 0), start: true };
            else xm.endingStop = true;
          }
          break;
        }
        case 'note': {
          const n = parseNote(el, pos, lastStart, warn);
          if (!n) break;
          if (!n.chord) lastStart = n.start;
          xm.notes.push(n);
          if (!n.chord && !n.grace) pos = n.start + n.dur;
          xm.length = Math.max(xm.length, pos);
          break;
        }
      }
    }
    measures.push(xm);
  }
  return { measures, staves, initialClefs };
}

function parseNote(el: XmlNode, pos: number, lastStart: number, warn: (w: string) => void): XNote | null {
  if (child(el, 'cue')) return null;
  const chord = !!child(el, 'chord');
  const graceEl = child(el, 'grace');
  const pitchEl = child(el, 'pitch');
  const restEl = child(el, 'rest');
  if (!pitchEl && !restEl) {
    if (child(el, 'unpitched')) warn('Ударные (unpitched) пропущены.');
    return null;
  }
  const typeName = text(el, 'type');
  const tmEl = child(el, 'time-modification');
  const notations = children(el, 'notations');
  const n: XNote = {
    staff: num(el, 'staff', 1),
    voice: text(el, 'voice') || '1',
    start: chord ? lastStart : pos,
    dur: graceEl ? 0 : num(el, 'duration', 0),
    chord,
    rest: !!restEl,
    measureRest: restEl?.attrs.measure === 'yes',
    type: TYPES[typeName],
    dots: children(el, 'dot').length,
    tieStart: children(el, 'tie').some((t) => t.attrs.type === 'start'),
    slurs: [],
    tupletStart: false,
    tupletStop: false,
    artics: [],
    fermata: false,
    color: el.attrs.color && /^#[0-9a-fA-F]{6}/.test(el.attrs.color) ? el.attrs.color.slice(0, 7).toLowerCase() : undefined,
  };
  if (graceEl) n.grace = graceEl.attrs.slash === 'yes' ? 'acciaccatura' : 'appoggiatura';
  if (pitchEl) {
    const step = text(pitchEl, 'step').toUpperCase() as Step;
    n.pitch = { step: (['C', 'D', 'E', 'F', 'G', 'A', 'B'].includes(step) ? step : 'C') as Step, octave: num(pitchEl, 'octave', 4), alter: Math.max(-2, Math.min(2, Math.round(num(pitchEl, 'alter', 0)))) };
    if (num(pitchEl, 'alter', 0) % 1) warn('Микрохроматические альтерации округлены.');
  }
  if (tmEl) n.tm = { act: num(tmEl, 'actual-notes', 1), norm: num(tmEl, 'normal-notes', 1) };
  const stem = text(el, 'stem');
  if (stem === 'up' || stem === 'down') n.stem = stem;
  for (const no of notations) {
    for (const c of no.children) {
      if (c.name === 'tied' && c.attrs.type === 'start') n.tieStart = true;
      else if (c.name === 'slur') n.slurs.push({ type: c.attrs.type, num: c.attrs.number ?? '1' });
      else if (c.name === 'tuplet') {
        if (c.attrs.type === 'start') n.tupletStart = true;
        if (c.attrs.type === 'stop') n.tupletStop = true;
      } else if (c.name === 'fermata') n.fermata = true;
      else if (c.name === 'articulations') {
        for (const a of c.children) if (ARTIC[a.name]) n.artics.push(ARTIC[a.name]);
      } else if (c.name === 'ornaments') {
        for (const a of c.children) if (ORN[a.name]) n.ornament = ORN[a.name];
      }
    }
  }
  return n;
}

function parseDirection(el: XmlNode, pos: number, xm: XMeasure) {
  const staff = num(el, 'staff', 1);
  const offset = num(el, 'offset', 0);
  const at = pos + offset;
  for (const dt of children(el, 'direction-type')) {
    for (const c of dt.children) {
      switch (c.name) {
        case 'dynamics': {
          const d = c.children.map((x) => x.name).find((x) => (DYNAMICS as string[]).includes(x));
          if (d) xm.dirs.push({ staff, pos: at, kind: 'dynamic', value: d, num: '1' });
          break;
        }
        case 'wedge':
          xm.dirs.push({ staff, pos: at, kind: 'wedge', value: c.attrs.type, num: c.attrs.number ?? '1' });
          break;
        case 'pedal':
          if (['start', 'stop', 'change'].includes(c.attrs.type)) xm.dirs.push({ staff, pos: at, kind: 'pedal', value: c.attrs.type, num: '1' });
          break;
        case 'octave-shift':
          xm.dirs.push({ staff, pos: at, kind: 'octave', value: c.attrs.type, num: c.attrs.number ?? '1', size: Number(c.attrs.size ?? 8) });
          break;
        case 'segno':
          xm.info.marker = 'segno';
          break;
        case 'coda':
          xm.info.marker = xm.info.marker ?? 'coda';
          break;
        case 'rehearsal':
          xm.info.rehearsal = text(c);
          break;
        case 'metronome': {
          const unit = TYPES[text(c, 'beat-unit')] ?? 4;
          const bpm = num(c, 'per-minute', 0);
          if (bpm > 0) xm.tempo = { bpm: Math.round(bpm), beatUnit: unit, beatDots: child(c, 'beat-unit-dot') ? 1 : 0, text: xm.tempo?.text ?? '' };
          break;
        }
        case 'words': {
          const w = text(c);
          const lw = w.toLowerCase().replace(/\s+/g, ' ');
          const jump = jumpOf(lw);
          if (jump) xm.info.jump = jump;
          else if (lw === 'fine') xm.info.marker = 'fine';
          else if (lw.startsWith('to coda')) xm.info.marker = 'toCoda';
          else if (w && /^[A-Z][a-z]+( [a-z]+)*$/.test(w) && pos === 0) xm.tempo = { ...(xm.tempo ?? { bpm: 100, beatUnit: 4, beatDots: 0 }), text: w };
          break;
        }
      }
    }
  }
  const sound = child(el, 'sound');
  if (sound) {
    const tempo = Number(sound.attrs.tempo);
    if (tempo > 0) xm.tempo = { ...(xm.tempo ?? { beatUnit: 4, beatDots: 0, text: '' }), bpm: xm.tempo?.bpm ?? Math.round(tempo) };
    if (sound.attrs.fine) xm.info.marker = 'fine';
    if (sound.attrs.tocoda) xm.info.marker = 'toCoda';
    if (sound.attrs.dacapo === 'yes' && !xm.info.jump) xm.info.jump = 'DC';
    if (sound.attrs.dalsegno && !xm.info.jump) xm.info.jump = 'DS';
  }
}

function jumpOf(w: string): JumpKind | undefined {
  const dc = /^(d\.? ?c\.?|da capo)/.test(w);
  const ds = /^(d\.? ?s\.?|dal segno)/.test(w);
  if (!dc && !ds) return undefined;
  const fine = w.includes('fine');
  const coda = w.includes('coda');
  if (dc) return fine ? 'DCalFine' : coda ? 'DCalCoda' : 'DC';
  return fine ? 'DSalFine' : coda ? 'DSalCoda' : 'DS';
}

function buildVoice(
  notes: XNote[],
  homeStaff: number,
  toF: (d: number) => Frac,
  mlen: Frac,
  warn: (w: string) => void,
  colorLines: Map<string, string>,
): { events: VoiceEvent[]; slurs: { type: string; num: string; eventId: string }[] } {
  const events: VoiceEvent[] = [];
  const slurs: { type: string; num: string; eventId: string }[] = [];
  // Group chord members with their main note (document order is kept).
  const groups: XNote[][] = [];
  for (const n of notes) {
    if (n.chord && groups.length) groups[groups.length - 1].push(n);
    else groups.push([n]);
  }
  let cursor: Frac = ZERO;
  let tup: { t: Tuplet; written: Frac; unit: Frac } | null = null;
  for (const g of groups) {
    const lead = g[0];
    const start = toF(lead.start);
    if (lead.measureRest) {
      continue;
    }
    if (!lead.grace) {
      if (lt(cursor, start)) {
        try {
          events.push(...restsFor(cursor, sub(start, cursor)));
        } catch {
          warn('Не удалось точно восстановить ритм в некоторых тактах.');
        }
        cursor = start;
      } else if (lt(start, cursor)) {
        warn('Перекрывающиеся ноты в одном голосе пропущены.');
        continue;
      }
    }
    // Written duration.
    let dur: Duration | null = lead.type ? { base: lead.type as DurBase, dots: Math.min(3, lead.dots) } : null;
    const real = toF(lead.dur);
    if (!lead.grace && !lead.tm) {
      if (!dur || cmp(durToFrac(dur), real) !== 0) dur = fracToDuration(real) ?? dur;
    }
    if (!dur) {
      warn('Ноты неизвестной длительности пропущены.');
      continue;
    }
    let ev: VoiceEvent;
    if (lead.rest) ev = { id: newId('r'), type: 'rest', dur: { ...dur } };
    else {
      const ns: Note[] = [];
      for (const x of g) {
        if (!x.pitch || ns.some((y) => y.step === x.pitch!.step && y.octave === x.pitch!.octave)) continue;
        const note: Note = { id: newId('n'), ...x.pitch };
        if (x.tieStart) note.tie = true;
        ns.push(note);
      }
      if (!ns.length) continue;
      ns.sort((a, b) => a.octave * 7 + 'CDEFGAB'.indexOf(a.step) - (b.octave * 7 + 'CDEFGAB'.indexOf(b.step)));
      const c: ChordEvent = { id: newId('c'), type: 'chord', dur: { ...dur }, notes: ns };
      if (lead.grace) c.grace = lead.grace;
      if (lead.artics.length) c.artics = [...new Set(lead.artics)];
      if (lead.ornament) c.ornament = lead.ornament;
      if (lead.stem) c.stem = lead.stem;
      if (lead.staff !== homeStaff) c.staffShift = lead.staff - homeStaff;
      const color = g.find((x) => x.color)?.color;
      if (color) {
        if (!colorLines.has(color)) colorLines.set(color, newId('l'));
        c.line = colorLines.get(color);
      }
      ev = c;
      for (const s of lead.slurs) slurs.push({ ...s, eventId: c.id });
    }
    if (lead.fermata) ev.fermata = true;
    // Tuplets.
    if (lead.tm && !lead.grace && lead.tm.act !== lead.tm.norm) {
      const written = durToFrac(dur);
      if (!tup || lead.tupletStart || tup.t.num !== lead.tm.act || tup.t.den !== lead.tm.norm) tup = { t: { id: newId('t'), num: lead.tm.act, den: lead.tm.norm }, written: ZERO, unit: written };
      ev.tuplet = tup.t;
      tup.written = add(tup.written, written);
      if (lt(written, tup.unit)) tup.unit = written;
      if (lead.tupletStop || cmp(tup.written, mul(tup.unit, frac(tup.t.num))) >= 0) tup = null;
    } else if (!lead.grace) tup = null;
    events.push(ev);
    if (!lead.grace) cursor = add(cursor, eventLen(ev));
  }
  if (le(cursor, mlen) && lt(cursor, mlen)) {
    try {
      events.push(...restsFor(cursor, sub(mlen, cursor)));
    } catch {
      warn('Не удалось точно восстановить ритм в некоторых тактах.');
    }
  }
  // A measure rest / empty voice.
  if (!events.some((e) => !(e.type === 'chord' && e.grace))) return { events: measureRests(mlen), slurs };
  return { events, slurs };
}

function eventAtOrAfter(voices: VoiceEvent[][], t: Frac): VoiceEvent | undefined {
  for (const events of voices) {
    let pos = ZERO;
    for (const ev of events) {
      if (!(ev.type === 'chord' && ev.grace) && le(t, pos)) return ev;
      const end = add(pos, eventLen(ev));
      if (lt(pos, t) && lt(t, end)) return ev;
      pos = end;
    }
  }
  return undefined;
}

function eventBefore(voices: VoiceEvent[][], t: Frac): VoiceEvent | undefined {
  for (const events of voices) {
    let pos = ZERO;
    let last: VoiceEvent | undefined;
    for (const ev of events) {
      if (le(t, pos) && last) return last;
      if (!(ev.type === 'chord' && ev.grace)) last = ev;
      pos = add(pos, eventLen(ev));
    }
    if (last) return last;
  }
  return undefined;
}
