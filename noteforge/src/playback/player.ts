/**
 * Realtime player: look-ahead scheduler over a Performance, with speed,
 * looping, metronome, per-staff mixer and optional external MIDI output.
 * Position updates are published through a lightweight store so the UI can
 * follow the music without re-rendering the whole app each frame.
 */
import { useSyncExternalStore } from 'react';
import { SoundFont } from './sf2';
import { Synth } from './synth';
import { perform, positionAt, timeOf, type Performance, type PNote, type PerformOptions } from './perform';
import type { Score } from '../model/types';

export type PlayStatus = 'stopped' | 'playing' | 'paused';

export interface MixerChannel {
  id: string;
  label: string;
  volume: number; // 0 … 1.5
  mute: boolean;
  solo: boolean;
}

export interface PlayerState {
  status: PlayStatus;
  /** Current position in performance seconds. */
  position: number;
  duration: number;
  measure: number;
  speed: number;
  loop: boolean;
  metronome: boolean;
  /** Mixer: one channel per staff plus melody/accompaniment roles. */
  channels: MixerChannel[];
  soundfont: { status: 'none' | 'loading' | 'ready' | 'error'; name: string; error?: string };
  midiOutputs: { id: string; name: string }[];
  midiOutputId: string | null;
  reverb: number;
  previewNotes: boolean;
}

type Listener = () => void;

const LOOKAHEAD = 0.3;
const TICK_MS = 25;

class Player {
  state: PlayerState = {
    status: 'stopped',
    position: 0,
    duration: 0,
    measure: 0,
    speed: 1,
    loop: false,
    metronome: false,
    channels: [
      { id: 'staff-0', label: 'Правая рука', volume: 1, mute: false, solo: false },
      { id: 'staff-1', label: 'Левая рука', volume: 1, mute: false, solo: false },
      { id: 'role-melody', label: 'Мелодия', volume: 1, mute: false, solo: false },
      { id: 'role-accomp', label: 'Сопровождение', volume: 1, mute: false, solo: false },
    ],
    soundfont: { status: 'none', name: '' },
    midiOutputs: [],
    midiOutputId: null,
    reverb: 0.55,
    previewNotes: true,
  };
  private listeners = new Set<Listener>();
  private frameListeners = new Set<(sec: number, playing: Set<string>) => void>();
  ctx: AudioContext | null = null;
  synth: Synth | null = null;
  soundFont: SoundFont | null = null;
  private sfPromise: Promise<void> | null = null;
  private perf: Performance | null = null;
  private perfScore: Score | null = null;
  private perfOpts: PerformOptions = {};
  private channelNodes = new Map<string, GainNode>();
  private metroNode: GainNode | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private raf = 0;
  private lastNotified = -1;
  private anchorAudio = 0;
  private anchorPerf = 0;
  private noteIdx = 0;
  private beatIdx = 0;
  private loopStart = 0;
  private loopEnd = 0;
  private midiAccess: MIDIAccess | null = null;
  /** Measure range of the current "play selection" (kept for resume after pause). */
  lastRange: { from: number; to: number } | undefined;
  /** Provides the score and selection-based start position (set by the app). */
  getScore: () => Score = () => {
    throw new Error('Player not connected');
  };
  /** Role of a note for the melody/accompaniment mixer (set by the app). */
  roleOf: (eventId: string) => 'melody' | 'accomp' = () => 'accomp';

  // ── store ──
  subscribe = (l: Listener) => {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  };
  private set(p: Partial<PlayerState>) {
    this.state = { ...this.state, ...p };
    this.listeners.forEach((l) => l());
  }
  onFrame(cb: (sec: number, playing: Set<string>) => void): () => void {
    this.frameListeners.add(cb);
    return () => this.frameListeners.delete(cb);
  }

