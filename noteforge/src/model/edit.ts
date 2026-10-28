/**
 * Editing operations on the score model.
 *
 * All functions mutate the score passed in (normally an Immer draft) and keep
 * the model invariant: every non-empty voice exactly fills its measure.
 * Entering music uses MuseScore-like "overwrite" semantics: writing an event
 * of length L at time t replaces whatever was in [t, t+L) of that voice;
 * music that crosses a barline is split and tied automatically.
 *
 * Tuplets are atomic blocks for writes coming from outside; writing at a
 * position inside a tuplet edits the tuplet's content in its written values.
 * Grace notes take no metric time and stay attached to the following event.
 */
import type {
  Articulation,
  ChordEvent,
  ClefKind,
  Duration,
  Dynamic,
  JumpKind,
  MarkerKind,
  MeasureInfo,
  Note,
  Ornament,
  Score,
  SpannerType,
  StaffMeasure,
  Tempo,
  TimeSig,
  Tuplet,
  VoiceEvent,
} from './types';
import { MAX_VOICES } from './types';
import { Frac, ZERO, add, sub, lt, le, gt, ge, isZero, min, eq, cmp, mul, div, frac } from './fraction';
import { decomposeNote, durToFrac, eventLen, fracToDuration, measureLength } from './duration';
import { getStaff, measureLen, staffCount, timeSigAt, timeline, voiceLength, effectiveTimeSigs } from './query';
import { emptyStaffMeasure, makeRest, measureRests, restsFor } from './factory';
import { newId } from './ids';
import type { Pitch } from './pitch';
import { sortNotes, diatonicOf, samePitch, midiOf, pitchFromMidi, keyAlter } from './pitch';

/** Chord properties that travel with a chord when it is rewritten (split, re-barred, pasted). */
export type ChordAttrs = Partial<Pick<ChordEvent, 'artics' | 'ornament' | 'dynamic' | 'staffShift' | 'stem' | 'beam' | 'line' | 'fermata'>>;

export function chordAttrs(ev: ChordEvent): ChordAttrs {
  const a: ChordAttrs = {};
  if (ev.artics?.length) a.artics = [...ev.artics];
  if (ev.ornament) a.ornament = ev.ornament;
  if (ev.dynamic) a.dynamic = ev.dynamic;
  if (ev.staffShift) a.staffShift = ev.staffShift;
  if (ev.stem) a.stem = ev.stem;
  if (ev.beam) a.beam = ev.beam;
  if (ev.line) a.line = ev.line;
  if (ev.fermata) a.fermata = true;
  return a;
}

/** Attributes for piece `i` of `n` when one chord is written as several tied chords. */
function pieceAttrs(a: ChordAttrs | undefined, i: number, n: number): ChordAttrs {
  if (!a) return {};
  const out: ChordAttrs = {};
  if (a.line) out.line = a.line;
  if (a.staffShift) out.staffShift = a.staffShift;
  if (a.stem) out.stem = a.stem;
  if (i === 0) {
    if (a.artics) out.artics = [...a.artics];
    if (a.ornament) out.ornament = a.ornament;
    if (a.dynamic) out.dynamic = a.dynamic;
    if (a.beam) out.beam = a.beam;
  }
  if (i === n - 1 && a.fermata) out.fermata = true;
  return out;
}

// ───────────────────────────── measures ─────────────────────────────

/** Appends `n` empty measures to the end of the score. */
export function appendMeasures(score: Score, n: number): void {
  insertMeasures(score, score.measures.length, n);
}

/** Inserts `n` empty measures before measure index `at`. */
export function insertMeasures(score: Score, at: number, n: number): void {
  if (n <= 0) return;
  at = Math.max(0, Math.min(at, score.measures.length));
  const infos: MeasureInfo[] = Array.from({ length: n }, () => ({ id: newId('m') }));
  if (at === 0) {
    // The new first measure takes over the opening signatures.
    const first = score.measures[0];
    infos[0].timeSig = first?.timeSig ? { ...first.timeSig } : { count: 4, unit: 4 };
    infos[0].keySig = first?.keySig ?? 0;
  }
  const len = at === 0 ? measureLength(infos[0].timeSig!) : measureLen(score, at - 1);
  score.measures.splice(at, 0, ...infos);
  for (let s = 0; s < staffCount(score); s++) {
    getStaff(score, s).measures.splice(at, 0, ...Array.from({ length: n }, () => emptyStaffMeasure(len)));
  }
}

/** Deletes measures [from, to] inclusive. At least one measure always remains. */
export function deleteMeasures(score: Score, from: number, to: number): boolean {
  from = Math.max(0, from);
  to = Math.min(score.measures.length - 1, to);
  if (to < from) return false;
  if (to - from + 1 >= score.measures.length) return false;
  // Carry the changes in effect at the end of the range to the next measure,
  // so the music after the deleted range keeps its meter, key, tempo and clefs.
  const nextIdx = to + 1;
  if (nextIdx < score.measures.length) {
    const next = score.measures[nextIdx];
    if (!next.timeSig) next.timeSig = { ...timeSigAt(score, to) };
    for (let i = to; i >= from; i--) {
      const mi = score.measures[i];
      if (next.keySig === undefined && mi.keySig !== undefined) next.keySig = mi.keySig;
      if (!next.tempo && mi.tempo) next.tempo = { ...mi.tempo };
    }
    if (next.keySig === undefined && from === 0) next.keySig = 0;
    for (let s = 0; s < staffCount(score); s++) {
      const st = getStaff(score, s);
      if (st.measures[nextIdx].clef) continue;
      for (let i = to; i >= from; i--) {
        const c = st.measures[i].clef;
        if (c) {
          if (from === 0) st.clef = c;
          else st.measures[nextIdx].clef = c;
          break;
        }
      }
    }
  }
  const removed = new Set<string>();
  for (let s = 0; s < staffCount(score); s++)
    for (let i = from; i <= to; i++) for (const v of getStaff(score, s).measures[i].voices) for (const ev of v) removed.add(ev.id);
  const count = to - from + 1;
  score.measures.splice(from, count);
  for (let s = 0; s < staffCount(score); s++) getStaff(score, s).measures.splice(from, count);
  if (!score.measures[0].timeSig) score.measures[0].timeSig = { count: 4, unit: 4 };
  if (score.measures[0].keySig === undefined) score.measures[0].keySig = 0;
  score.spanners = score.spanners.filter((sp) => !removed.has(sp.start) && !removed.has(sp.end));
  for (const b of score.bookmarks) {
    if (b.measure > to) b.measure -= count;
    else if (b.measure >= from) b.measure = from;
    b.measure = Math.min(b.measure, score.measures.length - 1);
  }
  return true;
}

