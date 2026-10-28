import { useState } from 'react';
import * as A from '../state/actions';
import * as N from '../state/notation';
import { runCommand } from '../input/commands';
import { keyName } from '../model/pitch';
import type { ClefKind, TimeSig } from '../model/types';
import { DYNAMICS } from '../model/types';
import { useStore } from '../state/store';

const CLEFS: { clef: ClefKind; glyph: string; name: string }[] = [
  { clef: 'treble', glyph: '𝄞', name: 'Скрипичный' },
  { clef: 'bass', glyph: '𝄢', name: 'Басовый' },
  { clef: 'alto', glyph: '𝄡', name: 'Альтовый' },
  { clef: 'tenor', glyph: '𝄡', name: 'Теноровый' },
  { clef: 'treble8vb', glyph: '𝄠', name: 'Скрипичный 8vb' },
];

const TIMES: (TimeSig & { label?: string })[] = [
  { count: 2, unit: 4 },
  { count: 3, unit: 4 },
  { count: 4, unit: 4 },
  { count: 4, unit: 4, symbol: 'common', label: 'C' },
  { count: 2, unit: 2, symbol: 'cut', label: '¢' },
  { count: 5, unit: 4 },
  { count: 3, unit: 8 },
  { count: 6, unit: 8 },
  { count: 7, unit: 8 },
  { count: 9, unit: 8 },
  { count: 12, unit: 8 },
  { count: 2, unit: 2 },
];

const TEMPI = [
  { text: 'Grave', bpm: 40 },
  { text: 'Largo', bpm: 50 },
  { text: 'Adagio', bpm: 70 },
  { text: 'Andante', bpm: 90 },
  { text: 'Moderato', bpm: 110 },
  { text: 'Allegro', bpm: 130 },
  { text: 'Vivace', bpm: 156 },
  { text: 'Presto', bpm: 180 },
];

function Section({ title, children, initiallyOpen = false }: { title: string; children: React.ReactNode; initiallyOpen?: boolean }) {
  const [open, setOpen] = useState(initiallyOpen);
  return (
    <div className={`palette-section${open ? ' open' : ''}`}>
      <button className="palette-title" onClick={() => setOpen(!open)}>
        <span>{open ? '▾' : '▸'}</span> {title}
      </button>
      {open && <div className="palette-grid">{children}</div>}
    </div>
  );
}

/** Palette cell that runs a registered command (so the tooltip shows the real shortcut). */
function Cmd({ id, glyph, label, cls }: { id: string; glyph: React.ReactNode; label: string; cls?: string }) {
  return (
    <button className="pal-item" title={label} onClick={() => runCommand(id)}>
      <span className={cls ?? 'pal-glyph'}>{glyph}</span>
      <small>{label}</small>
    </button>
  );
}

function MelodyPanel() {
  const lines = useStore((s) => s.score.lines);
  const active = useStore((s) => s.input.line);
  const show = useStore((s) => s.view.showLines);
  return (
    <div className="melody-panel">
      <div className="melody-head">
        <b>Мелодические линии</b>
        <label className="check" title="Показывать линии на листе">
          <input type="checkbox" checked={show} onChange={N.toggleShowLines} /> видно
        </label>
      </div>
      {lines.map((l) => (
        <div key={l.id} className={`melody-row${active === l.id ? ' active' : ''}`}>
          <input type="color" value={l.color} title="Цвет" onChange={(e) => N.recolorLine(l.id, e.target.value)} />
          <span className="melody-name" title="Двойной щелчок — переименовать" onDoubleClick={() => {
            const name = window.prompt('Название линии', l.name);
            if (name) N.renameLine(l.id, name);
          }}>
            {l.name}
          </span>
          <button className={`small${active === l.id ? ' on' : ''}`} title="Новые ноты будут попадать в эту линию" onClick={() => N.setInputLine(active === l.id ? null : l.id)}>
            ввод
          </button>
          <button className="small" title="Добавить выделенное в эту линию (M)" onClick={() => N.assignLine(l.id)}>
            +
          </button>
          <button className="small" title="Выделить все ноты линии" onClick={() => N.selectLine(l.id)}>
            ⌖
          </button>
          <button className="small" title="Удалить линию" onClick={() => N.deleteLine(l.id)}>
            ×
          </button>
        </div>
      ))}
      <div className="melody-actions">
        <button className="small" onClick={N.createLine}>
          + линия
        </button>
        <button className="small" onClick={() => N.assignLine(null)} title="Shift+M">
          убрать из мелодии
        </button>
      </div>
      <div className="melody-actions">
        <span className="hint-inline">Слушать:</span>
        <button className="small" onClick={() => N.listen('melody')}>
          мелодию
        </button>
        <button className="small" onClick={() => N.listen('accomp')}>
          аккомп.
        </button>
        <button className="small" onClick={() => N.listen('all')}>
          всё
        </button>
      </div>
    </div>
  );
}

