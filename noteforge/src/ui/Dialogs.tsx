import { useEffect, useMemo, useRef, useState } from 'react';
import { useStore, getState, setState } from '../state/store';
import * as A from '../state/actions';
import { keyName } from '../model/pitch';
import { computeStats, formatDuration } from '../model/stats';
import { APP_VERSION } from '../model/serialize';
import { Mixer } from './Transport';
import { PrintPreview } from './PrintPreview';
import { Navigator } from './Navigator';
import * as NAV from '../state/navigation';
import * as AS from '../state/autosave';
import { checkScore, fixIssues } from '../model/check';
import { commands, defaultKeys, applyShortcutOverrides, captureNextShortcut, commandForKey } from '../input/commands';
import { useSettings, updateSettings, getSettings, type Snap } from '../state/settings';
import { midiInputs } from '../input/midiInput';
import { player } from '../playback/player';
import * as P from '../state/playback';
import * as N from '../state/notation';
import { selectedMeasure } from '../state/actions';

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
      <p className="hint">Звук: банк GeneralUser GS © S. Christian Collins (свободная лицензия, см. soundfonts/GeneralUser-GS-LICENSE.txt).</p>
    </Modal>
  );
}

function TempoDialog() {
  const st = getState();
  const m = selectedMeasure() ?? 0;
  const cur = m === 0 ? st.score.tempo : (st.score.measures[m].tempo ?? st.score.tempo);
  const [t, setT] = useState({ ...cur });
  const hasChange = m > 0 && !!st.score.measures[m].tempo;
  return (
    <Modal
      title={m === 0 ? 'Темп произведения' : `Смена темпа с такта ${m + 1}`}
      submitLabel="Применить"
      onSubmit={() => {
        A.closeDialog();
        N.tempoChange({ ...t, bpm: Math.max(10, Math.min(500, t.bpm || 100)) });
      }}
    >
      <Field label="Обозначение (Allegro, a tempo, Meno mosso…)">
        <input value={t.text} onChange={(e) => setT({ ...t, text: e.target.value })} />
      </Field>
      <Field label="Метроном">
        <span className="inline">
          <select value={`${t.beatUnit}:${t.beatDots}`} onChange={(e) => {
            const [u, d] = e.target.value.split(':').map(Number);
            setT({ ...t, beatUnit: u, beatDots: d });
          }}>
            <option value="2:0">𝅗𝅥</option>
            <option value="4:0">♩</option>
            <option value="4:1">♩.</option>
            <option value="8:0">♪</option>
          </select>
          =
          <input type="number" min={10} max={500} value={t.bpm} onChange={(e) => setT({ ...t, bpm: Number(e.target.value) })} />
        </span>
      </Field>
      {hasChange && (
        <button type="button" className="small" onClick={() => {
          A.closeDialog();
          N.tempoChange(undefined);
        }}>
          Удалить смену темпа в этом такте
        </button>
      )}
    </Modal>
  );
}

function TupletDialog() {
  const [num, setNum] = useState(5);
  const [den, setDen] = useState(4);
  return (
    <Modal title="Ритмическая группа" submitLabel="Создать" onSubmit={() => {
      A.closeDialog();
      N.tuplet(num, den);
    }}>
      <p className="hint">Группа заменит выделенную ноту (или, в режиме ввода, длительность ввода от курсора): {num} нот в времени {den}.</p>
      <div className="row">
        <Field label="Нот в группе">
          <input type="number" min={2} max={32} value={num} onChange={(e) => setNum(Number(e.target.value))} />
        </Field>
        <Field label="Вместо (нот обычной длительности)">
          <input type="number" min={1} max={32} value={den} onChange={(e) => setDen(Number(e.target.value))} />
        </Field>
      </div>
    </Modal>
  );
}

const INTERVALS: { label: string; steps: number; semitones: number }[] = [
  { label: 'Малая секунда', steps: 1, semitones: 1 },
  { label: 'Большая секунда', steps: 1, semitones: 2 },
  { label: 'Малая терция', steps: 2, semitones: 3 },
  { label: 'Большая терция', steps: 2, semitones: 4 },
  { label: 'Чистая кварта', steps: 3, semitones: 5 },
  { label: 'Увеличенная кварта', steps: 3, semitones: 6 },
  { label: 'Уменьшённая квинта', steps: 4, semitones: 6 },
  { label: 'Чистая квинта', steps: 4, semitones: 7 },
  { label: 'Малая секста', steps: 5, semitones: 8 },
  { label: 'Большая секста', steps: 5, semitones: 9 },
  { label: 'Малая септима', steps: 6, semitones: 10 },
  { label: 'Большая септима', steps: 6, semitones: 11 },
  { label: 'Октава', steps: 7, semitones: 12 },
];