// ───────────────────────────── voices ─────────────────────────────

function staffMeasure(score: Score, staff: number, m: number): StaffMeasure {
  const sm = getStaff(score, staff).measures[m];
  while (sm.voices.length < MAX_VOICES) sm.voices.push([]);
  return sm;
}

/** Makes sure a voice exists in a measure (an unused voice is filled with rests). */
export function ensureVoice(score: Score, staff: number, m: number, voice: number): VoiceEvent[] {
  const sm = staffMeasure(score, staff, m);
  if (sm.voices[voice].length === 0) sm.voices[voice] = measureRests(measureLen(score, m));
  return sm.voices[voice];
}

/** Removes a secondary voice from a measure if it contains only rests. */
export function pruneVoice(score: Score, staff: number, m: number, voice: number): void {
  if (voice === 0) return;
  const sm = staffMeasure(score, staff, m);
  if (sm.voices[voice].every((e) => e.type === 'rest')) sm.voices[voice] = [];
}

function newChord(dur: Duration, notes: (Pitch & { tie?: boolean })[], attrs?: ChordAttrs): ChordEvent {
  const c: ChordEvent = { id: newId('c'), type: 'chord', dur: { ...dur }, notes: notes.map((p) => ({ id: newId('n'), step: p.step, octave: p.octave, alter: p.alter })) };
  Object.assign(c, structuredClone(attrs ?? {}));
  return c;
}

/** Splits a chord into tied pieces of the given durations. */
function splitChord(ev: ChordEvent, durs: Duration[], keepFirstId: boolean, lastTie: boolean): ChordEvent[] {
  const attrs = chordAttrs(ev);
  return durs.map((d, i) => {
    const last = i === durs.length - 1;
    const c = newChord(d, ev.notes, pieceAttrs(attrs, i, durs.length));
    c.notes.forEach((n) => {
      if (!last || lastTie) n.tie = true;
    });
    if (i === 0 && keepFirstId) {
      c.id = ev.id;
      c.notes.forEach((n, k) => (n.id = ev.notes[k].id));
    }
    if (ev.tuplet) c.tuplet = ev.tuplet;
    return c;
  });
}

interface Block {
  start: Frac;
  end: Frac;
  events: VoiceEvent[];
  tuplet: Tuplet | null;
  grace: boolean;
}

/** Groups a voice into blocks: single events, whole tuplets and grace notes. */
export function blocksOf(events: VoiceEvent[]): Block[] {
  const out: Block[] = [];
  let t = ZERO;
  for (const ev of events) {
    const len = eventLen(ev);
    const end = add(t, len);
    const isGrace = ev.type === 'chord' && !!ev.grace;
    const last = out[out.length - 1];
    if (ev.tuplet && !isGrace && last && last.tuplet && last.tuplet.id === ev.tuplet.id) {
      last.events.push(ev);
      last.end = end;
    } else {
      out.push({ start: t, end, events: [ev], tuplet: !isGrace && ev.tuplet ? ev.tuplet : null, grace: isGrace });
    }
    t = end;
  }
  return out;
}

/**
 * Replaces the span [t, t+len) of a full voice with `insert` (whose total length must be len).
 * Events cut at the start are shortened; the cut-off tail of an event is turned into rests.
 * Tuplets touched by the span are removed as a whole (their uncovered part becomes rests).
 */
export function overwriteSpan(events: VoiceEvent[], t: Frac, len: Frac, insert: VoiceEvent[]): VoiceEvent[] {
  const end = add(t, len);
  const before: VoiceEvent[] = [];
  const after: VoiceEvent[] = [];
  for (const b of blocksOf(events)) {
    if (b.grace) {
      if (lt(b.start, t)) before.push(...b.events);
      else if (ge(b.start, end)) after.push(...b.events);
      continue;
    }
    if (le(b.end, t)) {
      before.push(...b.events);
    } else if (le(end, b.start)) {
      after.push(...b.events);
    } else {
      const ev = b.events[0];
      if (lt(b.start, t)) {
        const headLen = sub(t, b.start);
        if (!b.tuplet && ev.type === 'chord') before.push(...splitChord(ev, decomposeNote(b.start, headLen), true, false));
        else before.push(...restsFor(b.start, headLen));
      }
      if (gt(b.end, end)) after.unshift(...restsFor(end, sub(b.end, end)));
    }
  }
  return [...before, ...insert, ...after];
}

export type Template =
  | { type: 'rest'; fermata?: boolean }
  | { type: 'chord'; notes: (Pitch & { tie?: boolean })[]; attrs?: ChordAttrs };

export interface WriteResult {
  /** Id of the first event written. */
  firstId: string;
  firstMeasure: number;
  lastId: string;
  lastMeasure: number;
  /** Position right after the written music. */
  endMeasure: number;
  endTime: Frac;
}

/** The tuplet block containing time t of a voice, if any. */
function tupletAt(events: VoiceEvent[], t: Frac): Block | null {
  for (const b of blocksOf(events)) if (b.tuplet && le(b.start, t) && lt(t, b.end)) return b;
  return null;
}

/**
 * Writes inside a tuplet. `writtenLen` is in written values (an eighth inside
 * a triplet is 1/8); the write is clipped at the end of the tuplet.
 */
