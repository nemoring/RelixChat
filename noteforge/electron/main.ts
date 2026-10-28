/**
 * Electron main process: window, local file I/O for .nfg projects (atomic
 * writes + .bak backups) and the app:// protocol that serves the built UI.
 * Nothing here talks to the network.
 */
import { app, BrowserWindow, dialog, ipcMain, Menu, net, protocol, session, shell } from 'electron';
import fs from 'node:fs/promises';
import type { FileHandle } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import os from 'node:os';

const DEV_URL = process.env.VITE_DEV_SERVER_URL;
const DIST = path.join(__dirname, '..', 'dist');

protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } },
]);

let win: BrowserWindow | null = null;
let dirty = false;
let allowClose = false;

function launchFile(argv: string[]): string | null {
  const f = argv.slice(1).find((a) => a.toLowerCase().endsWith('.nfg') && existsSync(a));
  return f ? path.resolve(f) : null;
}
let pendingLaunchFile = launchFile(process.argv);

function createWindow() {
  win = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#16181d',
    title: 'NoteForge',
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      spellcheck: false,
      autoplayPolicy: 'no-user-gesture-required',
    },
  });
  win.once('ready-to-show', () => win?.show());
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) void shell.openExternal(url);
    return { action: 'deny' };
  });
  win.on('close', (e) => {
    if (allowClose || !dirty) return;
    e.preventDefault();
    win?.webContents.send('app:closeRequest');
  });
  win.on('closed', () => (win = null));
  if (DEV_URL) void win.loadURL(DEV_URL);
  else void win.loadURL('app://noteforge/index.html');
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) app.quit();
app.on('second-instance', () => {
  if (win) {
    if (win.isMinimized()) win.restore();
    win.focus();
  }
});

