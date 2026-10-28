/**
 * Draws the playback position on the engraved pages: highlights the notes
 * that are sounding and moves a playhead line through the current measure.
 * Runs imperatively on every animation frame (no React re-render).
 */
import { player } from '../playback/player';
import { positionAt } from '../playback/perform';
import { getState } from '../state/store';
import { getStaff, staffCount, timeline } from '../model/query';
import { measureSvgId, staffSvgId } from '../engrave/mei';
import { toNumber } from '../model/fraction';
import { measureLength } from '../model/duration';
import { timeSigAt } from '../model/query';
import * as A from '../state/actions';

let generation = 0;
/** Called by the score view whenever page SVGs are replaced. */
export function invalidatePlaybackGeometry() {
  generation++;
}

interface Geometry {
  gen: number;
  page: HTMLElement;
  top: number;
  bottom: number;
  points: { t: number; x: number }[];
}

function staffLineRects(el: Element): DOMRect[] {
  return Array.from(el.children)
    .filter((c) => c.tagName === 'path')
    .slice(0, 5)
    .map((l) => l.getBoundingClientRect());
}

export function measureGeometry(root: HTMLElement, m: number): Omit<Geometry, 'gen'> | null {
  const score = getState().score;
  const n = staffCount(score);
  const first = root.querySelector(`[id="${staffSvgId(0, m)}"]`);
  const last = root.querySelector(`[id="${staffSvgId(n - 1, m)}"]`);
  if (!first || !last) return null;
  const page = first.closest('.page') as HTMLElement | null;
  if (!page) return null;
  const pr = page.getBoundingClientRect();
  const l0 = staffLineRects(first);
  const l1 = staffLineRects(last);
  if (l0.length < 5 || l1.length < 5) return null;
  const len = toNumber(measureLength(timeSigAt(score, m)));
  const points: { t: number; x: number }[] = [];
  for (let s = 0; s < n; s++) {
    const sm = getStaff(score, s).measures[m];
    for (const events of sm?.voices ?? []) {
      if (events.every((e) => e.type === 'rest')) continue;
      for (const tl of timeline(events)) {
        const id = tl.ev.type === 'chord' && tl.ev.notes.length === 1 ? tl.ev.notes[0].id : tl.ev.id;
        const el = root.querySelector(`[id="${id}"]`);
        if (!el) continue;
        const r = el.getBoundingClientRect();
        points.push({ t: toNumber(tl.start), x: r.left + Math.min(r.width, 10) / 2 - pr.left });
      }
    }
  }
  // Measure start (after clef/key/time) and end (barline).
  let startX = l0[0].left - pr.left + 4;
  for (const el of Array.from(first.querySelectorAll(':scope > g.clef, :scope > g.keySig, :scope > g.meterSig'))) {
    const r = el.getBoundingClientRect();
    if (r.width) startX = Math.max(startX, r.right - pr.left + 4);
  }
  const endX = l0[0].right - pr.left - 4;
  points.sort((a, b) => a.t - b.t || a.x - b.x);
  const dedup: { t: number; x: number }[] = [];
  for (const p of points) if (!dedup.length || p.t > dedup[dedup.length - 1].t + 1e-9) dedup.push(p);
  if (!dedup.length || dedup[0].t > 1e-9) dedup.unshift({ t: 0, x: startX });
  dedup.push({ t: len, x: Math.max(endX, dedup[dedup.length - 1].x + 4) });
  return { page, top: l0[0].top - pr.top - 10, bottom: l1[4].bottom - pr.top + 10, points: dedup };
}

export function attachPlayback(root: HTMLElement): () => void {
  let lit = new Set<string>();
  let geom: (Geometry & { m: number }) | null = null;
  let head: HTMLDivElement | null = null;
  let lastMeasure = -1;
  let litGen = generation;
  const unsub = player.onFrame((sec, playing) => {
    if (litGen !== generation) {
      lit = new Set();
      litGen = generation;
    }
    // Note highlighting.
    for (const id of lit) if (!playing.has(id)) root.querySelector(`[id="${id}"]`)?.classList.remove('nf-play');
    for (const id of playing) if (!lit.has(id)) root.querySelector(`[id="${id}"]`)?.classList.add('nf-play');
    lit = playing;
    const perf = player.current();
    if (sec < 0 || !perf) {
      head?.remove();
      head = null;
      root.querySelectorAll('.nf-play').forEach((el) => el.classList.remove('nf-play'));
      lit = new Set();
      lastMeasure = -1;
      return;
    }
    const pos = positionAt(perf, sec);
    if (pos.measure !== lastMeasure) {
      lastMeasure = pos.measure;
      geom = null;
      // Follow the music: keep the playing measure in view.
      const el = root.querySelector(`[id="${measureSvgId(pos.measure)}"]`);
      if (el) {
        const r = el.getBoundingClientRect();
        const rr = root.getBoundingClientRect();
        if (r.bottom > rr.bottom - 20 || r.top < rr.top || r.right > rr.right || r.left < rr.left) el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'smooth' });
      } else A.revealMeasure(pos.measure);
    }
    if (!geom || geom.gen !== generation || geom.m !== pos.measure) {
      const g = measureGeometry(root, pos.measure);
      geom = g ? { ...g, gen: generation, m: pos.measure } : null;
    }
    if (!geom) return;
    const pts = geom.points;
    let x = pts[0].x;
    for (let i = 0; i < pts.length - 1; i++) {
      if (pos.time >= pts[i].t && pos.time <= pts[i + 1].t) {
        const f = (pos.time - pts[i].t) / Math.max(1e-9, pts[i + 1].t - pts[i].t);
        x = pts[i].x + f * (pts[i + 1].x - pts[i].x);
        break;
      }
      if (pos.time > pts[i + 1].t) x = pts[i + 1].x;
    }
    if (!head || head.parentElement !== geom.page.querySelector('.play-overlay')) {
      head?.remove();
      head = document.createElement('div');
      head.className = 'playhead';
      geom.page.querySelector('.play-overlay')?.appendChild(head);
    }
    head.style.left = `${x}px`;
    head.style.top = `${geom.top}px`;
    head.style.height = `${geom.bottom - geom.top}px`;
  });
  return () => {
    unsub();
    head?.remove();
  };
}