function TransposeDialog() {
  const hasSel = getState().selection.kind !== 'none';
  const [iv, setIv] = useState(1);
  const [dir, setDir] = useState<1 | -1>(1);
  const [scope, setScope] = useState<'selection' | 'all'>(hasSel ? 'selection' : 'all');
  const [keys, setKeys] = useState(true);
  return (
    <Modal title="Транспонирование" submitLabel="Транспонировать" onSubmit={() => {
      A.closeDialog();
      const i = INTERVALS[iv];
      N.transpose({ steps: i.steps * dir, semitones: i.semitones * dir }, scope, keys);
    }}>
      <div className="row">
        <Field label="Направление">
          <select value={dir} onChange={(e) => setDir(Number(e.target.value) as 1 | -1)}>
            <option value={1}>Вверх</option>
            <option value={-1}>Вниз</option>
          </select>
        </Field>
        <Field label="Интервал">
          <select value={iv} onChange={(e) => setIv(Number(e.target.value))}>
            {INTERVALS.map((x, i) => (
              <option key={i} value={i}>{x.label}</option>
            ))}
          </select>
        </Field>
      </div>
      <Field label="Что транспонировать">
        <select value={scope} onChange={(e) => setScope(e.target.value as 'selection' | 'all')}>
          {hasSel && <option value="selection">Выделенные такты</option>}
          <option value="all">Всю партитуру</option>
        </select>
      </Field>
      <label className="field check-row">
        <input type="checkbox" checked={keys} onChange={(e) => setKeys(e.target.checked)} /> Транспонировать ключевые знаки (когда выбраны оба нотоносца)
      </label>
    </Modal>
  );
}

function VoltaDialog() {
  const [text, setText] = useState('1, 2');
  return (
    <Modal title="Вольта" submitLabel="Поставить" onSubmit={() => {
      const nums = text.split(/[^0-9]+/).map(Number).filter((n) => n > 0);
      A.closeDialog();
      if (nums.length) N.volta(nums);
    }}>
      <p className="hint">Вольта ставится над выделенными тактами. Номера — проходы, на которых она играется (например «1, 2» или «3»).</p>
      <Field label="Номера проходов">
        <input value={text} onChange={(e) => setText(e.target.value)} />
      </Field>
    </Modal>
  );
}

function RepeatTimesDialog() {
  const [n, setN] = useState(3);
  return (
    <Modal title="Конец повтора" submitLabel="Поставить" onSubmit={() => {
      A.closeDialog();
      N.repeatEnd(Math.max(2, Math.min(16, n)));
    }}>
      <Field label="Сколько раз играть фрагмент">
        <input type="number" min={2} max={16} value={n} onChange={(e) => setN(Number(e.target.value))} />
      </Field>
    </Modal>
  );
}

function RecoveryDialog() {
  const list = useStore((s) => s.recovery);
  const done = async (keys: string[]) => {
    await AS.discardRecovery(keys);
    setState({ recovery: [], dialog: { kind: 'none' } });
  };
  return (
    <Modal title="Восстановление после аварийного завершения">
      <p className="hint">NoteForge в прошлый раз закрылся некорректно. Найдены автоматически сохранённые копии:</p>
      {list.map((r) => (
        <div key={r.key} className="issue">
          <span className="t">
            <b>{r.title}</b>
            <br />
            <small>{new Date(r.savedAt).toLocaleString()} {r.filePath ? `· ${r.filePath}` : '· не сохранялась'}</small>
          </span>
          <button type="button" className="small on" onClick={async () => {
            await AS.recover(r.key, r.filePath);
            await done(list.filter((x) => x.key !== r.key).map((x) => x.key));
          }}>
            Восстановить
          </button>
        </div>
      ))}
      <div className="melody-actions">
        <button type="button" className="small" onClick={() => void done(list.map((x) => x.key))}>
          Удалить все копии
        </button>
      </div>
    </Modal>
  );
}

