/**
 * Editor commands. Every menu item, toolbar button and shortcut calls one of
 * these; they translate UI intent into model edits (src/model/edit.ts).
 */
import type { ClefKind, DurBase, Score, Step, TimeSig, ChordEvent } from '../model/types';
import { MAX_VOICES } from '../model/types';
import { Frac, ZERO, lt, le } from '../model/fraction';
import { durToFrac } from '../model/duration';
import * as E from '../model/edit';
import { findEvent, getStaff, keyAt, previousChord, staffCount, timeline, clefAt } from '../model/query';
import { clefMiddle, diatonicOf, fromDiatonic, keyAlter, midiOf, nearestOctave, pitchFromMidi, MIDI_MAX, MIDI_MIN, type Pitch } from '../model/pitch';
import { createPianoScore, type NewScoreOptions } from '../model/factory';
import { parseProject, serializeProject } from '../model/serialize';
import { commit, getState, setState, undo, redo, loadDocument, isDirty, type Selection, type Cursor, type AppState } from './store';
import { platform } from '../platform';
import { previewSelection } from './playback';
import { selectedEvents, selectionMeasures } from './selection';

export { undo, redo };

let clipboard: E.Clip | null = null;

// ───────────────────────────── helpers ─────────────────────────────

function selectedEvent() {
  const sel = getState().selection;
  if (sel.kind !== 'event') return null;
  return findEvent(getState().score, sel.eventId, sel);
}

const reveal = (measure: number): Partial<AppState> => ({ reveal: { measure, token: Date.now() + Math.random() } });

function selectionFromWrite(staff: number, voice: number, r: E.WriteResult, score: Score): Selection {
  const found = findEvent(score, r.firstId, { staff, measure: r.firstMeasure, voice });
  const noteId = found && found.ev.type === 'chord' ? found.ev.notes[0]?.id : undefined;
  return { kind: 'event', staff, measure: r.firstMeasure, voice, eventId: r.firstId, noteId };
}

/** Reference pitch for choosing the octave of a letter entered at the cursor. */
function referenceDiatonic(score: Score, c: Cursor): number {
  const events = getStaff(score, c.staff).measures[c.measure]?.voices[c.voice] ?? [];
  const idx = timeline(events).findIndex((x) => le(c.time, x.start));
  const prev = previousChord(score, c.staff, c.measure, c.voice, idx < 0 ? events.length : idx);
  if (prev) return diatonicOf(prev.notes[prev.notes.length - 1]);
  for (let v = 0; v < MAX_VOICES; v++) {
    const p = previousChord(score, c.staff, c.measure, v, idx < 0 ? 999 : idx);
    if (p) return diatonicOf(p.notes[0]);
  }
  return clefMiddle(clefAt(score, c.staff, c.measure));
}

function defaultCursor(): Cursor {
  const { selection, input, score } = getState();
  if (selection.kind === 'event') {
    const f = findEvent(score, selection.eventId, selection);
    if (f) return { staff: f.staff, measure: f.measure, voice: f.voice, time: f.start };
  }
  if (selection.kind === 'range') return { staff: selection.staffFrom, measure: selection.mFrom, voice: input.voice, time: ZERO };
  return { staff: 0, measure: 0, voice: input.voice, time: ZERO };
}

// ───────────────────────────── note input ─────────────────────────────

export function toggleInputMode(on?: boolean): void {
  const s = getState();
  const active = on ?? !s.input.active;
  if (active === s.input.active) return;
  if (active) {
    const cursor = defaultCursor();
    setState({ input: { ...s.input, active: true, voice: cursor.voice }, cursor, status: 'Режим ввода нот: A–G — нота, 0 — пауза, 1–7 — длительность', ...reveal(cursor.measure) });
  } else {
    setState({ input: { ...s.input, active: false }, cursor: null, status: 'Режим выделения' });
  }
}

/** Writes a chord/rest of the current input duration at the cursor and advances. */
function writeAtCursor(label: string, tpl: E.Template, cursorOverride?: Cursor): void {
  const s = getState();
  const c = cursorOverride ?? s.cursor ?? defaultCursor();
  const len = durToFrac(s.input.dur);
  commit(label, (d) => {
    const r = E.writeAt(d, c.staff, c.measure, c.voice, c.time, len, tpl);
    if (r.endMeasure >= d.measures.length) E.appendMeasures(d, 1);
    const cursor: Cursor = { staff: c.staff, measure: r.endMeasure, voice: c.voice, time: r.endTime };
    return { selection: selectionFromWrite(c.staff, c.voice, r, d), cursor, ...reveal(r.endMeasure) };
  });
  if (tpl.type === 'chord') previewSelection();
}

