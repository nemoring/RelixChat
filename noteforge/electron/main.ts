/**
 * Electron main process: window, local file I/O for .nfg projects (atomic
 * writes + .bak backups) and the app:// protocol that serves the built UI.
 * Nothing here talks to the network.
 */
import { app, BrowserWindow, dialog, ipcMain, Menu, net, protocol, shell } from 'electron';
import fs from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

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

app.whenReady().then(() => {
  protocol.handle('app', (req) => {
    const url = new URL(req.url);
    const rel = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html';
    const file = path.normalize(path.join(DIST, rel));
    if (!file.startsWith(DIST)) return new Response('Forbidden', { status: 403 });
    return net.fetch(pathToFileURL(file).toString());
  });
  Menu.setApplicationMenu(null);
  createWindow();
});

app.on('window-all-closed', () => app.quit());

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
