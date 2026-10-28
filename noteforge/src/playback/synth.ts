/**
 * SoundFont sample-playback synthesizer on Web Audio. The same code drives
 * realtime playback (AudioContext) and WAV rendering (OfflineAudioContext),
 * so exported audio matches what the user hears.
 */
import type { Region, SoundFont } from './sf2';

export interface NoteRequest {
  /** Context time (seconds) of the note-on. */
  time: number;
  /** Sounding length in seconds (release starts at time + dur). */
  dur: number;
  key: number;
  vel: number;
  program: number;
  channel: AudioNode;
}

interface Voice {
  src: AudioScheduledSourceNode;
  env: GainNode;
  end: number;
}

const HEADROOM = 0.9;
/** SF2 initialAttenuation is applied at 0.4× as in EMU hardware and FluidSynth. */
const ATTEN_SCALE = 0.4;

/** SF2 concave transform (0 → 0, 1 → 1). */
function concave(x: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  return Math.min(1, (-20 / 96) * Math.log10((1 - x) * (1 - x)));
}

function makeImpulse(ctx: BaseAudioContext, seconds: number): AudioBuffer {
  const len = Math.floor(ctx.sampleRate * seconds);
  const buf = ctx.createBuffer(2, len, ctx.sampleRate);
  // Deterministic noise so offline renders are reproducible.
  let seed = 12345;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff) * 2 - 1;
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    for (let i = 0; i < len; i++) {
      const t = i / ctx.sampleRate;
      d[i] = rnd() * Math.pow(1 - i / len, 2.2) * Math.exp(-t * 1.6) * (t < 0.012 ? t / 0.012 : 1);
    }
  }
  return buf;
}

export class Synth {
  readonly ctx: BaseAudioContext;
  readonly master: GainNode;
  private reverbIn: GainNode;
  private reverbOut: GainNode;
  private buffers = new Map<string, AudioBuffer>();
  private voices = new Set<Voice>();
  private sf: SoundFont | null;

  constructor(ctx: BaseAudioContext, sf: SoundFont | null, destination?: AudioNode) {
    this.ctx = ctx;
    this.sf = sf;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -6;
    comp.knee.value = 6;
    comp.ratio.value = 4;
    comp.attack.value = 0.003;
    comp.release.value = 0.25;
    this.master = ctx.createGain();
    this.master.gain.value = 1;
    this.master.connect(comp);
    comp.connect(destination ?? ctx.destination);
    const conv = ctx.createConvolver();
    conv.buffer = makeImpulse(ctx, 2.4);
    this.reverbIn = ctx.createGain();
    this.reverbOut = ctx.createGain();
    this.reverbOut.gain.value = 0.55;
    this.reverbIn.connect(conv);
    conv.connect(this.reverbOut);
    this.reverbOut.connect(this.master);
  }

  setSoundFont(sf: SoundFont | null) {
    this.sf = sf;
    this.buffers.clear();
  }

  setReverb(level: number) {
    this.reverbOut.gain.value = level;
  }

  /** Creates a mixer channel (gain stage) feeding the master bus. */
  createChannel(): GainNode {
    const g = this.ctx.createGain();
    g.connect(this.master);
    const send = this.ctx.createGain();
    send.gain.value = 0.18;
    g.connect(send);
    send.connect(this.reverbIn);
    return g;
  }

  private bufferFor(r: Region): AudioBuffer {
    const key = `${r.start}:${r.end}:${r.sample.sampleRate}`;
    let b = this.buffers.get(key);
    if (!b) {
      const sf = this.sf!;
      const len = Math.max(1, r.end - r.start);
      b = this.ctx.createBuffer(1, len, Math.max(3000, Math.min(384000, r.sample.sampleRate)));
      const d = b.getChannelData(0);
      const src = sf.data;
      for (let i = 0; i < len; i++) d[i] = src[r.start + i] / 32768;
      this.buffers.set(key, b);
    }
    return b;
  }

