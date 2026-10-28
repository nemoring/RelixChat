/**
 * The score canvas: real engraved pages from Verovio, virtualised (only the
 * pages near the viewport are rendered to SVG), with selection highlighting,
 * the note-input cursor and mouse note entry.
 */
import { memo, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useStore, getState } from '../state/store';
import { scoreToMei, parseStaffSvgId, measureSvgId, staffSvgId, type ElementRef } from '../engrave/mei';
import { getEngraver } from '../engrave/engraver';
import { changedMeasures, pageMetaOf, renderPartialPage, warmUpFastLayout, type PageMeta } from '../engrave/fastLayout';
import { verovioOptions, pageSizeMm, PX_PER_MM, hasForcedBreaks } from '../engrave/layout';
import { getStaff, timeline, clefAt, staffCount, ottavaOctaves, eventIndex, comparePos } from '../model/query';
import { selectedEvents } from '../state/selection';
import { svgIdOf } from '../engrave/mei';
import { clefBottomLine } from '../model/pitch';
import { Frac, ZERO, cmp } from '../model/fraction';
import * as A from '../state/actions';
import { attachPlayback, invalidatePlaybackGeometry, measureGeometry } from './playbackOverlay';
import { getSettings } from '../state/settings';
import { frac as mkFrac } from '../model/fraction';
import { measureLength } from '../model/duration';
import { timeSigAt } from '../model/query';
import type { Score } from '../model/types';

interface RenderInfo {
  renderId: number;
  pageCount: number;
  index: Map<string, ElementRef>;
  ms: number;
}

interface CachedPage {
  renderId: number;
  svg: string;
  /** viewBox width/height in Verovio units (tenths of mm). */
  w: number;
  h: number;
  /** Measures and systems on the page (from the full layout). */
  meta?: PageMeta | null;
}

function viewBoxOf(svg: string): [number, number] {
  const m = /viewBox="0 0 (\d+(?:\.\d+)?) (\d+(?:\.\d+)?)"/.exec(svg);
  return m ? [Number(m[1]), Number(m[2])] : [2100, 2970];
}

const PageBox = memo(function PageBox(props: { page: number; svg: string | null; width: number; height: number; stale: boolean }) {
  return (
    <div className={`page${props.stale ? ' stale' : ''}`} data-page={props.page} style={{ width: props.width, height: props.height }}>
      {props.svg ? <div className="svg-host" dangerouslySetInnerHTML={{ __html: props.svg }} /> : <div className="page-loading">Гравировка…</div>}
      <div className="overlay" />
      <div className="play-overlay" />
    </div>
  );
});

/** SVG element id that represents an event (single notes are drawn as <note>). */
function svgIdForEvent(ev: Score['parts'][number]['staves'][number]['measures'][number]['voices'][number][number]): string {
  return ev.type === 'chord' && ev.notes.length === 1 ? ev.notes[0].id : ev.id;
}

function staffLines(staffEl: Element): DOMRect[] {
  const lines = Array.from(staffEl.children).filter((c) => c.tagName === 'path').slice(0, 5);
  return lines.map((l) => l.getBoundingClientRect());
}

