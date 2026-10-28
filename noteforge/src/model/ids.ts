/** Short unique ids, valid as XML ids (start with a letter). */
const ALPHABET = 'abcdefghijklmnopqrstuvwxyz0123456789';
let counter = 0;
const session = randomChars(4);

function randomChars(n: number): string {
  const bytes = new Uint8Array(n);
  globalThis.crypto.getRandomValues(bytes);
  let s = '';
  for (const b of bytes) s += ALPHABET[b % ALPHABET.length];
  return s;
}

export function newId(prefix = 'e'): string {
  counter++;
  return `${prefix}${session}${counter.toString(36)}`;
}