function SectionDialog() {
  const m = selectedMeasure() ?? 0;
  const cur = getState().score.measures[m]?.section;
  const [title, setTitle] = useState(cur?.title ?? '');
  const [newPage, setNewPage] = useState(cur?.newPage ?? false);
  return (
    <Modal title={`Часть / раздел с такта ${m + 1}`} submitLabel="Применить" onSubmit={() => {
      A.closeDialog();
      NAV.setSection(title.trim(), newPage, m);
    }}>
      <Field label="Название (пусто — убрать раздел)">
        <input value={title} placeholder="II. Adagio sostenuto" onChange={(e) => setTitle(e.target.value)} />
      </Field>
      <label className="field check-row">
        <input type="checkbox" checked={newPage} onChange={(e) => setNewPage(e.target.checked)} /> Начинать с новой страницы
      </label>
    </Modal>
  );
}

function BookmarkDialog() {
  const m = selectedMeasure() ?? 0;
  const [name, setName] = useState(`Такт ${m + 1}`);
  return (
    <Modal title="Закладка" submitLabel="Добавить" onSubmit={() => {
      A.closeDialog();
      NAV.addBookmark(name.trim(), m);
    }}>
      <Field label={`Название закладки на такте ${m + 1}`}>
        <input value={name} onChange={(e) => setName(e.target.value)} />
      </Field>
    </Modal>
  );
}

function CheckDialog() {
  const score = useStore((s) => s.score);
  const issues = useMemo(() => checkScore(score), [score]);
  const fixable = issues.filter((i) => i.kind === 'underfull' || i.kind === 'overfull' || i.kind === 'tie');
  const shown = issues.slice(0, 300);
  return (
    <Modal title="Проверка тактов" wide>
      <p className="hint">
        Ошибок: {issues.filter((i) => i.severity === 'error').length} · предупреждений: {issues.filter((i) => i.severity === 'warning').length} · пустых тактов:{' '}
        {issues.filter((i) => i.kind === 'empty').length}
      </p>
      <div className="issues">
        {issues.length === 0 && <p>Проблем не найдено.</p>}
        {shown.map((i, k) => (
          <div key={k} className="issue">
            <span className={`sev ${i.severity}`} />
            <span className="t">{i.text}</span>
            <button type="button" className="small" onClick={() => NAV.goTo(i.measure)}>
              Перейти
            </button>
          </div>
        ))}
        {issues.length > shown.length && <p className="hint">… и ещё {issues.length - shown.length}</p>}
      </div>
      {fixable.length > 0 && (
        <div className="melody-actions">
          <button type="button" className="small on" onClick={() => A.updateScore('Исправление тактов', (d) => void fixIssues(d, fixable))}>
            Исправить автоматически ({fixable.length})
          </button>
        </div>
      )}
    </Modal>
  );
}

function ShortcutsEditDialog() {
  const overrides = useSettings((s) => s.shortcuts);
  const [capturing, setCapturing] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [, force] = useState(0);
  useEffect(() => () => captureNextShortcut(null), []);
  const set = (id: string, keys: string[]) => {
    const next = { ...getSettings().shortcuts, [id]: keys };
    updateSettings({ shortcuts: next });
    applyShortcutOverrides(next);
    force((x) => x + 1);
  };
  const reset = (id: string) => {
    const next = { ...getSettings().shortcuts };
    delete next[id];
    updateSettings({ shortcuts: next });
    applyShortcutOverrides(next);
    force((x) => x + 1);
  };
  const list = [...commands.values()].filter((c) => !filter || c.label.toLowerCase().includes(filter.toLowerCase()) || c.group.toLowerCase().includes(filter.toLowerCase()));
  return (
    <Modal title="Горячие клавиши" wide>
      <p className="hint">Нажмите «изменить» и затем нужное сочетание клавиш. Клавиша, занятая другой командой, будет снята с неё.</p>
      <Field label="Поиск">
        <input value={filter} onChange={(e) => setFilter(e.target.value)} />
      </Field>
      <div className="issues shortcut-edit">
        {list.map((c) => (
          <div key={c.id} style={{ display: 'contents' }}>
            <span>
              {c.label} <small className="hint-inline">· {c.group}</small>
            </span>
            <kbd className={capturing === c.id ? 'capturing' : ''}>{capturing === c.id ? 'нажмите клавиши…' : c.keys.join(' / ') || '—'}</kbd>
            <span>
              <button type="button" className="small" onClick={() => {
                setCapturing(c.id);
                captureNextShortcut((sc) => {
                  setCapturing(null);
                  if (sc === 'Escape') return;
                  const owner = commandForKey(sc);
                  if (owner && owner.id !== c.id && !window.confirm(`«${sc}» уже назначено команде «${owner.label}». Переназначить?`)) return;
                  set(c.id, [sc]);
                });
              }}>
                изменить
              </button>{' '}
              <button type="button" className="small" onClick={() => set(c.id, [])} title="Без клавиши">
                ×
              </button>{' '}
              {overrides[c.id] && (
                <button type="button" className="small" onClick={() => reset(c.id)} title={`По умолчанию: ${(defaultKeys.get(c.id) ?? []).join(' / ') || '—'}`}>
                  сброс
                </button>
              )}
            </span>
          </div>
        ))}
      </div>
    </Modal>
  );
}

