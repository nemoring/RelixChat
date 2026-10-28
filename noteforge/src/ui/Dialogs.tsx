import { useEffect, useMemo, useRef, useState } from 'react';
import { useStore, getState } from '../state/store';
import * as A from '../state/actions';
import { commands } from '../input/commands';
import { keyName } from '../model/pitch';
import { computeStats, formatDuration } from '../model/stats';
import { APP_VERSION } from '../model/serialize';
import type { PageLayout } from '../model/types';
import { Mixer } from './Transport';
import * as P from '../state/playback';

function Modal({ title, children, onSubmit, submitLabel = 'OK', wide }: { title: string; children: React.ReactNode; onSubmit?: () => void; submitLabel?: string; wide?: boolean }) {
  const ref = useRef<HTMLFormElement>(null);
  useEffect(() => {
    const el = ref.current?.querySelector<HTMLElement>('input, select, button.primary');
    el?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        A.closeDialog();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
  return (
    <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && A.closeDialog()}>
      <form
        ref={ref}
        className={`modal${wide ? ' wide' : ''}`}
        onSubmit={(e) => {
          e.preventDefault();
          if (onSubmit) onSubmit();
          else A.closeDialog();
        }}
      >
        <h2>{title}</h2>
        <div className="modal-body">{children}</div>
        <div className="modal-actions">
          {onSubmit && (
            <button type="button" onClick={A.closeDialog}>
              Отмена
            </button>
          )}
          <button type="submit" className="primary">
            {submitLabel}
          </button>
        </div>
      </form>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}

const KEYS = Array.from({ length: 15 }, (_, i) => i - 7);
const UNITS = [1, 2, 4, 8, 16, 32];

function NewScoreDialog() {
  const [title, setTitle] = useState('Без названия');
  const [composer, setComposer] = useState('');
  const [count, setCount] = useState(4);
  const [unit, setUnit] = useState(4);
  const [key, setKey] = useState(0);
  const [measures, setMeasures] = useState(32);
  const [bpm, setBpm] = useState(100);
  return (
    <Modal
      title="Новая партитура для фортепиано"
      submitLabel="Создать"
      onSubmit={() => {
        A.closeDialog();
        void A.newScore({ title, composer, timeSig: { count, unit }, keySig: key, measures, bpm });
      }}
    >
      <Field label="Название">
        <input value={title} onChange={(e) => setTitle(e.target.value)} />
      </Field>
      <Field label="Композитор">
        <input value={composer} onChange={(e) => setComposer(e.target.value)} />
      </Field>
      <div className="row">
        <Field label="Размер">
          <span className="inline">
            <input type="number" min={1} max={64} value={count} onChange={(e) => setCount(Number(e.target.value))} />/
            <select value={unit} onChange={(e) => setUnit(Number(e.target.value))}>
              {UNITS.map((u) => (
                <option key={u}>{u}</option>
              ))}
            </select>
          </span>
        </Field>
        <Field label="Тональность">
          <select value={key} onChange={(e) => setKey(Number(e.target.value))}>
            {KEYS.map((k) => (
              <option key={k} value={k}>
                {keyName(k)}
              </option>
            ))}
          </select>
        </Field>
      </div>
      <div className="row">
        <Field label="Тактов">
          <input type="number" min={1} max={20000} value={measures} onChange={(e) => setMeasures(Number(e.target.value))} />
        </Field>
        <Field label="Темп (♩ в минуту)">
          <input type="number" min={10} max={500} value={bpm} onChange={(e) => setBpm(Number(e.target.value))} />
        </Field>
      </div>
    </Modal>
  );
}

function ScoreInfoDialog() {
  const score = getState().score;
  const [meta, setMeta] = useState({ ...score.meta });
  const [tempo, setTempo] = useState({ ...score.tempo });
  const set = (k: keyof typeof meta) => (e: React.ChangeEvent<HTMLInputElement>) => setMeta({ ...meta, [k]: e.target.value });
  return (
    <Modal
      title="Свойства партитуры"
      onSubmit={() => {
        A.closeDialog();
        A.updateScore('Свойства партитуры', (d) => {
          d.meta = meta;
          d.tempo = { ...tempo, bpm: Math.max(10, Math.min(500, tempo.bpm || 100)) };
        });
      }}
    >
      <Field label="Название">
        <input value={meta.title} onChange={set('title')} />
      </Field>
      <Field label="Подзаголовок">
        <input value={meta.subtitle} onChange={set('subtitle')} />
      </Field>
      <div className="row">
        <Field label="Композитор">
          <input value={meta.composer} onChange={set('composer')} />
        </Field>
        <Field label="Аранжировщик">
          <input value={meta.arranger} onChange={set('arranger')} />
        </Field>
      </div>
      <div className="row">
        <Field label="Автор текста / посвящение">
          <input value={meta.lyricist} onChange={set('lyricist')} />
        </Field>
        <Field label="Авторские права">
          <input value={meta.copyright} onChange={set('copyright')} />
        </Field>
      </div>
      <div className="row">
        <Field label="Обозначение темпа">
          <input value={tempo.text} placeholder="напр. Allegro moderato" onChange={(e) => setTempo({ ...tempo, text: e.target.value })} />
        </Field>
        <Field label="Метроном">
          <span className="inline">
            <select value={`${tempo.beatUnit}:${tempo.beatDots}`} onChange={(e) => {
              const [u, d] = e.target.value.split(':').map(Number);
              setTempo({ ...tempo, beatUnit: u, beatDots: d });
            }}>
              <option value="2:0">𝅗𝅥</option>
              <option value="4:0">♩</option>
              <option value="4:1">♩.</option>
              <option value="8:0">♪</option>
            </select>
            =
            <input type="number" min={10} max={500} value={tempo.bpm} onChange={(e) => setTempo({ ...tempo, bpm: Number(e.target.value) })} />
          </span>
        </Field>
      </div>
    </Modal>
  );
}

function TimeSigDialog() {
  const [count, setCount] = useState(5);
  const [unit, setUnit] = useState(8);
  const sel = getState().selection;
  const where = sel.kind === 'event' ? sel.measure + 1 : sel.kind === 'range' ? sel.mFrom + 1 : 1;
  return (
    <Modal
      title="Размер"
      submitLabel="Применить"
      onSubmit={() => {
        A.closeDialog();
        A.applyTimeSig({ count: Math.max(1, Math.min(64, count)), unit });
      }}
    >
      <p className="hint">Размер устанавливается с такта {where}. Музыка до следующей смены размера будет перегруппирована по новым тактам, ноты на границах — залигованы.</p>
      <Field label="Размер">
        <span className="inline">
          <input type="number" min={1} max={64} value={count} onChange={(e) => setCount(Number(e.target.value))} />/
          <select value={unit} onChange={(e) => setUnit(Number(e.target.value))}>
            {UNITS.map((u) => (
              <option key={u}>{u}</option>
            ))}
          </select>
        </span>
      </Field>
    </Modal>
  );
}

function MeasuresDialog() {
  const [n, setN] = useState(4);
  const [where, setWhere] = useState<'append' | 'insert'>('append');
  return (
    <Modal
      title="Такты"
      submitLabel="Добавить"
      onSubmit={() => {
        A.closeDialog();
        const k = Math.max(1, Math.min(5000, n));
        if (where === 'append') A.appendMeasures(k);
        else A.insertMeasures(k);
      }}
    >
      <Field label="Количество">
        <input type="number" min={1} max={5000} value={n} onChange={(e) => setN(Number(e.target.value))} />
      </Field>
      <Field label="Куда">
        <select value={where} onChange={(e) => setWhere(e.target.value as 'append' | 'insert')}>
          <option value="append">В конец партитуры</option>
          <option value="insert">Перед выделенным тактом</option>
        </select>
      </Field>
    </Modal>
  );
}

function GotoDialog() {
  const total = getState().score.measures.length;
  const [n, setN] = useState(1);
  return (
    <Modal
      title="Перейти к такту"
      submitLabel="Перейти"
      onSubmit={() => {
        A.closeDialog();
        A.gotoMeasure(n);
      }}
    >
      <Field label={`Номер такта (1–${total})`}>
        <input type="number" min={1} max={total} value={n} onChange={(e) => setN(Number(e.target.value))} />
      </Field>
    </Modal>
  );
}

function StatsDialog() {
  const score = getState().score;
  const st = useMemo(() => computeStats(score), [score]);
  return (
    <Modal title="Статистика произведения">
      <table className="stats">
        <tbody>
          <tr><td>Тактов</td><td>{st.measures}</td></tr>
          <tr><td>Нот</td><td>{st.notes}</td></tr>
          <tr><td>Аккордов / одиночных нот (событий)</td><td>{st.chords}</td></tr>
          <tr><td>Пауз</td><td>{st.rests}</td></tr>
          <tr><td>Длительность при ♩ = {score.tempo.bpm}</td><td>{formatDuration(st.seconds)}</td></tr>
          <tr><td>Диапазон</td><td>{st.lowest ? `${st.lowest} – ${st.highest}` : '—'}</td></tr>
          {st.perStaff.map((p, i) => (
            <tr key={i}>
              <td>{i === 0 ? 'Правая рука (верхний стан)' : i === 1 ? 'Левая рука (нижний стан)' : `Нотоносец ${i + 1}`}</td>
              <td>{p.notes} нот{p.lowest ? `, ${p.lowest} – ${p.highest}` : ''}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="hint">Длительность рассчитана без учёта повторов и изменений темпа.</p>
    </Modal>
  );
}

function PageSetupDialog() {
  const [layout, setLayout] = useState<PageLayout>(structuredClone(getState().score.layout));
  const setMargin = (k: keyof PageLayout['margins']) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setLayout({ ...layout, margins: { ...layout.margins, [k]: Math.max(0, Math.min(80, Number(e.target.value))) } });
  return (
    <Modal
      title="Параметры страницы"
      onSubmit={() => {
        A.closeDialog();
        A.updateScore('Параметры страницы', (d) => {
          d.layout = { ...layout, staffScale: Math.max(40, Math.min(200, layout.staffScale)) };
        });
      }}
    >
      <div className="row">
        <Field label="Формат">
          <select value={layout.size} onChange={(e) => setLayout({ ...layout, size: e.target.value as PageLayout['size'] })}>
            <option value="A4">A4 (210 × 297 мм)</option>
            <option value="A3">A3 (297 × 420 мм)</option>
            <option value="Letter">Letter (216 × 279 мм)</option>
          </select>
        </Field>
        <Field label="Ориентация">
          <select value={layout.orientation} onChange={(e) => setLayout({ ...layout, orientation: e.target.value as PageLayout['orientation'] })}>
            <option value="portrait">Книжная</option>
            <option value="landscape">Альбомная</option>
          </select>
        </Field>
      </div>
      <div className="row">
        <Field label="Поле сверху, мм"><input type="number" value={layout.margins.top} onChange={setMargin('top')} /></Field>
        <Field label="Снизу, мм"><input type="number" value={layout.margins.bottom} onChange={setMargin('bottom')} /></Field>
        <Field label="Слева, мм"><input type="number" value={layout.margins.left} onChange={setMargin('left')} /></Field>
        <Field label="Справа, мм"><input type="number" value={layout.margins.right} onChange={setMargin('right')} /></Field>
      </div>
      <Field label="Размер нотного стана, %">
        <input type="number" min={40} max={200} value={layout.staffScale} onChange={(e) => setLayout({ ...layout, staffScale: Number(e.target.value) })} />
      </Field>
    </Modal>
  );
}

function ShortcutsDialog() {
  const groups = new Map<string, { label: string; keys: string[] }[]>();
  for (const c of commands.values()) {
    if (!c.keys.length) continue;
    if (!groups.has(c.group)) groups.set(c.group, []);
    groups.get(c.group)!.push({ label: c.label, keys: c.keys });
  }
  return (
    <Modal title="Горячие клавиши" wide>
      <p className="hint">Буквы A–G вводят ноты в режиме ввода (N). Клавиши работают и в русской раскладке. Мышью в режиме ввода: щелчок по нотоносцу ставит ноту, Shift+щелчок добавляет её в аккорд.</p>
      <div className="shortcut-groups">
        {[...groups].map(([g, items]) => (
          <div key={g} className="shortcut-group">
            <h3>{g}</h3>
            {items.map((it) => (
              <div key={it.label} className="shortcut-row">
                <span>{it.label}</span>
                <kbd>{it.keys.join(' / ')}</kbd>
              </div>
            ))}
          </div>
        ))}
      </div>
    </Modal>
  );
}

function AboutDialog() {
  return (
    <Modal title="О программе NoteForge">
      <p>
        <b>NoteForge {APP_VERSION}</b> — редактор фортепианных партитур.
      </p>
      <p>Гравировка нот: Verovio (LGPL). Формат проекта: .nfg (JSON).</p>
      <p className="hint">Этап 1: редактирование, сохранение, отмена. Воспроизведение, печать/PDF и MusicXML — следующие этапы.</p>
    </Modal>
  );
}

function MessageDialog() {
  const msg = useStore((s) => s.dialog.message);
  return (
    <Modal title={msg?.title ?? ''}>
      <pre className="message">{msg?.text}</pre>
    </Modal>
  );
}

export function ExportProgress() {
  const p = useStore((s) => s.exportProgress);
  if (!p) return null;
  return (
    <div className="modal-backdrop">
      <div className="modal">
        <h2>{p.text}</h2>
        <div className="modal-body">
          <div className="progress">
            <div className="progress-bar" style={{ width: `${Math.round((p.progress ?? 0) * 100)}%` }} />
          </div>
          <p className="hint">{p.progress !== null ? `${Math.round(p.progress * 100)} %` : 'Подготовка…'}</p>
        </div>
        <div className="modal-actions">
          <button type="button" onClick={P.cancelExport}>
            Отмена
          </button>
        </div>
      </div>
    </div>
  );
}

export function Dialogs() {
  const kind = useStore((s) => s.dialog.kind);
  switch (kind) {
    case 'newScore':
      return <NewScoreDialog />;
    case 'scoreInfo':
      return <ScoreInfoDialog />;
    case 'timeSig':
      return <TimeSigDialog />;
    case 'measures':
      return <MeasuresDialog />;
    case 'gotoMeasure':
      return <GotoDialog />;
    case 'stats':
      return <StatsDialog />;
    case 'pageSetup':
      return <PageSetupDialog />;
    case 'shortcuts':
      return <ShortcutsDialog />;
    case 'about':
      return <AboutDialog />;
    case 'message':
      return <MessageDialog />;
    case 'mixer':
      return (
        <Modal title="Микшер">
          <div className="mixer inline">
            <Mixer onClose={() => {}} embedded />
          </div>
        </Modal>
      );
    default:
      return null;
  }
}
