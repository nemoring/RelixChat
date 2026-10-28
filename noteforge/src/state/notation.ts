/**
 * Notation commands (stage 3): articulations, ornaments, dynamics, grace
 * notes, tuplets, lines (slurs, hairpins, pedal, octave), cross-staff notes,
 * stems/beams, repeats and jumps, tempo changes, melody lines, transposition.
 */
import type { Articulation, ChordEvent, Dynamic, JumpKind, MarkerKind, Ornament, Score, SpannerType, Tempo } from '../model/types';
import * as E from '../model/edit';
import { commit, getState, setState } from './store';
import { selectedEvents, selectionEnds, selectionMeasures } from './selection';
import { selectedMeasure } from './actions';
import { eventIndex, staffCount } from '../model/query';
import { durToFrac } from '../model/duration';
import { newId } from '../model/ids';
import { player } from '../playback/player';

const say = (status: string) => setState({ status });

/** Chord events of the selection (draft-aware). */
function chords(d: Score) {
  return selectedEvents(d, getState().selection).filter((e) => e.ev.type === 'chord') as (ReturnType<typeof selectedEvents>[number] & { ev: ChordEvent })[];
}

function needChords(): boolean {
  if (!chords(getState().score).length) {
    say('Выделите ноту, аккорд или фрагмент');
    return false;
  }
  return true;
}

export function toggleArtic(a: Articulation): void {
  if (!needChords()) return;
  const all = chords(getState().score).every((e) => e.ev.artics?.includes(a));
  commit('Артикуляция', (d) => {
    for (const e of chords(d)) if (!e.ev.grace) E.toggleArticulation(e.ev, a, !all);
  });
}

export function toggleFermata(): void {
  const evs = selectedEvents(getState().score, getState().selection);
  if (!evs.length) return say('Выделите ноту или паузу');
  commit('Фермата', (d) => {
    const target = selectedEvents(d, getState().selection);
    const on = !target.every((e) => e.ev.fermata);
    for (const e of target) {
      if (on) e.ev.fermata = true;
      else delete e.ev.fermata;
    }
  });
}

export function ornament(o: Ornament): void {
  if (!needChords()) return;
  commit('Орнамент', (d) => {
    for (const e of chords(d)) E.setOrnament(e.ev, o);
  });
}

export function dynamic(dyn: Dynamic): void {
  if (!needChords()) return;
  commit('Динамика', (d) => {
    const cs = chords(d);
    E.setDynamic(cs[0].ev, dyn);
  });
}

export function grace(kind: 'acciaccatura' | 'appoggiatura'): void {
  const sel = getState().selection;
  if (sel.kind !== 'event') return say('Выделите ноту, к которой добавить форшлаг');
  commit('Форшлаг', (d) => {
    const id = E.addGrace(d, sel.staff, sel.measure, sel.voice, sel.eventId, kind);
    return id ? { selection: { kind: 'event', staff: sel.staff, measure: sel.measure, voice: sel.voice, eventId: id } } : undefined;
  });
}

/** Creates a tuplet over the selected event, or at the input cursor using the input duration. */
export function tuplet(num: number, den?: number): void {
  const s = getState();
  if (s.input.active && s.cursor) {
    const c = s.cursor;
    const total = durToFrac(s.input.dur);
    commit(`Ритмическая группа ${num}`, (d) => {
      const r = E.createTuplet(d, c.staff, c.measure, c.voice, c.time, total, num, den);
      if (typeof r === 'string') throw new Error(r);
      return { input: { ...getState().input, dur: r.unit } };
    });
    return;
  }
  const sel = s.selection;
  if (sel.kind !== 'event') return say('Выделите ноту/паузу или включите режим ввода');
  const e = eventIndex(s.score).get(sel.eventId);
  if (!e) return;
  commit(`Ритмическая группа ${num}`, (d) => {
    const r = E.createTuplet(d, e.staff, e.measure, e.voice, e.start, durToFrac(e.ev.dur), num, den);
    if (typeof r === 'string') throw new Error(r);
    return { selection: { kind: 'event', staff: e.staff, measure: e.measure, voice: e.voice, eventId: r.id } };
  });
}

export function removeTuplet(): void {
  const sel = getState().selection;
  if (sel.kind !== 'event') return;
  commit('Группа удалена', (d) => {
    const id = E.removeTuplet(d, sel.staff, sel.measure, sel.voice, sel.eventId);
    return id ? { selection: { kind: 'event', staff: sel.staff, measure: sel.measure, voice: sel.voice, eventId: id } } : undefined;
  });
}