function writeInTuplet(score: Score, staff: number, m: number, voice: number, t: Frac, writtenLen: Frac, tpl: Template, block: Block): WriteResult {
  const tup = block.tuplet!;
  const ratio = frac(tup.den, tup.num);
  const stripped = block.events.map((e) => {
    const c = { ...e } as VoiceEvent;
    delete c.tuplet;
    return c;
  });
  const wt = div(sub(t, block.start), ratio);
  const total = div(sub(block.end, block.start), ratio);
  const seg = min(writtenLen, sub(total, wt));
  const pieces: VoiceEvent[] = decomposeNote(wt, seg).map((d, i, arr) => (tpl.type === 'rest' ? makeRest(d) : newChord(d, tpl.notes, pieceAttrs(tpl.attrs, i, arr.length))));
  if (tpl.type === 'chord') pieces.forEach((p, i) => (p as ChordEvent).notes.forEach((n, k) => (i < pieces.length - 1 || tpl.notes[k].tie) && (n.tie = true)));
  const rewritten = overwriteSpan(stripped, wt, seg, pieces).map((e) => ({ ...e, tuplet: tup }) as VoiceEvent);
  const sm = staffMeasure(score, staff, m);
  const events = sm.voices[voice];
  const i0 = events.indexOf(block.events[0]);
  sm.voices[voice] = [...events.slice(0, i0), ...rewritten, ...events.slice(i0 + block.events.length)];
  const endTime = add(block.start, mul(add(wt, seg), ratio));
  let endM = m;
  let endT = endTime;
  if (eq(endT, measureLen(score, m))) {
    endM++;
    endT = ZERO;
  }
  return { firstId: pieces[0].id, firstMeasure: m, lastId: pieces[pieces.length - 1].id, lastMeasure: m, endMeasure: endM, endTime: endT };
}

/**
 * Writes an event of total length `len` at (measure m, time t) in a voice.
 * If it does not fit before the barline it continues into following measures
 * (appending measures at the end of the score when needed) as tied notes.
 * At a position inside a tuplet, `len` is taken as a written value inside it.
 */
export function writeAt(score: Score, staff: number, m: number, voice: number, t: Frac, len: Frac, tpl: Template): WriteResult {
  if (m < score.measures.length) {
    const evs = staffMeasure(score, staff, m).voices[voice];
    const blk = evs.length ? tupletAt(evs, t) : null;
    if (blk) return writeInTuplet(score, staff, m, voice, t, len, tpl, blk);
  }
  let remaining = len;
  let curM = m;
  let curT = t;
  const written: { ev: VoiceEvent; m: number }[] = [];
  let guard = 0;
  while (!isZero(remaining)) {
    if (++guard > 10000) throw new Error('writeAt: runaway');
    if (curM >= score.measures.length) appendMeasures(score, 1);
    const mlen = measureLen(score, curM);
    const avail = sub(mlen, curT);
    if (le(avail, ZERO)) {
      curM++;
      curT = ZERO;
      continue;
    }
    const seg = min(remaining, avail);
    const events = ensureVoice(score, staff, curM, voice);
    const durs = decomposeNote(curT, seg);
    const pieces: VoiceEvent[] = durs.map((d) => {
      if (tpl.type === 'rest') return makeRest(d);
      return newChord(d, tpl.notes);
    });
    staffMeasure(score, staff, curM).voices[voice] = overwriteSpan(events, curT, seg, pieces);
    for (const p of pieces) written.push({ ev: p, m: curM });
    remaining = sub(remaining, seg);
    curT = add(curT, seg);
    if (eq(curT, mlen) && !isZero(remaining)) {
      curM++;
      curT = ZERO;
    }
  }
  if (tpl.type === 'chord') {
    // Tie chain: every piece except the last ties into the next; the last keeps the template's ties.
    written.forEach((w, i) => {
      const ev = w.ev as ChordEvent;
      const last = i === written.length - 1;
      Object.assign(ev, structuredClone(pieceAttrs(tpl.attrs, i, written.length)));
      ev.notes.forEach((n, k) => {
        if (!last || tpl.notes[k].tie) n.tie = true;
      });
      sortNotes(ev.notes);
    });
  } else if (tpl.fermata) {
    written[written.length - 1].ev.fermata = true;
  }
  let endM = curM;
  let endT = curT;
  if (endM < score.measures.length && eq(endT, measureLen(score, endM))) {
    endM++;
    endT = ZERO;
  }
  return {
    firstId: written[0].ev.id,
    firstMeasure: written[0].m,
    lastId: written[written.length - 1].ev.id,
    lastMeasure: written[written.length - 1].m,
    endMeasure: endM,
    endTime: endT,
  };
}

/** Replaces [t, t+len) of a voice (possibly across measures) with aligned rests. */
export function clearSpan(score: Score, staff: number, m: number, voice: number, t: Frac, len: Frac): void {
  let remaining = len;
  let curM = m;
  let curT = t;
  while (!isZero(remaining) && curM < score.measures.length) {
    const mlen = measureLen(score, curM);
    const seg = min(remaining, sub(mlen, curT));
    if (gt(seg, ZERO)) {
      const events = ensureVoice(score, staff, curM, voice);
      staffMeasure(score, staff, curM).voices[voice] = overwriteSpan(events, curT, seg, restsFor(curT, seg));
      remaining = sub(remaining, seg);
    }
    curM++;
    curT = ZERO;
  }
}

/** Advances a (measure, time) position by `len`. */
function advance(score: Score, m: number, t: Frac, len: Frac): { m: number; t: Frac } {
  let curM = m;
  let curT = add(t, len);
  while (curM < score.measures.length && !lt(curT, measureLen(score, curM))) {
    curT = sub(curT, measureLen(score, curM));
    curM++;
  }
  return { m: curM, t: curT };
}

const templateOf = (ev: VoiceEvent): Template =>
  ev.type === 'rest' ? { type: 'rest', fermata: ev.fermata } : { type: 'chord', notes: ev.notes.map((n) => ({ ...n })), attrs: chordAttrs(ev) };

function cloneWithNewIds(ev: VoiceEvent, tuplet?: Tuplet): VoiceEvent {
  const c = structuredClone(ev) as VoiceEvent;
  c.id = newId(c.type === 'rest' ? 'r' : 'c');
  if (c.type === 'chord') c.notes.forEach((n) => (n.id = newId('n')));
  if (tuplet) c.tuplet = tuplet;
  else delete c.tuplet;
  return c;
}

