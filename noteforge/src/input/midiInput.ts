/**
 * Note entry from a MIDI keyboard (Web MIDI). Keys pressed together (within
 * a short window) form a chord; each note is also auditioned.
 */
import { player } from '../playback/player';
import { getSettings } from '../state/settings';
import { getState } from '../state/store';
import * as A from '../state/actions';

const CHORD_WINDOW_MS = 70;
let lastNoteAt = 0;
const held = new Set<number>();
let attached = new WeakSet<MIDIInput>();

function onMessage(input: MIDIInput, e: MIDIMessageEvent) {
  const want = getSettings().midiInput;
  if (want === 'none' || (want !== 'all' && want !== input.id)) return;
  const d = e.data;
  if (!d || d.length < 3) return;
  const cmd = d[0] & 0xf0;
  const key = d[1];
  const vel = d[2];
  if (cmd === 0x90 && vel > 0) {
    player.preview([key], getState().score.parts[0]?.program ?? 0, 0.8, vel);
    const now = performance.now();
    const chord = held.size > 0 && now - lastNoteAt < CHORD_WINDOW_MS;
    held.add(key);
    lastNoteAt = now;
    if (getState().input.active || getState().selection.kind !== 'none') A.enterMidiPitch(key, chord);
  } else if (cmd === 0x80 || (cmd === 0x90 && vel === 0)) {
    held.delete(key);
  }
}

/** Connects every MIDI input (including devices plugged in later). */
export async function startMidiInput(): Promise<void> {
  await player.refreshMidi();
  const access = player.midi;
  if (!access) return;
  const connect = () => {
    for (const input of access.inputs.values()) {
      if (attached.has(input)) continue;
      attached.add(input);
      input.onmidimessage = (e) => onMessage(input, e as MIDIMessageEvent);
    }
  };
  connect();
  access.addEventListener('statechange', connect);
}

export function midiInputs(): { id: string; name: string }[] {
  const access = player.midi;
  return access ? [...access.inputs.values()].map((i) => ({ id: i.id, name: i.name ?? i.id })) : [];
}

export function resetMidiInput() {
  attached = new WeakSet();
}
