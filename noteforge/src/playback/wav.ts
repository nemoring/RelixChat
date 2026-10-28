/**
 * Offline WAV rendering with the same synthesizer as realtime playback.
 * The piece is rendered in chunks; every note is rendered completely (with
 * release and reverb tail) in the chunk where it starts and the chunks are
 * overlap-added, so long pieces need little memory and have no seams.
 */
import { Synth } from './synth';
import type { SoundFont } from './sf2';
import type { Performance, PNote } from './perform';

export interface WavSink {
  write(bytes: Uint8Array): Promise<void>;
}

export interface WavOptions {
  sampleRate?: number;
  reverb?: number;
  gainFor: (n: PNote) => number;
  onProgress?: (fraction: number) => void;
  isCancelled?: () => boolean;
}

const CHUNK = 8; // seconds of note onsets per render pass
const TAIL = 4; // seconds of release + reverb rendered after the last note-off

export function wavHeader(frames: number, sampleRate: number, channels = 2): Uint8Array {
  const dataBytes = frames * channels * 2;
  const b = new DataView(new ArrayBuffer(44));
  const s = (o: number, t: string) => [...t].forEach((c, i) => b.setUint8(o + i, c.charCodeAt(0)));
  s(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, true);
  s(8, 'WAVE');
  s(12, 'fmt ');
  b.setUint32(16, 16, true);
  b.setUint16(20, 1, true);
  b.setUint16(22, channels, true);
  b.setUint32(24, sampleRate, true);
  b.setUint32(28, sampleRate * channels * 2, true);
  b.setUint16(32, channels * 2, true);
  b.setUint16(34, 16, true);
  s(36, 'data');
  b.setUint32(40, dataBytes, true);
  return new Uint8Array(b.buffer);
}

function toPcm(l: Float32Array, r: Float32Array, from: number, to: number): Uint8Array {
  const out = new DataView(new ArrayBuffer((to - from) * 4));
  for (let i = from, o = 0; i < to; i++, o += 4) {
    out.setInt16(o, Math.max(-32768, Math.min(32767, Math.round(l[i] * 32767))), true);
    out.setInt16(o + 2, Math.max(-32768, Math.min(32767, Math.round(r[i] * 32767))), true);
  }
  return new Uint8Array(out.buffer);
}

/** Renders the performance to 16-bit stereo PCM WAV, streaming bytes to `sink`. Returns frame count. */
export async function renderWav(perf: Performance, sf: SoundFont | null, sink: WavSink, opts: WavOptions): Promise<number> {
  const sr = opts.sampleRate ?? 44100;
  const lastEnd = perf.notes.reduce((m, n) => Math.max(m, n.end), perf.duration);
  const totalFrames = Math.ceil((lastEnd + TAIL) * sr);
  await sink.write(wavHeader(totalFrames, sr));
  // Accumulator for frames not yet written: [accStart, accStart + acc.length).
  let accStart = 0;
  let accL = new Float32Array(0);
  let accR = new Float32Array(0);
  const ensure = (endFrame: number) => {
    const need = endFrame - accStart;
    if (need <= accL.length) return;
    const nl = new Float32Array(need);
    const nr = new Float32Array(need);
    nl.set(accL);
    nr.set(accR);
    accL = nl;
    accR = nr;
  };
  let written = 0;
  let ni = 0;
  for (let c0 = 0; c0 * sr < totalFrames; c0 += CHUNK) {
    if (opts.isCancelled?.()) throw new Error('Отменено');
    const c1 = c0 + CHUNK;
    const chunkNotes: PNote[] = [];
    while (ni < perf.notes.length && perf.notes[ni].start < c1) chunkNotes.push(perf.notes[ni++]);
    const audible = chunkNotes.filter((n) => opts.gainFor(n) > 0);
    if (audible.length) {
      const renderEnd = Math.max(c1, ...audible.map((n) => n.end)) + TAIL;
      const frames = Math.ceil((renderEnd - c0) * sr);
      const ctx = new OfflineAudioContext(2, frames, sr);
      const synth = new Synth(ctx, sf);
      synth.setReverb(opts.reverb ?? 0.55);
      const channels = new Map<number, GainNode>();
      for (const n of audible) {
        const g = opts.gainFor(n);
        let ch = channels.get(g);
        if (!ch) {
          ch = synth.createChannel();
          ch.gain.value = g;
          channels.set(g, ch);
        }
        synth.playNote({ time: n.start - c0, dur: n.end - n.start, key: n.key, vel: n.vel, program: n.program, channel: ch });
      }
      const buf = await ctx.startRendering();
      const start = Math.round(c0 * sr);
      ensure(start + buf.length);
      const l = buf.getChannelData(0);
      const r = buf.getChannelData(1);
      const off = start - accStart;
      for (let i = 0; i < buf.length; i++) {
        accL[off + i] += l[i];
        accR[off + i] += r[i];
      }
    }
    // Frames before c1 are final now.
    const finalEnd = Math.min(totalFrames, Math.round(c1 * sr));
    ensure(finalEnd);
    const count = finalEnd - accStart;
    if (count > 0) {
      await sink.write(toPcm(accL, accR, 0, count));
      written += count;
      accL = accL.slice(count);
      accR = accR.slice(count);
      accStart = finalEnd;
    }
    opts.onProgress?.(Math.min(1, finalEnd / totalFrames));
  }
  return written;
}
