/**
 * Command registry: one place that defines every editor command, its label
 * and its default shortcut. Menus, toolbar tooltips, the shortcuts dialog and
 * the keyboard handler all read from here, so a shortcut shown in the UI is
 * always the one that actually works.
 */
import * as A from '../state/actions';
import * as P from '../state/playback';
import { player } from '../playback/player';
import { getState } from '../state/store';
import type { DurBase, Step } from '../model/types';

export interface Command {
  id: string;
  label: string;
  /** Shortcut strings like "Ctrl+Shift+Z", "Alt+Up", "A". */
  keys: string[];
  run: () => void;
  /** Group shown in the shortcuts dialog. */
  group: string;
  enabled?: () => boolean;
}

const hasSelection = () => getState().selection.kind !== 'none';
const DURS: [DurBase, string, string][] = [
  [64, '1/64', '1'],
  [32, '1/32', '2'],
  [16, '1/16', '3'],
  [8, 'Восьмая', '4'],
  [4, 'Четвертная', '5'],
  [2, 'Половинная', '6'],
  [1, 'Целая', '7'],
];

const list: Command[] = [
  // File
  { id: 'file.new', label: 'Новая партитура…', keys: ['Ctrl+N'], group: 'Файл', run: () => A.openDialog('newScore') },
  { id: 'file.open', label: 'Открыть…', keys: ['Ctrl+O'], group: 'Файл', run: () => void A.openProject() },
  { id: 'file.save', label: 'Сохранить', keys: ['Ctrl+S'], group: 'Файл', run: () => void A.saveProject(false) },
  { id: 'file.saveAs', label: 'Сохранить как…', keys: ['Ctrl+Shift+S'], group: 'Файл', run: () => void A.saveProject(true) },
  { id: 'file.info', label: 'Свойства партитуры…', keys: [], group: 'Файл', run: () => A.openDialog('scoreInfo') },
  // Edit
  { id: 'edit.undo', label: 'Отменить', keys: ['Ctrl+Z'], group: 'Правка', run: A.undo, enabled: () => getState().past.length > 0 },
  { id: 'edit.redo', label: 'Повторить', keys: ['Ctrl+Y', 'Ctrl+Shift+Z'], group: 'Правка', run: A.redo, enabled: () => getState().future.length > 0 },
  { id: 'edit.cut', label: 'Вырезать', keys: ['Ctrl+X'], group: 'Правка', run: A.cutSelection, enabled: () => getState().selection.kind === 'range' },
  { id: 'edit.copy', label: 'Копировать', keys: ['Ctrl+C'], group: 'Правка', run: () => void A.copySelection(), enabled: () => getState().selection.kind === 'range' },
  { id: 'edit.paste', label: 'Вставить', keys: ['Ctrl+V'], group: 'Правка', run: A.paste },
  { id: 'edit.delete', label: 'Удалить', keys: ['Delete', 'Backspace'], group: 'Правка', run: A.deleteSelection, enabled: hasSelection },
  { id: 'edit.selectAll', label: 'Выделить всё', keys: ['Ctrl+A'], group: 'Правка', run: A.selectAll },
  { id: 'edit.escape', label: 'Снять выделение / выйти из ввода', keys: ['Escape'], group: 'Правка', run: A.clearSelection },
  { id: 'edit.up', label: 'Выше на полутон', keys: ['Up'], group: 'Правка', run: () => A.transposeSelection(1), enabled: hasSelection },
  { id: 'edit.down', label: 'Ниже на полутон', keys: ['Down'], group: 'Правка', run: () => A.transposeSelection(-1), enabled: hasSelection },
  { id: 'edit.octUp', label: 'Выше на октаву', keys: ['Ctrl+Up'], group: 'Правка', run: () => A.transposeSelection(12), enabled: hasSelection },
  { id: 'edit.octDown', label: 'Ниже на октаву', keys: ['Ctrl+Down'], group: 'Правка', run: () => A.transposeSelection(-12), enabled: hasSelection },
  { id: 'edit.next', label: 'Следующий элемент', keys: ['Right'], group: 'Навигация', run: () => A.moveHorizontal(1) },
  { id: 'edit.prev', label: 'Предыдущий элемент', keys: ['Left'], group: 'Навигация', run: () => A.moveHorizontal(-1) },
  { id: 'edit.extendNext', label: 'Расширить выделение вправо', keys: ['Shift+Right'], group: 'Навигация', run: () => A.moveHorizontal(1, true) },
  { id: 'edit.extendPrev', label: 'Расширить выделение влево', keys: ['Shift+Left'], group: 'Навигация', run: () => A.moveHorizontal(-1, true) },
  { id: 'edit.chordUp', label: 'Верхняя нота аккорда', keys: ['Alt+Up'], group: 'Навигация', run: () => A.moveInChord(1) },
  { id: 'edit.chordDown', label: 'Нижняя нота аккорда', keys: ['Alt+Down'], group: 'Навигация', run: () => A.moveInChord(-1) },
  { id: 'edit.staffUp', label: 'Курсор на верхний нотоносец', keys: ['Ctrl+Alt+Up'], group: 'Навигация', run: () => A.moveCursorStaff(-1) },
  { id: 'edit.staffDown', label: 'Курсор на нижний нотоносец', keys: ['Ctrl+Alt+Down'], group: 'Навигация', run: () => A.moveCursorStaff(1) },
  { id: 'edit.goto', label: 'Перейти к такту…', keys: ['Ctrl+G'], group: 'Навигация', run: () => A.openDialog('gotoMeasure') },
  // Note input
  { id: 'input.toggle', label: 'Режим ввода нот', keys: ['N'], group: 'Ввод нот', run: () => A.toggleInputMode() },
  ...DURS.map(([base, name, key]): Command => ({ id: `dur.${base}`, label: name, keys: [key], group: 'Длительности', run: () => A.setDurationBase(base) })),
  { id: 'dur.dot', label: 'Точка', keys: ['.'], group: 'Длительности', run: A.toggleDot },
  { id: 'input.rest', label: 'Пауза', keys: ['0'], group: 'Ввод нот', run: A.enterRest },
  { id: 'input.tie', label: 'Залигованная нота (связка)', keys: ['+', '='], group: 'Ввод нот', run: A.toggleTie },
  ...(['A', 'B', 'C', 'D', 'E', 'F', 'G'] as Step[]).flatMap((st): Command[] => [
    { id: `note.${st}`, label: `Нота ${st}`, keys: [st], group: 'Ввод нот', run: () => A.enterNote(st) },
    { id: `chord.${st}`, label: `Добавить ${st} в аккорд`, keys: [`Shift+${st}`], group: 'Ввод нот', run: () => A.enterNote(st, true) },
  ]),
  ...[0, 1, 2, 3].map((v): Command => ({ id: `voice.${v + 1}`, label: `Голос ${v + 1}`, keys: [`Ctrl+Alt+${v + 1}`], group: 'Ввод нот', run: () => A.setVoice(v) })),
  { id: 'acc.sharp', label: 'Диез', keys: [], group: 'Альтерация', run: () => A.setAlter(1) },
  { id: 'acc.flat', label: 'Бемоль', keys: [], group: 'Альтерация', run: () => A.setAlter(-1) },
  { id: 'acc.natural', label: 'Бекар', keys: [], group: 'Альтерация', run: () => A.setAlter(0) },
  { id: 'acc.dsharp', label: 'Дубль-диез', keys: [], group: 'Альтерация', run: () => A.setAlter(2) },
  { id: 'acc.dflat', label: 'Дубль-бемоль', keys: [], group: 'Альтерация', run: () => A.setAlter(-2) },
  // Measures
  { id: 'measure.append', label: 'Добавить такт в конец', keys: ['Ctrl+B'], group: 'Такты', run: () => A.appendMeasures(1) },
  { id: 'measure.insert', label: 'Вставить такт перед выделенным', keys: ['Insert'], group: 'Такты', run: () => A.insertMeasures(1) },
  { id: 'measure.many', label: 'Вставить / добавить такты…', keys: [], group: 'Такты', run: () => A.openDialog('measures') },
  { id: 'measure.delete', label: 'Удалить выделенные такты', keys: ['Ctrl+Delete'], group: 'Такты', run: A.deleteSelectedMeasures, enabled: hasSelection },
  // Format
  { id: 'format.timeSig', label: 'Размер…', keys: ['Ctrl+T'], group: 'Формат', run: () => A.openDialog('timeSig') },
  { id: 'format.page', label: 'Параметры страницы…', keys: [], group: 'Формат', run: () => A.openDialog('pageSetup') },
  // View
  { id: 'view.zoomIn', label: 'Увеличить', keys: ['Ctrl+='], group: 'Вид', run: () => A.zoomBy(1.15) },
  { id: 'view.zoomOut', label: 'Уменьшить', keys: ['Ctrl+-'], group: 'Вид', run: () => A.zoomBy(1 / 1.15) },
  { id: 'view.zoom100', label: 'Масштаб 100 %', keys: ['Ctrl+0'], group: 'Вид', run: () => A.setZoom(1) },
  { id: 'view.page', label: 'Постраничный вид', keys: [], group: 'Вид', run: () => A.setViewMode('page') },
  { id: 'view.continuous', label: 'Непрерывный вид', keys: [], group: 'Вид', run: () => A.setViewMode('continuous') },
  { id: 'view.palette', label: 'Палитра символов', keys: ['F9'], group: 'Вид', run: A.togglePalette },
  // Playback
  { id: 'play.toggle', label: 'Воспроизведение / пауза', keys: ['Space'], group: 'Воспроизведение', run: () => void P.playPause() },
  { id: 'play.stop', label: 'Стоп', keys: ['Shift+Space'], group: 'Воспроизведение', run: P.stop },
  { id: 'play.restart', label: 'С начала', keys: ['Home'], group: 'Воспроизведение', run: () => void P.restart() },
  { id: 'play.selection', label: 'Воспроизвести выделенное', keys: ['Ctrl+Space'], group: 'Воспроизведение', run: () => void P.playFromSelection() },
  { id: 'play.loop', label: 'Повтор (цикл) выделенного фрагмента', keys: ['Ctrl+L'], group: 'Воспроизведение', run: P.toggleLoop },
  { id: 'play.metronome', label: 'Метроном', keys: ['Ctrl+M'], group: 'Воспроизведение', run: P.toggleMetronome },
  { id: 'play.faster', label: 'Быстрее (+5 %)', keys: ['Ctrl+]'], group: 'Воспроизведение', run: () => P.changeSpeed(0.05) },
  { id: 'play.slower', label: 'Медленнее (−5 %)', keys: ['Ctrl+['], group: 'Воспроизведение', run: () => P.changeSpeed(-0.05) },
  { id: 'play.speed100', label: 'Скорость 100 %', keys: [], group: 'Воспроизведение', run: () => player.setSpeed(1) },
  { id: 'play.mixer', label: 'Микшер…', keys: ['F10'], group: 'Воспроизведение', run: () => A.openDialog('mixer') },
  { id: 'play.soundfont', label: 'Загрузить SoundFont (.sf2)…', keys: [], group: 'Воспроизведение', run: () => void P.chooseSoundFont() },
  { id: 'export.midi', label: 'Экспорт в MIDI…', keys: [], group: 'Файл', run: () => void P.exportMidi() },
  { id: 'export.wav', label: 'Экспорт в WAV…', keys: [], group: 'Файл', run: () => void P.exportWav() },
  // Tools / help
  { id: 'tools.stats', label: 'Статистика произведения…', keys: [], group: 'Инструменты', run: () => A.openDialog('stats') },
  { id: 'help.shortcuts', label: 'Горячие клавиши', keys: ['F1'], group: 'Справка', run: () => A.openDialog('shortcuts') },
  { id: 'help.about', label: 'О программе', keys: [], group: 'Справка', run: () => A.openDialog('about') },
];

