import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import { createPianoScore } from '../src/model/factory';
import { writeAt, setTimeSig } from '../src/model/edit';
import { frac, ZERO } from '../src/model/fraction';
import { perform, positionAt, timeOf, scoreDuration, PPQ } from '../src/playback/perform';
import { performanceToMidi } from '../src/playback/midifile';
import { SoundFont } from '../src/playback/sf2';
import { wavHeader } from '../src/playback/wav';
import { edit } from './helpers';

function song() {
  return edit(createPianoScore({ measures: 3, bpm: 120 }), (d) => {
    writeAt(d, 0, 0, 0, ZERO, frac(1, 4), { type: 'chord', notes: [{ step: 'C', octave: 5, alter: 0 }] });
    writeAt(d, 0, 0, 0, frac(1, 4), frac(1, 4), { type: 'chord', notes: [{ step: 'B', octave: 4, alter: 0 }] });
    // Tied across the barline: one sounding note of 3 beats.
    writeAt(d, 0, 0, 0, frac(3, 4), frac(3, 4), { type: 'chord', notes: [{ step: 'E', octave: 5, alter: 0 }] });
    writeAt(d, 1, 0, 0, frac(1, 2), frac(1, 4), { type: 'chord', notes: [{ step: 'A', octave: 4, alter: 0 }] });
    writeAt(d, 1, 0, 0, frac(3, 4), frac(1, 4), { type: 'chord', notes: [{ step: 'G', octave: 4, alter: 0 }] });
  });
}

describe('performance model', () => {
  it('times every note from the score (120 bpm: a quarter = 0.5 s)', () => {
    const p = perform(song());
    const keys = p.notes.map((n) => [n.key, n.start, Math.round((n.end - n.start) * 1000) / 1000, n.staff]);
    // Notes sound 97 % of their value (detached legato); a tie chain sounds as one note.
    expect(keys).toEqual([
      [72, 0, 0.485, 0],
      [71, 0.5, 0.485, 0],
      [69, 1, 0.485, 1],
      [67, 1.5, 0.485, 1],
      [76, 1.5, 1.47, 0],
    ]);
    expect(p.notes[4].noteIds.length).toBe(2); // tie chain spans two model notes
    expect(p.duration).toBeCloseTo(6);
    expect(scoreDuration(song())).toBeCloseTo(6);
    expect(p.beats.length).toBe(12);
    expect(p.beats.filter((b) => b.accent).length).toBe(3);
  });

  it('maps time to positions and back', () => {
    const p = perform(song());
    expect(timeOf(p, 1, 0.5)).toBeCloseTo(3);
    const pos = positionAt(p, 3.25);
    expect(pos.measure).toBe(1);
    expect(pos.time).toBeCloseTo(0.625);
  });

  it('follows meter changes', () => {
    const s = edit(song(), (d) => setTimeSig(d, 1, { count: 6, unit: 8 }));
    const p = perform(s);
    expect(p.measures[1].endTick - p.measures[1].startTick).toBe(PPQ * 3);
    // 6/8 beats are dotted quarters: two per bar.
    expect(p.beats.filter((b) => b.tick >= p.measures[1].startTick && b.tick < p.measures[1].endTick).length).toBe(2);
  });

  it('plays a measure range on its own', () => {
    const p = perform(song(), { range: { from: 1, to: 2 } });
    expect(p.measures.map((m) => m.measure)).toEqual([1, 2]);
    expect(p.notes.length).toBe(1);
    expect(p.notes[0].start).toBe(0);
  });
});

describe('MIDI export', () => {
  it('writes a valid type-1 file with all notes', () => {
    const s = song();
    const bytes = performanceToMidi(s, perform(s));
    const txt = String.fromCharCode(...bytes.slice(0, 4));
    expect(txt).toBe('MThd');
    expect(bytes[9]).toBe(1); // format 1
    expect((bytes[10] << 8) | bytes[11]).toBe(3); // conductor + 2 staves
    expect((bytes[12] << 8) | bytes[13]).toBe(PPQ);
    // Count note-on events with velocity > 0.
    let noteOns = 0;
    for (let i = 14; i < bytes.length - 2; i++) if ((bytes[i] & 0xf0) === 0x90 && bytes[i + 1] < 128 && bytes[i + 2] > 0 && bytes[i + 2] < 128) noteOns++;
    expect(noteOns).toBeGreaterThanOrEqual(5);
  });
});

describe('SoundFont', () => {
  it('parses the bundled GeneralUser GS bank and finds piano regions', () => {
    const buf = fs.readFileSync('public/soundfonts/GeneralUser-GS.sf2');
    const sf = new SoundFont(new Uint8Array(buf).buffer);
    expect(sf.presets.length).toBeGreaterThan(100);
    expect(sf.findPreset(0)?.name).toMatch(/Piano/);
    for (const key of [21, 60, 108]) {
      const r = sf.regionsFor(0, key, 90);
      expect(r.length).toBeGreaterThan(0);
      expect(r[0].end).toBeGreaterThan(r[0].start);
    }
  });

  it('rejects files that are not SoundFonts', () => {
    expect(() => new SoundFont(new ArrayBuffer(64))).toThrow();
  });
});

describe('WAV', () => {
  it('writes a canonical 16-bit stereo header', () => {
    const h = wavHeader(44100, 44100);
    const v = new DataView(h.buffer);
    expect(String.fromCharCode(...h.slice(0, 4))).toBe('RIFF');
    expect(v.getUint32(40, true)).toBe(44100 * 4);
    expect(v.getUint16(22, true)).toBe(2);
  });
});
