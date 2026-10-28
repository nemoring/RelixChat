/**
 * .nfg project files: JSON envelope + structural validation + repair.
 */
import type { MeasureInfo, ProjectFile, Score, VoiceEvent, TimeSig } from './types';
import { ARTICULATIONS, DYNAMICS, FORMAT_VERSION, MAX_VOICES, ORNAMENTS, STEPS } from './types';
import { isValidDuration, eventLen, measureLength, decomposeNote } from './duration';
import { add, cmp, lt, sub, ZERO, le } from './fraction';
import { restsFor } from './factory';
import { newId } from './ids';

export const APP_VERSION = '0.1.0';

export function serializeProject(score: Score): string {
  const file: ProjectFile = {
    format: 'noteforge',
    formatVersion: FORMAT_VERSION,
    app: APP_VERSION,
    savedAt: new Date().toISOString(),
    score,
  };
  return JSON.stringify(file);
}

export interface LoadResult {
  score: Score | null;
  errors: string[];
  /** Problems that were repaired automatically while loading. */
  repaired: string[];
}

const isObj = (x: unknown): x is Record<string, unknown> => !!x && typeof x === 'object' && !Array.isArray(x);
const isStr = (x: unknown): x is string => typeof x === 'string';
const isInt = (x: unknown): x is number => Number.isInteger(x);

function validTimeSig(ts: unknown): ts is TimeSig {
  return isObj(ts) && isInt(ts.count) && ts.count >= 1 && ts.count <= 64 && isInt(ts.unit) && [1, 2, 4, 8, 16, 32, 64].includes(ts.unit as number);
}

export function parseProject(text: string): LoadResult {
  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return { score: null, errors: [`Файл повреждён: это не корректный JSON (${(e as Error).message}).`], repaired: [] };
  }
  if (!isObj(data) || data.format !== 'noteforge') return { score: null, errors: ['Это не файл проекта NoteForge.'], repaired: [] };
  if (!isInt(data.formatVersion) || data.formatVersion > FORMAT_VERSION) {
    return { score: null, errors: [`Версия формата ${String(data.formatVersion)} не поддерживается этой версией NoteForge.`], repaired: [] };
  }
  return validateScore(data.score);
}