/** Adds a line from the first to the last selected event (a single event: the line covers it). */
export function line(type: SpannerType, ottava?: number): void {
  const ends = selectionEnds(getState().score, getState().selection);
  if (!ends) return say('Выделите ноты: щелчок по первой, Shift+щелчок по последней');
  let { first, last } = ends;
  if (type === 'slur' && first.ev.id === last.ev.id) {
    // A slur needs two notes: extend to the next chord in the voice.
    const nx = E.nextEventInVoice(getState().score, first.staff, first.measure, first.voice, first.ev.id);
    if (!nx || nx.ev.type !== 'chord') return say('Для лиги выделите две ноты или больше');
    last = { ...first, measure: nx.m, ev: nx.ev };
  }
  commit(type === 'slur' ? 'Лига' : type === 'pedal' ? 'Педаль' : type === 'ottava' ? 'Октавная линия' : 'Вилка', (d) => {
    E.addSpanner(d, type, first.ev.id, last.ev.id, ottava);
  });
}

export function removeLines(): void {
  const evs = selectedEvents(getState().score, getState().selection);
  if (!evs.length) return;
  commit('Линии удалены', (d) => {
    const n = E.removeSpanners(d, new Set(evs.map((e) => e.ev.id)));
    if (!n) throw new Error('у выделенных нот нет лиг, вилок, педали или октавных линий');
  });
}

export function crossStaff(delta: number): void {
  if (!needChords()) return;
  commit(delta > 0 ? 'На нижний нотоносец' : 'На верхний нотоносец', (d) => {
    let ok = 0;
    for (const e of chords(d)) if (E.shiftStaff(d, e.staff, e.ev, delta)) ok++;
    if (!ok) throw new Error('дальше нотоносцев нет');
  });
}

export function flipStem(): void {
  if (!needChords()) return;
  commit('Направление штиля', (d) => {
    for (const e of chords(d)) E.cycleStem(e.ev);
  });
}

export function beam(mode: ChordEvent['beam']): void {
  if (!needChords()) return;
  commit('Ребро', (d) => {
    for (const e of chords(d)) E.setBeamMode(e.ev, mode);
  });
}

// ── measures ──

function measureRange(): { from: number; to: number } | null {
  const r = selectionMeasures(getState().score, getState().selection);
  if (r) return r;
  const m = selectedMeasure();
  return m === null ? null : { from: m, to: m };
}

export function repeatStart(): void {
  const r = measureRange();
  if (!r) return say('Выделите такт');
  commit('Начало повтора', (d) => E.setRepeatStart(d, r.from, !d.measures[r.from].repeatStart));
}

export function repeatEnd(times = 2): void {
  const r = measureRange();
  if (!r) return say('Выделите такт');
  commit('Конец повтора', (d) => E.setRepeatEnd(d, r.to, d.measures[r.to].repeatEnd === times ? undefined : times));
}

export function volta(numbers: number[]): void {
  const r = measureRange();
  if (!r) return say('Выделите такты вольты');
  commit(`Вольта ${numbers.join(', ')}`, (d) => {
    const same = d.measures[r.from].volta && d.measures[r.from].volta!.numbers.join() === numbers.join();
    E.setVolta(d, r.from, r.to, same ? undefined : numbers);
  });
}

export function marker(kind: MarkerKind): void {
  const r = measureRange();
  if (!r) return say('Выделите такт');
  commit('Знак перехода', (d) => E.setMarker(d, kind === 'fine' || kind === 'toCoda' ? r.to : r.from, kind));
}

export function jump(kind: JumpKind): void {
  const r = measureRange();
  if (!r) return say('Выделите такт');
  commit('Переход', (d) => E.setJump(d, r.to, kind));
}

export function barline(kind: 'double' | 'final'): void {
  const r = measureRange();
  if (!r) return say('Выделите такт');
  commit('Тактовая черта', (d) => E.setBarline(d, r.to, kind));
}

export function tempoChange(t: Tempo | undefined): void {
  const m = measureRange()?.from ?? 0;
  commit(t ? `Темп ${t.text || ''} ♩=${t.bpm}` : 'Смена темпа удалена', (d) => E.setMeasureTempo(d, m, t));
}

export function removeClefChange(): void {
  const r = measureRange();
  if (!r || r.from === 0) return;
  commit('Смена ключа удалена', (d) => {
    for (let st = 0; st < staffCount(d); st++) E.removeClefChange(d, st, r.from);
  });
}

// ── melody lines ──

