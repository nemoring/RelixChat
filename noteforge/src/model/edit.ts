/**
 * Editing operations on the score model.
 *
 * All functions mutate the score passed in (normally an Immer draft) and keep
 * the model invariant: every non-empty voice exactly fills its measure.
 * Entering music uses MuseScore-like "overwrite" semantics: writing an event
 * of length L at time t replaces whatever was in [t, t+L) of that voice;
 * music that crosses a barline is split and tied automatically.
 */
import type { ChordEvent, ClefKind, Duration, MeasureInfo, Note, Score, StaffMeasure, TimeSig, VoiceEvent } from './types';
import { MAX_VOICES } from './types';
import { Frac, ZERO, add, sub, lt, le, gt, isZero, min, eq, cmp } from './fraction';
import { decomposeNote, durToFrac, measureLength } from './duration';
import { getStaff, measureLen, staffCount, timeSigAt, timeline, voiceLength, effectiveTimeSigs } from './query';
import { emptyStaffMeasure, makeRest, measureRests, restsFor } from './factory';
import { newId } from './ids';
import type { Pitch } from './pitch';
import { sortNotes, diatonicOf, samePitch } from './pitch';

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
  // Carry the signature changes in effect at the end of the range to the next measure,
  // so the music after the deleted range keeps its meter and key.
  const nextIdx = to + 1;
  if (nextIdx < score.measures.length) {
    const next = score.measures[nextIdx];
    if (!next.timeSig) next.timeSig = { ...timeSigAt(score, to) };
    if (next.keySig === undefined) {
      for (let i = to; i >= 0; i--) {
        if (score.measures[i].keySig !== undefined) {
          next.keySig = score.measures[i].keySig;
          break;
        }
      }
    }
  }
  const count = to - from + 1;
  score.measures.splice(from, count);
  for (let s = 0; s < staffCount(score); s++) getStaff(score, s).measures.splice(from, count);
  if (!score.measures[0].timeSig) score.measures[0].timeSig = { count: 4, unit: 4 };
  if (score.measures[0].keySig === undefined) score.measures[0].keySig = 0;
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

function cloneChordWith(ev: ChordEvent, dur: Duration, tie: boolean | 'keep'): ChordEvent {
  return {
    id: newId('c'),
    type: 'chord',
    dur: { ...dur },
    notes: ev.notes.map((n) => {
      const c: Note = { id: newId('n'), step: n.step, octave: n.octave, alter: n.alter };
      if (tie === true || (tie === 'keep' && n.tie)) c.tie = true;
      return c;
    }),
  };
}

/** Writes `pieces` of a chord split at `durs`, tying them together. */
function splitChord(ev: ChordEvent, durs: Duration[], keepFirstId: boolean, lastTie: boolean | 'keep'): ChordEvent[] {
  return durs.map((d, i) => {
    const last = i === durs.length - 1;
    const c = cloneChordWith(ev, d, last ? lastTie : true);
    if (i === 0 && keepFirstId) {
      c.id = ev.id;
      c.notes.forEach((n, k) => (n.id = ev.notes[k].id));
    }
    return c;
  });
}

/**
 * Replaces the span [t, t+len) of a full voice with `insert` (whose total length must be len).
 * Events cut at the start are shortened; the cut-off tail of an event is turned into rests.
 */
export function overwriteSpan(events: VoiceEvent[], t: Frac, len: Frac, insert: VoiceEvent[]): VoiceEvent[] {
  const end = add(t, len);
  const before: VoiceEvent[] = [];
  const after: VoiceEvent[] = [];
  for (const x of timeline(events)) {
    if (le(x.end, t)) {
      before.push(x.ev);
    } else if (le(end, x.start)) {
      after.push(x.ev);
    } else {
      if (lt(x.start, t)) {
        const headLen = sub(t, x.start);
        if (x.ev.type === 'chord') before.push(...splitChord(x.ev, decomposeNote(x.start, headLen), true, false));
        else before.push(...restsFor(x.start, headLen));
      }
      if (gt(x.end, end)) after.unshift(...restsFor(end, sub(x.end, end)));
    }
  }
  return [...before, ...insert, ...after];
}

export type Template = { type: 'rest' } | { type: 'chord'; notes: (Pitch & { tie?: boolean })[] };

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

/**
 * Writes an event of total length `len` at (measure m, time t) in a voice.
 * If it does not fit before the barline it continues into following measures
 * (appending measures at the end of the score when needed) as tied notes.
 */