/** Attributes for newly entered notes (the active melody line). */
function lineAttrs(): E.ChordAttrs | undefined {
  const line = getState().input.line;
  return line ? { line } : undefined;
}

/** Letter key A–G. With addToChord the pitch is added above the selected chord. */
export function enterNote(step: Step, addToChord = false): void {
  const s = getState();
  if (!s.input.active) {
    if (s.selection.kind === 'none') return;
    toggleInputMode(true);
  }
  const st = getState();
  const c = st.cursor!;
  const key = keyAt(st.score, c.measure);
  if (addToChord) {
    const sel = selectedEvent();
    if (sel && sel.ev.type === 'chord') {
      const top = sel.ev.notes[sel.ev.notes.length - 1];
      const topD = diatonicOf(top);
      let d = nearestOctave(step, topD) * 7 + ['C', 'D', 'E', 'F', 'G', 'A', 'B'].indexOf(step);
      while (d <= topD) d += 7;
      while (d - 7 > topD) d -= 7;
      const p = fromDiatonic(d);
      addPitch({ ...p, alter: keyAlter(keyAt(st.score, sel.measure), p.step) });
      return;
    }
  }
  const ref = referenceDiatonic(st.score, c);
  const octave = nearestOctave(step, ref);
  writeAtCursor(`Нота ${step}`, { type: 'chord', notes: [{ step, octave, alter: keyAlter(key, step) }], attrs: lineAttrs() });
}

/** Mouse entry: note at a staff position (diatonic) and time. */
export function enterNoteAt(staff: number, measure: number, time: Frac, diatonic: number, addToChord: boolean): void {
  const s = getState();
  const voice = s.input.voice;
  const p = fromDiatonic(diatonic);
  const pitch: Pitch = { ...p, alter: keyAlter(keyAt(s.score, measure), p.step) };
  if (addToChord) {
    const events = getStaff(s.score, staff).measures[measure]?.voices[voice] ?? [];
    const hit = timeline(events).find((x) => le(x.start, time) && lt(time, x.end));
    if (hit && hit.ev.type === 'chord') {
      setState({ selection: { kind: 'event', staff, measure, voice, eventId: hit.ev.id } });
      addPitch(pitch);
      return;
    }
  }
  const cursor: Cursor = { staff, measure, voice, time };
  if (s.input.rest) writeAtCursor('Пауза', { type: 'rest' }, cursor);
  else writeAtCursor(`Нота ${p.step}`, { type: 'chord', notes: [pitch], attrs: lineAttrs() }, cursor);
}

function addPitch(p: Pitch): void {
  const sel = selectedEvent();
  if (!sel) return;
  commit('Нота добавлена в аккорд', (d) => {
    const noteId = E.addPitchToEvent(d, sel.staff, sel.measure, sel.voice, sel.eventId, p);
    return { selection: { kind: 'event', staff: sel.staff, measure: sel.measure, voice: sel.voice, eventId: sel.eventId, noteId } };
  });
  previewSelection();
}

export function enterRest(): void {
  const s = getState();
  if (!s.input.active) {
    // Outside input mode "0" turns the selected chord into a rest.
    const sel = selectedEvent();
    if (sel && sel.ev.type === 'chord') {
      commit('Нота заменена паузой', (d) => {
        const id = E.deleteEvent(d, sel.staff, sel.measure, sel.voice, sel.eventId);
        return { selection: id ? { kind: 'event', staff: sel.staff, measure: sel.measure, voice: sel.voice, eventId: id } : { kind: 'none' } };
      });
    }
    return;
  }
  writeAtCursor('Пауза', { type: 'rest' });
}

export function setDurationBase(base: DurBase): void {
  const s = getState();
  setState({ input: { ...s.input, dur: { base, dots: 0 } } });
  if (!s.input.active && selectedEvent()) changeSelectedDuration({ base, dots: 0 });
}

export function toggleDot(): void {
  const s = getState();
  const dots = s.input.dur.dots ? 0 : 1;
  if (s.input.dur.base === 64 && dots) return;
  setState({ input: { ...s.input, dur: { ...s.input.dur, dots } } });
  if (!s.input.active) {
    const sel = selectedEvent();
    if (sel && sel.ev.dur.base < 64) changeSelectedDuration({ base: sel.ev.dur.base, dots: sel.ev.dur.dots ? 0 : 1 });
  }
}

