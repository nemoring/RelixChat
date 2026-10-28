// Debug helper: builds a sample score through the editing API and writes MEI + SVG pages.
// Usage: npx vite-node scripts/render-sample.ts <outDir>
import fs from 'node:fs';
import path from 'node:path';
import { produce } from 'immer';
import { createPianoScore } from '../src/model/factory';
import * as E from '../src/model/edit';
import { frac, ZERO } from '../src/model/fraction';
import { scoreToMei } from '../src/engrave/mei';
import { getStaff } from '../src/model/query';
import type { ChordEvent, Step } from '../src/model/types';
import createVerovioModule from 'verovio/wasm';
import { VerovioToolkit } from 'verovio/esm';

const outDir = process.argv[2] ?? '.';
const N = (step: Step, octave: number, alter = 0) => ({ step, octave, alter });
let score = createPianoScore({ title: 'Этюд', composer: 'NoteForge', measures: 8 });
score = produce(score, (d) => {
  d.meta.subtitle = 'все элементы этапа 3';
  const q = frac(1, 4);
  const line = d.lines[0].id;
  // m1: melody handed from RH (C5 → B4) to LH (A4 → G4), tagged as one melody line.
  const a = E.writeAt(d, 0, 0, 0, ZERO, q, { type: 'chord', notes: [N('C', 5)], attrs: { line, dynamic: 'p' } });
  E.writeAt(d, 0, 0, 0, q, q, { type: 'chord', notes: [N('B', 4)], attrs: { line } });
  E.writeAt(d, 1, 0, 0, frac(1, 2), q, { type: 'chord', notes: [N('A', 4)], attrs: { line, staffShift: -1 } });
  const e = E.writeAt(d, 1, 0, 0, frac(3, 4), q, { type: 'chord', notes: [N('G', 4)], attrs: { line, staffShift: -1 } });
  E.addSpanner(d, 'slur', a.firstId, e.firstId);
  E.writeAt(d, 1, 0, 0, ZERO, frac(1, 2), { type: 'chord', notes: [N('C', 3), N('G', 3)] });
  // m2: triplet, grace note, articulations, ornaments.
  const t = E.createTuplet(d, 0, 1, 0, ZERO, frac(1, 4), 3) as { id: string };
  E.writeAt(d, 0, 1, 0, ZERO, frac(1, 8), { type: 'chord', notes: [N('D', 5)] });
  E.writeAt(d, 0, 1, 0, frac(1, 12), frac(1, 8), { type: 'chord', notes: [N('E', 5)] });
  E.writeAt(d, 0, 1, 0, frac(2, 12), frac(1, 8), { type: 'chord', notes: [N('F', 5, 1)] });
  void t;
  const g = E.writeAt(d, 0, 1, 0, frac(1, 4), q, { type: 'chord', notes: [N('G', 5)], attrs: { artics: ['staccato', 'accent'] } });
  E.addGrace(d, 0, 1, 0, g.firstId, 'acciaccatura');
  E.writeAt(d, 0, 1, 0, frac(1, 2), q, { type: 'chord', notes: [N('A', 5)], attrs: { ornament: 'trill', dynamic: 'f' } });
  E.writeAt(d, 0, 1, 0, frac(3, 4), q, { type: 'chord', notes: [N('B', 5)], attrs: { ornament: 'mordent', fermata: true } });
  const lh1 = E.writeAt(d, 1, 1, 0, ZERO, frac(1, 1), { type: 'chord', notes: [N('C', 3)] });
  E.addSpanner(d, 'pedal', lh1.firstId, lh1.firstId);
  // m3–4: hairpins, 8va, quintuplet.
  const h1 = E.writeAt(d, 0, 2, 0, ZERO, frac(1, 2), { type: 'chord', notes: [N('C', 6)] });
  const h2 = E.writeAt(d, 0, 2, 0, frac(1, 2), frac(1, 2), { type: 'chord', notes: [N('E', 6)] });
  E.addSpanner(d, 'cresc', h1.firstId, h2.firstId);
  E.addSpanner(d, 'ottava', h1.firstId, h2.firstId, 8);
  E.createTuplet(d, 0, 3, 0, ZERO, frac(1, 4), 5);
  for (let i = 0; i < 5; i++) E.writeAt(d, 0, 3, 0, frac(i, 20), frac(1, 16), { type: 'chord', notes: [N((['C', 'D', 'E', 'F', 'G'] as Step[])[i], 5)] });
  // Repeats, volta, tempo change, clef change, D.C. al Fine.
  E.setRepeatStart(d, 2, true);
  E.setRepeatEnd(d, 4, 2);
  E.setVolta(d, 4, 4, [1]);
  E.setVolta(d, 5, 5, [2]);
  E.setMeasureTempo(d, 5, { bpm: 72, beatUnit: 4, beatDots: 0, text: 'Adagio' });
  E.setClef(d, 1, 'treble', 6);
  E.setMarker(d, 3, 'fine');
  E.setJump(d, 7, 'DCalFine');
  const m7 = getStaff(d, 1).measures[6].voices[0][0];
  void (m7 as ChordEvent);
  E.writeAt(d, 1, 6, 0, ZERO, frac(1, 1), { type: 'chord', notes: [N('E', 4), N('G', 4)] });
});
const { mei } = scoreToMei(score);
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'sample.mei'), mei);
const tk = new VerovioToolkit(await createVerovioModule());
tk.setOptions({ pageWidth: 2100, pageHeight: 2970, scale: 45, header: 'encoded', footer: 'encoded', breaks: 'auto' });
tk.loadData(mei);
console.log('pages', tk.getPageCount());
console.log('log:', tk.getLog());
for (let p = 1; p <= tk.getPageCount(); p++) fs.writeFileSync(path.join(outDir, `page${p}.svg`), tk.renderToSVG(p));