/** Checks a score structurally. Recoverable timing problems are repaired. */
export function validateScore(raw: unknown): LoadResult {
  const errors: string[] = [];
  const repaired: string[] = [];
  const fail = (msg: string): LoadResult => ({ score: null, errors: [...errors, msg], repaired });
  if (!isObj(raw)) return fail('Нет данных партитуры.');
  const score = structuredClone(raw) as unknown as Score;

  if (!isObj(score.meta)) return fail('Отсутствуют метаданные.');
  for (const k of ['title', 'subtitle', 'composer', 'arranger', 'lyricist', 'copyright'] as const) {
    if (!isStr(score.meta[k])) score.meta[k] = '';
  }
  if (!isObj(score.tempo) || typeof score.tempo.bpm !== 'number' || score.tempo.bpm < 10 || score.tempo.bpm > 500) {
    score.tempo = { bpm: 100, beatUnit: 4, beatDots: 0, text: '' };
    repaired.push('Темп восстановлен по умолчанию.');
  }
  if (!isStr(score.tempo.text)) score.tempo.text = '';
  if (![1, 2, 4, 8, 16].includes(score.tempo.beatUnit)) score.tempo.beatUnit = 4;
  if (!isInt(score.tempo.beatDots) || score.tempo.beatDots < 0 || score.tempo.beatDots > 2) score.tempo.beatDots = 0;
  if (!isObj(score.layout)) {
    score.layout = { ...DEFAULT_LAYOUT, margins: { ...DEFAULT_LAYOUT.margins } };
    repaired.push('Параметры страницы восстановлены по умолчанию.');
  }
  for (const [k, v] of Object.entries(DEFAULT_LAYOUT)) {
    const cur = (score.layout as unknown as Record<string, unknown>)[k];
    if (typeof cur !== typeof v) (score.layout as unknown as Record<string, unknown>)[k] = structuredClone(v);
  }
  if (!['A4', 'A3', 'Letter'].includes(score.layout.size)) score.layout.size = 'A4';
  if (!['portrait', 'landscape'].includes(score.layout.orientation)) score.layout.orientation = 'portrait';
  if (!isObj(score.layout.margins)) score.layout.margins = { top: 15, bottom: 15, left: 15, right: 15 };
  if (typeof score.layout.staffScale !== 'number') score.layout.staffScale = 100;

  if (!Array.isArray(score.measures) || score.measures.length === 0) return fail('В партитуре нет тактов.');
  const ids = new Set<string>();
  const uniq = (id: unknown, what: string): string => {
    if (!isStr(id) || !/^[A-Za-z][\w.-]*$/.test(id) || ids.has(id)) {
      const nid = newId(what[0]);
      repaired.push(`Исправлен идентификатор (${what}).`);
      ids.add(nid);
      return nid;
    }
    ids.add(id);
    return id;
  };
  for (const [i, m] of score.measures.entries()) {
    if (!isObj(m)) return fail(`Такт ${i + 1}: повреждённые данные.`);
    m.id = uniq(m.id, 'measure');
    if (m.timeSig !== undefined && !validTimeSig(m.timeSig)) return fail(`Такт ${i + 1}: некорректный размер.`);
    if (m.keySig !== undefined && (!isInt(m.keySig) || m.keySig < -7 || m.keySig > 7)) return fail(`Такт ${i + 1}: некорректная тональность.`);
    sanitizeMeasure(m, repaired, i);
  }
  if (!score.measures[0].timeSig) {
    score.measures[0].timeSig = { count: 4, unit: 4 };
    repaired.push('Начальный размер не был задан — установлен 4/4.');
  }
  if (score.measures[0].keySig === undefined) score.measures[0].keySig = 0;

  if (!Array.isArray(score.parts) || score.parts.length === 0) return fail('В партитуре нет партий.');
  const sigs: TimeSig[] = [];
  let cur = score.measures[0].timeSig!;
  for (const m of score.measures) {
    if (m.timeSig) cur = m.timeSig;
    sigs.push(cur);
  }

  for (const [pi, part] of score.parts.entries()) {
    if (!isObj(part) || !Array.isArray(part.staves) || part.staves.length === 0) return fail(`Партия ${pi + 1}: нет нотоносцев.`);
    part.id = uniq(part.id, 'part');
    if (!isStr(part.name)) part.name = 'Партия';
    if (!isStr(part.abbreviation)) part.abbreviation = '';
    if (!isInt(part.program) || part.program < 0 || part.program > 127) part.program = 0;
    for (const [si, staff] of part.staves.entries()) {
      const where = `Партия ${pi + 1}, нотоносец ${si + 1}`;
      if (!isObj(staff) || !Array.isArray(staff.measures)) return fail(`${where}: повреждённые данные.`);
      staff.id = uniq(staff.id, 'staff');
      if (!CLEFS.includes(staff.clef)) staff.clef = si === 1 ? 'bass' : 'treble';
      if (staff.measures.length !== score.measures.length) return fail(`${where}: число тактов (${staff.measures.length}) не совпадает с партитурой (${score.measures.length}).`);
      for (const [mi, sm] of staff.measures.entries()) {
        if (!isObj(sm) || !Array.isArray(sm.voices)) return fail(`${where}, такт ${mi + 1}: повреждённые данные.`);
        if (sm.clef !== undefined && !CLEFS.includes(sm.clef)) delete sm.clef;
        while (sm.voices.length < MAX_VOICES) sm.voices.push([]);
        if (sm.voices.length > MAX_VOICES) sm.voices.length = MAX_VOICES;
        const mlen = measureLength(sigs[mi]);
        for (let v = 0; v < MAX_VOICES; v++) {
          const events = sm.voices[v];
          if (!Array.isArray(events)) return fail(`${where}, такт ${mi + 1}: повреждённый голос.`);
          for (const ev of events as VoiceEvent[]) {
            if (!isObj(ev) || (ev.type !== 'rest' && ev.type !== 'chord')) return fail(`${where}, такт ${mi + 1}: неизвестное событие.`);
            if (!isValidDuration(ev.dur)) return fail(`${where}, такт ${mi + 1}: некорректная длительность.`);
            ev.id = uniq(ev.id, 'event');
            sanitizeEvent(ev);
            if (ev.type === 'chord') {
              if (!Array.isArray(ev.notes) || ev.notes.length === 0) return fail(`${where}, такт ${mi + 1}: пустой аккорд.`);
              for (const n of ev.notes) {
                if (!isObj(n) || !STEPS.includes(n.step) || !isInt(n.octave) || n.octave < 0 || n.octave > 9 || !isInt(n.alter) || n.alter < -2 || n.alter > 2) {
                  return fail(`${where}, такт ${mi + 1}: некорректная высота ноты.`);
                }
                n.id = uniq(n.id, 'note');
                if (n.tie !== undefined && n.tie !== true) delete n.tie;
              }
            }
          }
          if (v === 0 && events.length === 0) {
            sm.voices[0] = restsFor(ZERO, mlen);
            repaired.push(`${where}, такт ${mi + 1}: пустой первый голос заполнен паузами.`);
            continue;
          }
          if (events.length) {
            const fixed = fitVoice(events as VoiceEvent[], mlen);
            if (fixed) {
              sm.voices[v] = fixed;
              repaired.push(`${where}, такт ${mi + 1}, голос ${v + 1}: длительность такта исправлена.`);
            }
          }
        }
      }
    }
  }
  // Spanners, melody lines, bookmarks.
  const eventIds = new Set<string>();
  for (const part of score.parts) for (const st of part.staves) for (const sm of st.measures) for (const v of sm.voices) for (const ev of v) eventIds.add(ev.id);
  if (!Array.isArray(score.spanners)) score.spanners = [];
  const before = score.spanners.length;
  score.spanners = score.spanners.filter(
    (sp) => isObj(sp) && isStr(sp.id) && SPANNERS.includes(sp.type) && eventIds.has(sp.start) && eventIds.has(sp.end) && (sp.type !== 'ottava' || [8, 15, -8, -15].includes(sp.ottava as number)),
  );
  if (score.spanners.length !== before) repaired.push(`Удалено повреждённых линий (лиг, вилок, педали): ${before - score.spanners.length}.`);
  if (!Array.isArray(score.lines)) score.lines = [];
  score.lines = score.lines.filter((l) => isObj(l) && isStr(l.id) && isStr(l.name) && isStr(l.color));
  const lineIds = new Set(score.lines.map((l) => l.id));
  for (const part of score.parts)
    for (const st of part.staves)
      for (const sm of st.measures)
        for (const v of sm.voices)
          for (const ev of v) if (ev.type === 'chord' && ev.line && !lineIds.has(ev.line)) delete ev.line;
  if (!Array.isArray(score.bookmarks)) score.bookmarks = [];
  score.bookmarks = score.bookmarks.filter((b) => isObj(b) && isStr(b.id) && isStr(b.name) && isInt(b.measure) && b.measure >= 0 && b.measure < score.measures.length);
  return { score, errors, repaired };
}