function changeSelectedDuration(dur: { base: DurBase; dots: number }): void {
  const sel = selectedEvent();
  if (!sel) return;
  commit('Длительность изменена', (d) => {
    const r = E.setEventDuration(d, sel.staff, sel.measure, sel.voice, sel.eventId, dur);
    const s = getState().selection;
    return { selection: { kind: 'event', staff: sel.staff, measure: r.firstMeasure, voice: sel.voice, eventId: r.firstId, noteId: s.kind === 'event' ? s.noteId : undefined } };
  });
}

export function setVoice(voice: number): void {
  const s = getState();
  setState({ input: { ...s.input, voice }, cursor: s.cursor ? { ...s.cursor, voice } : null, status: `Голос ${voice + 1}` });
}

export function toggleRestMode(): void {
  const s = getState();
  setState({ input: { ...s.input, rest: !s.input.rest } });
}

// ───────────────────────────── pitch edits ─────────────────────────────

/** Notes affected by pitch commands: the selected note, or every note of the selected chords. */
function forEachSelectedNote(d: Score, fn: (n: ChordEvent['notes'][number], key: number) => void): void {
  const sel = getState().selection;
  for (const e of selectedEvents(d, sel)) {
    if (e.ev.type !== 'chord') continue;
    const key = keyAt(d, e.measure);
    for (const n of e.ev.notes) if (sel.kind !== 'event' || !sel.noteId || n.id === sel.noteId) fn(n, key);
  }
}

function sortSelectedChords(d: Score): void {
  for (const e of selectedEvents(d, getState().selection)) {
    const ev = e.ev;
    if (ev.type !== 'chord') continue;
    ev.notes.sort((a, b) => midiOf(a) - midiOf(b));
    // Remove exact duplicates that transposition may have produced.
    ev.notes = ev.notes.filter((n, i) => i === 0 || diatonicOf(n) !== diatonicOf(ev.notes[i - 1]) || n.alter !== ev.notes[i - 1].alter);
  }
}

export function transposeSelection(semitones: number): void {
  const sel = getState().selection;
  if (sel.kind === 'none') return;
  commit(semitones % 12 === 0 ? 'Перенос на октаву' : 'Транспонирование на полутон', (d) => {
    forEachSelectedNote(d, (n) => {
      if (semitones % 12 === 0) {
        const oct = n.octave + semitones / 12;
        if (midiOf({ ...n, octave: oct }) < MIDI_MIN || midiOf({ ...n, octave: oct }) > MIDI_MAX) return;
        n.octave = oct;
        return;
      }
      const target = midiOf(n) + semitones;
      if (target < MIDI_MIN || target > MIDI_MAX) return;
      const p = pitchFromMidi(target, semitones < 0);
      n.step = p.step;
      n.octave = p.octave;
      n.alter = p.alter;
    });
    sortSelectedChords(d);
  });
  previewSelection();
}

export function setAlter(alter: number): void {
  if (getState().selection.kind === 'none') return;
  commit('Знак альтерации', (d) => {
    forEachSelectedNote(d, (n) => {
      n.alter = n.alter === alter && alter !== 0 ? 0 : alter;
    });
  });
}

export function toggleTie(): void {
  const s = getState();
  const sel = selectedEvent();
  if (!sel || sel.ev.type !== 'chord') return;
  const ev = sel.ev;
  const noteId = s.selection.kind === 'event' ? s.selection.noteId : undefined;
  if (s.input.active && s.cursor) {
    // In input mode "+" repeats the selected chord at the cursor, tied from it.
    const tied = ev.notes.filter((n) => !noteId || n.id === noteId || ev.notes.length === 1);
    commit('Лига', (d) => {
      const f = findEvent(d, sel.eventId, sel);
      if (f && f.ev.type === 'chord') for (const n of f.ev.notes) if (tied.some((t) => t.id === n.id)) n.tie = true;
      const c = getState().cursor!;
      const r = E.writeAt(d, c.staff, c.measure, c.voice, c.time, durToFrac(getState().input.dur), {
        type: 'chord',
        notes: tied.map((n) => ({ step: n.step, octave: n.octave, alter: n.alter })),
      });
      if (r.endMeasure >= d.measures.length) E.appendMeasures(d, 1);
      return { selection: selectionFromWrite(c.staff, c.voice, r, d), cursor: { ...c, measure: r.endMeasure, time: r.endTime } };
    });
    return;
  }
  commit('Лига', (d) => E.toggleTie(d, sel.staff, sel.measure, sel.voice, sel.eventId, ev.notes.length > 1 ? noteId : undefined));
}