app.whenReady().then(async () => {
  await startSession();
  protocol.handle('app', (req) => {
    const url = new URL(req.url);
    const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.normalize(path.join(DIST, rel));
    if (!file.startsWith(DIST)) return new Response('Forbidden', { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });
  Menu.setApplicationMenu(null);
  // Web MIDI (MIDI keyboards / external synths) needs an explicit permission in Electron.
  session.defaultSession.setPermissionRequestHandler((_wc, permission, cb) => cb(permission === 'midi' || permission === 'midiSysex'));
  session.defaultSession.setPermissionCheckHandler((_wc, permission) => permission === 'midi' || permission === 'midiSysex');
  createWindow();
});

app.on('window-all-closed', () => app.quit());
let ending = false;
app.on('will-quit', (e) => {
  if (ending) return;
  e.preventDefault();
  ending = true;
  void endSession().finally(() => app.quit());
});

// ───────────── IPC ─────────────

const FILTERS = [{ name: 'Проект NoteForge', extensions: ['nfg'] }];

ipcMain.handle('project:open', async () => {
  if (!win) return null;
  const r = await dialog.showOpenDialog(win, { title: 'Открыть партитуру', filters: FILTERS, properties: ['openFile'] });
  if (r.canceled || !r.filePaths[0]) return null;
  const p = r.filePaths[0];
  return { path: p, content: await fs.readFile(p, 'utf8') };
});

ipcMain.handle('project:read', async (_e, p: string) => {
  if (typeof p !== 'string' || !p.toLowerCase().endsWith('.nfg')) throw new Error('Можно открыть только файлы .nfg');
  return fs.readFile(p, 'utf8');
});

/** Atomic save: write a temp file, keep the previous version as .bak, then rename. */
async function writeProject(target: string, content: string) {
  const tmp = `${target}.tmp-${process.pid}`;
  await fs.writeFile(tmp, content, 'utf8');
  // Re-read to make sure the bytes on disk are what we meant to write.
  const check = await fs.readFile(tmp, 'utf8');
  if (check !== content) throw new Error('Проверка записанного файла не прошла');
  if (existsSync(target)) await fs.copyFile(target, `${target}.bak`);
  await fs.rename(tmp, target);
}

ipcMain.handle('project:save', async (_e, p: string | null, content: string, suggestedName: string) => {
  if (!win) return null;
  let target = p;
  if (!target) {
    const r = await dialog.showSaveDialog(win, { title: 'Сохранить партитуру', defaultPath: suggestedName, filters: FILTERS });
    if (r.canceled || !r.filePath) return null;
    target = r.filePath.toLowerCase().endsWith('.nfg') ? r.filePath : `${r.filePath}.nfg`;
  }
  await writeProject(target, content);
  return target;
});

async function askSavePath(name: string, filterName: string, ext: string): Promise<string | null> {
  if (!win) return null;
  const r = await dialog.showSaveDialog(win, { defaultPath: name, filters: [{ name: filterName, extensions: [ext] }] });
  if (r.canceled || !r.filePath) return null;
  return r.filePath.toLowerCase().endsWith(`.${ext}`) ? r.filePath : `${r.filePath}.${ext}`;
}

ipcMain.handle('file:saveBinary', async (_e, name: string, filterName: string, ext: string, data: Uint8Array) => {
  const p = await askSavePath(name, filterName, ext);
  if (!p) return null;
  await fs.writeFile(p, Buffer.from(data));
  return p;
});

ipcMain.handle('file:saveText', async (_e, name: string, filterName: string, ext: string, content: string) => {
  const p = await askSavePath(name, filterName, ext);
  if (!p) return null;
  await fs.writeFile(p, content, 'utf8');
  return p;
});

const writers = new Map<string, { fh: FileHandle; path: string }>();
ipcMain.handle('file:createWriter', async (_e, name: string, filterName: string, ext: string) => {
  const p = await askSavePath(name, filterName, ext);
  if (!p) return null;
  const id = `w${Date.now()}${Math.random().toString(36).slice(2, 6)}`;
  writers.set(id, { fh: await fs.open(`${p}.part`, 'w'), path: p });
  return { id, path: p };
});
ipcMain.handle('file:writeChunk', async (_e, id: string, data: Uint8Array) => {
  const w = writers.get(id);
  if (!w) throw new Error('Файл экспорта закрыт');
  await w.fh.write(Buffer.from(data));
});
ipcMain.handle('file:closeWriter', async (_e, id: string, abort: boolean) => {
  const w = writers.get(id);
  if (!w) return;
  writers.delete(id);
  await w.fh.close();
  if (abort) await fs.rm(`${w.path}.part`, { force: true });
  else await fs.rename(`${w.path}.part`, w.path);
});

ipcMain.handle('file:openBinary', async (_e, filterName: string, exts: string[]) => {
  if (!win) return null;
  const r = await dialog.showOpenDialog(win, { filters: [{ name: filterName, extensions: exts }], properties: ['openFile'] });
  if (r.canceled || !r.filePaths[0]) return null;
  const p = r.filePaths[0];
  const buf = await fs.readFile(p);
  return { name: path.basename(p), path: p, data: buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength) };
});

ipcMain.handle('file:openText', async (_e, filterName: string, exts: string[]) => {
  if (!win) return null;
  const r = await dialog.showOpenDialog(win, { filters: [{ name: filterName, extensions: exts }], properties: ['openFile'] });
  if (r.canceled || !r.filePaths[0]) return null;
  const p = r.filePaths[0];
  return { name: path.basename(p), path: p, content: await fs.readFile(p, 'utf8') };
});

// ───────────── printing / PDF ─────────────

interface PrintJob {
  file: string;
  widthMm: number;
  heightMm: number;
  fh: FileHandle;
}
const printJobs = new Map<string, PrintJob>();

ipcMain.handle('print:begin', async (_e, widthMm: number, heightMm: number, title: string) => {
  const id = `job${Date.now()}${Math.random().toString(36).slice(2, 6)}`;
  const file = path.join(os.tmpdir(), `noteforge-print-${id}.html`);
  const fh = await fs.open(file, 'w');
  const esc = (t: string) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  await fh.write(`<!doctype html><html><head><meta charset="utf-8"><title>${esc(title)}</title><style>
@page { size: ${widthMm}mm ${heightMm}mm; margin: 0 }
html, body { margin: 0; padding: 0; background: #fff }
.pg { width: ${widthMm}mm; height: ${heightMm}mm; overflow: hidden; page-break-after: always; break-after: page }
.pg:last-child { page-break-after: auto; break-after: auto }
.pg svg { width: 100%; height: 100%; display: block }
</style></head><body>`);
  printJobs.set(id, { file, widthMm, heightMm, fh });
  return id;
});

ipcMain.handle('print:page', async (_e, id: string, svg: string) => {
  const j = printJobs.get(id);
  if (!j) throw new Error('Задание печати не найдено');
  await j.fh.write(`<div class="pg">${svg}</div>`);
});

ipcMain.handle('print:finish', async (_e, id: string, action: 'pdf' | 'print', suggestedName: string) => {
  const j = printJobs.get(id);
  if (!j) throw new Error('Задание печати не найдено');
  printJobs.delete(id);
  await j.fh.write('</body></html>');
  await j.fh.close();
  const pw = new BrowserWindow({ show: false, webPreferences: { sandbox: true, javascript: false } });
  try {
    await pw.loadFile(j.file);
    const inch = (mm: number) => mm / 25.4;
    if (action === 'pdf') {
      const target = await askSavePath(suggestedName, 'PDF', 'pdf');
      if (!target) return null;
      const data = await pw.webContents.printToPDF({
        pageSize: { width: inch(j.widthMm), height: inch(j.heightMm) },
        margins: { marginType: 'none' },
        printBackground: true,
        preferCSSPageSize: true,
      });
      await fs.writeFile(target, data);
      return target;
    }
    return await new Promise<string | null>((resolve, reject) => {
      pw.webContents.print(
        { silent: false, printBackground: true, margins: { marginType: 'none' }, pageSize: { width: Math.round(j.widthMm * 1000), height: Math.round(j.heightMm * 1000) } },
        (ok, reason) => (ok ? resolve('printed') : reason === 'cancelled' || reason === 'Print job canceled' ? resolve(null) : reject(new Error(reason))),
      );
    });
  } finally {
    pw.destroy();
    await fs.rm(j.file, { force: true });
  }
});

// ───────────── settings, autosave & crash recovery ─────────────

const userDir = () => app.getPath('userData');
const settingsFile = () => path.join(userDir(), 'settings.json');
const autosaveDir = () => path.join(userDir(), 'autosave');
const sessionFile = () => path.join(userDir(), 'session.lock');
/** Set when the previous run did not shut down cleanly. */
let crashedLastTime = false;

async function startSession() {
  await fs.mkdir(autosaveDir(), { recursive: true });
  crashedLastTime = existsSync(sessionFile());
  await fs.writeFile(sessionFile(), JSON.stringify({ pid: process.pid, started: new Date().toISOString() }));
}

async function endSession() {
  // Clean exit: autosaves of this session are no longer needed.
  try {
    const files = await fs.readdir(autosaveDir());
    await Promise.all(files.map((f) => fs.rm(path.join(autosaveDir(), f), { force: true })));
    await fs.rm(sessionFile(), { force: true });
  } catch {
    /* ignore */
  }
}

ipcMain.handle('settings:get', async () => {
  try {
    return JSON.parse(await fs.readFile(settingsFile(), 'utf8'));
  } catch {
    return {};
  }
});
ipcMain.handle('settings:set', async (_e, value: unknown) => {
  await fs.mkdir(userDir(), { recursive: true });
  await fs.writeFile(`${settingsFile()}.tmp`, JSON.stringify(value, null, 1));
  await fs.rename(`${settingsFile()}.tmp`, settingsFile());
});

const safeKey = (k: string) => k.replace(/[^\w-]/g, '').slice(0, 64) || 'doc';
ipcMain.handle('autosave:write', async (_e, key: string, content: string, meta: unknown) => {
  const base = path.join(autosaveDir(), safeKey(key));
  await fs.writeFile(`${base}.nfg.tmp`, content, 'utf8');
  await fs.rename(`${base}.nfg.tmp`, `${base}.nfg`);
  await fs.writeFile(`${base}.json`, JSON.stringify({ ...(meta as object), savedAt: new Date().toISOString() }));
});
ipcMain.handle('autosave:clear', async (_e, key: string) => {
  const base = path.join(autosaveDir(), safeKey(key));
  await fs.rm(`${base}.nfg`, { force: true });
  await fs.rm(`${base}.json`, { force: true });
});
/** Autosaves left over from a crashed session. */
ipcMain.handle('autosave:recoverable', async () => {
  if (!crashedLastTime) return [];
  const out: unknown[] = [];
  for (const f of await fs.readdir(autosaveDir())) {
    if (!f.endsWith('.json')) continue;
    try {
      const meta = JSON.parse(await fs.readFile(path.join(autosaveDir(), f), 'utf8'));
      out.push({ key: f.replace(/\.json$/, ''), ...meta });
    } catch {
      /* skip */
    }
  }
  return out;
});
ipcMain.handle('autosave:read', async (_e, key: string) => fs.readFile(path.join(autosaveDir(), `${safeKey(key)}.nfg`), 'utf8'));
ipcMain.handle('autosave:discardRecovered', async () => {
  crashedLastTime = false;
});

ipcMain.on('doc:state', (_e, title: string, isDirty: boolean) => {
  dirty = isDirty;
  win?.setTitle(`${isDirty ? '• ' : ''}${title} — NoteForge`);
  win?.setDocumentEdited(isDirty);
});

ipcMain.handle('app:launchFile', () => {
  const f = pendingLaunchFile;
  pendingLaunchFile = null;
  return f;
});

ipcMain.on('app:confirmClose', () => {
  allowClose = true;
  win?.close();
});

ipcMain.on('app:quit', () => app.quit());
