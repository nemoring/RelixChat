import { useMemo, useState } from 'react';
import { useStore } from '../state/store';
import * as NAV from '../state/navigation';
import * as A from '../state/actions';

const ICON: Record<NAV.NavItem['kind'], string> = { section: '§', rehearsal: '▣', bookmark: '🔖', tempo: '♩', key: '♯', time: '⅞', repeat: '𝄆' };

export function Navigator() {
  const score = useStore((s) => s.score);
  const items = useMemo(() => NAV.navItems(score), [score]);
  const [n, setN] = useState('');
  const [filter, setFilter] = useState<'all' | 'section' | 'bookmark'>('all');
  const shown = items.filter((i) => filter === 'all' || i.kind === filter || (filter === 'section' && i.kind === 'rehearsal'));
  return (
    <div className="navigator">
      <form
        className="nav-goto"
        onSubmit={(e) => {
          e.preventDefault();
          const v = parseInt(n, 10);
          if (v > 0) NAV.goTo(v - 1);
        }}
      >
        <input placeholder={`Такт (1–${score.measures.length})`} value={n} onChange={(e) => setN(e.target.value.replace(/\D/g, ''))} />
        <button type="submit" className="small">Перейти</button>
      </form>
      <div className="nav-actions">
        <button className="small" onClick={() => A.openDialog('section')}>+ часть / раздел</button>
        <button className="small" onClick={NAV.toggleRehearsal}>+ буква</button>
        <button className="small" onClick={() => A.openDialog('bookmark')}>+ закладка</button>
      </div>
      <div className="nav-filter">
        {(['all', 'section', 'bookmark'] as const).map((f) => (
          <button key={f} className={`small${filter === f ? ' on' : ''}`} onClick={() => setFilter(f)}>
            {f === 'all' ? 'всё' : f === 'section' ? 'разделы' : 'закладки'}
          </button>
        ))}
      </div>
      <div className="nav-list">
        {shown.length === 0 && <p className="hint">Нет разделов и закладок. Выделите такт и добавьте их кнопками выше.</p>}
        {shown.map((i, k) => (
          <div key={k} className={`nav-item nav-${i.kind}`} onClick={() => NAV.goTo(i.measure)} title={`Перейти к такту ${i.measure + 1}`}>
            <span className="nav-icon">{ICON[i.kind]}</span>
            <span className="nav-label">{i.label}</span>
            <span className="nav-measure">{i.measure + 1}</span>
            {i.kind === 'bookmark' && (
              <button
                className="nav-del"
                title="Удалить закладку"
                onClick={(e) => {
                  e.stopPropagation();
                  NAV.removeBookmark(i.id!);
                }}
              >
                ×
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