export function writeAt(score: Score, staff: number, m: number, voice: number, t: Frac, len: Frac, tpl: Template): WriteResult {
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
    const pieces: VoiceEvent[] = durs.map((d) =>
      tpl.type === 'rest'
        ? makeRest(d)
        : {
            id: newId('c'),
            type: 'chord' as const,
            dur: { ...d },
            notes: tpl.notes.map((p) => ({ id: newId('n'), step: p.step, octave: p.octave, alter: p.alter })),
          },
    );
    staffMeasure(score, staff, curM).voices[voice] = overwriteSpan(events, curT, seg, pieces);
    for (const p of pieces) written.push({ ev: p, m: curM });
    remaining = sub(remaining, seg);
    curT = add(curT, seg);
    if (eq(curT, mlen) && !isZero(remaining)) {
      curM++;
      curT = ZERO;
    }
  }
  // Tie chain: every piece except the last ties into the next; the last keeps the template's ties.
  if (tpl.type === 'chord') {
    written.forEach((w, i) => {
      const ev = w.ev as ChordEvent;
      const last = i === written.length - 1;
      ev.notes.forEach((n, k) => {
        if (!last || tpl.notes[k].tie) n.tie = true;
      });
      sortNotes(ev.notes);
    });
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

/**
 * Writes a sequence of events starting at (m, 0). Rests only advance time:
 * the target span is expected to be cleared already, so the remaining gaps
 * keep cleanly aligned rests.
 */
function writeSequence(score: Score, staff: number, m: number, voice: number, seq: VoiceEvent[], limitMeasure?: number): number {
  let pos = { m, t: ZERO as Frac };
  let last = m;
  for (const ev of seq) {
    if (limitMeasure !== undefined && pos.m >= limitMeasure) break;
    const len = durToFrac(ev.dur);
    if (ev.type === 'chord') {
      const r = writeAt(score, staff, pos.m, voice, pos.t, len, { type: 'chord', notes: ev.notes.map((n) => ({ ...n })) });
      last = Math.max(last, r.lastMeasure);
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
  const oldLen = sub(x.end, x.start);
  const newLen = durToFrac(dur);
  const ev = x.ev;
  if (le(newLen, oldLen)) {
    const changed: VoiceEvent = { ...ev, dur: { ...dur } } as VoiceEvent;
    const pad = restsFor(add(x.start, newLen), sub(oldLen, newLen));
    staffMeasure(score, staff, m).voices[voice] = [...events.slice(0, x.index), changed, ...pad, ...events.slice(x.index + 1)];
    return { firstId: ev.id, firstMeasure: m, lastId: ev.id, lastMeasure: m, endMeasure: m, endTime: add(x.start, newLen) };
  }
  const tpl: Template = ev.type === 'rest' ? { type: 'rest' } : { type: 'chord', notes: ev.notes.map((n) => ({ ...n })) };
  const r = writeAt(score, staff, m, voice, x.start, newLen, tpl);
  // Preserve the identity of the first piece so the selection stays on it.
  const first = staffMeasure(score, staff, r.firstMeasure).voices[voice].find((e) => e.id === r.firstId);
  if (first && first.type === ev.type) {
    first.id = ev.id;
    if (first.type === 'chord' && ev.type === 'chord') first.notes.forEach((n, k) => (n.id = ev.notes[k]?.id ?? n.id));
    if (r.lastId === r.firstId) r.lastId = ev.id;
    r.firstId = ev.id;
  }
  return r;
}

/** Turns an event into a rest of the same length (or removes a whole secondary voice). */
export function deleteEvent(score: Score, staff: number, m: number, voice: number, eventId: string): string | null {
  const { events, x } = locate(score, staff, m, voice, eventId);
  if (x.ev.type === 'rest') {
    if (voice > 0) {
      pruneVoice(score, staff, m, voice);
      return null;
    }
    return x.ev.id;
  }
  const rest = makeRest(x.ev.dur);
  events[x.index] = rest;
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
export function addPitchToEvent(score: Score, staff: number, m: number, voice: number, eventId: string, p: Pitch): string {
  const { events, x } = locate(score, staff, m, voice, eventId);
  if (x.ev.type === 'rest') {
    const note: Note = { id: newId('n'), ...pick(p) };
    events[x.index] = { id: x.ev.id, type: 'chord', dur: { ...x.ev.dur }, notes: [note] };
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

/** The chord following an event in the same voice (possibly in the next measure). */
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

// ───────────────────────────── signatures ─────────────────────────────

export function setKeySig(score: Score, m: number, fifths: number): void {
  score.measures[m].keySig = Math.max(-7, Math.min(7, Math.round(fifths)));
}

export function setClef(score: Score, staff: number, clef: ClefKind): void {
  getStaff(score, staff).clef = clef;
}

/**
 * Sets a time signature at measure `m` and re-bars the music up to the next
 * time signature change. Notes crossing the new barlines are split and tied.
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
  // Total length of the region and the start offsets of key changes inside it.
  let total = ZERO;
  const keyChanges: { offset: Frac; key: number }[] = [];
  for (let i = m; i < end; i++) {
    const k = score.measures[i].keySig;
    if (k !== undefined) keyChanges.push({ offset: total, key: k });
    total = add(total, measureLength(sigs[i]));
  }
  const newLen = measureLength(ts);
  let newCount = 0;
  for (let acc = ZERO; lt(acc, total); acc = add(acc, newLen)) newCount++;
  newCount = Math.max(1, newCount);

  // Flatten each staff/voice of the region.
  const nStaves = staffCount(score);
  const flat: VoiceEvent[][][] = [];
  for (let s = 0; s < nStaves; s++) {
    const st = getStaff(score, s);
    flat[s] = [];
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
  infos[0].timeSig = { ...ts };
  for (const kc of keyChanges) {
    let idx = 0;
    for (let acc = newLen; le(acc, kc.offset) && idx < newCount - 1; acc = add(acc, newLen)) idx++;
    infos[idx].keySig = kc.key;
  }
  score.measures.splice(m, oldCount, ...infos);
  for (let s = 0; s < nStaves; s++) {
    getStaff(score, s).measures.splice(m, oldCount, ...Array.from({ length: newCount }, () => emptyStaffMeasure(newLen)));
  }
  for (let s = 0; s < nStaves; s++) {
    for (let v = 0; v < MAX_VOICES; v++) {
      const seq = flat[s][v];
      if (!seq.length) continue;
      writeSequence(score, s, m, v, seq, m + newCount);
      for (let i = m; i < m + newCount; i++) pruneVoice(score, s, i, v);
    }
  }
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
    for (let i = mFrom; i <= mTo; i++) st.measures[i] = emptyStaffMeasure(measureLen(score, i));
  }
}

/** Sanity check used by tests and the file validator. */
export function voiceFillsMeasure(events: VoiceEvent[], len: Frac): boolean {
  return events.length === 0 || cmp(voiceLength(events), len) === 0;
}

