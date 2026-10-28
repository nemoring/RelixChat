import { produce } from 'immer';
import type { Score } from '../src/model/types';

/** Applies an edit the same way the app does (through an Immer draft). */
export function edit(score: Score, fn: (d: Score) => void): Score {
  return produce(score, fn);
}

export async function loadVerovio() {
  const { default: createVerovioModule } = await import('verovio/wasm');
  const { VerovioToolkit } = await import('verovio/esm');
  const module = await createVerovioModule();
  return new VerovioToolkit(module);
}
