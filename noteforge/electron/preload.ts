/** Exposes a narrow, typed API to the renderer (see src/platform.ts). */
import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('noteforge', {
  isElectron: true,
  openProject: () => ipcRenderer.invoke('project:open'),
  readFile: (path: string) => ipcRenderer.invoke('project:read', path),
  saveProject: (path: string | null, content: string, suggestedName: string) => ipcRenderer.invoke('project:save', path, content, suggestedName),
  saveBinary: (name: string, filterName: string, ext: string, data: Uint8Array) => ipcRenderer.invoke('file:saveBinary', name, filterName, ext, data),
  createWriter: (name: string, filterName: string, ext: string) => ipcRenderer.invoke('file:createWriter', name, filterName, ext),
  writeChunk: (id: string, data: Uint8Array) => ipcRenderer.invoke('file:writeChunk', id, data),
  closeWriter: (id: string, abort?: boolean) => ipcRenderer.invoke('file:closeWriter', id, !!abort),
  openBinary: (filterName: string, exts: string[]) => ipcRenderer.invoke('file:openBinary', filterName, exts),
  openText: (filterName: string, exts: string[]) => ipcRenderer.invoke('file:openText', filterName, exts),
  saveText: (name: string, filterName: string, ext: string, content: string) => ipcRenderer.invoke('file:saveText', name, filterName, ext, content),
  printBegin: (w: number, h: number, title: string) => ipcRenderer.invoke('print:begin', w, h, title),
  printPage: (job: string, svg: string) => ipcRenderer.invoke('print:page', job, svg),
  printFinish: (job: string, action: 'pdf' | 'print', name: string) => ipcRenderer.invoke('print:finish', job, action, name),
  setDocumentState: (title: string, dirty: boolean) => ipcRenderer.send('doc:state', title, dirty),
  getLaunchFile: () => ipcRenderer.invoke('app:launchFile'),
  onCloseRequest: (cb: () => void) => {
    ipcRenderer.removeAllListeners('app:closeRequest');
    ipcRenderer.on('app:closeRequest', () => cb());
  },
  confirmClose: () => ipcRenderer.send('app:confirmClose'),
  quit: () => ipcRenderer.send('app:quit'),
});
