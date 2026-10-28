/**
 * Performance model: turns the score into timed note events — the single
 * source for realtime playback, MIDI export and WAV rendering. Every note
 * carries the ids of the model notes it comes from, which is how the score
 * view highlights exactly what is sounding.
 *
 * Interpreted markings: repeats, voltas, D.C./D.S./Fine/Coda, tempo changes,
 * fermatas, dynamics and hairpins, articulations, grace notes, ornaments,
 * sustain pedal and ties.
 */
import type { ChordEvent, Dynamic, Score, Tempo, VoiceEvent } from '../model/types';
import { Frac, toNumber } from '../model/fraction';
import { durToFrac, eventLen, measureLength } from '../model/duration';
import { effectiveKeys, effectiveTimeSigs, eventIndex, staffRefs, comparePos } from '../model/query';
import { midiOf } from '../model/pitch';
import { neighbour } from '../model/edit';

export const PPQ = 480;
const TPW = PPQ * 4; // ticks per whole note

export interface PNote {
  startTick: number;
  endTick: number;
  start: number;
  end: number;
  key: number;
  vel: number;
  staff: number;
  voice: number;
  program: number;
  /** Model note ids sounding in this note (a tie chain gives several). */
  noteIds: string[];
  /** First event id (for "play from here" and the melody/accompaniment mixer). */
  eventId: string;
  /** Unrolled measure index where the note starts. */
  pass: number;
}

export interface PMeasure {
  /** Score measure index. */
  measure: number;
  startTick: number;
  endTick: number;
  start: number;
  end: number;
  /** Quarter notes per minute in this measure. */
  qpm: number;
  /** Held portions (fermatas): [t0, t1) ticks inside the measure played `factor` times slower. */
  holds: { t0: number; t1: number; factor: number }[];
}

export interface PBeat {
  time: number;
  tick: number;
  accent: boolean;
}

export interface PPedal {
  startTick: number;
  endTick: number;
  start: number;
  end: number;
  staff?: number;
}

export interface Performance {
  notes: PNote[];
  /** Sustain pedal intervals (MIDI CC64). */
  pedals: PPedal[];
  measures: PMeasure[];
  beats: PBeat[];
  duration: number;
  totalTicks: number;
}

export interface PerformOptions {
  /** Restrict to a measure range played straight through (loop playback). */
  range?: { from: number; to: number };
}

/** Quarter-notes-per-minute for a tempo marking. */
export function quarterBpm(t: Tempo): number {
  const beat = toNumber(durToFrac({ base: t.beatUnit as 4, dots: t.beatDots }));
  return t.bpm * beat * 4;
}

/**
 * Order in which measures are played: repeats (with voltas), then D.C./D.S.
 * jumps (repeats are not taken again after a jump and the last ending is
 * used), Fine and To Coda → Coda.
 */
export function unroll(score: Score, opts: PerformOptions = {}): number[] {
  if (opts.range) {
    const out: number[] = [];
    for (let m = opts.range.from; m <= opts.range.to; m++) out.push(m);
    return out;
  }
  const ms = score.measures;
  const n = ms.length;
  // Highest volta number of each run of consecutive volta measures.
  const groupMax = new Array<number>(n).fill(0);
  for (let i = 0; i < n; ) {
    if (!ms[i].volta) {
      i++;
      continue;
    }
    let j = i;
    let mx = 0;
    while (j < n && ms[j].volta) mx = Math.max(mx, ...ms[j++].volta!.numbers);
    for (let k = i; k < j; k++) groupMax[k] = mx;
    i = j;
  }
  const out: number[] = [];
  const counts = new Map<number, number>();
  let repeatStart = 0;
  let pass = 1;
  let afterJump: null | { fine: boolean; coda: boolean } = null;
  let jumped = false;
  let m = 0;
  let guard = 0;
  while (m < n && guard++ < n * 64 + 1000) {
    const mi = ms[m];
    if (mi.repeatStart && !afterJump) repeatStart = m;
    if (mi.volta) {
      const include = afterJump ? mi.volta.numbers.includes(groupMax[m]) : mi.volta.numbers.includes(pass);
      if (!include) {
        m++;
        continue;
      }
    }
    out.push(m);
    if (afterJump?.fine && mi.marker === 'fine') break;
    if (afterJump?.coda && mi.marker === 'toCoda') {
      const coda = ms.findIndex((x, i) => i > m && x.marker === 'coda');
      if (coda < 0) break;
      m = coda;
      afterJump = null;
      continue;
    }
    if (mi.repeatEnd && !afterJump) {
      const done = counts.get(m) ?? 1;
      if (done < mi.repeatEnd) {
        counts.set(m, done + 1);
        pass = done + 1;
        m = repeatStart;
        continue;
      }
      counts.delete(m);
      pass = 1;
      repeatStart = m + 1;
    }
    if (mi.jump && !jumped) {
      jumped = true;
      afterJump = { fine: mi.jump.endsWith('Fine'), coda: mi.jump.endsWith('Coda') };
      if (mi.jump.startsWith('DS')) {
        const segno = ms.findIndex((x) => x.marker === 'segno');
        m = segno >= 0 ? segno : 0;
      } else m = 0;
      pass = 1;
      continue;
    }
    m++;
  }
  return out;
}