// ───────────────────────────── selection ─────────────────────────────

export function selectElement(ref: { staff: number; measure: number; voice: number; eventId: string; noteId?: string }, extend = false): void {
  const sel = getState().selection;
  if (extend && (sel.kind === 'event' || sel.kind === 'span')) {
    const anchor = sel.kind === 'event' ? { staff: sel.staff, measure: sel.measure, voice: sel.voice, eventId: sel.eventId } : sel.anchor;
    const focus = { staff: ref.staff, measure: ref.measure, voice: ref.voice, eventId: ref.eventId };
    if (anchor.eventId !== focus.eventId) {
      setState({ selection: { kind: 'span', anchor, focus } });
      return;
    }
  }
  setState({ selection: { kind: 'event', ...ref } });
  previewSelection();
}

/** Scrolls the score so that measure `m` is visible. */
export function revealMeasure(m: number): void {
  setState(reveal(m));
}

export function selectMeasure(staff: number, measure: number, extend: boolean): void {
  const sel = getState().selection;
  if (extend && sel.kind !== 'none') {
    const aStaff = sel.kind === 'range' ? sel.anchorStaff : sel.kind === 'span' ? sel.anchor.staff : sel.staff;
    const aM = sel.kind === 'range' ? sel.anchorMeasure : sel.kind === 'span' ? sel.anchor.measure : sel.measure;
    setState({
      selection: {
        kind: 'range',
        staffFrom: Math.min(aStaff, staff),
        staffTo: Math.max(aStaff, staff),
        mFrom: Math.min(aM, measure),
        mTo: Math.max(aM, measure),
        anchorStaff: aStaff,
        anchorMeasure: aM,
      },
    });
    return;
  }
  setState({ selection: { kind: 'range', staffFrom: staff, staffTo: staff, mFrom: measure, mTo: measure, anchorStaff: staff, anchorMeasure: measure } });
}

export function selectAll(): void {
  const { score } = getState();
  setState({
    selection: { kind: 'range', staffFrom: 0, staffTo: staffCount(score) - 1, mFrom: 0, mTo: score.measures.length - 1, anchorStaff: 0, anchorMeasure: 0 },
  });
}

export function clearSelection(): void {
  if (getState().input.active) toggleInputMode(false);
  else setState({ selection: { kind: 'none' } });
}

