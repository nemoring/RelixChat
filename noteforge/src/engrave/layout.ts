import type { PageLayout } from '../model/types';

const SIZES_MM: Record<PageLayout['size'], [number, number]> = {
  A4: [210, 297],
  A3: [297, 420],
  Letter: [215.9, 279.4],
};

export function pageSizeMm(layout: PageLayout): [number, number] {
  const [w, h] = SIZES_MM[layout.size];
  return layout.orientation === 'landscape' ? [h, w] : [w, h];
}

/** CSS pixels per millimetre at 100 % zoom (96 dpi). */
export const PX_PER_MM = 96 / 25.4;

/** Verovio options for a page layout. Verovio page units are tenths of a millimetre. */
export function verovioOptions(layout: PageLayout, mode: 'page' | 'continuous'): Record<string, unknown> {
  const [w, h] = pageSizeMm(layout);
  const base: Record<string, unknown> = {
    pageWidth: Math.round(w * 10),
    pageHeight: Math.round(h * 10),
    pageMarginTop: Math.round(layout.margins.top * 10),
    pageMarginBottom: Math.round(layout.margins.bottom * 10),
    pageMarginLeft: Math.round(layout.margins.left * 10),
    pageMarginRight: Math.round(layout.margins.right * 10),
    scale: layout.staffScale,
    scaleToPageSize: true,
    svgViewBox: true,
    svgRemoveXlink: true,
    header: 'encoded',
    footer: 'encoded',
    breaks: 'auto',
    adjustPageHeight: false,
    justifyVertically: false,
    font: 'Leipzig',
    xmlIdSeed: 1,
  };
  if (mode === 'continuous') {
    Object.assign(base, { breaks: 'none', adjustPageWidth: true, adjustPageHeight: true, header: 'none', footer: 'none' });
  }
  return base;
}
