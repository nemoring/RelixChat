/** Sections (movements), rehearsal marks and bookmarks. */
import { commit, getState, setState } from './store';
import { selectedMeasure } from './actions';
import { newId } from '../model/ids';
import type { Score } from '../model/types';

const target = () => selectedMeasure() ?? 0;

export function setSection(title: string, newPage: boolean, m = target()): void {
  commit(title ? `Раздел «${title}»` : 'Раздел удалён', (d) => {
    if (title) d.measures[m].section = { title, newPage };
    else delete d.measures[m].section;
  });
}

/** Next rehearsal letter after those already used before measure m. */
function nextLetter(score: Score, m: number): string {
  let last = '';
  for (let i = 0; i < m; i++) if (score.measures[i].rehearsal) last = score.measures[i].rehearsal!;
  if (!last) return 'A';
  if (/^[A-Y]$/.test(last)) return String.fromCharCode(last.charCodeAt(0) + 1);
  if (/^\d+$/.test(last)) return String(Number(last) + 1);
  return `${last}'`;
}

export function toggleRehearsal(): void {
  const m = target();
  commit('Буква-ориентир', (d) => {
    if (d.measures[m].rehearsal) delete d.measures[m].rehearsal;
    else d.measures[m].rehearsal = nextLetter(d, m);
  });
}

export function addBookmark(name: string, m = target()): void {
  commit('Закладка', (d) => {
    d.bookmarks.push({ id: newId('b'), name: name || `Такт ${m + 1}`, measure: m });
    d.bookmarks.sort((a, b) => a.measure - b.measure);
  });
}

export function removeBookmark(id: string): void {
  commit('Закладка удалена', (d) => {
    d.bookmarks = d.bookmarks.filter((b) => b.id !== id);
  });
}

export interface NavItem {
  measure: number;
  kind: 'section' | 'rehearsal' | 'bookmark' | 'tempo' | 'key' | 'time' | 'repeat';
  label: string;
  id?: string;
}

/** Everything worth jumping to, in score order. */
export function navItems(score: Score): NavItem[] {
  const out: NavItem[] = [];
  score.measures.forEach((mi, m) => {
    if (mi.section) out.push({ measure: m, kind: 'section', label: mi.section.title });
    if (mi.rehearsal) out.push({ measure: m, kind: 'rehearsal', label: `[${mi.rehearsal}]` });
    if (mi.tempo) out.push({ measure: m, kind: 'tempo', label: `${mi.tempo.text ? mi.tempo.text + ' ' : ''}♩ = ${mi.tempo.bpm}` });
    if (m > 0 && mi.timeSig) out.push({ measure: m, kind: 'time', label: `${mi.timeSig.count}/${mi.timeSig.unit}` });
    if (m > 0 && mi.keySig !== undefined) out.push({ measure: m, kind: 'key', label: `Тональность ${mi.keySig > 0 ? mi.keySig + '♯' : mi.keySig < 0 ? -mi.keySig + '♭' : '—'}` });
    if (mi.repeatStart) out.push({ measure: m, kind: 'repeat', label: 'Начало повтора' });
  });
  for (const b of score.bookmarks) out.push({ measure: b.measure, kind: 'bookmark', label: b.name, id: b.id });
  out.sort((a, b) => a.measure - b.measure);
  return out;
}

export function goTo(m: number): void {
  const score = getState().score;
  const mm = Math.max(0, Math.min(score.measures.length - 1, m));
  setState({
    selection: { kind: 'range', staffFrom: 0, staffTo: 0, mFrom: mm, mTo: mm, anchorStaff: 0, anchorMeasure: mm },
    reveal: { measure: mm, token: Date.now() + Math.random() },
    status: `Такт ${mm + 1}`,
  });
}
