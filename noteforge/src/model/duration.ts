import type { Duration, DurBase, TimeSig } from './types';
import { DUR_BASES } from './types';
import { Frac, frac, add, sub, le, isZero, isMultipleOf, ZERO } from './fraction';

/** Length of a duration in whole notes. base 4 + 1 dot → 3/8. */
export function durToFrac(d: Duration): Frac {
  // value = (1/base) * (2 - 1/2^dots)
  const p = 2 ** d.dots;
  return frac(2 * p - 1, d.base * p);
}

export function measureLength(ts: TimeSig): Frac {
  return frac(ts.count, ts.unit);
}

/** Returns an exact single-symbol duration for f (with up to maxDots dots), or null. */
export function fracToDuration(f: Frac, maxDots = 3): Duration | null {
  for (const base of DUR_BASES) {
    for (let dots = 0; dots <= maxDots; dots++) {
      const d = { base, dots };
      const v = durToFrac(d);
      if (v.n === f.n && v.d === f.d) return d;
    }
  }
  return null;
}

const UNDOTTED: Frac[] = DUR_BASES.map((b) => frac(1, b));

/**
 * Splits a span [start, start+len) (positions relative to the measure start)
 * into standard undotted durations aligned on their own value — the
 * conventional way of writing rests and of splitting tied notes.
 * Example: start 1/4, len 3/4 → [1/4, 1/2].
 */
export function decomposeAligned(start: Frac, len: Frac): Duration[] {
  const out: Duration[] = [];
  let pos = start;
  let rest = len;
  let guard = 0;
  while (!isZero(rest)) {
    if (++guard > 512) throw new Error('decomposeAligned: cannot decompose');
    let chosen: number | null = null;
    for (let i = 0; i < UNDOTTED.length; i++) {
      const v = UNDOTTED[i];
      if (le(v, rest) && isMultipleOf(pos, v)) {
        chosen = i;
        break;
      }
    }
    if (chosen === null) {
      // Position finer than 1/64 — fall back to the largest value that fits.
      chosen = UNDOTTED.findIndex((v) => le(v, rest));
      if (chosen < 0) throw new Error('decomposeAligned: remainder below 1/64');
    }
    out.push({ base: DUR_BASES[chosen], dots: 0 });
    pos = add(pos, UNDOTTED[chosen]);
    rest = sub(rest, UNDOTTED[chosen]);
  }
  return out;
}

/**
 * Splits a note span into as few symbols as possible: a single (dotted) value
 * when the length is representable, aligned decomposition otherwise.
 */
export function decomposeNote(start: Frac, len: Frac): Duration[] {
  const single = fracToDuration(len, 2);
  if (single) return [single];
  return decomposeAligned(start, len);
}

export function sumDurations(ds: Duration[]): Frac {
  return ds.reduce((acc, d) => add(acc, durToFrac(d)), ZERO);
}

export function isValidDuration(d: unknown): d is Duration {
  if (!d || typeof d !== 'object') return false;
  const x = d as Duration;
  return DUR_BASES.includes(x.base as DurBase) && Number.isInteger(x.dots) && x.dots >= 0 && x.dots <= 3 && x.base * 2 ** x.dots <= 512;
}

export function durationName(d: Duration): string {
  const names: Record<number, string> = {
    1: 'Целая',
    2: 'Половинная',
    4: 'Четвертная',
    8: 'Восьмая',
    16: '1/16',
    32: '1/32',
    64: '1/64',
  };
  return names[d.base] + (d.dots ? ' ' + '•'.repeat(d.dots) : '');
}

/** Beat-grouping span used for automatic beaming. */
export function beamGroupLength(ts: TimeSig): Frac {
  if (ts.unit === 8 && ts.count % 3 === 0 && ts.count > 3) return frac(3, 8);
  if (ts.unit === 2) return frac(1, 2);
  if (ts.unit >= 8) return frac(1, 4);
  if (ts.unit === 4 && ts.count === 4) return frac(1, 4);
  return frac(1, ts.unit);
}
