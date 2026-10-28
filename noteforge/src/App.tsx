import { useEffect } from 'react';
import { MenuBar } from './ui/MenuBar';
import { Toolbar } from './ui/Toolbar';
import { Palette } from './ui/Palette';
import { ScoreView } from './ui/ScoreView';
import { StatusBar } from './ui/StatusBar';
import { Dialogs, ExportProgress } from './ui/Dialogs';
import { Transport } from './ui/Transport';
import { handleKeyDown } from './input/commands';
import { useStore, getState, isDirty, subscribe } from './state/store';
import * as A from './state/actions';
import { platform } from './platform';

export function App() {
  const showPalette = useStore((s) => s.view.showPalette);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => handleKeyDown(e);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Keep the window title / unsaved marker in sync with the document.
  useEffect(() => {
    let last = '';
    const sync = () => {
      const s = getState();
      const key = `${A.documentTitle()}|${isDirty(s)}`;
      if (key === last) return;
      last = key;
      platform.setDocumentState(A.documentTitle(), isDirty(s));
    };
    sync();
    return subscribe(sync);
  }, []);

  // Closing the window with unsaved changes (Electron asks the renderer first).
  useEffect(() => {
    platform.onCloseRequest(async () => {
      if (!isDirty(getState())) return platform.confirmClose();
      const choice = window.confirm('Сохранить изменения перед выходом?\n\nOK — сохранить, Отмена — выйти без сохранения.');
      if (choice) {
        const ok = await A.saveProject(false);
        if (!ok) return;
      }
      platform.confirmClose();
    });
    const beforeUnload = (e: BeforeUnloadEvent) => {
      if (!platform.isElectron && isDirty(getState())) e.preventDefault();
    };
    window.addEventListener('beforeunload', beforeUnload);
    // A project passed on the command line (double-click on a .nfg file).
    platform.getLaunchFile().then(async (path) => {
      if (!path) return;
      try {
        A.loadProjectText(await platform.readFile(path), path);
      } catch (e) {
        console.error(e);
      }
    });
    return () => window.removeEventListener('beforeunload', beforeUnload);
  }, []);

  return (
    <div className="app">
      <MenuBar />
      <Toolbar />
      <div className="workspace">
        {showPalette && <Palette />}
        <ScoreView />
      </div>
      <Transport />
      <StatusBar />
      <Dialogs />
      <ExportProgress />
    </div>
  );
}
