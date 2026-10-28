/**
 * Minimal ZIP reader for compressed MusicXML (.mxl): central directory,
 * stored and deflated entries (via DecompressionStream).
 */
export interface ZipEntry {
  name: string;
  method: number;
  compressedSize: number;
  offset: number;
}

export function listZip(buf: ArrayBuffer): ZipEntry[] {
  const v = new DataView(buf);
  // End of central directory record (search backwards, comment up to 64 KiB).
  let eocd = -1;
  for (let i = buf.byteLength - 22; i >= Math.max(0, buf.byteLength - 65557); i--) {
    if (v.getUint32(i, true) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error('Файл не является ZIP-архивом (.mxl)');
  const count = v.getUint16(eocd + 10, true);
  let p = v.getUint32(eocd + 16, true);
  const out: ZipEntry[] = [];
  const dec = new TextDecoder();
  for (let k = 0; k < count; k++) {
    if (v.getUint32(p, true) !== 0x02014b50) throw new Error('Повреждённый ZIP-архив');
    const method = v.getUint16(p + 10, true);
    const compressedSize = v.getUint32(p + 20, true);
    const nameLen = v.getUint16(p + 28, true);
    const extraLen = v.getUint16(p + 30, true);
    const commentLen = v.getUint16(p + 32, true);
    const offset = v.getUint32(p + 42, true);
    const name = dec.decode(new Uint8Array(buf, p + 46, nameLen));
    out.push({ name, method, compressedSize, offset });
    p += 46 + nameLen + extraLen + commentLen;
  }
  return out;
}

export async function readZipEntry(buf: ArrayBuffer, e: ZipEntry): Promise<Uint8Array> {
  const v = new DataView(buf);
  if (v.getUint32(e.offset, true) !== 0x04034b50) throw new Error('Повреждённый ZIP-архив');
  const nameLen = v.getUint16(e.offset + 26, true);
  const extraLen = v.getUint16(e.offset + 28, true);
  const start = e.offset + 30 + nameLen + extraLen;
  const data = new Uint8Array(buf.slice(start, start + e.compressedSize));
  if (e.method === 0) return data;
  if (e.method !== 8) throw new Error(`Неподдерживаемое сжатие ZIP (${e.method})`);
  const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

/** Extracts the root MusicXML document of an .mxl archive. */
export async function readMxl(buf: ArrayBuffer): Promise<string> {
  const entries = listZip(buf);
  const dec = new TextDecoder();
  const container = entries.find((e) => e.name === 'META-INF/container.xml');
  let rootPath: string | undefined;
  if (container) {
    const xml = dec.decode(await readZipEntry(buf, container));
    rootPath = /full-path\s*=\s*"([^"]+)"/.exec(xml)?.[1];
  }
  const entry = entries.find((e) => e.name === rootPath) ?? entries.find((e) => /\.(musicxml|xml)$/i.test(e.name) && !e.name.startsWith('META-INF/'));
  if (!entry) throw new Error('В архиве .mxl не найдена партитура');
  return dec.decode(await readZipEntry(buf, entry));
}