const DEFAULT_LAYOUT = {
  size: 'A4' as const,
  orientation: 'portrait' as const,
  margins: { top: 15, bottom: 15, left: 15, right: 15 },
  staffScale: 100,
  measuresPerSystem: 0,
  staffSpacing: 12,
  systemSpacing: 6,
  showPageNumbers: true,
  showHeader: true,
};

const CLEFS = ['treble', 'bass', 'alto', 'tenor', 'treble8vb', 'percussion'];
const SPANNERS = ['slur', 'cresc', 'dim', 'pedal', 'ottava'];

/** Drops unknown or malformed measure marks instead of rejecting the file. */
function sanitizeMeasure(m: MeasureInfo, repaired: string[], i: number) {
  const bad = (what: string) => repaired.push(`Такт ${i + 1}: удалена некорректная отметка (${what}).`);
  if (m.tempo !== undefined && !(isObj(m.tempo) && typeof m.tempo.bpm === 'number' && m.tempo.bpm >= 10 && m.tempo.bpm <= 500 && [1, 2, 4, 8, 16].includes(m.tempo.beatUnit))) {
    delete m.tempo;
    bad('темп');
  } else if (m.tempo) {
    if (!isStr(m.tempo.text)) m.tempo.text = '';
    if (!isInt(m.tempo.beatDots)) m.tempo.beatDots = 0;
  }
  if (m.repeatStart !== undefined && m.repeatStart !== true) delete m.repeatStart;
  if (m.repeatEnd !== undefined && !(isInt(m.repeatEnd) && m.repeatEnd >= 2 && m.repeatEnd <= 16)) {
    delete m.repeatEnd;
    bad('реприза');
  }
  if (m.volta !== undefined && !(isObj(m.volta) && isStr(m.volta.id) && Array.isArray(m.volta.numbers) && m.volta.numbers.every(isInt))) {
    delete m.volta;
    bad('вольта');
  }
  if (m.marker !== undefined && !['segno', 'coda', 'fine', 'toCoda'].includes(m.marker)) delete m.marker;
  if (m.jump !== undefined && !['DC', 'DCalFine', 'DCalCoda', 'DS', 'DSalFine', 'DSalCoda'].includes(m.jump)) delete m.jump;
  if (m.barline !== undefined && !['double', 'final'].includes(m.barline)) delete m.barline;
  if (m.section !== undefined && !(isObj(m.section) && isStr(m.section.title))) delete m.section;
  else if (m.section) m.section.newPage = !!m.section.newPage;
  if (m.rehearsal !== undefined && !isStr(m.rehearsal)) delete m.rehearsal;
  if (m.breakBefore !== undefined && !['system', 'page'].includes(m.breakBefore)) delete m.breakBefore;
}