const DYN_VEL: Record<string, number> = { ppp: 22, pp: 34, p: 48, mp: 64, mf: 80, f: 96, ff: 110, fff: 122 };
const DYN_LEVELS = ['ppp', 'pp', 'p', 'mp', 'mf', 'f', 'ff', 'fff'];

/** Velocity curve of a part over unrolled ticks. */
class Dynamics {
  private points: { tick: number; vel: number }[] = [];
  private ramps: { t0: number; t1: number; from: number; to: number; up: boolean }[] = [];
  private accents = new Map<string, number>();

  setLevel(tick: number, vel: number) {
    this.points.push({ tick, vel });
  }
  accent(eventId: string, vel: number) {
    this.accents.set(eventId, vel);
  }
  addRamp(t0: number, t1: number, up: boolean) {
    this.ramps.push({ t0, t1, from: 0, to: 0, up });
  }
  finalize() {
    this.points.sort((a, b) => a.tick - b.tick);
    for (const r of this.ramps) {
      r.from = this.levelAt(r.t0);
      const next = this.points.find((p) => p.tick >= r.t1 - 1e-6 && p.tick <= r.t1 + PPQ * 2);
      const idx = DYN_LEVELS.findIndex((l) => DYN_VEL[l] >= r.from);
      const fallback = DYN_VEL[DYN_LEVELS[Math.max(0, Math.min(7, (idx < 0 ? 4 : idx) + (r.up ? 2 : -2)))]];
      r.to = next ? next.vel : fallback;
      if (!next) this.points.push({ tick: r.t1, vel: r.to });
    }
    this.points.sort((a, b) => a.tick - b.tick);
  }
  private levelAt(tick: number): number {
    let v = 80;
    for (const p of this.points) {
      if (p.tick > tick + 1e-6) break;
      v = p.vel;
    }
    return v;
  }
  velocity(tick: number, eventId: string): number {
    const acc = this.accents.get(eventId);
    if (acc) return acc;
    for (const r of this.ramps) if (tick >= r.t0 && tick < r.t1) return r.from + ((r.to - r.from) * (tick - r.t0)) / Math.max(1, r.t1 - r.t0);
    return this.levelAt(tick);
  }
}

