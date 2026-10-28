import type { ClefKind, Score, Staff, TimeSig, VoiceEvent, ChordEvent } from './types';
import { Frac, ZERO, add } from './fraction';
import { durToFrac, measureLength } from './duration';

export interface StaffRef {
  partIndex: number;
  staffInPart: number;
  staff: Staff;
}

/** All staves of the score in system order (global staff index = array index). */
export function staffRefs(score: Score): StaffRef[] {
  const out: StaffRef[] = [];
  score.parts.forEach((part, partIndex) =>
    part.staves.forEach((staff, staffInPart) => out.push({ partIndex, staffInPart, staff })),
  );
  return out;
}

export function getStaff(score: Score, staffIndex: number): Staff {
  let i = staffIndex;
  for (const part of score.parts) {
    if (i < part.staves.length) return part.staves[i];
    i -= part.staves.length;
  }
  throw new Error(`Staff ${staffIndex} does not exist`);
}

export function staffCount(score: Score): number {
  return score.parts.reduce((n, p) => n + p.staves.length, 0);
}

export function timeSigAt(score: Score, m: number): TimeSig {
  for (let i = Math.min(m, score.measures.length - 1); i >= 0; i--) {
    const ts = score.measures[i].timeSig;
    if (ts) return ts;
  }
  return { count: 4, unit: 4 };
}

export function keyAt(score: Score, m: number): number {
  for (let i = Math.min(m, score.measures.length - 1); i >= 0; i--) {
    const k = score.measures[i].keySig;
    if (k !== undefined) return k;
  }
  return 0;
}

export function clefAt(score: Score, staffIndex: number, _m: number): ClefKind {
  return getStaff(score, staffIndex).clef;
}

export function measureLen(score: Score, m: number): Frac {
  return measureLength(timeSigAt(score, m));
}

/** Per-measure effective time signatures, computed in one pass (for long scores). */
export function effectiveTimeSigs(score: Score): TimeSig[] {
  const out: TimeSig[] = [];
  let cur: TimeSig = { count: 4, unit: 4 };
  for (const mi of score.measures) {
    if (mi.timeSig) cur = mi.timeSig;
    out.push(cur);
  }
  return out;
}

export function effectiveKeys(score: Score): number[] {
  const out: number[] = [];
  let cur = 0;
  for (const mi of score.measures) {
    if (mi.keySig !== undefined) cur = mi.keySig;
    out.push(cur);
  }
  return out;
}

export interface Timed {
  ev: VoiceEvent;
  index: number;
  start: Frac;
  end: Frac;
}

export function timeline(events: VoiceEvent[]): Timed[] {
  let t = ZERO;
  return events.map((ev, index) => {
    const start = t;
    t = add(t, durToFrac(ev.dur));
    return { ev, index, start, end: t };
  });
}

export function voiceLength(events: VoiceEvent[]): Frac {
  return events.reduce((acc, e) => add(acc, durToFrac(e.dur)), ZERO);
}

export interface EventLoc {
  staff: number;
  measure: number;
  voice: number;
  eventId: string;
}

export interface FoundEvent extends EventLoc {
  ev: VoiceEvent;
  index: number;
  start: Frac;
}

/** Locates an event by id; `hint` (likely location) is checked first. */
export function findEvent(score: Score, eventId: string, hint?: Partial<EventLoc>): FoundEvent | null {
  const refs = staffRefs(score);
  const check = (s: number, m: number, v: number): FoundEvent | null => {
    const events = refs[s]?.staff.measures[m]?.voices[v];
    if (!events) return null;
    let t = ZERO;
    for (let i = 0; i < events.length; i++) {
      if (events[i].id === eventId) return { staff: s, measure: m, voice: v, eventId, ev: events[i], index: i, start: t };
      t = add(t, durToFrac(events[i].dur));
    }
    return null;
  };
  if (hint && hint.staff !== undefined && hint.measure !== undefined) {
    for (let v = 0; v < 4; v++) {
      const r = check(hint.staff, hint.measure, hint.voice ?? v);
      if (r) return r;
      if (hint.voice !== undefined) break;
    }
  }
  for (let s = 0; s < refs.length; s++) {
    const ms = refs[s].staff.measures;
    for (let m = 0; m < ms.length; m++) {
      for (let v = 0; v < ms[m].voices.length; v++) {
        const r = check(s, m, v);
        if (r) return r;
      }
    }
  }
  return null;
}

/** Finds the event containing a note id. */
export function findNote(score: Score, noteId: string, hint?: Partial<EventLoc>): (FoundEvent & { noteIndex: number }) | null {
  const tryEvent = (f: FoundEvent | null) => {
    if (!f || f.ev.type !== 'chord') return null;
    const noteIndex = f.ev.notes.findIndex((n) => n.id === noteId);
    return noteIndex >= 0 ? { ...f, noteIndex } : null;
  };
  if (hint?.eventId) {
    const r = tryEvent(findEvent(score, hint.eventId, hint));
    if (r) return r;
  }
  const refs = staffRefs(score);
  for (let s = 0; s < refs.length; s++) {
    const ms = refs[s].staff.measures;
    for (let m = 0; m < ms.length; m++) {
      for (let v = 0; v < ms[m].voices.length; v++) {
        let t = ZERO;
        const events = ms[m].voices[v];
        for (let i = 0; i < events.length; i++) {
          const ev = events[i];
          if (ev.type === 'chord') {
            const noteIndex = ev.notes.findIndex((n) => n.id === noteId);
            if (noteIndex >= 0) return { staff: s, measure: m, voice: v, eventId: ev.id, ev, index: i, start: t, noteIndex };
          }
          t = add(t, durToFrac(ev.dur));
        }
      }
    }
  }
  return null;
}

/** The event that starts at or contains time t in a voice. */
export function eventAtTime(events: VoiceEvent[], t: Frac): Timed | null {
  for (const x of timeline(events)) {
    if (x.start.n * t.d <= t.n * x.start.d && t.n * x.end.d < x.end.n * t.d) return x;
  }
  return null;
}

/** Previous chord in the same voice (searching backwards across measures). */
export function previousChord(score: Score, staff: number, measure: number, voice: number, beforeIndex: number): ChordEvent | null {
  const st = getStaff(score, staff);
  for (let m = measure; m >= 0 && m > measure - 64; m--) {
    const events = st.measures[m]?.voices[voice] ?? [];
    const start = m === measure ? Math.min(beforeIndex, events.length) - 1 : events.length - 1;
    for (let i = start; i >= 0; i--) {
      const e = events[i];
      if (e.type === 'chord') return e;
    }
  }
  return null;
}
