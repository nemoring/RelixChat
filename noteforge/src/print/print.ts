/**
 * Print / PDF: lays out the whole score with Verovio (page mode, current page
 * settings) in a dedicated worker and streams the vector SVG pages to the
 * main process, which prints them through Chromium (PDF or system dialog).
 */
import { Engraver } from '../engrave/engraver';
import { scoreToMei } from '../engrave/mei';
import { verovioOptions, pageSizeMm, hasForcedBreaks } from '../engrave/layout';
import type { Score } from '../model/types';

let printEngraver: Engraver | null = null;
export function getPrintEngraver(): Engraver {
  if (!printEngraver) printEngraver = new Engraver();
  return printEngraver;
}

export interface LaidOut {
  renderId: number;
  pageCount: number;
  widthMm: number;
  heightMm: number;
}

/** Lays out the score for printing; returns null if superseded. */
export async function layoutForPrint(score: Score): Promise<LaidOut | null> {
  const eng = getPrintEngraver();
  const info = await eng.load(scoreToMei(score).mei, verovioOptions(score.layout, 'page', hasForcedBreaks(score)));
  if (!info) return null;
  if (!info.ok) throw new Error(info.log || 'Verovio не смог разметить партитуру');
  const [widthMm, heightMm] = pageSizeMm(score.layout);
  return { renderId: info.renderId, pageCount: info.pageCount, widthMm, heightMm };
}

export function pageSvg(l: LaidOut, page: number): Promise<string> {
  return getPrintEngraver().page(l.renderId, page);
}

export interface PrintSink {
  begin(widthMm: number, heightMm: number, title: string): Promise<string>;
  page(job: string, svg: string): Promise<void>;
  finish(job: string, action: 'pdf' | 'print', suggestedName: string): Promise<string | null>;
}

/** Renders every page and hands it to the sink (main process). */
export async function printScore(score: Score, action: 'pdf' | 'print', suggestedName: string, sink: PrintSink, onProgress?: (f: number) => void): Promise<string | null> {
  const l = await layoutForPrint(score);
  if (!l) return null;
  const job = await sink.begin(l.widthMm, l.heightMm, score.meta.title || 'NoteForge');
  for (let p = 1; p <= l.pageCount; p++) {
    await sink.page(job, await pageSvg(l, p));
    onProgress?.(p / l.pageCount);
  }
  return sink.finish(job, action, suggestedName);
}
