/**
 * Score checker: measures whose voices do not add up to the time signature,
 * incomplete tuplets, ties that lead nowhere, notes outside the piano range
 * and completely empty measures.
 */
import type { Score } from './types';
import { cmp, add, ZERO, frac, mul } from './fraction';
import { durToFrac, measureLength } from './duration';
import { effectiveTimeSigs, staffRefs, voiceLength } from './query';
import { blocksOf, tieResolves } from './edit';
import { midiOf, pitchName } from './pitch';
import { fitVoice } from './serialize';

export interface Issue {
  measure: number;
  staff?: number;
  voice?: number;
  kind: 'underfull' | 'overfull' | 'tuplet' | 'tie' | 'range' | 'empty';
  severity: 'error' | 'warning' | 'info';
  text: string;
}

export function checkScore(score: Score): Issue[] {
  const out: Issue[] = [];
  const sigs = effectiveTimeSigs(score);
  const refs = staffRefs(score);
  for (let m = 0; m < score.measures.length; m++) {
    const mlen = measureLength(sigs[m]);
    let anyNote = false;
    refs.forEach(({ staff }, s) => {
      staff.measures[m].voices.forEach((events, v) => {
        if (!events.length) return;
        const len = voiceLength(events);
        const c = cmp(len, mlen);
        const where = `такт ${m + 1}, нотоносец ${s + 1}, голос ${v + 1}`;
        if (c < 0) out.push({ measure: m, staff: s, voice: v, kind: 'underfull', severity: 'error', text: `Незаполненный такт (${where})` });
        if (c > 0) out.push({ measure: m, staff: s, voice: v, kind: 'overfull', severity: 'error', text: `Переполненный такт (${where})` });
        for (const b of blocksOf(events)) {
          if (!b.tuplet) continue;
          const written = b.events.reduce((a, e) => add(a, durToFrac(e.dur)), ZERO);
          const unit = b.events.map((e) => durToFrac(e.dur)).reduce((a, x) => (cmp(x, a) < 0 ? x : a));
          if (cmp(written, mul(unit, frac(b.tuplet.num))) !== 0)
            out.push({ measure: m, staff: s, voice: v, kind: 'tuplet', severity: 'warning', text: `Неполная ритмическая группа ${b.tuplet.num}:${b.tuplet.den} (${where})` });
        }
        for (const ev of events) {
          if (ev.type !== 'chord') continue;
          anyNote = true;
          for (const n of ev.notes) {
            const k = midiOf(n);
            if (k < 21 || k > 108) out.push({ measure: m, staff: s, voice: v, kind: 'range', severity: 'warning', text: `Нота ${pitchName(n)} вне диапазона фортепиано (${where})` });
            if (n.tie && !ev.grace && !tieResolves(score, s, m, v, ev.id, n))
              out.push({ measure: m, staff: s, voice: v, kind: 'tie', severity: 'warning', text: `Лига от ${pitchName(n)} никуда не ведёт (${where})` });
          }
        }
      });
    });
    if (!anyNote) out.push({ measure: m, kind: 'empty', severity: 'info', text: `Пустой такт ${m + 1} (только паузы)` });
  }
  return out;
}

/** Repairs what can be repaired automatically: measure lengths and dangling ties. */
export function fixIssues(score: Score, issues: Issue[]): number {
  let fixed = 0;
  const sigs = effectiveTimeSigs(score);
  const refs = staffRefs(score);
  for (const i of issues) {
    if (i.staff === undefined || i.voice === undefined) continue;
    const sm = refs[i.staff].staff.measures[i.measure];
    if (i.kind === 'underfull' || i.kind === 'overfull') {
      const f = fitVoice(sm.voices[i.voice], measureLength(sigs[i.measure]));
      if (f) {
        sm.voices[i.voice] = f;
        fixed++;
      }
    } else if (i.kind === 'tie') {
      for (const ev of sm.voices[i.voice])
        if (ev.type === 'chord')
          for (const n of ev.notes)
            if (n.tie && !tieResolves(score, i.staff, i.measure, i.voice, ev.id, n)) {
              delete n.tie;
              fixed++;
            }
    }
  }
  return fixed;
}
