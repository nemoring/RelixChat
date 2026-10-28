import { useStore } from '../state/store';
import { runCommand, commands } from '../input/commands';
import { NoteIcon, RestIcon } from './icons';
import type { DurBase } from '../model/types';
import { findEvent } from '../model/query';

const DURS: DurBase[] = [1, 2, 4, 8, 16, 32, 64];
const ACCS: { id: string; glyph: string; alter: number }[] = [
  { id: 'acc.dflat', glyph: '𝄫', alter: -2 },
  { id: 'acc.flat', glyph: '♭', alter: -1 },
  { id: 'acc.natural', glyph: '♮', alter: 0 },
  { id: 'acc.sharp', glyph: '♯', alter: 1 },
  { id: 'acc.dsharp', glyph: '𝄪', alter: 2 },
];

function tip(id: string) {
  const c = commands.get(id)!;
  return c.keys.length ? `${c.label} (${c.keys[0]})` : c.label;
}

export function Toolbar() {
  const input = useStore((s) => s.input);
  const selection = useStore((s) => s.selection);
  const score = useStore((s) => s.score);
  const canUndo = useStore((s) => s.past.length > 0);
  const canRedo = useStore((s) => s.future.length > 0);

  // Duration shown as active: input duration in input mode, otherwise the selected event's.
  let shownDur = input.dur;
  let selAlter: number | null = null;
  if (selection.kind === 'event') {
    const f = findEvent(score, selection.eventId, selection);
    if (f) {
      if (!input.active) shownDur = f.ev.dur;
      if (f.ev.type === 'chord') {
        const n = selection.noteId ? f.ev.notes.find((x) => x.id === selection.noteId) : f.ev.notes.length === 1 ? f.ev.notes[0] : undefined;
        if (n) selAlter = n.alter;
      }
    }
  }

  return (
    <div className="toolbar">
      <div className="tool-group">
        <button className={`tool wide${input.active ? ' active' : ''}`} title={tip('input.toggle')} onClick={() => runCommand('input.toggle')}>
          <NoteIcon base={4} size={18} /> <span>Ввод</span>
        </button>
      </div>
      <div className="tool-group">
        {DURS.map((b) => (
          <button key={b} className={`tool${shownDur.base === b ? ' active' : ''}`} title={tip(`dur.${b}`)} onClick={() => runCommand(`dur.${b}`)}>
            <NoteIcon base={b} />
          </button>
        ))}
        <button className={`tool${shownDur.dots ? ' active' : ''}`} title={tip('dur.dot')} onClick={() => runCommand('dur.dot')}>
          <span className="glyph">•</span>
        </button>
        <button className="tool" title={tip('input.rest')} onClick={() => runCommand('input.rest')}>
          <RestIcon />
        </button>
      </div>
      <div className="tool-group">
        {ACCS.map((a) => (
          <button key={a.id} className={`tool${selAlter === a.alter && a.alter !== 0 ? ' active' : ''}`} title={tip(a.id)} disabled={selection.kind === 'none'} onClick={() => runCommand(a.id)}>
            <span className="glyph music">{a.glyph}</span>
          </button>
        ))}
        <button className="tool" title={tip('input.tie')} disabled={selection.kind !== 'event'} onClick={() => runCommand('input.tie')}>
          <span className="glyph">‿</span>
        </button>
      </div>
      <div className="tool-group">
        {[0, 1, 2, 3].map((v) => (
          <button key={v} className={`tool voice voice-${v + 1}${input.voice === v ? ' active' : ''}`} title={tip(`voice.${v + 1}`)} onClick={() => runCommand(`voice.${v + 1}`)}>
            {v + 1}
          </button>
        ))}
      </div>
      <div className="tool-group">
        <button className="tool" title={tip('edit.undo')} disabled={!canUndo} onClick={() => runCommand('edit.undo')}>
          ↶
        </button>
        <button className="tool" title={tip('edit.redo')} disabled={!canRedo} onClick={() => runCommand('edit.redo')}>
          ↷
        </button>
      </div>
      <div className="tool-group">
        <button className="tool wide" title={tip('measure.append')} onClick={() => runCommand('measure.append')}>
          + такт
        </button>
        <button className="tool wide" title={tip('measure.delete')} disabled={selection.kind === 'none'} onClick={() => runCommand('measure.delete')}>
          − такт
        </button>
      </div>
    </div>
  );
}
