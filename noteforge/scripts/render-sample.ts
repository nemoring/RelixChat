// Debug helper: builds a sample score through the editing API and writes MEI + SVG pages.
// Usage: npx vite-node scripts/render-sample.ts <outDir>
import fs from 'node:fs';
import path from 'node:path';
import { produce } from 'immer';
import { createPianoScore } from '../src/model/factory';
import { writeAt, setTimeSig, setKeySig } from '../src/model/edit';
import { frac, ZERO } from '../src/model/fraction';
import { scoreToMei } from '../src/engrave/mei';
import createVerovioModule from 'verovio/wasm';
import { VerovioToolkit } from 'verovio/esm';

const outDir = process.argv[2] ?? '.';
let score = createPianoScore({ title: 'Этюд', composer: 'NoteForge', measures: 6 });
score = produce(score, (d) => {
  d.meta.subtitle = 'тест гравировки';
  const q = frac(1, 4), e = frac(1, 8);
  // Melody passed between the hands: RH C5 → B4, LH A4 → G4.
  writeAt(d, 0, 0, 0, ZERO, q, { type: 'chord', notes: [{ step: 'C', octave: 5, alter: 0 }] });
  writeAt(d, 0, 0, 0, frac(1, 4), q, { type: 'chord', notes: [{ step: 'B', octave: 4, alter: 0 }] });
  writeAt(d, 1, 0, 0, frac(1, 2), q, { type: 'chord', notes: [{ step: 'A', octave: 4, alter: 0 }] });
  writeAt(d, 1, 0, 0, frac(3, 4), q, { type: 'chord', notes: [{ step: 'G', octave: 4, alter: 0 }] });
  // Eighths with accidentals, a chord and a tie across the barline.
  let t = ZERO;
  for (const [st, alt] of [['D', 0], ['E', -1], ['F', 1], ['G', 0]] as const) {
    writeAt(d, 0, 1, 0, t, e, { type: 'chord', notes: [{ step: st, octave: 5, alter: alt }] });
    t = frac(t.n * 8 + t.d, t.d * 8);
  }
  writeAt(d, 0, 1, 0, frac(1, 2), frac(3, 4), { type: 'chord', notes: [{ step: 'E', octave: 4, alter: 0 }, { step: 'G', octave: 4, alter: 0 }] });
  writeAt(d, 1, 1, 0, ZERO, frac(1, 1), { type: 'chord', notes: [{ step: 'C', octave: 3, alter: 0 }, { step: 'G', octave: 3, alter: 0 }] });
  // Second voice in the right hand.
  writeAt(d, 0, 3, 1, ZERO, frac(1, 2), { type: 'chord', notes: [{ step: 'E', octave: 4, alter: 0 }] });
  writeAt(d, 0, 3, 0, ZERO, frac(1, 2), { type: 'chord', notes: [{ step: 'C', octave: 5, alter: 0 }] });
  setKeySig(d, 4, 2);
  setTimeSig(d, 4, { count: 3, unit: 4 });
});
const { mei } = scoreToMei(score);
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'sample.mei'), mei);
const tk = new VerovioToolkit(await createVerovioModule());
tk.setOptions({ pageWidth: 2100, pageHeight: 2970, scale: 40, header: 'encoded', footer: 'encoded', breaks: 'auto' });
tk.loadData(mei);
console.log('pages', tk.getPageCount());
console.log('log:', tk.getLog());
for (let p = 1; p <= tk.getPageCount(); p++) fs.writeFileSync(path.join(outDir, `page${p}.svg`), tk.renderToSVG(p));
