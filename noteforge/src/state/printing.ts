/** Print, PDF export and print preview commands. */
import { getState, setState } from './store';
import { platform } from '../platform';
import { printScore } from '../print/print';
import type { Score } from '../model/types';

function baseName(): string {
  const s = getState();
  if (s.filePath) return s.filePath.split(/[\\/]/).pop()!.replace(/\.nfg$/i, '');
  return s.score.meta.title || 'Без названия';
}

const sink = {
  begin: (w: number, h: number, title: string) => platform.printBegin(w, h, title),
  page: (job: string, svg: string) => platform.printPage(job, svg),
  finish: (job: string, action: 'pdf' | 'print', name: string) => platform.printFinish(job, action, name),
};

export async function exportPdf(score: Score = getState().score): Promise<string | null> {
  setState({ exportProgress: { text: 'Экспорт PDF…', progress: 0 } });
  try {
    const p = await printScore(score, 'pdf', `${baseName()}.pdf`, sink, (f) => setState({ exportProgress: { text: 'Экспорт PDF…', progress: f } }));
    if (p) setState({ status: `PDF сохранён: ${p}` });
    return p;
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Ошибка экспорта PDF', text: (e as Error).message } } });
    return null;
  } finally {
    setState({ exportProgress: null });
  }
}

export async function printDocument(score: Score = getState().score): Promise<void> {
  setState({ exportProgress: { text: 'Подготовка к печати…', progress: 0 } });
  try {
    const r = await printScore(score, 'print', baseName(), {
      ...sink,
      finish: async (job, action, name) => {
        setState({ exportProgress: null });
        return sink.finish(job, action, name);
      },
    }, (f) => setState({ exportProgress: { text: 'Подготовка к печати…', progress: f } }));
    if (r) setState({ status: 'Отправлено на печать' });
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Ошибка печати', text: (e as Error).message } } });
  } finally {
    setState({ exportProgress: null });
  }
}
