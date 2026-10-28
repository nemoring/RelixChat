/**
 * Client side of the Verovio worker. Load requests are coalesced: while a
 * layout is running only the most recent pending request is kept.
 */
export interface LoadedInfo {
  renderId: number;
  pageCount: number;
  ok: boolean;
  log: string;
  ms: number;
}

type Pending = { mei: string; options: Record<string, unknown>; resolve: (i: LoadedInfo | null) => void };

export class Engraver {
  private worker: Worker;
  private nextId = 1;
  private busy = false;
  private pending: Pending | null = null;
  private loadResolvers = new Map<number, (i: LoadedInfo) => void>();
  private pageWaiters = new Map<string, ((svg: string) => void)[]>();
  private pageOfWaiters = new Map<number, (p: number) => void>();
  currentId = 0;

  constructor() {
    this.worker = new Worker(new URL('./verovio.worker.ts', import.meta.url), { type: 'module' });
    this.worker.onmessage = (e) => this.onMessage(e.data);
  }

  private onMessage(msg: any) {
    if (msg.type === 'loaded') {
      this.loadResolvers.get(msg.renderId)?.(msg);
      this.loadResolvers.delete(msg.renderId);
    } else if (msg.type === 'page') {
      const key = `${msg.renderId}:${msg.page}`;
      for (const w of this.pageWaiters.get(key) ?? []) w(msg.svg);
      this.pageWaiters.delete(key);
    } else if (msg.type === 'pageOf') {
      this.pageOfWaiters.get(msg.reqId)?.(msg.page);
      this.pageOfWaiters.delete(msg.reqId);
    } else if (msg.type === 'error') {
      console.error('[verovio]', msg.message);
    }
  }

  /** Lays out a new MEI document. Resolves null if superseded by a newer request. */
  load(mei: string, options: Record<string, unknown>): Promise<LoadedInfo | null> {
    return new Promise((resolve) => {
      if (this.pending) this.pending.resolve(null);
      this.pending = { mei, options, resolve };
      this.pump();
    });
  }

  private pump() {
    if (this.busy || !this.pending) return;
    const job = this.pending;
    this.pending = null;
    this.busy = true;
    const renderId = this.nextId++;
    this.loadResolvers.set(renderId, (info) => {
      this.busy = false;
      this.currentId = renderId;
      job.resolve(this.pending ? null : info);
      this.pump();
    });
    this.worker.postMessage({ type: 'load', renderId, mei: job.mei, options: job.options });
  }

  page(renderId: number, page: number): Promise<string> {
    return new Promise((resolve) => {
      const key = `${renderId}:${page}`;
      const list = this.pageWaiters.get(key);
      if (list) list.push(resolve);
      else {
        this.pageWaiters.set(key, [resolve]);
        this.worker.postMessage({ type: 'page', renderId, page });
      }
    });
  }

  pageOf(renderId: number, xmlId: string): Promise<number> {
    return new Promise((resolve) => {
      const reqId = this.nextId++;
      this.pageOfWaiters.set(reqId, resolve);
      this.worker.postMessage({ type: 'pageOf', renderId, reqId, xmlId });
    });
  }
}

let instance: Engraver | null = null;
export function getEngraver(): Engraver {
  if (!instance) instance = new Engraver();
  return instance;
}