/**
 * Writes a sequence of events starting at (m, 0). Rests only advance time:
 * the target span is expected to be cleared already, so the remaining gaps
 * keep cleanly aligned rests. Tuplets are copied whole when they fit in a
 * measure; grace notes are re-attached in front of the following chord.
 */
function writeSequence(score: Score, staff: number, m: number, voice: number, seq: VoiceEvent[], limitMeasure?: number): number {
  let pos = { m, t: ZERO as Frac };
  let last = m;
  let graces: VoiceEvent[] = [];
  for (const b of blocksOf(seq)) {
    if (limitMeasure !== undefined && pos.m >= limitMeasure) break;
    if (b.grace) {
      graces.push(...b.events);
      continue;
    }
    const len = sub(b.end, b.start);
    if (pos.m >= score.measures.length) appendMeasures(score, 1);
    if (b.tuplet) {
      const fits = le(add(pos.t, len), measureLen(score, pos.m));
      if (fits && b.events.some((e) => e.type === 'chord')) {
        const tup: Tuplet = { ...b.tuplet, id: newId('t') };
        const events = ensureVoice(score, staff, pos.m, voice);
        staffMeasure(score, staff, pos.m).voices[voice] = overwriteSpan(events, pos.t, len, b.events.map((e) => cloneWithNewIds(e, tup)));
        last = Math.max(last, pos.m);
      } else if (!fits) {
        // A tuplet cannot cross a barline: keep its first chord as a plain note.
        const firstChord = b.events.find((e) => e.type === 'chord');
        if (firstChord) last = Math.max(last, writeAt(score, staff, pos.m, voice, pos.t, len, templateOf(firstChord)).lastMeasure);
      }
      graces = [];
    } else {
      const ev = b.events[0];
      if (ev.type === 'chord' || ev.fermata) {
        const r = writeAt(score, staff, pos.m, voice, pos.t, len, templateOf(ev));
        last = Math.max(last, r.lastMeasure);
        if (graces.length && ev.type === 'chord') {
          const evs = staffMeasure(score, staff, r.firstMeasure).voices[voice];
          const i = evs.findIndex((e) => e.id === r.firstId);
          if (i >= 0) evs.splice(i, 0, ...graces.map((g) => cloneWithNewIds(g)));
        }
      }
      graces = [];
    }
    pos = advance(score, pos.m, pos.t, len);
  }
  return last;
}

function locate(score: Score, staff: number, m: number, voice: number, eventId: string) {
  const events = staffMeasure(score, staff, m).voices[voice];
  const tl = timeline(events);
  const x = tl.find((e) => e.ev.id === eventId);
  if (!x) throw new Error(`Event ${eventId} not found`);
  return { events, x };
}

/** Changes the duration of an event, overwriting what follows or padding with rests. */
export function setEventDuration(score: Score, staff: number, m: number, voice: number, eventId: string, dur: Duration): WriteResult {
  const { events, x } = locate(score, staff, m, voice, eventId);
  const ev = x.ev;
  if (ev.type === 'chord' && ev.grace) {
    ev.dur = { ...dur };
    return { firstId: ev.id, firstMeasure: m, lastId: ev.id, lastMeasure: m, endMeasure: m, endTime: x.start };
  }
  if (ev.tuplet) {
    // Inside a tuplet: rewrite in written values.
    const rest: VoiceEvent = { id: newId('r'), type: 'rest', dur: { ...ev.dur }, tuplet: ev.tuplet };
    events[x.index] = rest;
    const blk = tupletAt(events, x.start)!;
    const r = writeInTuplet(score, staff, m, voice, x.start, durToFrac(dur), templateOf(ev), blk);
    restoreIdentity(score, staff, voice, r, ev);
    return r;
  }
  const oldLen = sub(x.end, x.start);
  const newLen = durToFrac(dur);
  if (le(newLen, oldLen)) {
    const changed: VoiceEvent = { ...ev, dur: { ...dur } } as VoiceEvent;
    const pad = restsFor(add(x.start, newLen), sub(oldLen, newLen));
    staffMeasure(score, staff, m).voices[voice] = [...events.slice(0, x.index), changed, ...pad, ...events.slice(x.index + 1)];
    return { firstId: ev.id, firstMeasure: m, lastId: ev.id, lastMeasure: m, endMeasure: m, endTime: add(x.start, newLen) };
  }
  const r = writeAt(score, staff, m, voice, x.start, newLen, templateOf(ev));
  restoreIdentity(score, staff, voice, r, ev);
  return r;
}

/** Keeps the id of a rewritten event so selection and spanners stay attached. */
function restoreIdentity(score: Score, staff: number, voice: number, r: WriteResult, ev: VoiceEvent) {
  const first = staffMeasure(score, staff, r.firstMeasure).voices[voice].find((e) => e.id === r.firstId);
  if (first && first.type === ev.type) {
    first.id = ev.id;
    if (first.type === 'chord' && ev.type === 'chord') first.notes.forEach((n, k) => (n.id = ev.notes[k]?.id ?? n.id));
    if (r.lastId === r.firstId) r.lastId = ev.id;
    r.firstId = ev.id;
  }
}

/** Turns an event into a rest of the same length (or removes a grace note / tuplet / secondary voice). */
export function deleteEvent(score: Score, staff: number, m: number, voice: number, eventId: string): string | null {
  const { events, x } = locate(score, staff, m, voice, eventId);
  const ev = x.ev;
  if (ev.type === 'chord' && ev.grace) {
    events.splice(x.index, 1);
    return null;
  }
  if (ev.type === 'rest') {
    if (ev.tuplet) {
      // Deleting a rest of a tuplet removes the whole tuplet.
      const blk = tupletAt(events, x.start)!;
      const i0 = events.indexOf(blk.events[0]);
      const rests = restsFor(blk.start, sub(blk.end, blk.start));
      events.splice(i0, blk.events.length, ...rests);
      return rests[0].id;
    }
    if (voice > 0) {
      pruneVoice(score, staff, m, voice);
      return null;
    }
    return ev.id;
  }
  const rest = makeRest(ev.dur);
  if (ev.tuplet) rest.tuplet = ev.tuplet;
  // Graces in front of the removed chord go with it.
  let i = x.index;
  while (i > 0 && events[i - 1].type === 'chord' && (events[i - 1] as ChordEvent).grace) i--;
  events.splice(i, x.index - i + 1, rest);
  return rest.id;
}