/** Left/Right: moves the cursor (input mode) or the selection by one event. */
export function moveHorizontal(dir: 1 | -1, extend = false): void {
  const s = getState();
  const { score } = s;
  if (s.input.active && s.cursor) {
    const c = s.cursor;
    const events = getStaff(score, c.staff).measures[c.measure].voices[c.voice].length
      ? getStaff(score, c.staff).measures[c.measure].voices[c.voice]
      : getStaff(score, c.staff).measures[c.measure].voices[0];
    const starts = timeline(events).map((x) => x.start);
    if (dir > 0) {
      const next = starts.find((t) => lt(c.time, t));
      if (next) setState({ cursor: { ...c, time: next } });
      else if (c.measure + 1 < score.measures.length) setState({ cursor: { ...c, measure: c.measure + 1, time: ZERO }, ...reveal(c.measure + 1) });
    } else {
      const prev = [...starts].reverse().find((t) => lt(t, c.time));
      if (prev) setState({ cursor: { ...c, time: prev } });
      else if (c.measure > 0) {
        const pe = getStaff(score, c.staff).measures[c.measure - 1].voices[0];
        const last = timeline(pe).at(-1)!;
        setState({ cursor: { ...c, measure: c.measure - 1, time: last.start }, ...reveal(c.measure - 1) });
      }
    }
    return;
  }
  const sel = s.selection;
  if (sel.kind === 'range') {
    if (extend) {
      const edge = sel.anchorMeasure === sel.mFrom ? sel.mTo : sel.mFrom;
      const m = Math.max(0, Math.min(score.measures.length - 1, edge + dir));
      selectMeasure(sel.anchorStaff === sel.staffFrom ? sel.staffTo : sel.staffFrom, m, true);
    } else {
      const m = Math.max(0, Math.min(score.measures.length - 1, (dir > 0 ? sel.mTo : sel.mFrom) + dir));
      selectMeasure(sel.staffFrom, m, false);
      setState(reveal(m));
    }
    return;
  }
  if (sel.kind === 'span' || (sel.kind === 'event' && extend)) {
    const focus = sel.kind === 'span' ? sel.focus : sel;
    const anchor = sel.kind === 'span' ? sel.anchor : { staff: sel.staff, measure: sel.measure, voice: sel.voice, eventId: sel.eventId };
    const next = stepEvent(score, focus, dir);
    if (!next) return;
    if (!extend) {
      selectElement(next);
      return;
    }
    setState({ selection: next.eventId === anchor.eventId ? { kind: 'event', ...anchor } : { kind: 'span', anchor, focus: next }, ...reveal(next.measure) });
    return;
  }
  if (sel.kind !== 'event') return;
  const f = findEvent(score, sel.eventId, sel);
  if (!f) return;
  const st = getStaff(score, f.staff);
  let m = f.measure;
  let i = f.index + dir;
  while (m >= 0 && m < score.measures.length) {
    const evs = st.measures[m].voices[f.voice];
    if (i >= 0 && i < evs.length) {
      const ev = evs[i];
      setState({ selection: { kind: 'event', staff: f.staff, measure: m, voice: f.voice, eventId: ev.id, noteId: ev.type === 'chord' ? ev.notes[ev.notes.length - 1].id : undefined }, ...reveal(m) });
      return;
    }
    m += dir;
    if (m < 0 || m >= score.measures.length) return;
    i = dir > 0 ? 0 : st.measures[m].voices[f.voice].length - 1;
  }
}

/** The neighbouring event in the same staff and voice (across barlines). */
function stepEvent(score: Score, ref: { staff: number; measure: number; voice: number; eventId: string }, dir: 1 | -1) {
  const f = findEvent(score, ref.eventId, ref);
  if (!f) return null;
  const st = getStaff(score, f.staff);
  let m = f.measure;
  let i = f.index + dir;
  while (m >= 0 && m < score.measures.length) {
    const evs = st.measures[m].voices[f.voice];
    if (i >= 0 && i < evs.length) return { staff: f.staff, measure: m, voice: f.voice, eventId: evs[i].id };
    m += dir;
    if (m < 0 || m >= score.measures.length) return null;
    i = dir > 0 ? 0 : st.measures[m].voices[f.voice].length - 1;
  }
  return null;
}

/** Alt+Up/Down: moves the selection between notes of a chord. */
export function moveInChord(dir: 1 | -1): void {
  const s = getState();
  const sel = s.selection;
  if (sel.kind !== 'event') return;
  const f = findEvent(s.score, sel.eventId, sel);
  if (!f || f.ev.type !== 'chord') return;
  const i = f.ev.notes.findIndex((n) => n.id === sel.noteId);
  const j = Math.max(0, Math.min(f.ev.notes.length - 1, (i < 0 ? 0 : i) + dir));
  setState({ selection: { ...sel, noteId: f.ev.notes[j].id } });
}

/** Ctrl+Alt+Up/Down in input mode: move the cursor to another staff. */
export function moveCursorStaff(dir: 1 | -1): void {
  const s = getState();
  if (!s.cursor) return;
  const staff = Math.max(0, Math.min(staffCount(s.score) - 1, s.cursor.staff + dir));
  setState({ cursor: { ...s.cursor, staff, time: s.cursor.time } });
}

// ───────────────────────────── delete ─────────────────────────────

export function deleteSelection(): void {
  const sel = getState().selection;
  if (sel.kind === 'event') {
    const f = selectedEvent();
    if (!f) return;
    commit('Удалено', (d) => {
      if (f.ev.type === 'chord' && sel.noteId && f.ev.notes.length > 1) {
        E.deleteNote(d, f.staff, f.measure, f.voice, f.eventId, sel.noteId);
        return { selection: { ...sel, noteId: undefined } };
      }
      const id = E.deleteEvent(d, f.staff, f.measure, f.voice, f.eventId);
      return { selection: id ? { kind: 'event', staff: f.staff, measure: f.measure, voice: f.voice, eventId: id } : { kind: 'none' } };
    });
  } else if (sel.kind === 'range') {
    commit('Такты очищены', (d) => E.clearRange(d, sel.staffFrom, sel.staffTo, sel.mFrom, sel.mTo));
  } else if (sel.kind === 'span') {
    commit('Удалено', (d) => {
      const evs = selectedEvents(d, sel).reverse();
      for (const e of evs) if (e.ev.type === 'chord') E.deleteEvent(d, e.staff, e.measure, e.voice, e.ev.id);
      return { selection: { kind: 'none' } };
    });
  }
}

