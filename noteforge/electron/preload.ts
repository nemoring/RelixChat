/** Exposes a narrow, typed API to the renderer (see src/platform.ts). */
import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('noteforge', {
  isElectron: true,
  openProject: () => ipcRenderer.invoke('project:open'),
  readFile: (path: string) => ipcRenderer.invoke('project:read', path),
  saveProject: (path: string | null, content: string, suggestedName: string) => ipcRenderer.invoke('project:save', path, content, suggestedName),
  setDocumentState: (title: string, dirty: boolean) => ipcRenderer.send('doc:state', title, dirty),
  getLaunchFile: () => ipcRenderer.invoke('app:launchFile'),
  onCloseRequest: (cb: () => void) => {
    ipcRenderer.removeAllListeners('app:closeRequest');
    ipcRenderer.on('app:closeRequest', () => cb());
  },
  confirmClose: () => ipcRenderer.send('app:confirmClose'),
  quit: () => ipcRenderer.send('app:quit'),
});
