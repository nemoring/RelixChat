// Kiwion Web — API client (fetch + Server-Sent Events over POST)
const TOKEN_KEY = "kiwion.token";
const DEVICE_KEY = "kiwion.device";

export class ApiError extends Error {
  constructor(status, code, message, extra = {}) { super(message); this.status = status; this.code = code; this.extra = extra; }
}

const store = {
  get(k) { try { return localStorage.getItem(k); } catch (_) { return null; } },
  set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch (_) {} },
};
export { store };

export function deviceId() {
  let id = store.get(DEVICE_KEY);
  if (!id) {
    const b = new Uint8Array(16); crypto.getRandomValues(b);
    id = "web-" + Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
    store.set(DEVICE_KEY, id);
  }
  return id;
}

export const auth = {
  get token() { return store.get(TOKEN_KEY); },
  set token(v) { store.set(TOKEN_KEY, v); },
};

async function parseError(res) {
  let data = {};
  try { data = await res.json(); } catch (_) {}
  const d = data.detail || data.error || {};
  const code = typeof d === "object" ? d.code || "error" : "error";
  const msg = typeof d === "object" ? d.message || `Ошибка ${res.status}` : String(d);
  return new ApiError(res.status, code, msg, typeof d === "object" ? d : {});
}

export async function api(path, { method = "GET", body, signal, raw = false } = {}) {
  const headers = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (auth.token) headers.Authorization = `Bearer ${auth.token}`;
  let res;
  try {
    res = await fetch(path, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined, signal });
  } catch (e) {
    if (e.name === "AbortError") throw e;
    throw new ApiError(0, "network", "Нет соединения с сервером. Проверьте интернет.");
  }
  if (res.status === 401 && auth.token) {
    auth.token = null;
    window.dispatchEvent(new CustomEvent("kiwion:logout"));
  }
  if (!res.ok) throw await parseError(res);
  if (raw) return res;
  return res.status === 204 ? null : res.json();
}

/** POST that returns an SSE stream; calls onEvent for every `data:` JSON event. */
export async function stream(path, { method = "POST", body, signal, onEvent }) {
  const res = await api(path, { method, body, signal, raw: true });
  const reader = res.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    let idx;
    while ((idx = buf.indexOf("\n\n")) >= 0) {
      const block = buf.slice(0, idx); buf = buf.slice(idx + 2);
      for (const line of block.split("\n")) {
        if (line.startsWith("data: ")) {
          const payload = line.slice(6);
          if (payload !== "[DONE]") onEvent(JSON.parse(payload));
        }
      }
    }
  }
}

/** Hashcash proof of work required by /api/auth/register (anti-bot). */
export async function solvePow(challenge, difficulty, signal) {
  const enc = new TextEncoder();
  const zeroBits = (buf) => {
    const b = new Uint8Array(buf); let bits = 0;
    for (const x of b) { if (x === 0) { bits += 8; continue; } bits += Math.clz32(x) - 24; break; }
    return bits;
  };
  const batch = 512;
  for (let n = 0; ; n += batch) {
    if (signal && signal.aborted) throw new DOMException("aborted", "AbortError");
    const jobs = [];
    for (let i = n; i < n + batch; i++) jobs.push(crypto.subtle.digest("SHA-256", enc.encode(`${challenge}:${i}`)));
    const res = await Promise.all(jobs);
    for (let i = 0; i < res.length; i++) if (zeroBits(res[i]) >= difficulty) return String(n + i);
  }
}
