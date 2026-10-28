import { createRoot } from 'react-dom/client';
import { App } from './App';
import './styles.css';
import * as store from './state/store';
import * as actions from './state/actions';
import * as playback from './state/playback';
import { player } from './playback/player';
import * as autosave from './state/autosave';
import * as settings from './state/settings';

createRoot(document.getElementById('root')!).render(<App />);

// Exposed for automated UI tests and debugging from DevTools.
(window as unknown as { __noteforge: unknown }).__noteforge = { store, actions, playback, player, autosave, settings };