// ───────────────────────────── measures ─────────────────────────────

function selectedMeasure(): number | null {
  const s = getState();
  if (s.input.active && s.cursor) return s.cursor.measure;
  if (s.selection.kind === 'event') return s.selection.measure;
  if (s.selection.kind === 'range') return s.selection.mFrom;
  if (s.selection.kind === 'span') return Math.min(s.selection.anchor.measure, s.selection.focus.measure);
  return null;
}

export { selectedMeasure };

export function appendMeasures(n: number): void {
  commit(`Добавлено тактов: ${n}`, (d) => {
    E.appendMeasures(d, n);
    return reveal(d.measures.length - 1);
  });
}

export function insertMeasures(n: number): void {
  const m = selectedMeasure();
  if (m === null) {
    appendMeasures(n);
    return;
  }
  commit(`Вставлено тактов: ${n}`, (d) => {
    E.insertMeasures(d, m, n);
    const st = getState();
    return { selection: { kind: 'range', staffFrom: 0, staffTo: staffCount(d) - 1, mFrom: m, mTo: m + n - 1, anchorStaff: 0, anchorMeasure: m }, cursor: st.cursor ? { ...st.cursor, measure: m, time: ZERO } : null };
  });
}

export function deleteSelectedMeasures(): void {
  const s = getState();
  const sel = s.selection;
  let from: number, to: number;
  if (sel.kind === 'range') [from, to] = [sel.mFrom, sel.mTo];
  else if (sel.kind === 'event') from = to = sel.measure;
  else if (sel.kind === 'span') [from, to] = [Math.min(sel.anchor.measure, sel.focus.measure), Math.max(sel.anchor.measure, sel.focus.measure)];
  else return;
  if (to - from + 1 >= s.score.measures.length) {
    setState({ status: 'Нельзя удалить все такты партитуры' });
    return;
  }
  commit(`Удалено тактов: ${to - from + 1}`, (d) => {
    E.deleteMeasures(d, from, to);
    return { selection: { kind: 'none' }, cursor: null, input: { ...getState().input, active: false } };
  });
}

// ───────────────────────────── signatures ─────────────────────────────

export function applyTimeSig(ts: TimeSig): void {
  const m = selectedMeasure() ?? 0;
  commit(`Размер ${ts.count}/${ts.unit}`, (d) => {
    E.setTimeSig(d, m, ts);
    return { selection: { kind: 'none' }, cursor: null, input: { ...getState().input, active: false } };
  });
}

export function applyKeySig(fifths: number): void {
  const m = selectedMeasure() ?? 0;
  commit('Тональность', (d) => E.setKeySig(d, m, fifths));
}

export function applyClef(clef: ClefKind): void {
  const s = getState();
  const sel = s.selection;
  const staff = s.cursor?.staff ?? (sel.kind === 'event' ? sel.staff : sel.kind === 'range' ? sel.staffFrom : sel.kind === 'span' ? sel.anchor.staff : 0);
  const m = selectedMeasure() ?? 0;
  commit('Ключ', (d) => E.setClef(d, staff, clef, m));
}

// ───────────────────────────── clipboard ─────────────────────────────

export function copySelection(): boolean {
  const s = getState();
  const sel = s.selection;
  if (sel.kind === 'range') {
    clipboard = E.copyRange(s.score, sel.staffFrom, sel.staffTo, sel.mFrom, sel.mTo);
    setState({ status: `Скопировано тактов: ${clipboard.measures}` });
    return true;
  }
  if (sel.kind === 'span') {
    const r = selectionMeasures(s.score, sel)!;
    clipboard = E.copyRange(s.score, r.staffFrom, r.staffTo, r.from, r.to);
    setState({ status: `Скопировано тактов: ${clipboard.measures}` });
    return true;
  }
  setState({ status: 'Для копирования выделите такты (щелчок по пустому месту такта, Shift+щелчок — диапазон)' });
  return false;
}

export function cutSelection(): void {
  if (copySelection()) deleteSelection();
}