/** Removes one note from a chord; the last note of a chord turns the event into a rest. */
export function deleteNote(score: Score, staff: number, m: number, voice: number, eventId: string, noteId: string): string | null {
  const { x } = locate(score, staff, m, voice, eventId);
  if (x.ev.type !== 'chord') return null;
  if (x.ev.notes.length <= 1) return deleteEvent(score, staff, m, voice, eventId);
  x.ev.notes = x.ev.notes.filter((n) => n.id !== noteId);
  return x.ev.id;
}

/** Adds a pitch to an event (a rest becomes a chord). Returns the note id. */
export function addPitchToEvent(score: Score, staff: number, m: number, voice: number, eventId: string, p: Pitch, line?: string): string {
  const { events, x } = locate(score, staff, m, voice, eventId);
  if (x.ev.type === 'rest') {
    const note: Note = { id: newId('n'), ...pick(p) };
    const c: ChordEvent = { id: x.ev.id, type: 'chord', dur: { ...x.ev.dur }, notes: [note] };
    if (x.ev.tuplet) c.tuplet = x.ev.tuplet;
    if (x.ev.fermata) c.fermata = true;
    if (line) c.line = line;
    events[x.index] = c;
    return note.id;
  }
  const existing = x.ev.notes.find((n) => n.step === p.step && n.octave === p.octave);
  if (existing) {
    existing.alter = p.alter;
    return existing.id;
  }
  const note: Note = { id: newId('n'), ...pick(p) };
  x.ev.notes.push(note);
  sortNotes(x.ev.notes);
  return note.id;
}

function pick(p: Pitch): Pitch {
  return { step: p.step, octave: p.octave, alter: p.alter };
}

/** Sets the pitch of a single note, keeping the chord free of duplicates. */
export function setNotePitch(score: Score, staff: number, m: number, voice: number, eventId: string, noteId: string, p: Pitch): boolean {
  const { x } = locate(score, staff, m, voice, eventId);
  if (x.ev.type !== 'chord') return false;
  const note = x.ev.notes.find((n) => n.id === noteId);
  if (!note) return false;
  if (x.ev.notes.some((n) => n !== note && diatonicOf(n) === diatonicOf(p))) return false;
  note.step = p.step;
  note.octave = p.octave;
  note.alter = p.alter;
  sortNotes(x.ev.notes);
  return true;
}

export function toggleTie(score: Score, staff: number, m: number, voice: number, eventId: string, noteId?: string): void {
  const { x } = locate(score, staff, m, voice, eventId);
  if (x.ev.type !== 'chord') return;
  const targets = noteId ? x.ev.notes.filter((n) => n.id === noteId) : x.ev.notes;
  const on = !targets.every((n) => n.tie);
  for (const n of targets) {
    if (on) n.tie = true;
    else delete n.tie;
  }
}

/** The event following an event in the same voice (possibly in the next measure). */
export function nextEventInVoice(score: Score, staff: number, m: number, voice: number, eventId: string): { ev: VoiceEvent; m: number } | null {
  const st = getStaff(score, staff);
  const events = st.measures[m].voices[voice] ?? [];
  const i = events.findIndex((e) => e.id === eventId);
  if (i >= 0 && i + 1 < events.length) return { ev: events[i + 1], m };
  const next = st.measures[m + 1]?.voices[voice];
  if (next && next.length) return { ev: next[0], m: m + 1 };
  return null;
}

/** True if the note's tie resolves to an equal pitch in the next event. */
export function tieResolves(score: Score, staff: number, m: number, voice: number, eventId: string, note: Pitch): boolean {
  const nx = nextEventInVoice(score, staff, m, voice, eventId);
  return !!nx && nx.ev.type === 'chord' && nx.ev.notes.some((n) => samePitch(n, note));
}

// ───────────────────────────── tuplets & grace notes ─────────────────────────────

/** Default denominator: the largest power of two below the number of notes (3:2, 5:4, 7:4, 9:8 …). */
export function defaultTupletDen(num: number): number {
  if (num === 2) return 3;
  let d = 1;
  while (d * 2 < num) d *= 2;
  return d;
}

/**
 * Creates a tuplet of `num` notes in the time of `den` spanning `total` at
 * (m, t). The first member keeps the pitches of the event that was there.
 * Returns the first member's id, or an error message.
 */
export function createTuplet(score: Score, staff: number, m: number, voice: number, t: Frac, total: Frac, num: number, den = defaultTupletDen(num)): { id: string; unit: Duration } | string {
  if (num < 2 || num > 32 || den < 1) return 'Неверное отношение группы';
  if (gt(add(t, total), measureLen(score, m))) return 'Ритмическая группа не помещается в такт';
  const unit = fracToDuration(div(total, frac(den)), 1);
  if (!unit) return 'Для этой длительности нельзя построить такую группу';
  const events = ensureVoice(score, staff, m, voice);
  if (tupletAt(events, t)) return 'Здесь уже есть ритмическая группа';
  const at = timeline(events).find((x) => le(x.start, t) && lt(t, x.end) && !(x.ev.type === 'chord' && x.ev.grace));
  const tup: Tuplet = { id: newId('t'), num, den };
  const members: VoiceEvent[] = Array.from({ length: num }, (_, i) => {
    if (i === 0 && at && at.ev.type === 'chord') {
      const c = newChord(unit, at.ev.notes, pieceAttrs(chordAttrs(at.ev), 0, 1));
      delete c.fermata;
      c.tuplet = tup;
      return c;
    }
    const r = makeRest(unit);
    r.tuplet = tup;
    return r;
  });
  staffMeasure(score, staff, m).voices[voice] = overwriteSpan(events, t, total, members);
  return { id: members[0].id, unit };
}

