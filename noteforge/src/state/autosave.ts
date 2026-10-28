/**
 * Autosave and crash recovery. While a document has unsaved changes it is
 * written to the application's autosave folder every few minutes; a clean
 * exit removes the autosaves. After a crash the next start offers them back.
 */
import { getState, setState, subscribe, isDirty } from './store';
import { platform } from '../platform';
import { serializeProject } from '../model/serialize';
import { getSettings } from './settings';
import type { Score } from '../model/types';

let lastSaved: Score | null = null;
let lastKey = '';
let timer: ReturnType<typeof setInterval> | null = null;

export async function autosaveNow(): Promise<boolean> {
  const s = getState();
  if (!isDirty(s) || s.score === lastSaved) return false;
  await platform.autosaveWrite(s.docKey, serializeProject(s.score), { title: s.score.meta.title || 'Без названия', filePath: s.filePath });
  lastSaved = s.score;
  setState({ status: `Автосохранение: ${new Date().toLocaleTimeString()}` });
  return true;
}

export function startAutosave(): void {
  if (timer) clearInterval(timer);
  const minutes = getSettings().autosaveMinutes;
  if (minutes > 0) timer = setInterval(() => void autosaveNow().catch(() => {}), Math.max(15, minutes * 60) * 1000);
  // A newly loaded or saved document no longer needs its old autosave.
  lastKey = getState().docKey;
  subscribe(() => {
    const s = getState();
    if (s.docKey !== lastKey) {
      void platform.autosaveClear(lastKey);
      lastKey = s.docKey;
      lastSaved = null;
    }
    if (!isDirty(s) && lastSaved !== null) {
      void platform.autosaveClear(s.docKey);
      lastSaved = null;
    }
  });
}

export async function checkRecovery(): Promise<void> {
  const list = await platform.autosaveRecoverable();
  if (list.length) setState({ dialog: { kind: 'recovery' }, recovery: list });
}

export async function recover(key: string, filePath: string | null): Promise<void> {
  const { loadProjectText } = await import('./actions');
  const text = await platform.autosaveRead(key);
  if (loadProjectText(text, filePath)) {
    // The recovered content is not on disk yet.
    setState((s) => ({ savedScore: { ...s.score }, status: 'Партитура восстановлена из автосохранения — сохраните её' }));
  }
  await platform.autosaveClear(key);
}

export async function discardRecovery(keys: string[]): Promise<void> {
  for (const k of keys) await platform.autosaveClear(k);
  await platform.autosaveDiscardRecovered();
}