function sanitizeEvent(ev: VoiceEvent) {
  if (ev.tuplet !== undefined && !(isObj(ev.tuplet) && isStr(ev.tuplet.id) && isInt(ev.tuplet.num) && isInt(ev.tuplet.den) && ev.tuplet.num >= 2 && ev.tuplet.den >= 1)) delete ev.tuplet;
  if (ev.fermata !== undefined && ev.fermata !== true) delete ev.fermata;
  if (ev.type !== 'chord') return;
  if (ev.artics !== undefined) {
    ev.artics = Array.isArray(ev.artics) ? ev.artics.filter((a) => ARTICULATIONS.includes(a)) : [];
    if (!ev.artics.length) delete ev.artics;
  }
  if (ev.ornament !== undefined && !ORNAMENTS.includes(ev.ornament)) delete ev.ornament;
  if (ev.dynamic !== undefined && !DYNAMICS.includes(ev.dynamic)) delete ev.dynamic;
  if (ev.grace !== undefined && ev.grace !== 'acciaccatura' && ev.grace !== 'appoggiatura') delete ev.grace;
  if (ev.staffShift !== undefined && !(isInt(ev.staffShift) && Math.abs(ev.staffShift) <= 3 && ev.staffShift !== 0)) delete ev.staffShift;
  if (ev.stem !== undefined && ev.stem !== 'up' && ev.stem !== 'down') delete ev.stem;
  if (ev.beam !== undefined && !['break', 'join', 'none'].includes(ev.beam)) delete ev.beam;
  if (ev.line !== undefined && !isStr(ev.line)) delete ev.line;
}

/** Pads an underfull voice with rests or trims an overfull one; null if already correct. */
export function fitVoice(events: VoiceEvent[], mlen: { n: number; d: number }): VoiceEvent[] | null {
  let t = ZERO;
  const out: VoiceEvent[] = [];
  for (const ev of events) {
    const len = eventLen(ev);
    const end = add(t, len);
    if (le(end, mlen)) {
      out.push(ev);
      t = end;
      continue;
    }
    // Overfull: shorten the event that crosses the barline and drop the rest.
    const left = sub(mlen, t);
    if (lt(ZERO, left) && ev.tuplet) {
      // A cut tuplet cannot stay a tuplet: drop its members from here on.
      while (out.length && out[out.length - 1].tuplet?.id === ev.tuplet.id) {
        const removed = out.pop()!;
        t = sub(t, eventLen(removed));
      }
      out.push(...restsFor(t, sub(mlen, t)));
      t = mlen;
      break;
    }
    if (lt(ZERO, left)) {
      decomposeNote(t, left).forEach((d, i) => {
        if (i === 0) out.push({ ...ev, dur: d } as VoiceEvent);
        else if (ev.type === 'rest') out.push({ id: newId('r'), type: 'rest', dur: d });
        else out.push({ id: newId('c'), type: 'chord', dur: d, notes: ev.notes.map((n) => ({ ...n, id: newId('n') })) });
      });
    }
    t = mlen;
    break;
  }
  if (cmp(t, mlen) < 0) out.push(...restsFor(t, sub(mlen, t)));
  const same = out.length === events.length && out.every((e, i) => e === events[i]);
  return same ? null : out;
}
