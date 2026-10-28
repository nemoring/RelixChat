// Bundles the Electron main process and preload script into dist-electron/.
import { build } from 'esbuild';

const common = {
  bundle: true,
  platform: 'node',
  target: 'node20',
  format: 'cjs',
  external: ['electron'],
  sourcemap: true,
  logLevel: 'info',
};

export async function buildElectron() {
  await build({ ...common, entryPoints: ['electron/main.ts'], outfile: 'dist-electron/main.cjs' });
  await build({ ...common, entryPoints: ['electron/preload.ts'], outfile: 'dist-electron/preload.cjs' });
}

if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('build-electron.mjs')) {
  await buildElectron();
}