/** Removes the tuplet containing an event, leaving rests in its place. */
export function removeTuplet(score: Score, staff: number, m: number, voice: number, eventId: string): string | null {
  const { events, x } = locate(score, staff, m, voice, eventId);
  if (!x.ev.tuplet) return null;
  const blk = tupletAt(events, x.start)!;
  const i0 = events.indexOf(blk.events[0]);
  const firstChord = blk.events.find((e) => e.type === 'chord') as ChordEvent | undefined;
  const len = sub(blk.end, blk.start);
  const repl: VoiceEvent[] = firstChord
    ? decomposeNote(blk.start, len).map((d, i, a) => {
        const c = newChord(d, firstChord.notes, pieceAttrs(chordAttrs(firstChord), i, a.length));
        if (i < a.length - 1) c.notes.forEach((n) => (n.tie = true));
        return c;
      })
    : restsFor(blk.start, len);
  events.splice(i0, blk.events.length, ...repl);
  return repl[0].id;
}

/** Inserts a grace note (copy of the chord's pitches) in front of a chord. */
export function addGrace(score: Score, staff: number, m: number, voice: number, eventId: string, kind: 'acciaccatura' | 'appoggiatura'): string | null {
  const { events, x } = locate(score, staff, m, voice, eventId);
  const ev = x.ev;
  if (ev.type !== 'chord') return null;
  if (ev.grace) {
    ev.grace = kind;
    return ev.id;
  }
  const g = newChord({ base: kind === 'acciaccatura' ? 8 : 16, dots: 0 }, ev.notes);
  g.grace = kind;
  if (ev.line) g.line = ev.line;
  if (ev.staffShift) g.staffShift = ev.staffShift;
  events.splice(x.index, 0, g);
  return g.id;
}

// ───────────────────────────── marks on events ─────────────────────────────

const EXCLUSIVE: Partial<Record<Articulation, Articulation>> = { staccato: 'staccatissimo', staccatissimo: 'staccato', accent: 'marcato', marcato: 'accent' };

export function toggleArticulation(ev: ChordEvent, a: Articulation, on?: boolean): void {
  const cur = new Set(ev.artics ?? []);
  const enable = on ?? !cur.has(a);
  if (enable) {
    cur.add(a);
    const ex = EXCLUSIVE[a];
    if (ex) cur.delete(ex);
  } else cur.delete(a);
  if (cur.size) ev.artics = [...cur];
  else delete ev.artics;
}

export function setOrnament(ev: ChordEvent, o: Ornament | undefined): void {
  if (!o || ev.ornament === o) delete ev.ornament;
  else ev.ornament = o;
}

export function setDynamic(ev: ChordEvent, d: Dynamic | undefined): void {
  if (!d || ev.dynamic === d) delete ev.dynamic;
  else ev.dynamic = d;
}

export function toggleFermata(ev: VoiceEvent): void {
  if (ev.fermata) delete ev.fermata;
  else ev.fermata = true;
}

/** Moves a chord to the staff above/below for display (cross-staff notation). */
export function shiftStaff(score: Score, staff: number, ev: ChordEvent, delta: number): boolean {
  const target = (ev.staffShift ?? 0) + delta;
  if (staff + target < 0 || staff + target >= staffCount(score)) return false;
  if (target === 0) delete ev.staffShift;
  else ev.staffShift = target;
  return true;
}

export function cycleStem(ev: ChordEvent): void {
  ev.stem = ev.stem === undefined ? 'up' : ev.stem === 'up' ? 'down' : undefined;
  if (!ev.stem) delete ev.stem;
}

export function setBeamMode(ev: ChordEvent, mode: ChordEvent['beam'] | undefined): void {
  if (!mode || ev.beam === mode) delete ev.beam;
  else ev.beam = mode;
}

// ───────────────────────────── spanners ─────────────────────────────

export function addSpanner(score: Score, type: SpannerType, start: string, end: string, ottava?: number): string {
  const existing = score.spanners.find((s) => s.type === type && s.start === start && s.end === end && s.ottava === ottava);
  if (existing) return existing.id;
  const sp = { id: newId('sp'), type, start, end, ...(ottava ? { ottava } : {}) };
  score.spanners.push(sp);
  return sp.id;
}

/** Removes spanners of a type (or all types) that start or end at any of the events. */
export function removeSpanners(score: Score, eventIds: Set<string>, type?: SpannerType): number {
  const before = score.spanners.length;
  score.spanners = score.spanners.filter((s) => !((eventIds.has(s.start) || eventIds.has(s.end)) && (!type || s.type === type)));
  return before - score.spanners.length;
}

// ───────────────────────────── measure-level marks ─────────────────────────────

export function setRepeatStart(score: Score, m: number, on: boolean): void {
  if (on) score.measures[m].repeatStart = true;
  else delete score.measures[m].repeatStart;
}

export function setRepeatEnd(score: Score, m: number, times: number | undefined): void {
  if (times && times >= 2) score.measures[m].repeatEnd = Math.min(16, Math.round(times));
  else delete score.measures[m].repeatEnd;
}

export function setVolta(score: Score, from: number, to: number, numbers: number[] | undefined): void {
  const id = newId('v');
  for (let m = from; m <= to; m++) {
    if (numbers && numbers.length) score.measures[m].volta = { id, numbers: [...numbers] };
    else delete score.measures[m].volta;
  }
}

export function setMarker(score: Score, m: number, marker: MarkerKind | undefined): void {
  if (!marker || score.measures[m].marker === marker) delete score.measures[m].marker;
  else score.measures[m].marker = marker;
}

export function setJump(score: Score, m: number, jump: JumpKind | undefined): void {
  if (!jump || score.measures[m].jump === jump) delete score.measures[m].jump;
  else score.measures[m].jump = jump;
}

export function setBarline(score: Score, m: number, barline: MeasureInfo['barline']): void {
  if (!barline || score.measures[m].barline === barline) delete score.measures[m].barline;
  else score.measures[m].barline = barline;
}

export function setMeasureTempo(score: Score, m: number, tempo: Tempo | undefined): void {
  if (m === 0 && tempo) {
    score.tempo = { ...tempo };
    delete score.measures[0].tempo;
    return;
  }
  if (tempo) score.measures[m].tempo = { ...tempo };
  else delete score.measures[m].tempo;
}