const LINE_COLORS = ['#d6336c', '#1c7ed6', '#2f9e44', '#e8590c', '#7048e8', '#0c8599'];

export function createLine(): void {
  commit('Новая мелодическая линия', (d) => {
    const id = newId('l');
    d.lines.push({ id, name: `Мелодия ${d.lines.length + 1}`, color: LINE_COLORS[d.lines.length % LINE_COLORS.length] });
    return { input: { ...getState().input, line: id } };
  });
}

export function renameLine(id: string, name: string): void {
  commit('Имя линии', (d) => {
    const l = d.lines.find((x) => x.id === id);
    if (l) l.name = name.trim() || l.name;
  });
}

export function recolorLine(id: string, color: string): void {
  commit('Цвет линии', (d) => {
    const l = d.lines.find((x) => x.id === id);
    if (l) l.color = color;
  });
}

export function deleteLine(id: string): void {
  commit('Линия удалена', (d) => {
    d.lines = d.lines.filter((l) => l.id !== id);
    for (const part of d.parts) for (const st of part.staves) for (const sm of st.measures) for (const v of sm.voices) for (const ev of v) if (ev.type === 'chord' && ev.line === id) delete ev.line;
    const input = getState().input;
    return input.line === id ? { input: { ...input, line: null } } : undefined;
  });
}

/** Sets the melody line that newly entered notes belong to. */
export function setInputLine(id: string | null): void {
  setState((s) => ({ input: { ...s.input, line: id }, status: id ? 'Новые ноты будут добавляться в мелодию' : 'Новые ноты — сопровождение' }));
}

/** Assigns the selection to a line (or removes it: id null); toggles when already assigned. */
export function assignLine(id?: string | null): void {
  if (!needChords()) return;
  const s = getState();
  const target = id === undefined ? (s.input.line ?? s.score.lines[0]?.id ?? null) : id;
  if (target === null && id === undefined) return say('Создайте мелодическую линию');
  const cs = chords(s.score);
  const all = target !== null && cs.every((e) => e.ev.line === target);
  commit(all || target === null ? 'Убрано из мелодии' : 'Добавлено в мелодию', (d) => {
    for (const e of chords(d)) {
      if (all || target === null) delete e.ev.line;
      else e.ev.line = target!;
    }
  });
}

export function toggleShowLines(): void {
  setState((s) => ({ view: { ...s.view, showLines: !s.view.showLines } }));
}

/** Solo the melody (or the accompaniment) in the mixer. */
export function listen(role: 'melody' | 'accomp' | 'all'): void {
  player.setChannel('role-melody', { solo: role === 'melody', mute: false });
  player.setChannel('role-accomp', { solo: role === 'accomp', mute: false });
  say(role === 'melody' ? 'Слушать: только мелодия' : role === 'accomp' ? 'Слушать: только сопровождение' : 'Слушать: всё');
}

/** Selects every note of a melody line (as a span from its first to last note). */
export function selectLine(id: string): void {
  const score = getState().score;
  const evs = [...eventIndex(score).values()].filter((e) => e.ev.type === 'chord' && e.ev.line === id);
  if (!evs.length) return say('В этой линии пока нет нот');
  evs.sort((a, b) => a.measure - b.measure || a.start.n * b.start.d - b.start.n * a.start.d);
  const a = evs[0];
  const b = evs[evs.length - 1];
  setState({
    selection: a.ev.id === b.ev.id ? { kind: 'event', staff: a.staff, measure: a.measure, voice: a.voice, eventId: a.ev.id } : { kind: 'span', anchor: { staff: a.staff, measure: a.measure, voice: a.voice, eventId: a.ev.id }, focus: { staff: b.staff, measure: b.measure, voice: b.voice, eventId: b.ev.id } },
    reveal: { measure: a.measure, token: Date.now() },
  });
}

// ── transposition ──

export function transpose(iv: E.Interval, scope: 'selection' | 'all', keys: boolean): void {
  const s = getState();
  const r = scope === 'all' ? { from: 0, to: s.score.measures.length - 1, staffFrom: 0, staffTo: staffCount(s.score) - 1 } : selectionMeasures(s.score, s.selection);
  if (!r) return say('Выделите фрагмент или выберите «вся партитура»');
  commit('Транспонирование', (d) => {
    const staves: number[] = [];
    for (let i = scope === 'all' ? 0 : r.staffFrom; i <= (scope === 'all' ? staffCount(d) - 1 : r.staffTo); i++) staves.push(i);
    E.transposeRange(d, staves, r.from, r.to, iv, keys && staves.length === staffCount(d));
  });
}
