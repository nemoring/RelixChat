/**
 * Application state: the document (score + undo history), selection,
 * note-input state and view settings. A tiny external store consumed with
 * React's useSyncExternalStore; the score is immutable (Immer), so undo
 * snapshots share structure and are cheap even for long scores.
 */
import { useSyncExternalStore } from 'react';
import { produce, setAutoFreeze } from 'immer';
import type { Duration, Score } from '../model/types';
import type { Frac } from '../model/fraction';
import { createPianoScore } from '../model/factory';

setAutoFreeze(true);

export type Selection =
  | { kind: 'none' }
  | { kind: 'event'; staff: number; measure: number; voice: number; eventId: string; noteId?: string }
  | { kind: 'range'; staffFrom: number; staffTo: number; mFrom: number; mTo: number; anchorStaff: number; anchorMeasure: number };

export interface InputState {
  active: boolean;
  dur: Duration;
  rest: boolean;
  voice: number;
}

export interface Cursor {
  staff: number;
  measure: number;
  voice: number;
  time: Frac;
}

export interface ViewState {
  zoom: number;
  mode: 'page' | 'continuous';
  showPalette: boolean;
}

export interface Dialog {
  kind: 'none' | 'scoreInfo' | 'newScore' | 'timeSig' | 'measures' | 'gotoMeasure' | 'stats' | 'shortcuts' | 'about' | 'pageSetup' | 'message';
  message?: { title: string; text: string };
}

interface HistoryEntry {
  score: Score;
  selection: Selection;
}

export interface AppState {
  score: Score;
  past: HistoryEntry[];
  future: HistoryEntry[];
  savedScore: Score;
  filePath: string | null;
  selection: Selection;
  input: InputState;
  cursor: Cursor | null;
  view: ViewState;
  dialog: Dialog;
  status: string;
  /** Measure index the score view should scroll to (incremented token forces re-scroll). */
  reveal: { measure: number; token: number } | null;
}

const HISTORY_LIMIT = 500;

function initialState(): AppState {
  const score = createPianoScore();
  return {
    score,
    past: [],
    future: [],
    savedScore: score,
    filePath: null,
    selection: { kind: 'none' },
    input: { active: false, dur: { base: 4, dots: 0 }, rest: false, voice: 0 },
    cursor: null,
    view: { zoom: 1, mode: 'page', showPalette: true },
    dialog: { kind: 'none' },
    status: 'Готово',
    reveal: null,
  };
}

let state: AppState = initialState();
const listeners = new Set<() => void>();

export function getState(): AppState {
  return state;
}

export function setState(patch: Partial<AppState> | ((s: AppState) => Partial<AppState>)): void {
  const p = typeof patch === 'function' ? patch(state) : patch;
  state = { ...state, ...p };
  listeners.forEach((l) => l());
}

export function subscribe(l: () => void): () => void {
  listeners.add(l);
  return () => listeners.delete(l);
}

export function useStore<T>(selector: (s: AppState) => T): T {
  return useSyncExternalStore(subscribe, () => selector(state), () => selector(state));
}

/**
 * Applies an undoable edit. `fn` mutates an Immer draft of the score and may
 * return extra state to set (typically the new selection / cursor).
 * Exceptions abort the edit and leave the score untouched.
 */
export function commit(label: string, fn: (draft: Score) => Partial<AppState> | void): boolean {
  let extra: Partial<AppState> | undefined;
  let next: Score;
  try {
    next = produce(state.score, (d) => {
      extra = fn(d as Score) ?? undefined;
    });
  } catch (e) {
    console.error(e);
    setState({ status: `Ошибка операции «${label}»: ${(e as Error).message}` });
    return false;
  }
  if (next === state.score) {
    if (extra !== undefined) setState(extra);
    return false;
  }
  const past = [...state.past, { score: state.score, selection: state.selection }];
  if (past.length > HISTORY_LIMIT) past.shift();
  setState({ score: next, past, future: [], status: label, ...(extra ?? {}) });
  return true;
}

export function undo(): void {
  const prev = state.past[state.past.length - 1];
  if (!prev) return;
  setState({
    score: prev.score,
    selection: prev.selection,
    past: state.past.slice(0, -1),
    future: [{ score: state.score, selection: state.selection }, ...state.future],
    status: 'Отменено',
  });
}

export function redo(): void {
  const next = state.future[0];
  if (!next) return;
  setState({
    score: next.score,
    selection: next.selection,
    future: state.future.slice(1),
    past: [...state.past, { score: state.score, selection: state.selection }],
    status: 'Повторено',
  });
}

/** Replaces the document (new / open) and clears history. */
export function loadDocument(score: Score, filePath: string | null): void {
  setState({
    score,
    savedScore: score,
    filePath,
    past: [],
    future: [],
    selection: { kind: 'none' },
    cursor: null,
    input: { ...state.input, active: false },
    reveal: { measure: 0, token: Date.now() },
  });
}

export const isDirty = (s: AppState) => s.score !== s.savedScore;