  // ── audio setup ──
  private ensureContext(): AudioContext {
    if (!this.ctx) {
      this.ctx = new AudioContext({ latencyHint: 'interactive' });
      this.synth = new Synth(this.ctx, this.soundFont);
      this.synth.setReverb(this.state.reverb);
      this.metroNode = this.ctx.createGain();
      this.metroNode.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') void this.ctx.resume();
    return this.ctx;
  }

  /** Loads the bundled GeneralUser GS bank (or another .sf2 given as bytes). */
  loadSoundFont(source?: { name: string; data: ArrayBuffer }): Promise<void> {
    if (!source && this.sfPromise) return this.sfPromise;
    this.set({ soundfont: { status: 'loading', name: source?.name ?? 'GeneralUser GS' } });
    const p = (async () => {
      try {
        let data = source?.data;
        if (!data) {
          const res = await fetch(new URL('soundfonts/GeneralUser-GS.sf2', document.baseURI).toString());
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          data = await res.arrayBuffer();
        }
        const sf = new SoundFont(data);
        this.soundFont = sf;
        this.synth?.setSoundFont(sf);
        this.set({ soundfont: { status: 'ready', name: source?.name ?? sf.name } });
      } catch (e) {
        this.set({ soundfont: { status: 'error', name: source?.name ?? 'GeneralUser GS', error: (e as Error).message } });
      }
    })();
    if (!source) this.sfPromise = p;
    return p;
  }

  private channel(id: string): GainNode {
    let g = this.channelNodes.get(id);
    if (!g) {
      g = this.synth!.createChannel();
      this.channelNodes.set(id, g);
      this.applyMixer();
    }
    return g;
  }

  /** Effective gain of each (staff, role) combination from the mixer settings. */
  gainForNote(staff: number, role: 'melody' | 'accomp'): number {
    const chs = this.state.channels;
    const st = chs.find((c) => c.id === `staff-${staff}`);
    const rl = chs.find((c) => c.id === `role-${role}`);
    const staffSolo = chs.some((c) => c.id.startsWith('staff-') && c.solo);
    const roleSolo = chs.some((c) => c.id.startsWith('role-') && c.solo);
    if (st && (st.mute || (staffSolo && !st.solo))) return 0;
    if (rl && (rl.mute || (roleSolo && !rl.solo))) return 0;
    return (st?.volume ?? 1) * (rl?.volume ?? 1);
  }

  private applyMixer() {
    for (const [id, node] of this.channelNodes) {
      const [, staff, role] = /^ch-(\d+)-(\w+)$/.exec(id) ?? [];
      if (staff === undefined) continue;
      node.gain.setTargetAtTime(this.gainForNote(Number(staff), role as 'melody' | 'accomp'), this.ctx!.currentTime, 0.015);
    }
  }

  setChannel(id: string, patch: Partial<MixerChannel>) {
    this.set({ channels: this.state.channels.map((c) => (c.id === id ? { ...c, ...patch } : c)) });
    if (this.ctx) this.applyMixer();
  }

  setReverb(level: number) {
    this.set({ reverb: level });
    this.synth?.setReverb(level);
  }

  // ── transport ──
  private build(opts: PerformOptions) {
    const score = this.getScore();
    if (!this.perf || this.perfScore !== score || JSON.stringify(opts) !== JSON.stringify(this.perfOpts)) {
      this.perf = perform(score, opts);
      this.perfScore = score;
      this.perfOpts = opts;
    }
    return this.perf;
  }

  /** Builds (or rebuilds) the performance and returns it — also used by exports. */
  performance(opts: PerformOptions = {}): Performance {
    return perform(this.getScore(), opts);
  }

  async play(from?: { measure: number; time?: number }, range?: { from: number; to: number }) {
    const ctx = this.ensureContext();
    await this.loadSoundFont();
    if (this.state.status === 'playing') this.halt();
    const opts: PerformOptions = range ? { range } : {};
    const resume = this.state.status === 'paused' && !from && JSON.stringify(opts) === JSON.stringify(this.perfOpts);
    const perf = this.build(opts);
    let start = resume ? this.state.position : 0;
    if (from) start = timeOf(perf, from.measure, from.time ?? 0);
    this.loopStart = 0;
    this.loopEnd = perf.duration;
    this.anchorAudio = ctx.currentTime + 0.08;
    this.anchorPerf = start;
    this.noteIdx = lowerBound(perf.notes, start);
    this.beatIdx = perf.beats.findIndex((b) => b.time >= start - 1e-6);
    if (this.beatIdx < 0) this.beatIdx = perf.beats.length;
    this.set({ status: 'playing', duration: perf.duration, position: start });
    this.timer = setInterval(() => this.schedule(), TICK_MS);
    this.schedule();
    const frame = () => {
      this.frame();
      if (this.state.status === 'playing') this.raf = requestAnimationFrame(frame);
    };
    this.raf = requestAnimationFrame(frame);
  }

  private perfTime(audio: number) {
    return this.anchorPerf + (audio - this.anchorAudio) * this.state.speed;
  }
  private audioTime(perfSec: number) {
    return this.anchorAudio + (perfSec - this.anchorPerf) / this.state.speed;
  }

  private schedule() {
    const perf = this.perf;
    const ctx = this.ctx;
    if (!perf || !ctx || !this.synth) return;
    const horizon = this.perfTime(ctx.currentTime + LOOKAHEAD);
    for (let guard = 0; guard < 4; guard++) {
      while (this.noteIdx < perf.notes.length && perf.notes[this.noteIdx].start < Math.min(horizon, this.loopEnd)) {
        const n = perf.notes[this.noteIdx++];
        this.startNote(n);
      }
      if (this.state.metronome) {
        while (this.beatIdx < perf.beats.length && perf.beats[this.beatIdx].time < Math.min(horizon, this.loopEnd)) {
          const b = perf.beats[this.beatIdx++];
          this.synth.click(Math.max(ctx.currentTime, this.audioTime(b.time)), b.accent, this.metroNode!);
        }
      } else {
        while (this.beatIdx < perf.beats.length && perf.beats[this.beatIdx].time < horizon) this.beatIdx++;
      }
      if (horizon < this.loopEnd) break;
      if (!this.state.loop) {
        if (this.perfTime(ctx.currentTime) >= this.loopEnd + 0.05) this.finish();
        break;
      }
      // Seamless loop: the next cycle starts exactly where this one ends.
      this.anchorAudio = this.audioTime(this.loopEnd);
      this.anchorPerf = this.loopStart;
      this.noteIdx = lowerBound(perf.notes, this.loopStart);
      this.beatIdx = perf.beats.findIndex((b) => b.time >= this.loopStart - 1e-6);
    }
  }

  private startNote(n: PNote) {
    const role = this.roleOf(n.eventId);
    const t = Math.max(this.ctx!.currentTime, this.audioTime(n.start));
    const dur = (n.end - n.start) / this.state.speed;
    const out = this.state.midiOutputId ? this.midiAccess?.outputs.get(this.state.midiOutputId) : undefined;
    if (out) {
      const gain = this.gainForNote(n.staff, role);
      if (gain > 0) {
        const ch = n.staff & 0x0f;
        const toMs = (audio: number) => performance.now() + (audio - this.ctx!.currentTime) * 1000;
        out.send([0xc0 | ch, n.program], toMs(t) - 1);
        out.send([0x90 | ch, n.key, Math.min(127, Math.round(n.vel * Math.min(1.5, gain)))], toMs(t));
        out.send([0x80 | ch, n.key, 0], toMs(t + dur));
      }
    } else {
      this.synth!.playNote({ time: t, dur, key: n.key, vel: n.vel, program: n.program, channel: this.channel(`ch-${n.staff}-${role}`) });
    }
  }

  private frame() {
    const perf = this.perf;
    if (!perf || !this.ctx) return;
    let sec = this.perfTime(this.ctx.currentTime);
    if (this.state.loop && sec >= this.loopEnd) sec = this.loopStart + ((sec - this.loopStart) % Math.max(0.001, this.loopEnd - this.loopStart));
    const playing = new Set<string>();
    // Notes sounding now: scan a window around the current note index.
    const i0 = lowerBound(perf.notes, sec - 30);
    for (let i = i0; i < perf.notes.length && perf.notes[i].start <= sec; i++) {
      const n = perf.notes[i];
      if (n.end > sec) for (const id of n.noteIds) playing.add(id);
    }
    const pos = positionAt(perf, sec);
    if (pos.measure !== this.state.measure || Math.abs(sec - this.lastNotified) >= 0.25) {
      this.lastNotified = sec;
      this.set({ position: sec, measure: pos.measure });
    }
    this.frameListeners.forEach((cb) => cb(sec, playing));
  }

  private halt() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    cancelAnimationFrame(this.raf);
    this.synth?.stopAll();
    if (this.state.midiOutputId) {
      const out = this.midiAccess?.outputs.get(this.state.midiOutputId);
      for (let ch = 0; ch < 16; ch++) out?.send([0xb0 | ch, 123, 0]);
    }
  }

