/**
 * Print preview with live page settings: page size, orientation, margins,
 * measures per system, staff/system spacing, staff size, header and page
 * numbers. Thumbnails are the real print layout (same Verovio pass as PDF).
 */
import { useEffect, useMemo, useRef, useState } from 'react';
import { getState } from '../state/store';
import * as A from '../state/actions';
import { exportPdf, printDocument } from '../state/printing';
import { layoutForPrint, pageSvg, type LaidOut } from '../print/print';
import type { PageLayout, Score } from '../model/types';

function Thumb({ l, page, scale }: { l: LaidOut; page: number; scale: number }) {
  const [svg, setSvg] = useState<string | null>(null);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    setSvg(null);
    let alive = true;
    const io = new IntersectionObserver((es) => {
      if (es.some((e) => e.isIntersecting)) {
        io.disconnect();
        pageSvg(l, page).then((s) => alive && setSvg(s));
      }
    });
    if (ref.current) io.observe(ref.current);
    return () => {
      alive = false;
      io.disconnect();
    };
  }, [l, page]);
  return (
    <div className="pv-page" ref={ref} style={{ width: l.widthMm * scale, height: l.heightMm * scale }}>
      {svg ? <div className="svg-host" dangerouslySetInnerHTML={{ __html: svg }} /> : <div className="page-loading">…</div>}
      <span className="pv-num">{page}</span>
    </div>
  );
}

export function PrintPreview() {
  const original = getState().score;
  const [layout, setLayout] = useState<PageLayout>(structuredClone(original.layout));
  const [laid, setLaid] = useState<LaidOut | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [zoom, setZoom] = useState(0.9);
  const score: Score = useMemo(() => ({ ...original, layout }), [original, layout]);

  useEffect(() => {
    let alive = true;
    setBusy(true);
    const t = setTimeout(() => {
      layoutForPrint(score)
        .then((l) => {
          if (alive && l) {
            setLaid(l);
            setError(null);
          }
        })
        .catch((e) => alive && setError(String(e)))
        .finally(() => alive && setBusy(false));
    }, 150);
    return () => {
      alive = false;
      clearTimeout(t);
    };
  }, [score]);

  const apply = () => {
    if (JSON.stringify(layout) !== JSON.stringify(original.layout)) A.updateScore('Параметры страницы', (d) => void (d.layout = structuredClone(layout)));
  };
  const set = <K extends keyof PageLayout>(k: K, v: PageLayout[K]) => setLayout({ ...layout, [k]: v });
  const margin = (k: keyof PageLayout['margins']) => (e: React.ChangeEvent<HTMLInputElement>) => setLayout({ ...layout, margins: { ...layout.margins, [k]: Math.max(0, Math.min(80, Number(e.target.value))) } });
  const scale = 1.2 * zoom;

  return (
    <div className="modal-backdrop">
      <div className="preview">
        <div className="pv-side">
          <h2>Предварительный просмотр</h2>
          <label className="field">
            <span>Формат</span>
            <select value={layout.size} onChange={(e) => set('size', e.target.value as PageLayout['size'])}>
              <option value="A4">A4 (210 × 297 мм)</option>
              <option value="A3">A3 (297 × 420 мм)</option>
              <option value="Letter">Letter (216 × 279 мм)</option>
            </select>
          </label>
          <label className="field">
            <span>Ориентация</span>
            <select value={layout.orientation} onChange={(e) => set('orientation', e.target.value as PageLayout['orientation'])}>
              <option value="portrait">Книжная</option>
              <option value="landscape">Альбомная</option>
            </select>
          </label>
          <div className="row">
            <label className="field"><span>Поле сверху</span><input type="number" value={layout.margins.top} onChange={margin('top')} /></label>
            <label className="field"><span>снизу</span><input type="number" value={layout.margins.bottom} onChange={margin('bottom')} /></label>
          </div>
          <div className="row">
            <label className="field"><span>слева</span><input type="number" value={layout.margins.left} onChange={margin('left')} /></label>
            <label className="field"><span>справа, мм</span><input type="number" value={layout.margins.right} onChange={margin('right')} /></label>
          </div>
          <label className="field">
            <span>Тактов в системе (0 — автоматически)</span>
            <input type="number" min={0} max={32} value={layout.measuresPerSystem} onChange={(e) => set('measuresPerSystem', Math.max(0, Math.min(32, Number(e.target.value))))} />
          </label>
          <label className="field">
            <span>Расстояние между станами</span>
            <input type="range" min={4} max={40} value={layout.staffSpacing} onChange={(e) => set('staffSpacing', Number(e.target.value))} />
          </label>
          <label className="field">
            <span>Расстояние между системами</span>
            <input type="range" min={0} max={40} value={layout.systemSpacing} onChange={(e) => set('systemSpacing', Number(e.target.value))} />
          </label>
          <label className="field">
            <span>Размер нотного стана: {layout.staffScale} %</span>
            <input type="range" min={50} max={160} value={layout.staffScale} onChange={(e) => set('staffScale', Number(e.target.value))} />
          </label>
          <label className="field check-row">
            <input type="checkbox" checked={layout.showHeader} onChange={(e) => set('showHeader', e.target.checked)} /> Заголовок и композитор
          </label>
          <label className="field check-row">
            <input type="checkbox" checked={layout.showPageNumbers} onChange={(e) => set('showPageNumbers', e.target.checked)} /> Номера страниц
          </label>
          <p className="hint">{busy ? 'Раскладка…' : laid ? `Страниц: ${laid.pageCount}` : ''}</p>
          {error && <p className="hint error">{error}</p>}
          <div className="pv-buttons">
            <button className="primary" onClick={() => { apply(); A.closeDialog(); void exportPdf({ ...getState().score, layout }); }}>
              Экспорт PDF…
            </button>
            <button className="primary" onClick={() => { apply(); A.closeDialog(); void printDocument({ ...getState().score, layout }); }}>
              Печать…
            </button>
            <button onClick={() => { apply(); A.closeDialog(); }}>Применить и закрыть</button>
            <button onClick={A.closeDialog}>Отмена</button>
          </div>
        </div>
        <div className="pv-pages">
          <div className="pv-zoom">
            <button onClick={() => setZoom(Math.max(0.4, zoom / 1.2))}>−</button>
            <span>{Math.round(zoom * 100)}%</span>
            <button onClick={() => setZoom(Math.min(2.5, zoom * 1.2))}>+</button>
          </div>
          <div className="pv-grid">{laid && Array.from({ length: laid.pageCount }, (_, i) => <Thumb key={`${laid.renderId}-${i}`} l={laid} page={i + 1} scale={scale} />)}</div>
        </div>
      </div>
    </div>
  );
}
