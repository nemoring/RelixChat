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
  /** Asks for a path and writes binary data. Returns the path or null. */
  saveBinary(suggestedName: string, filterName: string, ext: string, data: Uint8Array): Promise<string | null>;
  /** Streaming writer for large exports (WAV). */
  createWriter(suggestedName: string, filterName: string, ext: string): Promise<{ id: string; path: string } | null>;
  writeChunk(id: string, data: Uint8Array): Promise<void>;
  closeWriter(id: string, abort?: boolean): Promise<void>;
  /** Opens a binary file chosen by the user. */
  openBinary(filterName: string, exts: string[]): Promise<{ name: string; path: string; data: ArrayBuffer } | null>;
  /** Opens a text file chosen by the user. */
  openText(filterName: string, exts: string[]): Promise<{ name: string; path: string; content: string } | null>;
  saveText(suggestedName: string, filterName: string, ext: string, content: string): Promise<string | null>;
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

const writers = new Map<string, { name: string; parts: BlobPart[] }>();

function download(blob: Blob, name: string) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

function pickFile<T>(accept: string, read: (f: File) => Promise<T>): Promise<T | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.onchange = async () => {
      const f = input.files?.[0];
      resolve(f ? await read(f) : null);
    };
    input.click();
  });
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
  saveBinary: async (name, _f, ext, data) => {
    download(new Blob([new Uint8Array(data)]), name.endsWith(`.${ext}`) ? name : `${name}.${ext}`);
    return name;
  },
  createWriter: async (name, _f, ext) => {
    const id = `w${Date.now()}`;
    writers.set(id, { name: name.endsWith(`.${ext}`) ? name : `${name}.${ext}`, parts: [] });
    return { id, path: name };
  },
  writeChunk: async (id, data) => {
    writers.get(id)?.parts.push(new Uint8Array(data));
  },
  closeWriter: async (id, abort) => {
    const w = writers.get(id);
    writers.delete(id);
    if (w && !abort) download(new Blob(w.parts), w.name);
  },
  openBinary: (_f, exts) => pickFile(exts.map((e) => `.${e}`).join(','), async (f) => ({ name: f.name, path: f.name, data: await f.arrayBuffer() })),
  openText: (_f, exts) => pickFile(exts.map((e) => `.${e}`).join(','), async (f) => ({ name: f.name, path: f.name, content: await f.text() })),
  saveText: async (name, _f, ext, content) => {
    download(new Blob([content]), name.endsWith(`.${ext}`) ? name : `${name}.${ext}`);
    return name;
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