  /** Schedules one note; returns the time at which it is completely silent. */
  playNote(n: NoteRequest): number {
    if (!this.sf) return this.playFallback(n);
    const regions = this.sf.regionsFor(n.program, n.key, n.vel);
    if (!regions.length) return this.playFallback(n);
    let silentAt = n.time;
    // Default SF2 velocity modulator: concave curve, 96 dB range.
    const velGain = n.vel >= 127 ? 1 : Math.pow(10, (-96 * concave(1 - n.vel / 127)) / 20);
    for (const r of regions) {
      const ctx = this.ctx;
      const src = ctx.createBufferSource();
      src.buffer = this.bufferFor(r);
      const cents = (n.key - r.rootKey) * r.scaleTuning + r.tuneCents;
      src.playbackRate.value = Math.pow(2, cents / 1200);
      if ((r.loopMode === 1 || r.loopMode === 3) && r.loopEnd > r.loopStart) {
        src.loop = true;
        src.loopStart = (r.loopStart - r.start) / src.buffer.sampleRate;
        src.loopEnd = (r.loopEnd - r.start) / src.buffer.sampleRate;
      }
      let node: AudioNode = src;
      const fcCents = r.filterFc - 2400 * (1 - n.vel / 127);
      if (fcCents < 13400) {
        const f = ctx.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = Math.min(ctx.sampleRate / 2 - 100, 8.176 * Math.pow(2, fcCents / 1200));
        f.Q.value = r.filterQ / 10;
        node.connect(f);
        node = f;
      }
      const env = ctx.createGain();
      node.connect(env);
      const pan = ctx.createStereoPanner();
      pan.pan.value = r.pan / 500;
      env.connect(pan);
      pan.connect(n.channel);
      const peak = HEADROOM * velGain * Math.pow(10, (-r.attenuationCb * ATTEN_SCALE) / 200);
      const g = env.gain;
      const t0 = n.time + r.delayEnv;
      const tA = t0 + Math.max(0.001, r.attackEnv);
      const tH = tA + r.holdEnv;
      const sustain = peak * Math.pow(10, -r.sustainCb / 200);
      const off = Math.max(n.time + 0.005, n.time + n.dur);
      g.setValueAtTime(0, n.time);
      g.setValueAtTime(0, t0);
      g.linearRampToValueAtTime(peak, tA);
      if (tH > tA) g.setValueAtTime(peak, tH);
      g.setTargetAtTime(sustain, tH, Math.max(0.001, r.decayEnv / 11.5));
      // Release: hold the envelope where it is at note-off and fade out.
      const anyG = g as AudioParam & { cancelAndHoldAtTime?: (t: number) => void };
      if (anyG.cancelAndHoldAtTime) anyG.cancelAndHoldAtTime(off);
      else g.cancelScheduledValues(off);
      const release = Math.max(0.03, Math.min(r.releaseEnv, 6));
      g.setTargetAtTime(0, off, release / 6);
      const end = off + release * 1.2 + 0.05;
      src.start(n.time);
      src.stop(end);
      const v: Voice = { src, env, end };
      this.voices.add(v);
      src.onended = () => {
        this.voices.delete(v);
        src.disconnect();
        pan.disconnect();
      };
      silentAt = Math.max(silentAt, end);
    }
    return silentAt;
  }

  /** Simple built-in piano-like tone used when no SoundFont is available. */
  private playFallback(n: NoteRequest): number {
    const ctx = this.ctx;
    const freq = 440 * Math.pow(2, (n.key - 69) / 12);
    const env = ctx.createGain();
    env.connect(n.channel);
    const peak = 0.18 * Math.pow(n.vel / 127, 1.6);
    const off = n.time + Math.max(0.02, n.dur);
    const decay = Math.max(0.4, 3.2 - (n.key - 40) * 0.04);
    env.gain.setValueAtTime(0, n.time);
    env.gain.linearRampToValueAtTime(peak, n.time + 0.004);
    env.gain.setTargetAtTime(0, n.time + 0.004, decay / 4);
    const anyG = env.gain as AudioParam & { cancelAndHoldAtTime?: (t: number) => void };
    if (anyG.cancelAndHoldAtTime) anyG.cancelAndHoldAtTime(off);
    env.gain.setTargetAtTime(0, off, 0.06);
    const end = off + 0.4;
    for (const [mult, type, amp] of [[1, 'triangle', 1], [2, 'sine', 0.35], [3, 'sine', 0.12]] as const) {
      const o = ctx.createOscillator();
      o.type = type;
      o.frequency.value = freq * mult;
      const g = ctx.createGain();
      g.gain.value = amp;
      o.connect(g);
      g.connect(env);
      o.start(n.time);
      o.stop(end);
      const v: Voice = { src: o, env, end };
      this.voices.add(v);
      o.onended = () => this.voices.delete(v);
    }
    return end;
  }

  /** Metronome click (accented on the downbeat). */
  click(time: number, accent: boolean, channel: AudioNode): void {
    const ctx = this.ctx;
    const o = ctx.createOscillator();
    o.type = 'square';
    o.frequency.value = accent ? 1760 : 1175;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0, time);
    g.gain.linearRampToValueAtTime(accent ? 0.35 : 0.22, time + 0.001);
    g.gain.exponentialRampToValueAtTime(0.0001, time + 0.05);
    o.connect(g);
    g.connect(channel);
    o.start(time);
    o.stop(time + 0.06);
  }

  /** Quickly fades out every sounding voice. */
  stopAll(): void {
    const now = this.ctx.currentTime;
    for (const v of this.voices) {
      try {
        v.env.gain.cancelScheduledValues(now);
        v.env.gain.setTargetAtTime(0, now, 0.02);
        v.src.stop(now + 0.12);
      } catch {
        /* already stopped */
      }
    }
    this.voices.clear();
  }
}
