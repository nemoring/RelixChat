/**
 * SoundFont 2 parser (RIFF "sfbk"). Produces presets whose zones are resolved
 * on demand into playable regions: sample data + the generators that the
 * NoteForge synthesizer implements (key/velocity ranges, tuning, root key,
 * loop points, volume envelope, attenuation, pan, low-pass filter, reverb send).
 *
 * Modulators other than the SF2 default velocity curve are not implemented.
 */

export interface SampleHeader {
  name: string;
  start: number;
  end: number;
  loopStart: number;
  loopEnd: number;
  sampleRate: number;
  originalPitch: number;
  pitchCorrection: number;
  sampleLink: number;
  sampleType: number;
}

type GenMap = Map<number, number>;

interface Zone {
  gens: GenMap;
  keyLo: number;
  keyHi: number;
  velLo: number;
  velHi: number;
}

interface Instrument {
  name: string;
  global: Zone | null;
  zones: (Zone & { sampleId: number })[];
}

export interface Preset {
  name: string;
  program: number;
  bank: number;
  global: Zone | null;
  zones: (Zone & { instrument: number })[];
}

/** A fully resolved region ready to be played. */
export interface Region {
  sample: SampleHeader;
  sampleIndex: number;
  /** Sample-frame offsets (relative to the start of the smpl chunk). */
  start: number;
  end: number;
  loopStart: number;
  loopEnd: number;
  loopMode: number;
  rootKey: number;
  /** Total tuning in cents (coarse*100 + fine + sample correction). */
  tuneCents: number;
  scaleTuning: number;
  attenuationCb: number;
  pan: number; // -500 … 500
  filterFc: number; // absolute cents
  filterQ: number; // cB
  reverbSend: number; // 0 … 1000
  delayEnv: number; // seconds
  attackEnv: number;
  holdEnv: number;
  decayEnv: number;
  sustainCb: number;
  releaseEnv: number;
  exclusiveClass: number;
}

export const GEN = {
  startAddrsOffset: 0,
  endAddrsOffset: 1,
  startloopAddrsOffset: 2,
  endloopAddrsOffset: 3,
  startAddrsCoarseOffset: 4,
  initialFilterFc: 8,
  initialFilterQ: 9,
  endAddrsCoarseOffset: 12,
  reverbEffectsSend: 16,
  pan: 17,
  delayVolEnv: 33,
  attackVolEnv: 34,
  holdVolEnv: 35,
  decayVolEnv: 36,
  sustainVolEnv: 37,
  releaseVolEnv: 38,
  keynumToVolEnvHold: 39,
  keynumToVolEnvDecay: 40,
  instrument: 41,
  keyRange: 43,
  velRange: 44,
  startloopAddrsCoarseOffset: 45,
  keynum: 46,
  velocity: 47,
  initialAttenuation: 48,
  endloopAddrsCoarseOffset: 50,
  coarseTune: 51,
  fineTune: 52,
  sampleID: 53,
  sampleModes: 54,
  scaleTuning: 56,
  exclusiveClass: 57,
  overridingRootKey: 58,
} as const;

const DEFAULTS: Record<number, number> = {
  [GEN.initialFilterFc]: 13500,
  [GEN.delayVolEnv]: -12000,
  [GEN.attackVolEnv]: -12000,
  [GEN.holdVolEnv]: -12000,
  [GEN.decayVolEnv]: -12000,
  [GEN.releaseVolEnv]: -12000,
  [GEN.scaleTuning]: 100,
  [GEN.overridingRootKey]: -1,
  [GEN.keynum]: -1,
  [GEN.velocity]: -1,
};

/** Generators that must not be summed from preset level (they are ranges / indices). */
const NON_ADDITIVE = new Set<number>([GEN.keyRange, GEN.velRange, GEN.instrument, GEN.sampleID, GEN.sampleModes, GEN.exclusiveClass, GEN.overridingRootKey, GEN.keynum, GEN.velocity, 4, 0, 1, 2, 3, 12, 45, 50]);

export class SoundFont {
  readonly presets: Preset[] = [];
  readonly instruments: Instrument[] = [];
  readonly samples: SampleHeader[] = [];
  /** 16-bit sample data (the whole smpl chunk). */
  readonly data: Int16Array;
  readonly name: string;
  private regionCache = new Map<string, Region[]>();

