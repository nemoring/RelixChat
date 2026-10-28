/**
 * Standard MIDI File (type 1) export from a Performance: a conductor track
 * (tempo, meter, key, title) and one track per staff.
 */
import type { Score } from '../model/types';
import { effectiveKeys, effectiveTimeSigs, staffRefs } from '../model/query';
import { PPQ, type Performance } from './perform';

function vlq(n: number): number[] {
  n = Math.max(0, Math.round(n));
  const bytes = [n & 0x7f];
  while ((n >>= 7)) bytes.unshift((n & 0x7f) | 0x80);
  return bytes;
}

const str = (s: string) => Array.from(new TextEncoder().encode(s));

interface Ev {
  tick: number;
  order: number;
  bytes: number[];
}

function track(events: Ev[]): number[] {
  events.sort((a, b) => a.tick - b.tick || a.order - b.order);
  const out: number[] = [];
  let last = 0;
  for (const e of events) {
    const t = Math.max(last, Math.round(e.tick));
    out.push(...vlq(t - last), ...e.bytes);
    last = t;
  }
  out.push(0, 0xff, 0x2f, 0);
  return [...str('MTrk'), ...u32(out.length), ...out];
}

const u32 = (n: number) => [(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff];
const u16 = (n: number) => [(n >> 8) & 0xff, n & 0xff];

export function performanceToMidi(score: Score, perf: Performance): Uint8Array {
  const sigs = effectiveTimeSigs(score);
  const keys = effectiveKeys(score);
  const conductor: Ev[] = [];
  const meta = (tick: number, type: number, data: number[], order = 0) => conductor.push({ tick, order, bytes: [0xff, type, ...vlq(data.length), ...data] });
  meta(0, 0x03, str(score.meta.title || 'NoteForge'));
  if (score.meta.composer) meta(0, 0x02, str(`© ${score.meta.composer}`));
  let lastQpm = -1;
  let lastSig = '';
  let lastKey = 99;
  for (const pm of perf.measures) {
    if (Math.abs(pm.qpm - lastQpm) > 1e-6) {
      const us = Math.round(60_000_000 / pm.qpm);
      meta(pm.startTick, 0x51, [(us >> 16) & 0xff, (us >> 8) & 0xff, us & 0xff]);
      lastQpm = pm.qpm;
    }
    const ts = sigs[pm.measure];
    const sigKey = `${ts.count}/${ts.unit}`;
    if (sigKey !== lastSig) {
      meta(pm.startTick, 0x58, [ts.count, Math.round(Math.log2(ts.unit)), 24, 8]);
      lastSig = sigKey;
    }
    const k = keys[pm.measure];
    if (k !== lastKey) {
      meta(pm.startTick, 0x59, [k & 0xff, 0]);
      lastKey = k;
    }
  }
  const tracks: number[][] = [track(conductor)];
  const refs = staffRefs(score);
  refs.forEach((r, s) => {
    const ch = s & 0x0f;
    const evs: Ev[] = [];
    const part = score.parts[r.partIndex];
    evs.push({ tick: 0, order: 0, bytes: [0xff, 0x03, ...vlq(str(`${part.name} ${s + 1}`).length), ...str(`${part.name} ${s + 1}`)] });
    evs.push({ tick: 0, order: 1, bytes: [0xc0 | ch, part.program & 0x7f] });
    for (const n of perf.notes) {
      if (n.staff !== s) continue;
      evs.push({ tick: n.startTick, order: 3, bytes: [0x90 | ch, n.key, Math.max(1, Math.min(127, Math.round(n.vel)))] });
      evs.push({ tick: Math.max(n.startTick + 1, n.endTick), order: 2, bytes: [0x80 | ch, n.key, 64] });
    }
    for (const p of perf.pedals ?? []) {
      if (p.staff !== s && !(p.staff === undefined && s === 0)) continue;
      evs.push({ tick: p.startTick, order: 2, bytes: [0xb0 | ch, 64, 127] });
      evs.push({ tick: p.endTick, order: 1, bytes: [0xb0 | ch, 64, 0] });
    }
    tracks.push(track(evs));
  });
  const header = [...str('MThd'), ...u32(6), ...u16(1), ...u16(tracks.length), ...u16(PPQ)];
  return new Uint8Array([...header, ...tracks.flat()]);
}
