/** MusicXML import / export commands. */
import { getState, setState, loadDocument, isDirty } from './store';
import { platform } from '../platform';
import { scoreToMusicXml } from '../io/musicxml-export';
import { musicXmlToScore } from '../io/musicxml-import';
import { readMxl } from '../io/zip';

function baseName(): string {
  const s = getState();
  if (s.filePath) return s.filePath.split(/[\\/]/).pop()!.replace(/\.nfg$/i, '');
  return s.score.meta.title || 'Без названия';
}

export async function exportMusicXml(): Promise<void> {
  try {
    const p = await platform.saveText(`${baseName()}.musicxml`, 'MusicXML', 'musicxml', scoreToMusicXml(getState().score));
    if (p) setState({ status: `Экспортировано в MusicXML: ${p}` });
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Ошибка экспорта MusicXML', text: (e as Error).message } } });
  }
}

/** Decodes .musicxml / .xml (UTF-8 or UTF-16) or compressed .mxl bytes. */
export async function decodeMusicXml(data: ArrayBuffer): Promise<string> {
  const b = new Uint8Array(data);
  if (b[0] === 0x50 && b[1] === 0x4b) return readMxl(data);
  if (b[0] === 0xff && b[1] === 0xfe) return new TextDecoder('utf-16le').decode(b);
  if (b[0] === 0xfe && b[1] === 0xff) return new TextDecoder('utf-16be').decode(b);
  return new TextDecoder('utf-8').decode(b);
}

export async function importMusicXml(): Promise<void> {
  if (isDirty(getState()) && !window.confirm('В партитуре есть несохранённые изменения. Продолжить без сохранения?')) return;
  const f = await platform.openBinary('MusicXML', ['musicxml', 'xml', 'mxl']);
  if (!f) return;
  try {
    const { score, warnings } = musicXmlToScore(await decodeMusicXml(f.data));
    loadDocument(score, null);
    setState({ status: `Импортирован MusicXML: ${f.name}` });
    if (warnings.length) setState({ dialog: { kind: 'message', message: { title: 'MusicXML импортирован с замечаниями', text: warnings.slice(0, 25).join('\n') } } });
  } catch (e) {
    setState({ dialog: { kind: 'message', message: { title: 'Не удалось импортировать MusicXML', text: (e as Error).message } } });
  }
}