export function Palette() {
  const hasTarget = useStore((s) => s.selection.kind !== 'none' || s.cursor !== null);
  return (
    <aside className="palette">
      <MelodyPanel />
      <div className="palette-hint">{hasTarget ? 'Применяется к выделению' : 'Выделите ноту, фрагмент (Shift+щелчок) или такт'}</div>
      <Section title="Ключи">
        {CLEFS.map((c) => (
          <button key={c.clef} className="pal-item" title={`${c.name} ключ (с выделенного такта)`} onClick={() => A.applyClef(c.clef)}>
            <span className="music big">{c.glyph}</span>
            <small>{c.name}</small>
          </button>
        ))}
        <button className="pal-item" title="Удалить смену ключа в выделенном такте" onClick={N.removeClefChange}>
          <span className="pal-glyph">×</span>
          <small>без смены</small>
        </button>
      </Section>
      <Section title="Тональности">
        {Array.from({ length: 15 }, (_, i) => i - 7).map((f) => (
          <button key={f} className="pal-item" title={keyName(f)} onClick={() => A.applyKeySig(f)}>
            <span className="keysig">{f === 0 ? '—' : `${Math.abs(f)}${f > 0 ? '♯' : '♭'}`}</span>
            <small>{keyName(f).split(' / ')[0]}</small>
          </button>
        ))}
      </Section>
      <Section title="Размеры">
        {TIMES.map((t, i) => (
          <button key={i} className="pal-item" title={`Размер ${t.count}/${t.unit}`} onClick={() => A.applyTimeSig({ count: t.count, unit: t.unit, ...(t.symbol ? { symbol: t.symbol } : {}) })}>
            {t.label ? (
              <span className="timesig-sym">{t.label}</span>
            ) : (
              <span className="timesig">
                <b>{t.count}</b>
                <b>{t.unit}</b>
              </span>
            )}
          </button>
        ))}
        <Cmd id="format.timeSig" glyph="?" label="Другой…" cls="timesig-sym" />
      </Section>
      <Section title="Артикуляция" initiallyOpen>
        <Cmd id="art.staccato" glyph="•" label="Стаккато" />
        <Cmd id="art.staccatissimo" glyph="▾" label="Стаккатиссимо" />
        <Cmd id="art.tenuto" glyph="—" label="Тенуто" />
        <Cmd id="art.accent" glyph=">" label="Акцент" />
        <Cmd id="art.marcato" glyph="^" label="Маркато" />
        <Cmd id="art.fermata" glyph="𝄐" label="Фермата" cls="music big" />
      </Section>
      <Section title="Динамика" initiallyOpen>
        {DYNAMICS.map((d) => (
          <button key={d} className="pal-item" title={`Динамика ${d}`} onClick={() => N.dynamic(d)}>
            <span className="dyn">{d}</span>
          </button>
        ))}
        <Cmd id="line.cresc" glyph="<" label="Crescendo" cls="dyn" />
        <Cmd id="line.dim" glyph=">" label="Diminuendo" cls="dyn" />
      </Section>
      <Section title="Линии">
        <Cmd id="line.slur" glyph="⌒" label="Лига" />
        <Cmd id="line.pedal" glyph="Ped." label="Педаль" cls="dyn small-dyn" />
        <Cmd id="line.8va" glyph="8va" label="8va" cls="dyn small-dyn" />
        <Cmd id="line.8vb" glyph="8vb" label="8vb" cls="dyn small-dyn" />
        <Cmd id="line.15ma" glyph="15ma" label="15ma" cls="dyn small-dyn" />
        <Cmd id="line.15mb" glyph="15mb" label="15mb" cls="dyn small-dyn" />
        <Cmd id="line.remove" glyph="×" label="Удалить линии" />
      </Section>
      <Section title="Орнаменты и форшлаги">
        <Cmd id="orn.trill" glyph="tr" label="Трель" cls="dyn" />
        <Cmd id="orn.mordent" glyph="𝆘" label="Мордент" cls="music big" />
        <Cmd id="orn.invertedMordent" glyph="𝆗" label="Пралльтриллер" cls="music big" />
        <Cmd id="orn.turn" glyph="∽" label="Группетто" />
        <Cmd id="orn.invertedTurn" glyph="∼" label="Обращённое" />
        <Cmd id="grace.acc" glyph="𝆔" label="Форшлаг" cls="music big" />
        <Cmd id="grace.app" glyph="𝆕" label="Апподжиатура" cls="music big" />
      </Section>
      <Section title="Ритмические группы">
        <Cmd id="tuplet.2" glyph="2" label="Дуоль" />
        <Cmd id="tuplet.3" glyph="3" label="Триоль" />
        <Cmd id="tuplet.4" glyph="4" label="Квартоль" />
        <Cmd id="tuplet.5" glyph="5" label="Квинтоль" />
        <Cmd id="tuplet.6" glyph="6" label="Секстоль" />
        <Cmd id="tuplet.7" glyph="7" label="Септоль" />
        <Cmd id="tuplet.other" glyph="n:m" label="Другая…" />
        <Cmd id="tuplet.remove" glyph="×" label="Удалить" />
      </Section>
      <Section title="Повторы и переходы">
        <Cmd id="rep.start" glyph="𝄆" label="Начало повтора" cls="music big" />
        <Cmd id="rep.end" glyph="𝄇" label="Конец повтора" cls="music big" />
        <Cmd id="rep.times" glyph="×n" label="Повторить n раз" />
        <Cmd id="rep.volta1" glyph="1." label="Вольта 1" />
        <Cmd id="rep.volta2" glyph="2." label="Вольта 2" />
        <Cmd id="rep.voltaN" glyph="n." label="Вольта…" />
        <Cmd id="mk.segno" glyph="𝄋" label="Сеньо" cls="music big" />
        <Cmd id="mk.coda" glyph="𝄌" label="Кода" cls="music big" />
        <Cmd id="mk.toCoda" glyph="→𝄌" label="To Coda" cls="music" />
        <Cmd id="mk.fine" glyph="Fine" label="Fine" cls="dyn small-dyn" />
        <Cmd id="jump.DC" glyph="D.C." label="Da Capo" cls="dyn small-dyn" />
        <Cmd id="jump.DCalFine" glyph="D.C. al Fine" label="D.C. al Fine" cls="dyn tiny-dyn" />
        <Cmd id="jump.DCalCoda" glyph="D.C. al Coda" label="D.C. al Coda" cls="dyn tiny-dyn" />
        <Cmd id="jump.DS" glyph="D.S." label="Dal Segno" cls="dyn small-dyn" />
        <Cmd id="jump.DSalFine" glyph="D.S. al Fine" label="D.S. al Fine" cls="dyn tiny-dyn" />
        <Cmd id="jump.DSalCoda" glyph="D.S. al Coda" label="D.S. al Coda" cls="dyn tiny-dyn" />
        <Cmd id="bar.double" glyph="‖" label="Двойная черта" />
        <Cmd id="bar.final" glyph="𝄂" label="Конечная черта" cls="music big" />
      </Section>
      <Section title="Темп">
        {TEMPI.map((t) => (
          <button key={t.text} className="pal-item" title={`${t.text}, ♩ = ${t.bpm} (с выделенного такта)`} onClick={() => N.tempoChange({ bpm: t.bpm, beatUnit: 4, beatDots: 0, text: t.text })}>
            <span className="tempo-txt">{t.text}</span>
            <small>♩ = {t.bpm}</small>
          </button>
        ))}
        <Cmd id="tempo.change" glyph="♩=?" label="Другой…" />
      </Section>
      <Section title="Штили, рёбра, нотоносцы">
        <Cmd id="stem.flip" glyph="↕" label="Штиль" />
        <Cmd id="beam.break" glyph="⌐" label="Новое ребро" />
        <Cmd id="beam.join" glyph="═" label="Соединить" />
        <Cmd id="beam.none" glyph="♪" label="Без ребра" />
        <Cmd id="staff.up" glyph="⤒" label="На верхний стан" />
        <Cmd id="staff.down" glyph="⤓" label="На нижний стан" />
      </Section>
    </aside>
  );
}
