import { useState } from 'react';
import * as A from '../state/actions';
import { keyName } from '../model/pitch';
import type { ClefKind, TimeSig } from '../model/types';
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

function Section({ title, children, initiallyOpen = true }: { title: string; children: React.ReactNode; initiallyOpen?: boolean }) {
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

export function Palette() {
  const hasTarget = useStore((s) => s.selection.kind !== 'none' || s.cursor !== null);
  return (
    <aside className="palette">
      <div className="palette-hint">{hasTarget ? 'Применяется к выделенному такту / нотоносцу' : 'Без выделения применяется к началу партитуры'}</div>
      <Section title="Ключи">
        {CLEFS.map((c) => (
          <button key={c.clef} className="pal-item" title={`${c.name} ключ (начальный ключ нотоносца)`} onClick={() => A.applyClef(c.clef)}>
            <span className="music big">{c.glyph}</span>
            <small>{c.name}</small>
          </button>
        ))}
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
        <button className="pal-item" title="Произвольный размер" onClick={() => A.openDialog('timeSig')}>
          <span className="timesig-sym">?</span>
          <small>Другой…</small>
        </button>
      </Section>
    </aside>
  );
}
