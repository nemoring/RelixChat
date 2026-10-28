/** Resolves selections into the events they cover. */
import type { Score } from '../model/types';
import { eventIndex, comparePos, getStaff, type IndexedEvent } from '../model/query';
import { add, ZERO } from '../model/fraction';
import { eventLen } from '../model/duration';
import type { Selection, EventRef } from './store';

/** Events of a span selection: from the earlier to the later end, on the staves/voices of both ends. */
export function spanEvents(score: Score, anchor: EventRef, focus: EventRef): IndexedEvent[] {
  const idx = eventIndex(score);
  const a = idx.get(anchor.eventId);
  const b = idx.get(focus.eventId);
  if (!a || !b) return [];
  const [s0, e0] = comparePos(a, b) <= 0 ? [a, b] : [b, a];
  const lanes = new Set([`${a.staff}:${a.voice}`, `${b.staff}:${b.voice}`]);
  const out: IndexedEvent[] = [];
  for (const lane of lanes) {
    const [staff, voice] = lane.split(':').map(Number);
    const st = getStaff(score, staff);
    for (let m = s0.measure; m <= e0.measure; m++) {
      let t = ZERO;
      (st.measures[m].voices[voice] ?? []).forEach((ev, index) => {
        const pos = { measure: m, start: t };
        const end = add(t, eventLen(ev));
        if (comparePos(pos, s0) >= 0 && comparePos(pos, e0) <= 0) out.push({ staff, measure: m, voice, index, start: t, end, ev });
        t = end;
      });
    }
  }
  out.sort((x, y) => comparePos(x, y) || x.staff - y.staff);
  return out;
}

/** Every event covered by the selection (event, span or measure range), in score order. */
export function selectedEvents(score: Score, sel: Selection): IndexedEvent[] {
  if (sel.kind === 'event') {
    const e = eventIndex(score).get(sel.eventId);
    return e ? [e] : [];
  }
  if (sel.kind === 'span') return spanEvents(score, sel.anchor, sel.focus);
  if (sel.kind === 'range') {
    const out: IndexedEvent[] = [];
    for (let s = sel.staffFrom; s <= sel.staffTo; s++) {
      const st = getStaff(score, s);
      for (let m = sel.mFrom; m <= sel.mTo; m++)
        st.measures[m].voices.forEach((events, voice) => {
          let t = ZERO;
          events.forEach((ev, index) => {
            const end = add(t, eventLen(ev));
            out.push({ staff: s, measure: m, voice, index, start: t, end, ev });
            t = end;
          });
        });
    }
    out.sort((x, y) => comparePos(x, y) || x.staff - y.staff || x.voice - y.voice);
    return out;
  }
  return [];
}

/** First and last events of the selection (for spanners). */
export function selectionEnds(score: Score, sel: Selection): { first: IndexedEvent; last: IndexedEvent } | null {
  let evs = selectedEvents(score, sel).filter((e) => e.ev.type === 'chord' && !e.ev.grace);
  if (sel.kind === 'range') {
    // Measure range: use the first staff's voice 1.
    evs = evs.filter((e) => e.staff === sel.staffFrom && e.voice === 0);
  }
  if (!evs.length) return null;
  return { first: evs[0], last: evs[evs.length - 1] };
}

/** Measure range touched by the selection. */
export function selectionMeasures(score: Score, sel: Selection): { from: number; to: number; staffFrom: number; staffTo: number } | null {
  if (sel.kind === 'range') return { from: sel.mFrom, to: sel.mTo, staffFrom: sel.staffFrom, staffTo: sel.staffTo };
  const evs = selectedEvents(score, sel);
  if (!evs.length) return null;
  return {
    from: Math.min(...evs.map((e) => e.measure)),
    to: Math.max(...evs.map((e) => e.measure)),
    staffFrom: Math.min(...evs.map((e) => e.staff)),
    staffTo: Math.max(...evs.map((e) => e.staff)),
  };
}