export function perform(score: Score, opts: PerformOptions = {}): Performance {
  const order = unroll(score, opts);
  const sigs = effectiveTimeSigs(score);
  const keys = effectiveKeys(score);
  const refs = staffRefs(score);
  const idx = eventIndex(score);

  // Tempo per score measure.
  let tempo = score.tempo;
  const tempoAt: Tempo[] = [];
  for (let m = 0; m < score.measures.length; m++) {
    if (m > 0 && score.measures[m].tempo) tempo = score.measures[m].tempo!;
    tempoAt.push(tempo);
  }
  // Fermata holds per score measure (union over all staves and voices).
  const holdsAt = new Map<number, { t0: number; t1: number; factor: number }[]>();
  for (const r of refs)
    r.staff.measures.forEach((sm, m) =>
      sm.voices.forEach((events) => {
        let t = 0;
        for (const ev of events) {
          const len = toNumber(eventLen(ev)) * TPW;
          if (ev.fermata && len > 0) {
            if (!holdsAt.has(m)) holdsAt.set(m, []);
            holdsAt.get(m)!.push({ t0: t, t1: t + len, factor: 2 });
          }
          t += len;
        }
      }),
    );
  for (const [m, hs] of holdsAt) {
    hs.sort((a, b) => a.t0 - b.t0);
    const merged: typeof hs = [];
    for (const h of hs) {
      const last = merged[merged.length - 1];
      if (last && h.t0 <= last.t1) last.t1 = Math.max(last.t1, h.t1);
      else merged.push({ ...h });
    }
    holdsAt.set(m, merged);
  }

  const measures: PMeasure[] = [];
  let tick = 0;
  let sec = 0;
  for (const m of order) {
    const len = toNumber(measureLength(sigs[m])) * TPW;
    const pm: PMeasure = { measure: m, startTick: tick, endTick: tick + len, start: sec, end: 0, qpm: quarterBpm(tempoAt[m]), holds: holdsAt.get(m) ?? [] };
    pm.end = sec + measureSec(pm, len);
    measures.push(pm);
    tick += len;
    sec = pm.end;
  }
  const secAt = (pass: number, tickInMeasure: number) => measures[pass].start + measureSec(measures[pass], tickInMeasure);

  // Where each score measure occurs in the unrolled order.
  const passesOf = new Map<number, number[]>();
  measures.forEach((pm, p) => {
    if (!passesOf.has(pm.measure)) passesOf.set(pm.measure, []);
    passesOf.get(pm.measure)!.push(p);
  });
  const unrolledTick = (pass: number, t: Frac) => measures[pass].startTick + toNumber(t) * TPW;

  // Dynamics per part.
  const dyn = score.parts.map(() => new Dynamics());
  for (const [, e] of idx) {
    if (e.ev.type !== 'chord' || !e.ev.dynamic) continue;
    const part = refs[e.staff].partIndex;
    for (const p of passesOf.get(e.measure) ?? []) {
      const t = unrolledTick(p, e.start);
      const d: Dynamic = e.ev.dynamic;
      if (DYN_VEL[d]) dyn[part].setLevel(t, DYN_VEL[d]);
      else if (d === 'fp') {
        dyn[part].accent(e.ev.id, DYN_VEL.f);
        dyn[part].setLevel(t + 1, DYN_VEL.p);
      } else dyn[part].accent(e.ev.id, d === 'sf' ? 108 : 116);
    }
  }
  const pedals: PPedal[] = [];
  for (const sp of score.spanners) {
    if (sp.type !== 'cresc' && sp.type !== 'dim' && sp.type !== 'pedal') continue;
    const a = idx.get(sp.start);
    const b = idx.get(sp.end);
    if (!a || !b) continue;
    const [s0, e0] = comparePos(a, b) <= 0 ? [a, b] : [b, a];
    for (const p of passesOf.get(s0.measure) ?? []) {
      // The end is the first occurrence of the end measure at or after this pass.
      const pe = (passesOf.get(e0.measure) ?? []).find((q) => q >= p);
      if (pe === undefined) continue;
      const t0 = unrolledTick(p, s0.start);
      const t1 = unrolledTick(pe, e0.end);
      if (sp.type === 'pedal') pedals.push({ startTick: t0, endTick: t1, start: secAt(p, toNumber(s0.start) * TPW), end: secAt(pe, toNumber(e0.end) * TPW) });
      else dyn[refs[s0.staff].partIndex].addRamp(t0, t1, sp.type === 'cresc');
    }
  }
  dyn.forEach((d) => d.finalize());

  const notes: PNote[] = [];
  refs.forEach(({ staff, partIndex }, s) => {
    const program = score.parts[partIndex].program;
    for (let v = 0; v < 4; v++) {
      // Open tie chains for this voice, keyed by MIDI pitch.
      let open = new Map<number, PNote>();
      measures.forEach((pm, pass) => {
        const events = staff.measures[pm.measure].voices[v] ?? [];
        if (!events.length) {
          open = new Map();
          return;
        }
        let t = 0;
        let graces: ChordEvent[] = [];
        for (const ev of events) {
          if (ev.type === 'chord' && ev.grace) {
            graces.push(ev);
            continue;
          }
          const len = toNumber(eventLen(ev)) * TPW;
          const next = new Map<number, PNote>();
          if (ev.type === 'chord') {
            let start = t;
            let dur = len;
            // Grace notes: acciaccaturas are quick and steal from the main note; an appoggiatura takes half of it.
            if (graces.length) {
              const appo = graces.length === 1 && graces[0].grace === 'appoggiatura';
              const each = appo ? Math.min(len / 2, durTicks(graces[0]) * 2) : Math.min(PPQ / 8, len / (graces.length + 1));
              for (const g of graces) {
                for (const n of g.notes) {
                  const key = midiOf(n);
                  if (key >= 0 && key <= 127) pushNote(notes, pm, pass, start, start + each, key, dyn[partIndex].velocity(pm.startTick + start, g.id) * 0.9, s, v, program, [n.id], g.id, secAt);
                }
                start += each;
                dur -= each;
              }
            }
            const artic = new Set(ev.artics ?? []);
            const vel = Math.min(127, dyn[partIndex].velocity(pm.startTick + t, ev.id) + (artic.has('accent') ? 14 : 0) + (artic.has('marcato') ? 22 : 0));
            const gate = artic.has('staccatissimo') ? 0.3 : artic.has('staccato') ? 0.5 : artic.has('tenuto') ? 1 : 0.97;
            for (const n of ev.notes) {
              const key = midiOf(n);
              if (key < 0 || key > 127) continue;
              const g = n.tie ? 1 : gate;
              const cont = open.get(key);
              if (cont) {
                cont.endTick = pm.startTick + t + len * g;
                cont.end = secAt(pass, t + len * g);
                cont.noteIds.push(n.id);
                if (n.tie) next.set(key, cont);
                continue;
              }
              if (ev.ornament && ev.notes.length === 1) {
                for (const [k, f0, f1] of ornamentNotes(ev, n, key, keys[pm.measure])) {
                  const pn = pushNote(notes, pm, pass, start + dur * f0, start + dur * f1 * (f1 >= 1 ? g : 1), k, vel, s, v, program, [n.id], ev.id, secAt);
                  if (n.tie && f1 >= 1 && k === key) next.set(key, pn);
                }
                continue;
              }
              const pn = pushNote(notes, pm, pass, start, start + dur * g, key, vel, s, v, program, [n.id], ev.id, secAt);
              if (n.tie) next.set(key, pn);
            }
          }
          graces = [];
          open = next;
          t += len;
        }
      });
    }
  });

  // Sustain pedal: notes released while the pedal is down sound until it is lifted.
  if (pedals.length) {
    const tickToSec = (tk: number) => {
      let lo = 0;
      let hi = measures.length - 1;
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (measures[mid].startTick <= tk) lo = mid;
        else hi = mid - 1;
      }
      const pm = measures[lo];
      return pm.start + measureSec(pm, Math.min(tk, pm.endTick) - pm.startTick);
    };
    for (const n of notes) {
      for (const p of pedals) {
        if (n.startTick < p.endTick && n.endTick > p.startTick && n.endTick < p.endTick) {
          n.endTick = p.endTick;
          n.end = tickToSec(p.endTick);
        }
      }
    }
  }
  notes.sort((a, b) => a.start - b.start || a.key - b.key);

  const beats: PBeat[] = [];
  measures.forEach((pm, pass) => {
    const ts = sigs[pm.measure];
    const compound = ts.unit === 8 && ts.count % 3 === 0 && ts.count > 3;
    const beatTicks = (compound ? 3 : 1) * (TPW / ts.unit);
    for (let t = 0, i = 0; t < pm.endTick - pm.startTick - 1e-6; t += beatTicks, i++) {
      beats.push({ time: secAt(pass, t), tick: pm.startTick + t, accent: i === 0 });
    }
  });

  return { notes, pedals, measures, beats, duration: sec, totalTicks: tick };
}

