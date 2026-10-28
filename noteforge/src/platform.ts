/**
 * Bridge to the Electron main process (see electron/preload.ts).
 * When running in a plain browser (e.g. `vite` without Electron) a minimal
 * fallback based on file download/upload is used so the editor stays usable.
 */
export interface OpenResult {
  path: string;
  content: string;
}

export interface PlatformApi {
  isElectron: boolean;
  openProject(): Promise<OpenResult | null>;
  readFile(path: string): Promise<string>;
  /** Saves to `path`, or asks for a path when null. Returns the final path or null if cancelled. */
  saveProject(path: string | null, content: string, suggestedName: string): Promise<string | null>;
  setDocumentState(title: string, dirty: boolean): void;
  getLaunchFile(): Promise<string | null>;
  onCloseRequest(cb: () => void): void;
  confirmClose(): void;
  quit(): void;
}

declare global {
  interface Window {
    noteforge?: PlatformApi;
  }
}

const browserFallback: PlatformApi = {
  isElectron: false,
  openProject: () =>
    new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = '.nfg,application/json';
      input.onchange = async () => {
        const f = input.files?.[0];
        resolve(f ? { path: f.name, content: await f.text() } : null);
      };
      input.click();
    }),
  readFile: async () => {
    throw new Error('Чтение файлов по пути доступно только в настольной версии.');
  },
  saveProject: async (path, content, suggestedName) => {
    const name = path ?? suggestedName;
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([content], { type: 'application/json' }));
    a.download = name.endsWith('.nfg') ? name : `${name}.nfg`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
    return a.download;
  },
  setDocumentState: (title, dirty) => {
    document.title = `${dirty ? '• ' : ''}${title} — NoteForge`;
  },
  getLaunchFile: async () => null,
  onCloseRequest: () => {},
  confirmClose: () => {},
  quit: () => window.close(),
};

export const platform: PlatformApi = window.noteforge ?? browserFallback;