export function paste(): void {
  const s = getState();
  if (!clipboard) {
    setState({ status: 'Буфер обмена пуст' });
    return;
  }
  const sel = s.selection;
  const target =
    sel.kind === 'range' ? { staff: sel.staffFrom, m: sel.mFrom } : sel.kind === 'event' ? { staff: sel.staff, m: sel.measure } : s.cursor ? { staff: s.cursor.staff, m: s.cursor.measure } : null;
  if (!target) {
    setState({ status: 'Выберите такт, куда вставить' });
    return;
  }
  const clip = clipboard;
  commit('Вставка', (d) => {
    const r = E.pasteClip(d, clip, target.staff, target.m);
    const staffTo = Math.min(staffCount(d) - 1, target.staff + clip.staves.length - 1);
    return { selection: { kind: 'range', staffFrom: target.staff, staffTo, mFrom: target.m, mTo: r.lastMeasure, anchorStaff: target.staff, anchorMeasure: target.m } };
  });
}

// ───────────────────────────── metadata ─────────────────────────────

export function updateScore(label: string, fn: (d: Score) => void): void {
  commit(label, fn);
}

// ───────────────────────────── files ─────────────────────────────

function fileName(path: string | null): string {
  if (!path) return getState().score.meta.title || 'Без названия';
  return path.split(/[\\/]/).pop()!.replace(/\.nfg$/i, '');
}

export function documentTitle(): string {
  return fileName(getState().filePath);
}

async function confirmDiscard(): Promise<boolean> {
  if (!isDirty(getState())) return true;
  return window.confirm('В партитуре есть несохранённые изменения. Продолжить без сохранения?');
}

export async function newScore(opts: NewScoreOptions): Promise<void> {
  if (!(await confirmDiscard())) return;
  loadDocument(createPianoScore(opts), null);
  setState({ status: 'Новая партитура' });
}

export function loadProjectText(text: string, path: string | null): boolean {
  const res = parseProject(text);
  if (!res.score) {
    setState({ dialog: { kind: 'message', message: { title: 'Не удалось открыть файл', text: res.errors.join('\n') } } });
    return false;
  }
  loadDocument(res.score, path);
  if (res.repaired.length) {
    setState({
      dialog: { kind: 'message', message: { title: 'Файл открыт с исправлениями', text: res.repaired.slice(0, 20).join('\n') + (res.repaired.length > 20 ? `\n… и ещё ${res.repaired.length - 20}` : '') } },
    });
  }
  setState({ status: `Открыт файл ${fileName(path)}` });
  return true;
}

export async function openProject(): Promise<void> {
  if (!(await confirmDiscard())) return;
  try {
    const r = await platform.openProject();
    if (r) loadProjectText(r.content, platform.isElectron ? r.path : null);
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Ошибка открытия', text: (e as Error).message } } });
  }
}

export async function saveProject(saveAs = false): Promise<boolean> {
  const s = getState();
  const score = s.score;
  try {
    const path = await platform.saveProject(saveAs ? null : s.filePath, serializeProject(score), `${fileName(s.filePath)}.nfg`);
    if (!path) return false;
    setState({ savedScore: score, filePath: platform.isElectron ? path : s.filePath, status: `Сохранено: ${path}` });
    return true;
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Ошибка сохранения', text: (e as Error).message } } });
    return false;
  }
}

// ───────────────────────────── view ─────────────────────────────

export function setZoom(z: number): void {
  const zoom = Math.max(0.25, Math.min(4, Math.round(z * 100) / 100));
  setState((s) => ({ view: { ...s.view, zoom } }));
}

export function zoomBy(factor: number): void {
  setZoom(getState().view.zoom * factor);
}

export function setViewMode(mode: 'page' | 'continuous'): void {
  setState((s) => ({ view: { ...s.view, mode } }));
}

export function togglePalette(): void {
  setState((s) => ({ view: { ...s.view, showPalette: !s.view.showPalette } }));
}

export function gotoMeasure(n: number): void {
  const { score } = getState();
  const m = Math.max(0, Math.min(score.measures.length - 1, n - 1));
  selectMeasure(0, m, false);
  setState({ ...reveal(m), status: `Такт ${m + 1}` });
}

export function openDialog(kind: AppState['dialog']['kind']): void {
  setState({ dialog: { kind } });
}

export function closeDialog(): void {
  setState({ dialog: { kind: 'none' } });
}
