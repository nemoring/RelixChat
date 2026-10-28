/**
 * Command registry: one place that defines every editor command, its label
 * and its default shortcut. Menus, toolbar tooltips, the shortcuts dialog and
 * the keyboard handler all read from here, so a shortcut shown in the UI is
 * always the one that actually works.
 */
import * as A from '../state/actions';
import * as P from '../state/playback';
import * as N from '../state/notation';
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
  // Notation (stage 3)
  { id: 'art.staccato', label: 'Стаккато', keys: ['Shift+S'], group: 'Нотация', run: () => N.toggleArtic('staccato') },
  { id: 'art.staccatissimo', label: 'Стаккатиссимо', keys: [], group: 'Нотация', run: () => N.toggleArtic('staccatissimo') },
  { id: 'art.tenuto', label: 'Тенуто', keys: ['Shift+N'], group: 'Нотация', run: () => N.toggleArtic('tenuto') },
  { id: 'art.accent', label: 'Акцент', keys: ['Shift+V'], group: 'Нотация', run: () => N.toggleArtic('accent') },
  { id: 'art.marcato', label: 'Маркато', keys: ['Shift+O'], group: 'Нотация', run: () => N.toggleArtic('marcato') },
  { id: 'art.fermata', label: 'Фермата', keys: [], group: 'Нотация', run: N.toggleFermata },
  { id: 'orn.trill', label: 'Трель', keys: [], group: 'Нотация', run: () => N.ornament('trill') },
  { id: 'orn.mordent', label: 'Мордент', keys: [], group: 'Нотация', run: () => N.ornament('mordent') },
  { id: 'orn.invertedMordent', label: 'Перечёркнутый мордент (пралльтриллер)', keys: [], group: 'Нотация', run: () => N.ornament('invertedMordent') },
  { id: 'orn.turn', label: 'Группетто', keys: [], group: 'Нотация', run: () => N.ornament('turn') },
  { id: 'orn.invertedTurn', label: 'Обращённое группетто', keys: [], group: 'Нотация', run: () => N.ornament('invertedTurn') },
  { id: 'grace.acc', label: 'Форшлаг (короткий, перечёркнутый)', keys: ['/'], group: 'Нотация', run: () => N.grace('acciaccatura') },
  { id: 'grace.app', label: 'Форшлаг (долгий, апподжиатура)', keys: ['Shift+/'], group: 'Нотация', run: () => N.grace('appoggiatura') },
  { id: 'line.slur', label: 'Фразировочная лига', keys: ['S'], group: 'Нотация', run: () => N.line('slur') },
  { id: 'line.cresc', label: 'Crescendo (вилка)', keys: ['Shift+,'], group: 'Нотация', run: () => N.line('cresc') },
  { id: 'line.dim', label: 'Diminuendo (вилка)', keys: ['Shift+.'], group: 'Нотация', run: () => N.line('dim') },
  { id: 'line.pedal', label: 'Педаль', keys: ['Ctrl+Shift+P'], group: 'Нотация', run: () => N.line('pedal') },
  { id: 'line.8va', label: 'Октавой выше (8va)', keys: [], group: 'Нотация', run: () => N.line('ottava', 8) },
  { id: 'line.8vb', label: 'Октавой ниже (8vb)', keys: [], group: 'Нотация', run: () => N.line('ottava', -8) },
  { id: 'line.15ma', label: 'Две октавы выше (15ma)', keys: [], group: 'Нотация', run: () => N.line('ottava', 15) },
  { id: 'line.15mb', label: 'Две октавы ниже (15mb)', keys: [], group: 'Нотация', run: () => N.line('ottava', -15) },
  { id: 'line.remove', label: 'Удалить лиги и линии у выделенного', keys: ['Ctrl+Shift+Delete'], group: 'Нотация', run: N.removeLines },
  { id: 'tuplet.3', label: 'Триоль', keys: ['Ctrl+3'], group: 'Нотация', run: () => N.tuplet(3) },
  { id: 'tuplet.2', label: 'Дуоль', keys: ['Ctrl+2'], group: 'Нотация', run: () => N.tuplet(2) },
  { id: 'tuplet.4', label: 'Квартоль', keys: ['Ctrl+4'], group: 'Нотация', run: () => N.tuplet(4, 3) },
  { id: 'tuplet.5', label: 'Квинтоль', keys: ['Ctrl+5'], group: 'Нотация', run: () => N.tuplet(5) },
  { id: 'tuplet.6', label: 'Секстоль', keys: ['Ctrl+6'], group: 'Нотация', run: () => N.tuplet(6) },
  { id: 'tuplet.7', label: 'Септоль', keys: ['Ctrl+7'], group: 'Нотация', run: () => N.tuplet(7) },
  { id: 'tuplet.other', label: 'Другая ритмическая группа…', keys: [], group: 'Нотация', run: () => A.openDialog('tuplet') },
  { id: 'tuplet.remove', label: 'Удалить ритмическую группу', keys: [], group: 'Нотация', run: N.removeTuplet },
  { id: 'staff.down', label: 'Перенести на нижний нотоносец', keys: ['Ctrl+Shift+Down'], group: 'Нотация', run: () => N.crossStaff(1) },
  { id: 'staff.up', label: 'Перенести на верхний нотоносец', keys: ['Ctrl+Shift+Up'], group: 'Нотация', run: () => N.crossStaff(-1) },
  { id: 'stem.flip', label: 'Штиль: вверх / вниз / авто', keys: ['X'], group: 'Нотация', run: N.flipStem },
  { id: 'beam.break', label: 'Начать новое ребро', keys: [], group: 'Нотация', run: () => N.beam('break') },
  { id: 'beam.join', label: 'Соединить ребром с предыдущей', keys: [], group: 'Нотация', run: () => N.beam('join') },
  { id: 'beam.none', label: 'Без ребра', keys: [], group: 'Нотация', run: () => N.beam('none') },
  { id: 'rep.start', label: 'Начало повтора', keys: [], group: 'Форма', run: N.repeatStart },
  { id: 'rep.end', label: 'Конец повтора', keys: [], group: 'Форма', run: () => N.repeatEnd(2) },
  { id: 'rep.times', label: 'Конец повтора (число раз)…', keys: [], group: 'Форма', run: () => A.openDialog('repeatTimes') },
  { id: 'rep.volta1', label: 'Вольта 1', keys: [], group: 'Форма', run: () => N.volta([1]) },
  { id: 'rep.volta2', label: 'Вольта 2', keys: [], group: 'Форма', run: () => N.volta([2]) },
  { id: 'rep.voltaN', label: 'Вольта…', keys: [], group: 'Форма', run: () => A.openDialog('volta') },
  { id: 'mk.segno', label: 'Сеньо', keys: [], group: 'Форма', run: () => N.marker('segno') },
  { id: 'mk.coda', label: 'Кода', keys: [], group: 'Форма', run: () => N.marker('coda') },
  { id: 'mk.toCoda', label: 'To Coda', keys: [], group: 'Форма', run: () => N.marker('toCoda') },
  { id: 'mk.fine', label: 'Fine', keys: [], group: 'Форма', run: () => N.marker('fine') },
  ...(['DC', 'DCalFine', 'DCalCoda', 'DS', 'DSalFine', 'DSalCoda'] as const).map(
    (j): Command => ({ id: `jump.${j}`, label: j.replace('DC', 'D.C.').replace('DS', 'D.S.').replace('alFine', ' al Fine').replace('alCoda', ' al Coda'), keys: [], group: 'Форма', run: () => N.jump(j) }),
  ),
  { id: 'bar.double', label: 'Двойная тактовая черта', keys: [], group: 'Форма', run: () => N.barline('double') },
  { id: 'bar.final', label: 'Заключительная тактовая черта', keys: [], group: 'Форма', run: () => N.barline('final') },
  { id: 'tempo.change', label: 'Темп / смена темпа…', keys: ['Alt+T'], group: 'Форма', run: () => A.openDialog('tempo') },
  { id: 'tools.transpose', label: 'Транспонирование…', keys: ['Ctrl+Shift+T'], group: 'Инструменты', run: () => A.openDialog('transpose') },
  { id: 'melody.assign', label: 'Добавить / убрать выделенное из мелодии', keys: ['M'], group: 'Мелодия', run: () => N.assignLine() },
  { id: 'melody.remove', label: 'Убрать выделенное из всех мелодий', keys: ['Shift+M'], group: 'Мелодия', run: () => N.assignLine(null) },
  { id: 'melody.new', label: 'Новая мелодическая линия', keys: [], group: 'Мелодия', run: N.createLine },
  { id: 'melody.show', label: 'Показывать мелодические линии', keys: ['Ctrl+Shift+M'], group: 'Мелодия', run: N.toggleShowLines },
  { id: 'melody.solo', label: 'Слушать только мелодию', keys: [], group: 'Мелодия', run: () => N.listen('melody') },
  { id: 'melody.accomp', label: 'Слушать только сопровождение', keys: [], group: 'Мелодия', run: () => N.listen('accomp') },
  { id: 'melody.all', label: 'Слушать всё', keys: [], group: 'Мелодия', run: () => N.listen('all') },
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
  else if (e.code === 'Comma') key = ',';
  else if (e.code === 'Slash') key = '/';
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