function SettingsDialog() {
  const st = useSettings((s) => s);
  const preview = usePlayerPreview();
  const inputs = midiInputs();
  return (
    <Modal title="Настройки">
      <Field label="Автосохранение">
        <select value={st.autosaveMinutes} onChange={(e) => {
          updateSettings({ autosaveMinutes: Number(e.target.value) });
          AS.startAutosave();
        }}>
          <option value={0}>Выключено</option>
          <option value={1}>Каждую минуту</option>
          <option value={2}>Каждые 2 минуты</option>
          <option value={5}>Каждые 5 минут</option>
          <option value={10}>Каждые 10 минут</option>
        </select>
      </Field>
      <Field label="MIDI-клавиатура для ввода нот">
        <select value={st.midiInput} onChange={(e) => updateSettings({ midiInput: e.target.value })}>
          <option value="all">Все подключённые устройства</option>
          <option value="none">Не использовать</option>
          {inputs.map((i) => (
            <option key={i.id} value={i.id}>
              {i.name}
            </option>
          ))}
        </select>
      </Field>
      <p className="hint">{inputs.length ? `Найдено MIDI-входов: ${inputs.length}` : 'MIDI-устройства ввода не найдены (подключите клавиатуру — список обновится).'}</p>
      <Field label="Сетка при вводе нот мышью">
        <select value={String(st.snap)} onChange={(e) => updateSettings({ snap: (e.target.value === 'note' ? 'note' : Number(e.target.value)) as Snap })}>
          <option value="note">По существующим нотам</option>
          <option value="4">Четверти</option>
          <option value="8">Восьмые</option>
          <option value="16">Шестнадцатые</option>
          <option value="32">Тридцать вторые</option>
        </select>
      </Field>
      <label className="field check-row">
        <input type="checkbox" checked={st.showKeyboard} onChange={(e) => updateSettings({ showKeyboard: e.target.checked })} /> Экранная клавиатура фортепиано
      </label>
      <label className="field check-row">
        <input type="checkbox" checked={preview} onChange={(e) => player.setPreview(e.target.checked)} /> Проигрывать ноты при вводе и выделении
      </label>
      <button type="button" className="small" onClick={() => A.openDialog('shortcutsEdit')}>
        Горячие клавиши…
      </button>
    </Modal>
  );
}

function usePlayerPreview() {
  const [v, setV] = useState(player.state.previewNotes);
  useEffect(() => {
    const off = player.subscribe(() => setV(player.state.previewNotes));
    return () => void off();
  }, []);
  return v;
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
    case 'shortcuts':
      return <ShortcutsDialog />;
    case 'about':
      return <AboutDialog />;
    case 'message':
      return <MessageDialog />;
    case 'preview':
      return <PrintPreview />;
    case 'recovery':
      return <RecoveryDialog />;
    case 'section':
      return <SectionDialog />;
    case 'bookmark':
      return <BookmarkDialog />;
    case 'checkMeasures':
      return <CheckDialog />;
    case 'shortcutsEdit':
      return <ShortcutsEditDialog />;
    case 'settings':
      return <SettingsDialog />;
    case 'navigator':
      return (
        <Modal title="Навигатор">
          <Navigator />
        </Modal>
      );
    case 'tempo':
      return <TempoDialog />;
    case 'tuplet':
      return <TupletDialog />;
    case 'transpose':
      return <TransposeDialog />;
    case 'volta':
      return <VoltaDialog />;
    case 'repeatTimes':
      return <RepeatTimesDialog />;
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
