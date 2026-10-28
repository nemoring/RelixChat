/** Exact rational arithmetic for musical time (unit = whole note). */

export interface Frac {
  n: number;
  d: number;
}

function gcd(a: number, b: number): number {
  a = Math.abs(a);
  b = Math.abs(b);
  while (b) {
    [a, b] = [b, a % b];
  }
  return a || 1;
}

export function frac(n: number, d = 1): Frac {
  if (d === 0) throw new Error('Fraction with zero denominator');
  if (d < 0) {
    n = -n;
    d = -d;
  }
  const g = gcd(n, d);
  return { n: n / g, d: d / g };
}

export const ZERO: Frac = { n: 0, d: 1 };

export const add = (a: Frac, b: Frac): Frac => frac(a.n * b.d + b.n * a.d, a.d * b.d);
export const sub = (a: Frac, b: Frac): Frac => frac(a.n * b.d - b.n * a.d, a.d * b.d);
export const mul = (a: Frac, b: Frac): Frac => frac(a.n * b.n, a.d * b.d);
export const div = (a: Frac, b: Frac): Frac => frac(a.n * b.d, a.d * b.n);
export const cmp = (a: Frac, b: Frac): number => a.n * b.d - b.n * a.d;
export const eq = (a: Frac, b: Frac): boolean => cmp(a, b) === 0;
export const lt = (a: Frac, b: Frac): boolean => cmp(a, b) < 0;
export const le = (a: Frac, b: Frac): boolean => cmp(a, b) <= 0;
export const gt = (a: Frac, b: Frac): boolean => cmp(a, b) > 0;
export const ge = (a: Frac, b: Frac): boolean => cmp(a, b) >= 0;
export const isZero = (a: Frac): boolean => a.n === 0;
export const min = (a: Frac, b: Frac): Frac => (lt(a, b) ? a : b);
export const toNumber = (a: Frac): number => a.n / a.d;
/** True if a is an integer multiple of b. */
export const isMultipleOf = (a: Frac, b: Frac): boolean => {
  const q = div(a, b);
  return q.d === 1;
};
export const fracToString = (a: Frac): string => (a.d === 1 ? `${a.n}` : `${a.n}/${a.d}`);
