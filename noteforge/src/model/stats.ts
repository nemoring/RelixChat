import type { Score } from './types';
import { add, toNumber, ZERO } from './fraction';
import { durToFrac, measureLength } from './duration';
import { effectiveTimeSigs, staffRefs } from './query';
import { midiOf, pitchFromMidi, pitchName } from './pitch';

export interface ScoreStats {
  measures: number;
  notes: number;
  chords: number;
  rests: number;
  /** Duration in seconds at the score tempo (no repeats). */
  seconds: number;
  lowest: string | null;
  highest: string | null;
  perStaff: { notes: number; lowest: string | null; highest: string | null }[];
}

export function computeStats(score: Score): ScoreStats {
  const sigs = effectiveTimeSigs(score);
  let total = ZERO;
  for (const ts of sigs) total = add(total, measureLength(ts));
  const beat = toNumber(durToFrac({ base: score.tempo.beatUnit as 4, dots: score.tempo.beatDots }));
  const seconds = (toNumber(total) / beat) * (60 / score.tempo.bpm);
  let notes = 0, chords = 0, rests = 0, lo = Infinity, hi = -Infinity;
  const perStaff = staffRefs(score).map(({ staff }) => {
    let n = 0, sl = Infinity, sh = -Infinity;
    for (const sm of staff.measures)
      for (const v of sm.voices)
        for (const ev of v) {
          if (ev.type === 'rest') {
            rests++;
            continue;
          }
          chords++;
          for (const note of ev.notes) {
            n++;
            const m = midiOf(note);
            sl = Math.min(sl, m);
            sh = Math.max(sh, m);
          }
        }
    notes += n;
    lo = Math.min(lo, sl);
    hi = Math.max(hi, sh);
    const name = (m: number) => (Number.isFinite(m) ? pitchName(pitchFromMidi(m, false)) : null);
    return { notes: n, lowest: name(sl), highest: name(sh) };
  });
  const name = (m: number) => (Number.isFinite(m) ? pitchName(pitchFromMidi(m, false)) : null);
  return { measures: score.measures.length, notes, chords, rests, seconds, lowest: name(lo), highest: name(hi), perStaff };
}

export function formatDuration(sec: number): string {
  const s = Math.round(sec);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const r = s % 60;
  return h ? `${h}:${String(m).padStart(2, '0')}:${String(r).padStart(2, '0')}` : `${m}:${String(r).padStart(2, '0')}`;
}