  constructor(buffer: ArrayBuffer) {
    const view = new DataView(buffer);
    const tag = (o: number) => String.fromCharCode(view.getUint8(o), view.getUint8(o + 1), view.getUint8(o + 2), view.getUint8(o + 3));
    if (tag(0) !== 'RIFF' || tag(8) !== 'sfbk') throw new Error('Файл не является SoundFont 2 (.sf2)');
    let smplOffset = -1;
    let smplLength = 0;
    let name = 'SoundFont';
    const chunks = new Map<string, { offset: number; size: number }>();
    const walk = (start: number, end: number) => {
      let o = start;
      while (o + 8 <= end) {
        const id = tag(o);
        const size = view.getUint32(o + 4, true);
        if (id === 'LIST') {
          walk(o + 12, o + 8 + size);
        } else {
          chunks.set(id, { offset: o + 8, size });
          if (id === 'smpl') {
            smplOffset = o + 8;
            smplLength = size;
          }
          if (id === 'INAM') name = readStr(view, o + 8, size);
        }
        o += 8 + size + (size & 1);
      }
    };
    walk(12, Math.min(buffer.byteLength, 8 + view.getUint32(4, true)));
    if (smplOffset < 0) throw new Error('В SoundFont нет сэмплов');
    // Copy to an aligned buffer (the chunk may start at an odd offset).
    this.data = new Int16Array(buffer.slice(smplOffset, smplOffset + (smplLength & ~1)));
    this.name = name;

    const need = (id: string) => {
      const c = chunks.get(id);
      if (!c) throw new Error(`Повреждённый SoundFont: нет блока ${id}`);
      return c;
    };
    const phdr = need('phdr');
    const pbag = need('pbag');
    const pgen = need('pgen');
    const inst = need('inst');
    const ibag = need('ibag');
    const igen = need('igen');
    const shdr = need('shdr');

    const readGens = (c: { offset: number }, from: number, to: number): GenMap => {
      const m: GenMap = new Map();
      for (let i = from; i < to; i++) {
        const o = c.offset + i * 4;
        const oper = view.getUint16(o, true);
        if (oper === GEN.keyRange || oper === GEN.velRange) m.set(oper, view.getUint8(o + 2) | (view.getUint8(o + 3) << 8));
        else if (oper === GEN.instrument || oper === GEN.sampleID || oper === GEN.sampleModes) m.set(oper, view.getUint16(o + 2, true));
        else m.set(oper, view.getInt16(o + 2, true));
      }
      return m;
    };
    const toZone = (gens: GenMap): Zone => {
      const kr = gens.get(GEN.keyRange);
      const vr = gens.get(GEN.velRange);
      return { gens, keyLo: kr !== undefined ? kr & 0xff : 0, keyHi: kr !== undefined ? kr >> 8 : 127, velLo: vr !== undefined ? vr & 0xff : 0, velHi: vr !== undefined ? vr >> 8 : 127 };
    };

    // Samples.
    const nSamples = Math.floor(shdr.size / 46) - 1;
    for (let i = 0; i < nSamples; i++) {
      const o = shdr.offset + i * 46;
      this.samples.push({
        name: readStr(view, o, 20),
        start: view.getUint32(o + 20, true),
        end: view.getUint32(o + 24, true),
        loopStart: view.getUint32(o + 28, true),
        loopEnd: view.getUint32(o + 32, true),
        sampleRate: view.getUint32(o + 36, true),
        originalPitch: view.getUint8(o + 40),
        pitchCorrection: view.getInt8(o + 41),
        sampleLink: view.getUint16(o + 42, true),
        sampleType: view.getUint16(o + 44, true),
      });
    }

    // Instruments.
    const nInst = Math.floor(inst.size / 22) - 1;
    for (let i = 0; i < nInst; i++) {
      const o = inst.offset + i * 22;
      const bagFrom = view.getUint16(o + 20, true);
      const bagTo = view.getUint16(o + 22 + 20, true);
      const zones: Instrument['zones'] = [];
      let global: Zone | null = null;
      for (let b = bagFrom; b < bagTo; b++) {
        const g0 = view.getUint16(ibag.offset + b * 4, true);
        const g1 = view.getUint16(ibag.offset + (b + 1) * 4, true);
        const gens = readGens(igen, g0, g1);
        const sid = gens.get(GEN.sampleID);
        if (sid === undefined) {
          if (b === bagFrom) global = toZone(gens);
          continue;
        }
        zones.push({ ...toZone(gens), sampleId: sid });
      }
      this.instruments.push({ name: readStr(view, o, 20), global, zones });
    }

    // Presets.
    const nPresets = Math.floor(phdr.size / 38) - 1;
    for (let i = 0; i < nPresets; i++) {
      const o = phdr.offset + i * 38;
      const bagFrom = view.getUint16(o + 24, true);
      const bagTo = view.getUint16(o + 38 + 24, true);
      const zones: Preset['zones'] = [];
      let global: Zone | null = null;
      for (let b = bagFrom; b < bagTo; b++) {
        const g0 = view.getUint16(pbag.offset + b * 4, true);
        const g1 = view.getUint16(pbag.offset + (b + 1) * 4, true);
        const gens = readGens(pgen, g0, g1);
        const instIdx = gens.get(GEN.instrument);
        if (instIdx === undefined) {
          if (b === bagFrom) global = toZone(gens);
          continue;
        }
        zones.push({ ...toZone(gens), instrument: instIdx });
      }
      this.presets.push({ name: readStr(view, o, 20), program: view.getUint16(o + 20, true), bank: view.getUint16(o + 22, true), global, zones });
    }
  }

