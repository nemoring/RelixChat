/**
 * Fast partial re-layout for long scores.
 *
 * A full Verovio layout of a 60-minute piece takes seconds. After an edit
 * that only touches note content, the visible page(s) containing the changed
 * measures are re-engraved on their own — with the system breaks they had in
 * the last full layout — in a separate worker, so the change appears almost
 * immediately. The full layout keeps running in the background and replaces
 * the pages when it is done (it is the authority for page breaks).
 */
import type { Score } from '../model/types';
import { Engraver } from './engraver';
import { scoreToMei, type ElementRef } from './mei';
import { verovioOptions } from './layout';
import { staffRefs } from '../model/query';

export interface PageMeta {
  first: number;
  last: number;
  /** First measure of each system on the page. */
  systems: number[];
}

/** Reads the measure range and system starts of an engraved page. */
export function pageMetaOf(svg: string): PageMeta | null {
  const parts = svg.split(/class="system"/);
  if (parts.length < 2) return null;
  const systems: number[] = [];
  let first = Infinity;
  let last = -Infinity;
  for (const chunk of parts.slice(1)) {
    const ids = [...chunk.matchAll(/id="nf-m-(\d+)"/g)].map((m) => Number(m[1]));
    if (!ids.length) continue;
    systems.push(ids[0]);
    first = Math.min(first, ...ids);
    last = Math.max(last, ...ids);
  }
  return systems.length ? { first, last, systems } : null;
}

/**
 * Measures whose note content changed between two versions of the score, or
 * null when the change is structural (measure count, signatures, clefs,
 * spanners, layout…) and needs a full layout.
 */
export function changedMeasures(prev: Score, next: Score): Set<number> | null {
  if (prev === next) return new Set();
  if (prev.measures.length !== next.measures.length) return null;
  if (prev.layout !== next.layout || prev.meta !== next.meta || prev.tempo !== next.tempo || prev.spanners !== next.spanners || prev.lines !== next.lines) return null;
  const a = staffRefs(prev);
  const b = staffRefs(next);
  if (a.length !== b.length) return null;
  const out = new Set<number>();
  for (let m = 0; m < next.measures.length; m++) {
    if (prev.measures[m] !== next.measures[m]) return null;
    for (let s = 0; s < b.length; s++) {
      if (a[s].staff.clef !== b[s].staff.clef) return null;
      const x = a[s].staff.measures[m];
      const y = b[s].staff.measures[m];
      if (x === y) continue;
      if (x.clef !== y.clef) return null;
      // Ties reach into the neighbouring measures.
      out.add(m);
      if (m > 0) out.add(m - 1);
      if (m + 1 < next.measures.length) out.add(m + 1);
    }
  }
  return out;
}

let fast: Engraver | null = null;
const engraver = () => (fast ??= new Engraver());

/** Re-engraves one page of the score with fixed system breaks. */
export async function renderPartialPage(score: Score, page: number, meta: PageMeta): Promise<{ svg: string; index: Map<string, ElementRef> } | null> {
  const { mei, index } = scoreToMei(score, { from: meta.first, to: meta.last, systemBreaks: meta.systems.slice(1), pageLabel: String(page), partial: true });
  const opts = { ...verovioOptions(score.layout, 'page'), breaks: 'encoded' };
  const info = await engraver().load(mei, opts);
  if (!info || !info.ok || info.pageCount !== 1) return null;
  return { svg: await engraver().page(info.renderId, 1), index };
}

/** Starts the fast-layout worker early so the first edit does not pay for loading Verovio. */
export function warmUpFastLayout(): void {
  engraver();
}