export function ScoreView() {
  const score = useStore((s) => s.score);
  const view = useStore((s) => s.view);
  const selection = useStore((s) => s.selection);
  const cursor = useStore((s) => s.cursor);
  const inputActive = useStore((s) => s.input.active);
  const revealReq = useStore((s) => s.reveal);
  const scrollRef = useRef<HTMLDivElement>(null);
  const [render, setRender] = useState<RenderInfo | null>(null);
  const cache = useRef(new Map<number, CachedPage>());
  const [cacheVersion, setCacheVersion] = useState(0);
  const [visible, setVisible] = useState<Set<number>>(new Set([1, 2]));
  const [error, setError] = useState<string | null>(null);
  const engraver = useMemo(() => getEngraver(), []);

  // ── layout: score → MEI → Verovio (in the worker) ──
  const prevScore = useRef<Score | null>(null);
  const prevMode = useRef(view.mode);
  const renderRef = useRef<RenderInfo | null>(null);
  renderRef.current = render;
  useEffect(() => {
    let cancelled = false;
    const prev = prevScore.current;
    prevScore.current = score;
    const sameMode = prevMode.current === view.mode;
    prevMode.current = view.mode;
    // Fast path: re-engrave only the visible pages whose notes changed.
    const changed = prev && sameMode && view.mode === 'page' && renderRef.current ? changedMeasures(prev, score) : null;
    if (changed && changed.size) {
      for (const [p, c] of cache.current) {
        if (!c.meta || c.renderId !== renderRef.current!.renderId) continue;
        const meta = c.meta;
        if (![...changed].some((m) => m >= meta.first && m <= meta.last)) continue;
        renderPartialPage(score, p, meta).then((r) => {
          if (cancelled || !r || !renderRef.current) return;
          const cur = cache.current.get(p);
          if (!cur || cur.renderId !== renderRef.current.renderId) return;
          for (const [k, v] of r.index) renderRef.current.index.set(k, v);
          const [w, h] = viewBoxOf(r.svg);
          cache.current.set(p, { ...cur, svg: r.svg, w, h });
          setCacheVersion((x) => x + 1);
        });
      }
    }
    // Full layout (debounced while the fast path keeps the screen current).
    const timer = setTimeout(() => {
      if (cancelled) return;
      const { mei, index } = scoreToMei(score);
      engraver.load(mei, verovioOptions(score.layout, view.mode, hasForcedBreaks(score))).then((info) => {
        if (cancelled || !info) return;
        if (!info.ok) {
          setError(info.log || 'Verovio не смог обработать партитуру');
          return;
        }
        setError(null);
        setRender({ renderId: info.renderId, pageCount: info.pageCount, index, ms: info.ms });
      });
    }, changed && changed.size ? 350 : 0);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [score, view.mode, engraver]);

  // Drop cached pages beyond the new page count.
  useEffect(() => {
    if (!render) return;
    for (const p of [...cache.current.keys()]) if (p > render.pageCount) cache.current.delete(p);
  }, [render]);

  // ── fetch SVG for visible pages of the current render ──
  useEffect(() => {
    if (!render) return;
    const wanted = new Set<number>();
    for (const p of visible) for (const q of [p - 1, p, p + 1]) if (q >= 1 && q <= render.pageCount) wanted.add(q);
    if (wanted.size === 0) wanted.add(1);
    for (const p of wanted) {
      const c = cache.current.get(p);
      if (c && c.renderId === render.renderId) continue;
      engraver.page(render.renderId, p).then((svg) => {
        if (engraver.currentId !== render.renderId) return;
        const [w, h] = viewBoxOf(svg);
        cache.current.set(p, { renderId: render.renderId, svg, w, h, meta: pageMetaOf(svg) });
        setCacheVersion((v) => v + 1);
      });
    }
    // Evict far-away pages to bound memory on very long scores.
    for (const p of [...cache.current.keys()]) {
      if (![...wanted].some((q) => Math.abs(q - p) <= 4)) cache.current.delete(p);
    }
  }, [render, visible, engraver]);

  // ── visibility tracking ──
  const observer = useRef<IntersectionObserver | null>(null);
  useEffect(() => {
    observer.current = new IntersectionObserver(
      (entries) => {
        setVisible((prev) => {
          const next = new Set(prev);
          for (const e of entries) {
            const p = Number((e.target as HTMLElement).dataset.page);
            if (e.isIntersecting) next.add(p);
            else next.delete(p);
          }
          return next;
        });
      },
      { root: scrollRef.current, rootMargin: '400px' },
    );
    return () => observer.current?.disconnect();
  }, []);
  useEffect(() => {
    const root = scrollRef.current;
    if (!root || !observer.current) return;
    observer.current.disconnect();
    root.querySelectorAll('.page').forEach((el) => observer.current!.observe(el));
  }, [render?.pageCount, view.mode, view.zoom]);

  // ── page geometry ──
  const [pwMm, phMm] = pageSizeMm(score.layout);
  const scale = PX_PER_MM * view.zoom;
  const pages = useMemo(() => {
    const n = render?.pageCount ?? 1;
    return Array.from({ length: n }, (_, i) => {
      const c = cache.current.get(i + 1);
      const w = c ? c.w / 10 : pwMm;
      const h = c ? c.h / 10 : view.mode === 'continuous' ? 60 : phMm;
      return { page: i + 1, svg: c?.svg ?? null, width: w * scale, height: h * scale, stale: !!c && c.renderId !== render?.renderId };
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [render, cacheVersion, scale, pwMm, phMm, view.mode]);

  useEffect(() => {
    const t = setTimeout(warmUpFastLayout, 1500);
    return () => clearTimeout(t);
  }, []);

  // ── playback cursor ──
  useEffect(() => (scrollRef.current ? attachPlayback(scrollRef.current) : undefined), []);
  useLayoutEffect(() => invalidatePlaybackGeometry(), [pages, view.zoom]);

  // ── selection highlight & cursor overlays ──
  useLayoutEffect(() => {
    const root = scrollRef.current;
    if (!root) return;
    root.querySelectorAll('.nf-sel').forEach((el) => el.classList.remove('nf-sel'));
    root.querySelectorAll('.overlay').forEach((el) => (el.innerHTML = ''));
    const byId = (id: string) => root.querySelector(`[id="${id}"]`);
    const addBox = (el: Element, cls: string, rect?: { left: number; top: number; width: number; height: number }) => {
      const pageEl = el.closest('.page');
      const overlay = pageEl?.querySelector('.overlay');
      if (!pageEl || !overlay) return null;
      const pr = pageEl.getBoundingClientRect();
      const r = rect ?? el.getBoundingClientRect();
      const box = document.createElement('div');
      box.className = cls;
      Object.assign(box.style, { left: `${r.left - pr.left}px`, top: `${r.top - pr.top}px`, width: `${r.width}px`, height: `${r.height}px` });
      overlay.appendChild(box);
      return box;
    };
    // Melody lines: colour their notes and connect them across hands and voices.
    root.querySelectorAll('.nf-line').forEach((el) => {
      el.classList.remove('nf-line');
      (el as HTMLElement).style.removeProperty('fill');
      (el as HTMLElement).style.removeProperty('stroke');
    });
    root.querySelectorAll('svg.melody-overlay').forEach((el) => el.remove());
    if (view.showLines && score.lines.length) {
      const colors = new Map(score.lines.map((l) => [l.id, l.color]));
      const byLine = new Map<string, { measure: number; start: { n: number; d: number }; ev: import('../model/types').ChordEvent }[]>();
      for (const e of eventIndex(score).values()) {
        if (e.ev.type !== 'chord' || !e.ev.line || !colors.has(e.ev.line)) continue;
        if (!byLine.has(e.ev.line)) byLine.set(e.ev.line, []);
        byLine.get(e.ev.line)!.push({ measure: e.measure, start: e.start, ev: e.ev });
      }
      for (const [lineId, evs] of byLine) {
        const color = colors.get(lineId)!;
        evs.sort((a, b) => comparePos(a, b));
        let prev: { page: Element; x: number; y: number } | null = null;
        for (const e of evs) {
          const top = e.ev.notes[e.ev.notes.length - 1];
          for (const n of e.ev.notes) {
            const el = byId(n.id) as HTMLElement | null;
            if (!el) continue;
            el.classList.add('nf-line');
            el.style.setProperty('fill', color);
            el.style.setProperty('stroke', color);
          }
          const head = byId(top.id)?.querySelector('.notehead') ?? byId(top.id);
          const pageEl = head?.closest('.page');
          if (!head || !pageEl) {
            prev = null;
            continue;
          }
          const pr = pageEl.getBoundingClientRect();
          const r = head.getBoundingClientRect();
          const pt = { page: pageEl, x: r.left + r.width / 2 - pr.left, y: r.top + r.height / 2 - pr.top };
          if (prev && prev.page === pageEl && pt.x > prev.x) {
            let svg = pageEl.querySelector(`svg.melody-overlay[data-line="${lineId}"]`) as SVGSVGElement | null;
            if (!svg) {
              svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
              svg.setAttribute('class', 'melody-overlay');
              svg.dataset.line = lineId;
              Object.assign(svg.style, { position: 'absolute', inset: '0', width: '100%', height: '100%', pointerEvents: 'none', overflow: 'visible' });
              pageEl.querySelector('.overlay')?.after(svg);
            }
            const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            path.setAttribute('class', 'melody-path');
            path.setAttribute('stroke', color);
            path.setAttribute('d', `M${prev.x},${prev.y} L${pt.x},${pt.y}`);
            svg.appendChild(path);
          }
          prev = pt;
        }
      }
    }
    if (selection.kind === 'event') {
      const id = selection.noteId ?? selection.eventId;
      const el = byId(id) ?? byId(selection.eventId);
      el?.classList.add('nf-sel');
    } else if (selection.kind === 'span') {
      for (const e of selectedEvents(score, selection)) byId(svgIdOf(e.ev))?.classList.add('nf-sel');
    } else if (selection.kind === 'range') {
      for (let s = selection.staffFrom; s <= selection.staffTo; s++) {
        for (let m = selection.mFrom; m <= selection.mTo; m++) {
          const el = byId(staffSvgId(s, m));
          if (!el) continue;
          const lines = staffLines(el);
          if (lines.length < 5) continue;
          const mEl = byId(measureSvgId(m));
          const mr = mEl ? mEl.getBoundingClientRect() : lines[0];
          const top = lines[0].top - 6 * view.zoom;
          const bottom = lines[4].bottom + 6 * view.zoom;
          addBox(el, 'range-box', { left: lines[0].left, top, width: lines[0].width || mr.width, height: bottom - top });
        }
      }
    }
    if (inputActive && cursor) {
      const staffEl = byId(staffSvgId(cursor.staff, cursor.measure));
      if (staffEl) {
        const lines = staffLines(staffEl);
        if (lines.length >= 5) {
          let x = lines[0].left + 4;
          const st = getStaff(score, cursor.staff).measures[cursor.measure];
          const candidates = [st?.voices[cursor.voice] ?? [], ...(st?.voices ?? [])];
          outer: for (const events of candidates) {
            for (const tl of timeline(events)) {
              if (cmp(tl.start, cursor.time) === 0) {
                const el = byId(svgIdForEvent(tl.ev));
                if (el) {
                  x = el.classList.contains('mRest') ? measureContentLeft(staffEl, lines[0].left) : el.getBoundingClientRect().left - 3;
                  break outer;
                }
              }
            }
          }
          const sp = (lines[4].top - lines[0].top) / 4;
          addBox(staffEl, `input-cursor voice-${cursor.voice + 1}`, { left: x, top: lines[0].top - 2 * sp, width: Math.max(10, 1.6 * sp), height: lines[4].top - lines[0].top + 4 * sp });
        }
      }
    }
  }, [pages, selection, cursor, inputActive, score, view.zoom, view.showLines]);

  // ── scroll to requested measure ──
  useEffect(() => {
    if (!revealReq || !render) return;
    const root = scrollRef.current;
    if (!root) return;
    const id = measureSvgId(Math.min(revealReq.measure, score.measures.length - 1));
    const el = root.querySelector(`[id="${id}"]`);
    if (el) {
      const r = el.getBoundingClientRect();
      const rr = root.getBoundingClientRect();
      if (r.bottom > rr.bottom || r.top < rr.top || r.right > rr.right || r.left < rr.left) el.scrollIntoView({ block: 'center', inline: 'center' });
      return;
    }
    engraver.pageOf(render.renderId, id).then((p) => {
      if (p > 0) root.querySelector(`.page[data-page="${p}"]`)?.scrollIntoView({ block: 'start', inline: 'center' });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [revealReq, render, cacheVersion]);

  // ── mouse ──
  const onMouseDown = useCallback(
    (e: React.MouseEvent) => {
      if (e.button !== 0 || !render) return;
      const target = e.target as Element;
      const pageEl = target.closest('.page');
      const st = getState();
      if (!pageEl) {
        if (!st.input.active) A.clearSelection();
        return;
      }
      const hitStaff = findStaffAt(pageEl, e.clientX, e.clientY);
      if (st.input.active) {
        if (!hitStaff) return;
        const { staff, measure, lines } = hitStaff;
        const sp = (lines[4].top - lines[0].top) / 4;
        const bottomY = (lines[4].top + lines[4].bottom) / 2;
        const steps = Math.round((bottomY - e.clientY) / (sp / 2));
        const snap = getSettings().snap;
        const time = snap === 'note' ? timeAtX(pageEl, st.score, measure, e.clientX) : snappedTime(scrollRef.current!, st.score, measure, e.clientX, snap) ?? timeAtX(pageEl, st.score, measure, e.clientX);
        const diatonic = clefBottomLine(clefAt(st.score, staff, measure)) + steps + 7 * ottavaOctaves(st.score, staff, measure, time);
        A.enterNoteAt(staff, measure, time, diatonic, e.shiftKey || e.ctrlKey);
        e.preventDefault();
        return;
      }
      const hit = target.closest('g.note, g.rest, g.mRest, g.chord');
      if (hit && render.index.has(hit.id)) {
        const ref = render.index.get(hit.id)!;
        let noteId = ref.noteId;
        if (!noteId && ref.kind === 'chord') {
          // Clicked a stem: select the whole chord.
          noteId = undefined;
        }
        A.selectElement({ staff: ref.staff, measure: ref.measure, voice: ref.voice, eventId: ref.eventId, noteId }, e.shiftKey);
        return;
      }
      if (hitStaff) {
        A.selectMeasure(hitStaff.staff, hitStaff.measure, e.shiftKey);
        return;
      }
      A.clearSelection();
    },
    [render],
  );

  // Rhythmic grid under the mouse while entering notes.
  const gridRaf = useRef(0);
  const onMouseMove = useCallback((e: React.MouseEvent) => {
    const st = getState();
    const snap = getSettings().snap;
    if (!st.input.active || snap === 'note') return;
    const x = e.clientX;
    const y = e.clientY;
    const target = e.target as Element;
    cancelAnimationFrame(gridRaf.current);
    gridRaf.current = requestAnimationFrame(() => {
      const root = scrollRef.current;
      if (!root) return;
      root.querySelectorAll('.grid-line').forEach((g) => g.remove());
      const pageEl = target.closest('.page');
      if (!pageEl) return;
      const hit = findStaffAt(pageEl, x, y);
      if (!hit) return;
      const g = measureGeometry(root, hit.measure);
      if (!g) return;
      const len = measureLength(timeSigAt(st.score, hit.measure));
      const n = Math.round((len.n / len.d) * snap);
      const beat = 1 / timeSigAt(st.score, hit.measure).unit;
      for (let k = 0; k < n; k++) {
        const t = k / snap;
        const gx = interpolateX(g.points, t);
        const line = document.createElement('div');
        line.className = `grid-line${Math.abs(t / beat - Math.round(t / beat)) < 1e-9 ? ' beat' : ''}`;
        Object.assign(line.style, { left: `${gx}px`, top: `${g.top}px`, height: `${g.bottom - g.top}px` });
        g.page.querySelector('.play-overlay')?.appendChild(line);
      }
    });
  }, []);

  const onWheel = useCallback((e: React.WheelEvent) => {
    if (e.ctrlKey) {
      e.preventDefault();
      A.zoomBy(e.deltaY < 0 ? 1.1 : 1 / 1.1);
    }
  }, []);

  return (
    <div className={`score-scroll mode-${view.mode}${inputActive ? ' input-mode' : ''}`} ref={scrollRef} onMouseDown={onMouseDown} onMouseMove={onMouseMove} onWheel={onWheel} tabIndex={-1}>
      {error && <div className="engrave-error">Ошибка гравировки: {error}</div>}
      <div className="pages">
        {pages.map((p) => (
          <PageBox key={p.page} {...p} />
        ))}
      </div>
      {render && (
        <div className="render-stats" title="Время раскладки партитуры">
          {render.pageCount} стр. · {Math.round(render.ms)} мс · {staffCount(score)} нотоносца
        </div>
      )}
    </div>
  );
}

/** Finds the staff (and measure) under a point using the staff line geometry. */
function findStaffAt(pageEl: Element, x: number, y: number): { staff: number; measure: number; lines: DOMRect[] } | null {
  let best: { staff: number; measure: number; lines: DOMRect[]; dist: number } | null = null;
  for (const el of Array.from(pageEl.querySelectorAll('g.staff'))) {
    const ids = parseStaffSvgId(el.id);
    if (!ids) continue;
    const lines = staffLines(el);
    if (lines.length < 5) continue;
    const left = lines[0].left;
    const right = lines[0].right;
    if (x < left || x > right) continue;
    const sp = (lines[4].top - lines[0].top) / 4;
    const top = lines[0].top;
    const bottom = lines[4].bottom;
    const dist = y < top ? top - y : y > bottom ? y - bottom : 0;
    if (dist > sp * 6) continue;
    if (!best || dist < best.dist) best = { ...ids, lines, dist };
  }
  return best;
}

/** Rhythmic position in a measure closest to the left of x (segments are aligned across staves). */
function timeAtX(pageEl: Element, score: Score, measure: number, x: number): Frac {
  let bestT: Frac = ZERO;
  let bestX = -Infinity;
  for (let s = 0; s < staffCount(score); s++) {
    const sm = getStaff(score, s).measures[measure];
    if (!sm) continue;
    for (const events of sm.voices) {
      if (events.length === 1 && events[0].type === 'rest') continue; // mRest is centred, not positional
      for (const tl of timeline(events)) {
        const el = pageEl.querySelector(`[id="${svgIdForEvent(tl.ev)}"]`);
        if (!el) continue;
        const r = el.getBoundingClientRect();
        if (r.left - 4 <= x && r.left > bestX) {
          bestX = r.left;
          bestT = tl.start;
        }
      }
    }
  }
  return bestT;
}

/** Left edge of the music in a staff measure, after any clef / key / time signature. */
function measureContentLeft(staffEl: Element, lineLeft: number): number {
  let x = lineLeft + 6;
  for (const el of Array.from(staffEl.querySelectorAll(':scope > g.clef, :scope > g.keySig, :scope > g.meterSig'))) {
    const r = el.getBoundingClientRect();
    if (r.width > 0) x = Math.max(x, r.right + 6);
  }
  return x;
}

function interpolateX(pts: { t: number; x: number }[], t: number): number {
  for (let i = 0; i < pts.length - 1; i++) {
    if (t >= pts[i].t && t <= pts[i + 1].t) return pts[i].x + ((t - pts[i].t) / Math.max(1e-9, pts[i + 1].t - pts[i].t)) * (pts[i + 1].x - pts[i].x);
  }
  return pts[pts.length - 1]?.x ?? 0;
}

/** Time under x snapped to the grid (1/snap of a whole note), from the engraved positions. */
function snappedTime(root: HTMLElement, score: Score, measure: number, clientX: number, snap: number): Frac | null {
  const g = measureGeometry(root, measure);
  if (!g) return null;
  const x = clientX - g.page.getBoundingClientRect().left;
  const pts = g.points;
  let t = 0;
  if (x <= pts[0].x) t = 0;
  else if (x >= pts[pts.length - 1].x) t = pts[pts.length - 1].t;
  else
    for (let i = 0; i < pts.length - 1; i++) {
      if (x >= pts[i].x && x <= pts[i + 1].x) {
        t = pts[i].t + ((x - pts[i].x) / Math.max(1e-9, pts[i + 1].x - pts[i].x)) * (pts[i + 1].t - pts[i].t);
        break;
      }
    }
  const len = measureLength(timeSigAt(score, measure));
  const k = Math.max(0, Math.min(Math.floor(t * snap + 0.35), Math.round((len.n / len.d) * snap) - 1));
  return mkFrac(k, snap);
}