  findPreset(program: number, bank = 0): Preset | null {
    return (
      this.presets.find((p) => p.program === program && p.bank === bank) ??
      this.presets.find((p) => p.program === program && p.bank !== 128) ??
      this.presets.find((p) => p.bank !== 128) ??
      null
    );
  }

  /** All regions of a preset that sound for (key, velocity). */
  regionsFor(program: number, key: number, vel: number, bank = 0): Region[] {
    const cacheKey = `${bank}:${program}:${key}:${vel}`;
    const cached = this.regionCache.get(cacheKey);
    if (cached) return cached;
    const preset = this.findPreset(program, bank);
    const out: Region[] = [];
    if (preset) {
      for (const pz of preset.zones) {
        if (!inRange(pz, key, vel) || (preset.global && !inRange(preset.global, key, vel))) continue;
        const instr = this.instruments[pz.instrument];
        if (!instr) continue;
        for (const iz of instr.zones) {
          if (!inRange(iz, key, vel) || (instr.global && !inRange(instr.global, key, vel))) continue;
          const r = this.resolve(preset, pz, instr, iz, key);
          if (r) out.push(r);
        }
      }
    }
    this.regionCache.set(cacheKey, out);
    return out;
  }

  private resolve(preset: Preset, pz: Zone, instr: Instrument, iz: Zone & { sampleId: number }, key: number): Region | null {
    const sample = this.samples[iz.sampleId];
    if (!sample || sample.sampleType & 0x8000) return null; // ROM samples unsupported
    const ig = (id: number) => iz.gens.get(id) ?? instr.global?.gens.get(id) ?? DEFAULTS[id] ?? 0;
    const pg = (id: number) => (NON_ADDITIVE.has(id) ? 0 : pz.gens.get(id) ?? preset.global?.gens.get(id) ?? 0);
    const g = (id: number) => ig(id) + pg(id);
    const tc = (id: number) => Math.min(100, Math.pow(2, g(id) / 1200));
    const start = sample.start + ig(GEN.startAddrsOffset) + 32768 * ig(GEN.startAddrsCoarseOffset);
    const end = sample.end + ig(GEN.endAddrsOffset) + 32768 * ig(GEN.endAddrsCoarseOffset);
    const loopStart = sample.loopStart + ig(GEN.startloopAddrsOffset) + 32768 * ig(GEN.startloopAddrsCoarseOffset);
    const loopEnd = sample.loopEnd + ig(GEN.endloopAddrsOffset) + 32768 * ig(GEN.endloopAddrsCoarseOffset);
    const rootOverride = ig(GEN.overridingRootKey);
    const rootKey = rootOverride >= 0 ? rootOverride : sample.originalPitch;
    const holdKey = g(GEN.keynumToVolEnvHold);
    const decayKey = g(GEN.keynumToVolEnvDecay);
    return {
      sample,
      sampleIndex: iz.sampleId,
      start: Math.max(0, start),
      end: Math.min(this.data.length, end),
      loopStart,
      loopEnd,
      loopMode: ig(GEN.sampleModes) & 3,
      rootKey,
      tuneCents: g(GEN.coarseTune) * 100 + g(GEN.fineTune) + sample.pitchCorrection,
      scaleTuning: g(GEN.scaleTuning),
      attenuationCb: Math.max(0, g(GEN.initialAttenuation)),
      pan: Math.max(-500, Math.min(500, g(GEN.pan))),
      filterFc: g(GEN.initialFilterFc),
      filterQ: g(GEN.initialFilterQ),
      reverbSend: Math.max(0, Math.min(1000, g(GEN.reverbEffectsSend))),
      delayEnv: tc(GEN.delayVolEnv),
      attackEnv: tc(GEN.attackVolEnv),
      holdEnv: Math.min(100, Math.pow(2, (g(GEN.holdVolEnv) + holdKey * (60 - key)) / 1200)),
      decayEnv: Math.min(100, Math.pow(2, (g(GEN.decayVolEnv) + decayKey * (60 - key)) / 1200)),
      sustainCb: Math.max(0, Math.min(1440, g(GEN.sustainVolEnv))),
      releaseEnv: tc(GEN.releaseVolEnv),
      exclusiveClass: ig(GEN.exclusiveClass),
    };
  }
}

function inRange(z: Zone, key: number, vel: number): boolean {
  return key >= z.keyLo && key <= z.keyHi && vel >= z.velLo && vel <= z.velHi;
}

function readStr(view: DataView, o: number, n: number): string {
  let s = '';
  for (let i = 0; i < n; i++) {
    const c = view.getUint8(o + i);
    if (c === 0) break;
    s += String.fromCharCode(c);
  }
  return s.trim();
}
