/**
 * Playback commands: connect the player to the document and implement the
 * transport, exports (MIDI / WAV) and SoundFont selection.
 */
import { player } from '../playback/player';
import { performanceToMidi } from '../playback/midifile';
import { renderWav } from '../playback/wav';
import { SoundFont } from '../playback/sf2';
import { getState, setState } from './store';
import { platform } from '../platform';
import { findEvent } from '../model/query';
import { toNumber } from '../model/fraction';
import { midiOf } from '../model/pitch';
import type { Score } from '../model/types';

player.getScore = () => getState().score;

// Melody/accompaniment role of each event (melody lines are stored on events).
let roleCache: { score: Score; map: Map<string, string> } | null = null;
function lineOf(eventId: string): string | undefined {
  const score = getState().score;
  if (!roleCache || roleCache.score !== score) {
    const map = new Map<string, string>();
    for (const part of score.parts)
      for (const st of part.staves)
        for (const sm of st.measures)
          for (const v of sm.voices)
            for (const ev of v) {
              const line = (ev as { line?: string }).line;
              if (line) map.set(ev.id, line);
            }
    roleCache = { score, map };
  }
  return roleCache.map.get(eventId);
}
player.roleOf = (eventId) => (lineOf(eventId) ? 'melody' : 'accomp');

export function exportStatus(text: string | null, progress?: number) {
  setState({ exportProgress: text ? { text, progress: progress ?? null } : null });
}

export async function playPause(): Promise<void> {
  const st = player.state;
  if (st.status === 'playing') {
    player.pause();
    return;
  }
  if (st.status === 'paused') {
    await player.play(undefined, player.lastRange);
    return;
  }
  await playFromSelection();
}

/** Plays from the selected note / measure; a measure range is played (and looped if enabled) on its own. */
export async function playFromSelection(): Promise<void> {
  const { selection, score, cursor, input } = getState();
  if (selection.kind === 'range' && selection.mTo > selection.mFrom) {
    player.lastRange = { from: selection.mFrom, to: selection.mTo };
    await player.play(undefined, player.lastRange);
    return;
  }
  player.lastRange = undefined;
  if (input.active && cursor) {
    await player.play({ measure: cursor.measure, time: toNumber(cursor.time) });
    return;
  }
  if (selection.kind === 'event') {
    const f = findEvent(score, selection.eventId, selection);
    if (f) {
      await player.play({ measure: f.measure, time: toNumber(f.start) });
      return;
    }
  }
  if (selection.kind === 'range') {
    await player.play({ measure: selection.mFrom, time: 0 });
    return;
  }
  await player.play({ measure: 0, time: 0 });
}

export function stop(): void {
  player.stop();
}

export async function restart(): Promise<void> {
  player.stop();
  player.lastRange = undefined;
  await player.play({ measure: 0, time: 0 });
}

export function toggleLoop(): void {
  player.setLoop(!player.state.loop);
}

export function toggleMetronome(): void {
  player.setMetronome(!player.state.metronome);
}

export function changeSpeed(delta: number): void {
  player.setSpeed(player.state.speed + delta);
}

/** Auditions the selected note/chord (MuseScore-style feedback while editing). */
export function previewSelection(): void {
  const { selection, score } = getState();
  if (selection.kind !== 'event') return;
  const f = findEvent(score, selection.eventId, selection);
  if (!f || f.ev.type !== 'chord') return;
  const notes = selection.noteId ? f.ev.notes.filter((n) => n.id === selection.noteId) : f.ev.notes;
  player.preview(notes.map(midiOf), score.parts[0]?.program ?? 0);
}

function baseName(): string {
  const s = getState();
  if (s.filePath) return s.filePath.split(/[\\/]/).pop()!.replace(/\.nfg$/i, '');
  return s.score.meta.title || 'Без названия';
}

export async function exportMidi(): Promise<void> {
  const score = getState().score;
  const data = performanceToMidi(score, player.performance());
  const p = await platform.saveBinary(`${baseName()}.mid`, 'MIDI-файл', 'mid', data);
  if (p) setState({ status: `Экспортировано в MIDI: ${p}` });
}

let wavCancel = false;
export function cancelExport() {
  wavCancel = true;
}

export async function exportWav(): Promise<void> {
  await player.loadSoundFont();
  const w = await platform.createWriter(`${baseName()}.wav`, 'WAV-аудио', 'wav');
  if (!w) return;
  wavCancel = false;
  exportStatus('Экспорт WAV…', 0);
  try {
    const perf = player.performance();
    await renderWav(
      perf,
      player.soundFont,
      { write: (b) => platform.writeChunk(w.id, b) },
      {
        reverb: player.state.reverb,
        gainFor: (n) => player.gainForNote(n.staff, player.roleOf(n.eventId)),
        onProgress: (f) => exportStatus('Экспорт WAV…', f),
        isCancelled: () => wavCancel,
      },
    );
    await platform.closeWriter(w.id);
    setState({ status: `Экспортировано в WAV: ${w.path}` });
  } catch (e) {
    await platform.closeWriter(w.id, true);
    setState({ status: `Экспорт WAV прерван: ${(e as Error).message}` });
  } finally {
    exportStatus(null);
  }
}

export async function chooseSoundFont(): Promise<void> {
  const f = await platform.openBinary('SoundFont 2', ['sf2']);
  if (!f) return;
  try {
    new SoundFont(f.data); // validate before switching
    await player.loadSoundFont({ name: f.name, data: f.data });
    setState({ status: `SoundFont: ${f.name}` });
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Не удалось загрузить SoundFont', text: (e as Error).message } } });
  }
}

export async function useDefaultSoundFont(): Promise<void> {
  await player.loadSoundFont({ name: 'GeneralUser GS', data: await (await fetch(new URL('soundfonts/GeneralUser-GS.sf2', document.baseURI).toString())).arrayBuffer() });
}
