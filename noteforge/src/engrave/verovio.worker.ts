/// <reference lib="webworker" />
// Verovio runs in a worker so layout of long scores never blocks the UI.
import createVerovioModule from 'verovio/wasm';
import { VerovioToolkit } from 'verovio/esm';

type Req =
  | { type: 'load'; renderId: number; mei: string; options: Record<string, unknown> }
  | { type: 'page'; renderId: number; page: number }
  | { type: 'pageOf'; renderId: number; reqId: number; xmlId: string };

let tk: VerovioToolkit | null = null;
let loadedId = -1;
const ready = createVerovioModule().then((m) => {
  tk = new VerovioToolkit(m);
  (self as unknown as Worker).postMessage({ type: 'ready', version: tk.getVersion() });
});

self.onmessage = async (e: MessageEvent<Req>) => {
  await ready;
  const msg = e.data;
  const post = (data: unknown) => (self as unknown as Worker).postMessage(data);
  try {
    if (msg.type === 'load') {
      const t0 = performance.now();
      tk!.setOptions(msg.options);
      const ok = tk!.loadData(msg.mei);
      loadedId = msg.renderId;
      post({ type: 'loaded', renderId: msg.renderId, ok, pageCount: ok ? tk!.getPageCount() : 0, log: tk!.getLog(), ms: performance.now() - t0 });
    } else if (msg.type === 'page') {
      if (msg.renderId !== loadedId) return; // stale request
      post({ type: 'page', renderId: msg.renderId, page: msg.page, svg: tk!.renderToSVG(msg.page, false) });
    } else if (msg.type === 'pageOf') {
      post({ type: 'pageOf', reqId: msg.reqId, page: msg.renderId === loadedId ? tk!.getPageWithElement(msg.xmlId) : 0 });
    }
  } catch (err) {
    post({ type: 'error', renderId: (msg as { renderId?: number }).renderId, message: String(err) });
  }
};