// ───────────────────────────── signatures & clefs ─────────────────────────────

export function setKeySig(score: Score, m: number, fifths: number): void {
  score.measures[m].keySig = Math.max(-7, Math.min(7, Math.round(fifths)));
}

/** Sets the clef from measure `m` (measure 0 sets the initial clef of the staff). */
export function setClef(score: Score, staff: number, clef: ClefKind, m = 0): void {
  const st = getStaff(score, staff);
  if (m <= 0) {
    st.clef = clef;
    delete st.measures[0].clef;
  } else st.measures[m].clef = clef;
}

export function removeClefChange(score: Score, staff: number, m: number): void {
  delete getStaff(score, staff).measures[m].clef;
}

/**
 * Sets a time signature at measure `m` and re-bars the music up to the next
 * time signature change. Notes crossing the new barlines are split and tied;
 * measure marks move to the new measure that contains their old position.
 */
export function setTimeSig(score: Score, m: number, ts: TimeSig): void {
  const sigs = effectiveTimeSigs(score);
  let end = m + 1;
  while (end < score.measures.length && !score.measures[end].timeSig) end++;
  const oldCount = end - m;
  const old = sigs[m];
  if (old.count === ts.count && old.unit === ts.unit) {
    score.measures[m].timeSig = { ...ts };
    return;
  }
  const offsets: Frac[] = [];
  let total = ZERO;
  for (let i = m; i < end; i++) {
    offsets.push(total);
    total = add(total, measureLength(sigs[i]));
  }
  const newLen = measureLength(ts);
  let newCount = 0;
  for (let acc = ZERO; lt(acc, total); acc = add(acc, newLen)) newCount++;
  newCount = Math.max(1, newCount);
  const indexAt = (offset: Frac) => {
    let idx = 0;
    for (let acc = newLen; le(acc, offset) && idx < newCount - 1; acc = add(acc, newLen)) idx++;
    return idx;
  };

  // Flatten each staff/voice of the region.
  const nStaves = staffCount(score);
  const flat: VoiceEvent[][][] = [];
  const clefChanges: { staff: number; offset: Frac; clef: ClefKind }[] = [];
  for (let s = 0; s < nStaves; s++) {
    const st = getStaff(score, s);
    flat[s] = [];
    for (let i = m; i < end; i++) {
      const c = st.measures[i].clef;
      if (c) clefChanges.push({ staff: s, offset: offsets[i - m], clef: c });
    }
    for (let v = 0; v < MAX_VOICES; v++) {
      const seq: VoiceEvent[] = [];
      let used = false;
      for (let i = m; i < end; i++) {
        const evs = st.measures[i].voices[v] ?? [];
        if (evs.length) {
          used = true;
          seq.push(...evs);
        } else {
          seq.push(...restsFor(ZERO, measureLength(sigs[i])));
        }
      }
      flat[s][v] = used ? seq : [];
    }
  }

  const infos: MeasureInfo[] = Array.from({ length: newCount }, (_, i) => (i === 0 ? { id: score.measures[m].id } : { id: newId('m') }));
  for (let i = m; i < end; i++) {
    const { id: _id, timeSig: _ts, ...rest } = score.measures[i];
    const startIdx = indexAt(offsets[i - m]);
    const endIdx = indexAt(sub(add(offsets[i - m], measureLength(sigs[i])), frac(1, 4096)));
    const { repeatEnd, jump, barline, volta, ...startMarks } = rest;
    Object.assign(infos[startIdx], structuredClone(startMarks));
    if (repeatEnd) infos[endIdx].repeatEnd = repeatEnd;
    if (jump) infos[endIdx].jump = jump;
    if (barline) infos[endIdx].barline = barline;
    if (volta) for (let k = startIdx; k <= endIdx; k++) infos[k].volta = { ...volta, numbers: [...volta.numbers] };
  }
  infos[0].timeSig = { ...ts };
  score.measures.splice(m, oldCount, ...infos);
  for (let s = 0; s < nStaves; s++) {
    getStaff(score, s).measures.splice(m, oldCount, ...Array.from({ length: newCount }, () => emptyStaffMeasure(newLen)));
  }
  for (const c of clefChanges) getStaff(score, c.staff).measures[m + indexAt(c.offset)].clef = c.clef;
  const idMap = new Map<string, string>();
  for (let s = 0; s < nStaves; s++) {
    for (let v = 0; v < MAX_VOICES; v++) {
      const seq = flat[s][v];
      if (!seq.length) continue;
      writeSequence(score, s, m, v, seq, m + newCount);
      for (let i = m; i < m + newCount; i++) pruneVoice(score, s, i, v);
    }
  }
  remapSpanners(score, flat, m, m + newCount, idMap);
}

/**
 * After music has been rewritten with new ids (re-barring), re-attach spanners
 * to the events now occupying the same positions.
 */
function remapSpanners(score: Score, oldFlat: VoiceEvent[][][], from: number, to: number, idMap: Map<string, string>) {
  if (!score.spanners.length) return;
  for (let s = 0; s < oldFlat.length; s++) {
    for (let v = 0; v < oldFlat[s].length; v++) {
      const oldSeq = oldFlat[s][v];
      if (!oldSeq.length) continue;
      const newSeq: VoiceEvent[] = [];
      for (let i = from; i < to; i++) newSeq.push(...(getStaff(score, s).measures[i].voices[v] ?? []));
      const oldTl = timeline(oldSeq);
      const newTl = timeline(newSeq);
      for (const o of oldTl) {
        const hit = newTl.find((n) => cmp(n.start, o.start) === 0 && n.ev.type === o.ev.type);
        if (hit) idMap.set(o.ev.id, hit.ev.id);
      }
    }
  }
  for (const sp of score.spanners) {
    sp.start = idMap.get(sp.start) ?? sp.start;
    sp.end = idMap.get(sp.end) ?? sp.end;
  }
}

// ───────────────────────────── transposition ─────────────────────────────