  private finish() {
    this.halt();
    this.set({ status: 'stopped', position: 0 });
    this.frameListeners.forEach((cb) => cb(-1, new Set()));
  }

  pause() {
    if (this.state.status !== 'playing' || !this.ctx) return;
    const pos = this.perfTime(this.ctx.currentTime);
    this.halt();
    this.set({ status: 'paused', position: Math.max(0, pos) });
    this.frameListeners.forEach((cb) => cb(pos, new Set()));
  }

  stop() {
    this.halt();
    this.set({ status: 'stopped', position: 0 });
    this.frameListeners.forEach((cb) => cb(-1, new Set()));
  }

  setSpeed(speed: number) {
    const s = Math.max(0.25, Math.min(2, Math.round(speed * 100) / 100));
    if (this.ctx && this.state.status === 'playing') {
      // Re-anchor so the change applies from now on.
      const now = this.ctx.currentTime;
      this.anchorPerf = this.perfTime(now);
      this.anchorAudio = now;
    }
    this.set({ speed: s });
  }

  setLoop(loop: boolean) {
    this.set({ loop });
  }
  setMetronome(on: boolean) {
    this.set({ metronome: on });
  }
  setPreview(on: boolean) {
    this.set({ previewNotes: on });
  }

  /** Short audition of pitches (note entry, keyboard). */
  preview(keys: number[], program = 0, dur = 0.6, vel = 85) {
    if (!this.state.previewNotes) return;
    const ctx = this.ensureContext();
    void this.loadSoundFont().then(() => {
      for (const key of keys) this.synth!.playNote({ time: ctx.currentTime + 0.01, dur, key, vel, program, channel: this.channel('ch-0-accomp') });
    });
  }

  // ── MIDI devices ──
  async refreshMidi(): Promise<void> {
    try {
      if (!navigator.requestMIDIAccess) return;
      this.midiAccess = await navigator.requestMIDIAccess({ sysex: false });
      const list = () => this.set({ midiOutputs: [...this.midiAccess!.outputs.values()].map((o) => ({ id: o.id, name: o.name ?? o.id })) });
      list();
      this.midiAccess.onstatechange = list;
    } catch {
      /* MIDI not available */
    }
  }
  get midi(): MIDIAccess | null {
    return this.midiAccess;
  }
  setMidiOutput(id: string | null) {
    this.set({ midiOutputId: id });
  }

  /** The performance currently being played (for the score cursor). */
  current(): Performance | null {
    return this.perf;
  }

  /** Invalidates the cached performance (score changed). */
  invalidate() {
    this.perf = null;
  }
}

function lowerBound(notes: PNote[], sec: number): number {
  let lo = 0;
  let hi = notes.length;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (notes[mid].start < sec - 1e-6) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

export const player = new Player();

export function usePlayer<T>(sel: (s: PlayerState) => T): T {
  return useSyncExternalStore(player.subscribe, () => sel(player.state), () => sel(player.state));
}
