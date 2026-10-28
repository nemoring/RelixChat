/**
 * Performance model: turns the score into timed note events — the single
 * source for realtime playback, MIDI export and WAV rendering. Every note
 * carries the ids of the model notes it comes from, which is how the score
 * view highlights exactly what is sounding.
 */
import type { Score, Tempo, VoiceEvent } from '../model/types';
import { Frac, toNumber } from '../model/fraction';
import { durToFrac, measureLength } from '../model/duration';
import { effectiveTimeSigs, staffRefs } from '../model/query';
import { midiOf } from '../model/pitch';

export const PPQ = 480;
const TICKS_PER_WHOLE = PPQ * 4;

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
  /** First event id (for "play from here"). */
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

/** Order in which measures are played. */
export function unroll(score: Score, opts: PerformOptions = {}): number[] {
  if (opts.range) {
    const out: number[] = [];
    for (let m = opts.range.from; m <= opts.range.to; m++) out.push(m);
    return out;
  }
  return score.measures.map((_, i) => i);
}

const eventTicks = (ev: VoiceEvent) => toNumber(durToFrac(ev.dur)) * TICKS_PER_WHOLE;

export function perform(score: Score, opts: PerformOptions = {}): Performance {
  const order = unroll(score, opts);
  const sigs = effectiveTimeSigs(score);
  const refs = staffRefs(score);
  const measures: PMeasure[] = [];
  let tick = 0;
  let sec = 0;
  let tempo = score.tempo;
  const tempoAt: Tempo[] = [];
  for (let m = 0; m < score.measures.length; m++) {
    const mt = (score.measures[m] as { tempo?: Tempo }).tempo;
    if (mt) tempo = mt;
    tempoAt.push(tempo);
  }
  for (const m of order) {
    const len = toNumber(measureLength(sigs[m])) * TICKS_PER_WHOLE;
    const qpm = quarterBpm(tempoAt[m]);
    const dur = (len / PPQ) * (60 / qpm);
    measures.push({ measure: m, startTick: tick, endTick: tick + len, start: sec, end: sec + dur, qpm });
    tick += len;
    sec += dur;
  }
  const secAt = (pass: number, tickInMeasure: number) => {
    const pm = measures[pass];
    return pm.start + (tickInMeasure / PPQ) * (60 / pm.qpm);
  };

  const notes: PNote[] = [];
  refs.forEach(({ staff }, s) => {
    const program = score.parts[refs[s].partIndex].program;
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
        for (const ev of events) {
          const len = eventTicks(ev);
          const next = new Map<number, PNote>();
          if (ev.type === 'chord') {
            for (const n of ev.notes) {
              const key = midiOf(n);
              if (key < 0 || key > 127) continue;
              const cont = open.get(key);
              let pn: PNote;
              if (cont) {
                pn = cont;
                pn.endTick = pm.startTick + t + len;
                pn.end = secAt(pass, t + len);
                pn.noteIds.push(n.id);
              } else {
                pn = {
                  startTick: pm.startTick + t,
                  endTick: pm.startTick + t + len,
                  start: secAt(pass, t),
                  end: secAt(pass, t + len),
                  key,
                  vel: 80,
                  staff: s,
                  voice: v,
                  program,
                  noteIds: [n.id],
                  eventId: ev.id,
                  pass,
                };
                notes.push(pn);
              }
              if (n.tie) next.set(key, pn);
            }
          }
          open = next;
          t += len;
        }
      });
    }
  });
  notes.sort((a, b) => a.start - b.start || a.key - b.key);

  const beats: PBeat[] = [];
  measures.forEach((pm, pass) => {
    const ts = sigs[pm.measure];
    const compound = ts.unit === 8 && ts.count % 3 === 0 && ts.count > 3;
    const beatTicks = (compound ? 3 : 1) * (TICKS_PER_WHOLE / ts.unit);
    for (let t = 0, i = 0; t < pm.endTick - pm.startTick - 1e-6; t += beatTicks, i++) {
      beats.push({ time: secAt(pass, t), tick: pm.startTick + t, accent: i === 0 });
    }
  });

  return { notes, pedals: [], measures, beats, duration: sec, totalTicks: tick };
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
  const ticks = ((Math.max(pm.start, Math.min(sec, pm.end)) - pm.start) * pm.qpm * PPQ) / 60;
  return { pass, measure: pm.measure, time: ticks / TICKS_PER_WHOLE };
}

/** Time (s) of the first pass through measure `m` at offset `time` (whole notes). */
export function timeOf(perf: Performance, m: number, time: Frac | number = 0): number {
  const pm = perf.measures.find((x) => x.measure === m);
  if (!pm) return 0;
  const t = typeof time === 'number' ? time : toNumber(time);
  return pm.start + ((t * TICKS_PER_WHOLE) / PPQ) * (60 / pm.qpm);
}

/** Total playing time (seconds) without building the note list. */
export function scoreDuration(score: Score): number {
  const sigs = effectiveTimeSigs(score);
  let tempo = score.tempo;
  let sec = 0;
  for (const m of unroll(score)) {
    const mt = (score.measures[m] as { tempo?: Tempo }).tempo;
    if (mt) tempo = mt;
    sec += ((toNumber(measureLength(sigs[m])) * TICKS_PER_WHOLE) / PPQ) * (60 / quarterBpm(tempo));
  }
  return sec;
}