export const commands = new Map(list.map((c) => [c.id, c]));

export function runCommand(id: string): void {
  const c = commands.get(id);
  if (!c) throw new Error(`Unknown command ${id}`);
  if (c.enabled && !c.enabled()) return;
  c.run();
}

export function shortcutOf(id: string): string {
  return commands.get(id)?.keys[0] ?? '';
}

/** Normalises a keyboard event to the shortcut string format. */
export function eventToShortcut(e: KeyboardEvent): string | null {
  const names: Record<string, string> = { ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', ' ': 'Space' };
  let key = names[e.key] ?? e.key;
  if (['Control', 'Shift', 'Alt', 'Meta'].includes(key)) return null;
  // Use the physical key for letters/digits so layouts (e.g. Cyrillic) and Shift do not change the meaning.
  if (/^Key[A-Z]$/.test(e.code)) key = e.code.slice(3);
  else if (/^Digit\d$/.test(e.code)) key = e.code.slice(5);
  else if (e.code === 'Period' || e.code === 'NumpadDecimal') key = '.';
  else if (e.code === 'BracketLeft') key = '[';
  else if (e.code === 'BracketRight') key = ']';
  else if (e.code === 'Equal') key = e.shiftKey ? '+' : '=';
  else if (e.code === 'NumpadAdd') key = '+';
  else if (e.code === 'Minus' || e.code === 'NumpadSubtract') key = '-';
  else if (/^Numpad\d$/.test(e.code)) key = e.code.slice(6);
  else if (key.length === 1) key = key.toUpperCase();
  const mods: string[] = [];
  if (e.ctrlKey || e.metaKey) mods.push('Ctrl');
  if (e.altKey) mods.push('Alt');
  if (e.shiftKey && key !== '+') mods.push('Shift');
  return [...mods, key].join('+');
}

let keyIndex: Map<string, string> | null = null;
function index(): Map<string, string> {
  if (!keyIndex) {
    keyIndex = new Map();
    for (const c of list) for (const k of c.keys) keyIndex.set(k, c.id);
  }
  return keyIndex;
}

export function handleKeyDown(e: KeyboardEvent): boolean {
  const t = e.target as HTMLElement | null;
  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.tagName === 'SELECT' || t.isContentEditable)) return false;
  if (getState().dialog.kind !== 'none') return false;
  const sc = eventToShortcut(e);
  if (!sc) return false;
  const id = index().get(sc);
  if (!id) return false;
  e.preventDefault();
  runCommand(id);
  return true;
}
