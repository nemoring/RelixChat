import { useStore } from '../state/store';
import { findEvent, keyAt, timeSigAt } from '../model/query';
import { keyName, pitchName } from '../model/pitch';
import { durationName } from '../model/duration';
import { div, fracToString, add, frac } from '../model/fraction';
import * as A from '../state/actions';

function beatLabel(pos: { n: number; d: number }, unit: number): string {
  // 1-based beat number in units of the time signature denominator.
  const beats = div(pos, frac(1, unit));
  const b = add(beats, frac(1));
  return fracToString(b);
}

export function StatusBar() {
  const s = useStore((x) => x);
  const { score, selection, input, cursor, view } = s;
  let pos = '';
  if (input.active && cursor) {
    const ts = timeSigAt(score, cursor.measure);
    pos = `Курсор: такт ${cursor.measure + 1}, доля ${beatLabel(cursor.time, ts.unit)} · нотоносец ${cursor.staff + 1} · голос ${cursor.voice + 1}`;
  } else if (selection.kind === 'event') {
    const f = findEvent(score, selection.eventId, selection);
    if (f) {
      const ts = timeSigAt(score, f.measure);
      const what = f.ev.type === 'rest' ? 'Пауза' : f.ev.notes.length > 1 && !selection.noteId ? `Аккорд (${f.ev.notes.map(pitchName).join(' ')})` : `Нота ${pitchName(f.ev.notes.find((n) => n.id === selection.noteId) ?? f.ev.notes[0])}`;
      pos = `${what}, ${durationName(f.ev.dur)} · такт ${f.measure + 1}, доля ${beatLabel(f.start, ts.unit)} · нотоносец ${f.staff + 1} · голос ${f.voice + 1}`;
    }
  } else if (selection.kind === 'range') {
    pos = `Такты ${selection.mFrom + 1}–${selection.mTo + 1} · нотоносцы ${selection.staffFrom + 1}–${selection.staffTo + 1}`;
  }
  const m = input.active && cursor ? cursor.measure : selection.kind === 'event' ? selection.measure : selection.kind === 'range' ? selection.mFrom : 0;
  const ts = timeSigAt(score, m);
  return (
    <footer className="statusbar">
      <span className={`mode ${input.active ? 'input' : ''}`}>{input.active ? 'ВВОД' : 'ВЫДЕЛЕНИЕ'}</span>
      {input.active && (
        <span>
          {durationName(input.dur)} · голос {input.voice + 1}
        </span>
      )}
      <span className="pos">{pos || s.status}</span>
      <span className="spacer" />
      <span title="Размер в позиции">{ts.count}/{ts.unit}</span>
      <span title="Тональность в позиции">{keyName(keyAt(score, m))}</span>
      <span title="Темп">♩ = {score.tempo.bpm}</span>
      <span>Тактов: {score.measures.length}</span>
      <span className="zoom">
        <button onClick={() => A.zoomBy(1 / 1.15)}>−</button>
        <button className="zoom-value" onClick={() => A.setZoom(1)} title="Сбросить масштаб">
          {Math.round(view.zoom * 100)}%
        </button>
        <button onClick={() => A.zoomBy(1.15)}>+</button>
      </span>
      <span className="view-switch">
        <button className={view.mode === 'page' ? 'active' : ''} onClick={() => A.setViewMode('page')}>
          Страницы
        </button>
        <button className={view.mode === 'continuous' ? 'active' : ''} onClick={() => A.setViewMode('continuous')}>
          Лента
        </button>
      </span>
    </footer>
  );
}
