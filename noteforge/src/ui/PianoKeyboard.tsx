/** On-screen 88-key piano: enters notes in input mode, auditions otherwise, shows what is playing / selected. */
import { useEffect, useRef } from 'react';
import { player } from '../playback/player';
import { useStore, getState } from '../state/store';
import { findEvent } from '../model/query';
import { midiOf } from '../model/pitch';
import * as A from '../state/actions';

const LOW = 21;
const HIGH = 108;
const isBlack = (k: number) => [1, 3, 6, 8, 10].includes(k % 12);
const NAMES = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];

export function PianoKeyboard() {
  const ref = useRef<HTMLDivElement>(null);
  const selection = useStore((s) => s.selection);
  const score = useStore((s) => s.score);
  // Selected notes.
  useEffect(() => {
    const root = ref.current;
    if (!root) return;
    root.querySelectorAll('.pk.sel').forEach((el) => el.classList.remove('sel'));
    if (selection.kind !== 'event') return;
    const f = findEvent(score, selection.eventId, selection);
    if (!f || f.ev.type !== 'chord') return;
    for (const n of f.ev.notes) root.querySelector(`[data-key="${midiOf(n)}"]`)?.classList.add('sel');
  }, [selection, score]);
  // Playing notes.
  useEffect(() => {
    let lit = new Set<number>();
    return player.onFrame((_sec, _ids, keys) => {
      const root = ref.current;
      if (!root) return;
      for (const k of lit) if (!keys.has(k)) root.querySelector(`[data-key="${k}"]`)?.classList.remove('play');
      for (const k of keys) if (!lit.has(k)) root.querySelector(`[data-key="${k}"]`)?.classList.add('play');
      lit = new Set(keys);
    });
  }, []);
  // Centre around middle C on first show.
  useEffect(() => {
    const c4 = ref.current?.querySelector('[data-key="60"]') as HTMLElement | null;
    if (c4 && ref.current) ref.current.scrollLeft = c4.offsetLeft - ref.current.clientWidth / 2;
  }, []);

  const press = (key: number, e: React.MouseEvent) => {
    e.preventDefault();
    const s = getState();
    if (s.input.active || s.selection.kind !== 'none') A.enterMidiPitch(key, e.shiftKey);
    else player.preview([key], s.score.parts[0]?.program ?? 0);
  };

  const whites: number[] = [];
  for (let k = LOW; k <= HIGH; k++) if (!isBlack(k)) whites.push(k);
  return (
    <div className="piano" ref={ref} title="Щелчок — нота в позицию курсора (Shift — в аккорд); без режима ввода — прослушивание">
      <div className="piano-inner" style={{ width: whites.length * 24 }}>
        {whites.map((k, i) => (
          <div key={k} className="pk white" data-key={k} style={{ left: i * 24 }} onMouseDown={(e) => press(k, e)}>
            {k % 12 === 0 && <span>C{k / 12 - 1}</span>}
          </div>
        ))}
        {Array.from({ length: HIGH - LOW + 1 }, (_, i) => LOW + i)
          .filter(isBlack)
          .map((k) => {
            const leftWhite = whites.indexOf(k - 1);
            return <div key={k} className="pk black" data-key={k} title={NAMES[k % 12]} style={{ left: leftWhite * 24 + 16 }} onMouseDown={(e) => press(k, e)} />;
          })}
      </div>
    </div>
  );
}
