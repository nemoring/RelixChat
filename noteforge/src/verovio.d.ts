declare module 'verovio/wasm' {
  const createVerovioModule: () => Promise<unknown>;
  export default createVerovioModule;
}
declare module 'verovio/esm' {
  export class VerovioToolkit {
    constructor(module: unknown);
    setOptions(options: Record<string, unknown>): void;
    loadData(data: string): boolean;
    getPageCount(): number;
    renderToSVG(page?: number, xmlDeclaration?: boolean): string;
    renderToMIDI(): string;
    renderToTimemap(options?: Record<string, unknown>): unknown[];
    getLog(): string;
    getVersion(): string;
    getPageWithElement(xmlId: string): number;
    getElementsAtTime(ms: number): unknown;
    getTimeForElement(xmlId: string): number;
    getMEI(options?: Record<string, unknown>): string;
    redoLayout(options?: Record<string, unknown>): void;
  }
}