function durTicks(ev: VoiceEvent): number {
  return toNumber(durToFrac(ev.dur)) * TPW;
}

function pushNote(
  notes: PNote[],
  pm: PMeasure,
  pass: number,
  t0: number,
  t1: number,
  key: number,
  vel: number,
  staff: number,
  voice: number,
  program: number,
  noteIds: string[],
  eventId: string,
  secAt: (pass: number, t: number) => number,
): PNote {
  const end = Math.max(t0 + 1, t1);
  const pn: PNote = {
    startTick: pm.startTick + t0,
    endTick: pm.startTick + end,
    start: secAt(pass, t0),
    end: secAt(pass, end),
    key,
    vel: Math.max(1, Math.min(127, Math.round(vel))),
    staff,
    voice,
    program,
    noteIds,
    eventId,
    pass,
  };
  notes.push(pn);
  return pn;
}

/** Ornament realisation as [key, startFraction, endFraction] segments of the note. */
function ornamentNotes(ev: ChordEvent, n: ChordEvent['notes'][number], key: number, keySig: number): [number, number, number][] {
  const upper = midiOf(neighbour(n, 1, keySig));
  const lower = midiOf(neighbour(n, -1, keySig));
  const len = toNumber(eventLen(ev));
  switch (ev.ornament) {
    case 'trill': {
      const steps = Math.max(4, Math.round(len * 32));
      const k = steps % 2 ? steps - 1 : steps;
      const out: [number, number, number][] = [];
      for (let i = 0; i < k; i++) out.push([i % 2 === 0 ? key : upper, i / k, (i + 1) / k]);
      return out;
    }
    case 'mordent':
    case 'invertedMordent': {
      const other = ev.ornament === 'mordent' ? lower : upper;
      const f = Math.min(1 / 6, 1 / 32 / Math.max(len, 1 / 32));
      return [
        [key, 0, f],
        [other, f, 2 * f],
        [key, 2 * f, 1],
      ];
    }
    case 'turn':
    case 'invertedTurn': {
      const a = ev.ornament === 'turn' ? upper : lower;
      const b = ev.ornament === 'turn' ? lower : upper;
      return [
        [a, 0, 0.25],
        [key, 0.25, 0.5],
        [b, 0.5, 0.75],
        [key, 0.75, 1],
      ];
    }
    default:
      return [[key, 0, 1]];
  }
}