/** Interval in diatonic steps + semitones, e.g. major third up = (2, 4). */
export interface Interval {
  steps: number;
  semitones: number;
}

/** Transposes a pitch by an interval, keeping correct spelling. */
export function transposePitch(p: Pitch, iv: Interval): Pitch {
  const d = diatonicOf(p) + iv.steps;
  const octave = Math.floor(d / 7);
  const step = (['C', 'D', 'E', 'F', 'G', 'A', 'B'] as const)[((d % 7) + 7) % 7];
  const target = midiOf(p) + iv.semitones;
  const natural = midiOf({ step, octave, alter: 0 });
  const alter = target - natural;
  if (alter < -2 || alter > 2) return pitchFromMidi(target, iv.semitones < 0);
  return { step, octave, alter };
}

/** Fifths shift of an interval (major second = +2, minor third = -3 …). */
export function intervalFifths(iv: Interval): number {
  for (let f = -11; f <= 11; f++) {
    if ((((f * 4) % 7) + 7) % 7 === (((iv.steps % 7) + 7) % 7) && (((f * 7) % 12) + 12) % 12 === (((iv.semitones % 12) + 12) % 12)) return f;
  }
  return 0;
}

export function transposeKey(fifths: number, iv: Interval): number {
  let k = fifths + intervalFifths(iv);
  while (k > 7) k -= 12;
  while (k < -7) k += 12;
  if (k === 7 && fifths + intervalFifths(iv) > 7) k = -5;
  return k;
}

/** Transposes every note in measures [from, to] of the given staves, optionally with key signatures. */
export function transposeRange(score: Score, staves: number[], from: number, to: number, iv: Interval, keys: boolean): void {
  for (const s of staves) {
    const st = getStaff(score, s);
    for (let m = from; m <= to; m++)
      for (const v of st.measures[m].voices)
        for (const ev of v) {
          if (ev.type !== 'chord') continue;
          for (const n of ev.notes) Object.assign(n, transposePitch(n, iv));
          sortNotes(ev.notes);
        }
  }
  if (keys) {
    let last: number | undefined;
    for (let m = 0; m <= to; m++) {
      const k = score.measures[m].keySig;
      if (k !== undefined) last = k;
      if (m >= from && k !== undefined) score.measures[m].keySig = transposeKey(k, iv);
    }
    if (score.measures[from].keySig === undefined && last !== undefined) score.measures[from].keySig = transposeKey(last, iv);
    if (to + 1 < score.measures.length && score.measures[to + 1].keySig === undefined && last !== undefined) score.measures[to + 1].keySig = last;
  }
}

/** Upper / lower diatonic neighbour of a pitch in a key (for ornaments). */
export function neighbour(p: Pitch, dir: 1 | -1, key: number): Pitch {
  const d = diatonicOf(p) + dir;
  const octave = Math.floor(d / 7);
  const step = (['C', 'D', 'E', 'F', 'G', 'A', 'B'] as const)[((d % 7) + 7) % 7];
  return { step, octave, alter: keyAlter(key, step) };
}

// ───────────────────────────── clipboard ─────────────────────────────

export interface Clip {
  /** For each copied staff, the flattened events of every voice (null = voice unused). */
  staves: (VoiceEvent[] | null)[][];
  length: Frac;
  measures: number;
}

export function copyRange(score: Score, staffFrom: number, staffTo: number, mFrom: number, mTo: number): Clip {
  const staves: (VoiceEvent[] | null)[][] = [];
  let length = ZERO;
  for (let i = mFrom; i <= mTo; i++) length = add(length, measureLen(score, i));
  for (let s = staffFrom; s <= staffTo; s++) {
    const st = getStaff(score, s);
    const voices: (VoiceEvent[] | null)[] = [];
    for (let v = 0; v < MAX_VOICES; v++) {
      let used = false;
      const seq: VoiceEvent[] = [];
      for (let i = mFrom; i <= mTo; i++) {
        const evs = st.measures[i].voices[v] ?? [];
        if (evs.length) used = true;
        seq.push(...(evs.length ? structuredClone(evs) : restsFor(ZERO, measureLen(score, i))));
      }
      voices.push(used ? seq : null);
    }
    staves.push(voices);
  }
  return { staves, length, measures: mTo - mFrom + 1 };
}

/** Pastes a clip at the start of measure `m` on staff `staff`, overwriting existing music. */
export function pasteClip(score: Score, clip: Clip, staff: number, m: number): { lastMeasure: number } {
  let lastMeasure = m;
  const n = staffCount(score);
  // Make sure the whole target span exists.
  let have = ZERO;
  for (let i = m; i < score.measures.length; i++) have = add(have, measureLen(score, i));
  while (lt(have, clip.length)) {
    appendMeasures(score, 1);
    have = add(have, measureLen(score, score.measures.length - 1));
  }
  clip.staves.forEach((voices, i) => {
    const s = staff + i;
    if (s >= n) return;
    for (let v = 0; v < MAX_VOICES; v++) {
      clearSpan(score, s, m, v, ZERO, clip.length);
      const seq = voices[v];
      if (seq) lastMeasure = Math.max(lastMeasure, writeSequence(score, s, m, v, seq));
      if (v > 0) {
        const end = advance(score, m, ZERO, clip.length);
        for (let k = m; k <= Math.min(end.m, score.measures.length - 1); k++) pruneVoice(score, s, k, v);
      }
    }
  });
  return { lastMeasure };
}

/** Clears measures (all voices) on the given staves, leaving full-measure rests. */
export function clearRange(score: Score, staffFrom: number, staffTo: number, mFrom: number, mTo: number): void {
  for (let s = staffFrom; s <= staffTo; s++) {
    const st = getStaff(score, s);
    for (let i = mFrom; i <= mTo; i++) st.measures[i] = { ...emptyStaffMeasure(measureLen(score, i)), ...(st.measures[i].clef ? { clef: st.measures[i].clef } : {}) };
  }
}

/** Sanity check used by tests and the file validator. */
export function voiceFillsMeasure(events: VoiceEvent[], len: Frac): boolean {
  return events.length === 0 || cmp(voiceLength(events), len) === 0;
}
