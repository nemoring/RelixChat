import { useEffect, useRef, useState } from 'react';
import { commands, runCommand } from '../input/commands';
import { useStore } from '../state/store';
import { player } from '../playback/player';

type Item = string | '-';
const MENUS: { title: string; items: Item[] }[] = [
  { title: 'Файл', items: ['file.new', 'file.open', '-', 'file.save', 'file.saveAs', '-', 'export.midi', 'export.wav', '-', 'file.info'] },
  {
    title: 'Правка',
    items: ['edit.undo', 'edit.redo', '-', 'edit.cut', 'edit.copy', 'edit.paste', 'edit.delete', '-', 'edit.selectAll', '-', 'edit.up', 'edit.down', 'edit.octUp', 'edit.octDown', '-', 'edit.goto'],
  },
  { title: 'Вид', items: ['view.zoomIn', 'view.zoomOut', 'view.zoom100', '-', 'view.page', 'view.continuous', '-', 'view.palette'] },
  {
    title: 'Вставка',
    items: [
      'input.toggle', '-', 'measure.append', 'measure.insert', 'measure.many', 'measure.delete', '-',
      'tuplet.3', 'tuplet.5', 'tuplet.6', 'tuplet.other', 'tuplet.remove', '-',
      'grace.acc', 'grace.app', '-', 'line.slur', 'line.cresc', 'line.dim', 'line.pedal', 'line.8va', 'line.8vb', 'line.remove', '-',
      'rep.start', 'rep.end', 'rep.times', 'rep.volta1', 'rep.volta2', 'rep.voltaN', '-', 'mk.segno', 'mk.coda', 'mk.toCoda', 'mk.fine', 'jump.DC', 'jump.DCalFine', 'jump.DS', 'jump.DSalCoda', '-', 'tempo.change',
    ],
  },
  {
    title: 'Формат',
    items: [
      'format.timeSig', '-', 'acc.sharp', 'acc.flat', 'acc.natural', 'acc.dsharp', 'acc.dflat', '-',
      'art.staccato', 'art.tenuto', 'art.accent', 'art.marcato', 'art.fermata', '-', 'orn.trill', 'orn.mordent', 'orn.turn', '-',
      'staff.up', 'staff.down', 'stem.flip', 'beam.break', 'beam.join', 'beam.none', '-', 'bar.double', 'bar.final', '-', 'format.page',
    ],
  },
  { title: 'Мелодия', items: ['melody.assign', 'melody.remove', 'melody.new', '-', 'melody.show', '-', 'melody.solo', 'melody.accomp', 'melody.all'] },
  { title: 'Воспроизведение', items: ['play.toggle', 'play.stop', 'play.restart', 'play.selection', '-', 'play.loop', 'play.metronome', '-', 'play.faster', 'play.slower', 'play.speed100', '-', 'play.mixer', 'play.soundfont'] },
  { title: 'Инструменты', items: ['tools.transpose', 'tools.stats'] },
  { title: 'Справка', items: ['help.shortcuts', 'help.about'] },
];

export function MenuBar() {
  const [open, setOpen] = useState<number | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  // Re-render on state changes so enabled/disabled items stay current.
  useStore((s) => s.selection);
  useStore((s) => s.past.length);
  useStore((s) => s.future.length);
  const viewMode = useStore((s) => s.view.mode);
  const showLines = useStore((s) => s.view.showLines);

  useEffect(() => {
    const close = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(null);
    };
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(null);
    window.addEventListener('mousedown', close);
    window.addEventListener('keydown', esc);
    return () => {
      window.removeEventListener('mousedown', close);
      window.removeEventListener('keydown', esc);
    };
  }, []);

  return (
    <div className="menubar" ref={ref}>
      <div className="brand">NoteForge</div>
      {MENUS.map((menu, i) => (
        <div key={menu.title} className={`menu${open === i ? ' open' : ''}`}>
          <button className="menu-title" onMouseDown={() => setOpen(open === i ? null : i)} onMouseEnter={() => open !== null && setOpen(i)}>
            {menu.title}
          </button>
          {open === i && (
            <div className="menu-dropdown">
              {menu.items.map((id, k) => {
                if (id === '-') return <div key={k} className="menu-sep" />;
                const c = commands.get(id)!;
                const disabled = c.enabled ? !c.enabled() : false;
                const checked =
                  (id === 'view.page' && viewMode === 'page') ||
                  (id === 'view.continuous' && viewMode === 'continuous') ||
                  (id === 'play.loop' && player.state.loop) ||
                  (id === 'play.metronome' && player.state.metronome) ||
                  (id === 'melody.show' && showLines);
                return (
                  <button
                    key={id}
                    className="menu-item"
                    disabled={disabled}
                    onClick={() => {
                      setOpen(null);
                      runCommand(id);
                    }}
                  >
                    <span className="check">{checked ? '✓' : ''}</span>
                    <span className="label">{c.label}</span>
                    <span className="shortcut">{c.keys[0] ?? ''}</span>
                  </button>
                );
              })}
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
