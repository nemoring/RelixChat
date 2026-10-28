/** Persistent application settings (stored by the main process in userData/settings.json). */
import { useSyncExternalStore } from 'react';
import { platform } from '../platform';

export type Snap = 'note' | 4 | 8 | 16 | 32;

export interface Settings {
  /** Overridden shortcuts: command id → key list. */
  shortcuts: Record<string, string[]>;
  /** Minutes between autosaves (0 = off). */
  autosaveMinutes: number;
  /** MIDI input device for note entry: 'all', 'none' or a device id. */
  midiInput: string;
  /** Rhythmic grid for mouse note entry. */
  snap: Snap;
  showKeyboard: boolean;
  recentFiles: string[];
}

const DEFAULTS: Settings = { shortcuts: {}, autosaveMinutes: 2, midiInput: 'all', snap: 'note', showKeyboard: false, recentFiles: [] };

let settings: Settings = { ...DEFAULTS };
const listeners = new Set<() => void>();
let saveTimer: ReturnType<typeof setTimeout> | null = null;

export function getSettings(): Settings {
  return settings;
}

export async function loadSettings(): Promise<Settings> {
  try {
    const raw = await platform.getSettings();
    settings = { ...DEFAULTS, ...(raw as Partial<Settings>) };
    if (typeof settings.shortcuts !== 'object' || !settings.shortcuts) settings.shortcuts = {};
    if (!Array.isArray(settings.recentFiles)) settings.recentFiles = [];
  } catch {
    settings = { ...DEFAULTS };
  }
  listeners.forEach((l) => l());
  return settings;
}

export function updateSettings(patch: Partial<Settings>): void {
  settings = { ...settings, ...patch };
  listeners.forEach((l) => l());
  if (saveTimer) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => void platform.setSettings(settings as unknown as Record<string, unknown>), 300);
}

export function useSettings<T>(sel: (s: Settings) => T): T {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => sel(settings),
    () => sel(settings),
  );
}

export function addRecentFile(path: string): void {
  updateSettings({ recentFiles: [path, ...settings.recentFiles.filter((p) => p !== path)].slice(0, 10) });
}