/** Seconds from the start of a measure to `tick` inside it (fermata holds included). */
function measureSec(pm: PMeasure, tick: number): number {
  const spt = 60 / pm.qpm / PPQ; // seconds per tick
  let extra = 0;
  for (const h of pm.holds) extra += Math.max(0, Math.min(tick, h.t1) - h.t0) * (h.factor - 1);
  return (tick + extra) * spt;
}

/** Inverse of measureSec. */
function measureTick(pm: PMeasure, secs: number): number {
  const spt = 60 / pm.qpm / PPQ;
  let rest = secs / spt; // stretched ticks still to place
  let pos = 0;
  for (const h of pm.holds) {
    const plain = h.t0 - pos;
    if (rest <= plain) return pos + rest;
    rest -= plain;
    pos = h.t0;
    const held = (h.t1 - h.t0) * h.factor;
    if (rest <= held) return pos + rest / h.factor;
    rest -= held;
    pos = h.t1;
  }
  return pos + rest;
}

/** Index of the unrolled measure playing at time `sec`. */
export function passAt(perf: Performance, sec: number): number {
  const ms = perf.measures;
  let lo = 0;
  let hi = ms.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (ms[mid].start <= sec) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/** Position inside a measure (in whole notes) at time `sec`. */
export function positionAt(perf: Performance, sec: number): { pass: number; measure: number; time: number } {
  const pass = passAt(perf, sec);
  const pm = perf.measures[pass];
  if (!pm) return { pass: 0, measure: 0, time: 0 };
  const ticks = measureTick(pm, Math.max(0, Math.min(sec, pm.end) - pm.start));
  return { pass, measure: pm.measure, time: Math.min(ticks, pm.endTick - pm.startTick) / TPW };
}

/** Time (s) of the first pass through measure `m` at offset `time` (whole notes). */
export function timeOf(perf: Performance, m: number, time: Frac | number = 0): number {
  const pm = perf.measures.find((x) => x.measure === m);
  if (!pm) return 0;
  const t = typeof time === 'number' ? time : toNumber(time);
  return pm.start + measureSec(pm, t * TPW);
}

/** Total playing time (seconds) without building the note list (fermatas not included). */
export function scoreDuration(score: Score): number {
  const sigs = effectiveTimeSigs(score);
  let tempo = score.tempo;
  const tempoAt: Tempo[] = [];
  for (let m = 0; m < score.measures.length; m++) {
    if (m > 0 && score.measures[m].tempo) tempo = score.measures[m].tempo!;
    tempoAt.push(tempo);
  }
  let sec = 0;
  for (const m of unroll(score)) sec += ((toNumber(measureLength(sigs[m])) * TPW) / PPQ) * (60 / quarterBpm(tempoAt[m]));
  return sec;
}
