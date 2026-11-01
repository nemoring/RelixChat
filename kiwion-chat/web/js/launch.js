// Release countdown — the launch date comes from KIWION_LAUNCH_AT via /api/config/public.
import { mascot } from "./kiwi.js";

document.getElementById("bird").appendChild(mascot());
const pad = (n) => String(n).padStart(2, "0");

async function launchDate() {
  const q = new URLSearchParams(location.search).get("at"); // preview override: /launch?at=2027-01-01T00:00:00Z
  if (q && !isNaN(Date.parse(q))) return new Date(q);
  try {
    const r = await fetch("/api/config/public");
    const c = await r.json();
    return new Date(c.launch_at);
  } catch (_) {
    return null;
  }
}

launchDate().then((target) => {
  if (!target || isNaN(target)) { document.getElementById("date").textContent = "Дата запуска будет объявлена скоро"; return; }
  document.getElementById("date").textContent = "Запуск: " + target.toLocaleString("ru-RU", { dateStyle: "long", timeStyle: "short" });
  const tick = () => {
    let diff = Math.max(0, target - Date.now());
    const d = Math.floor(diff / 864e5); diff -= d * 864e5;
    const h = Math.floor(diff / 36e5); diff -= h * 36e5;
    const m = Math.floor(diff / 6e4); diff -= m * 6e4;
    const s = Math.floor(diff / 1e3);
    document.getElementById("d").textContent = d;
    document.getElementById("h").textContent = pad(h);
    document.getElementById("m").textContent = pad(m);
    document.getElementById("s").textContent = pad(s);
    if (target - Date.now() <= 0) {
      document.getElementById("cta").classList.remove("hidden");
      document.getElementById("date").textContent = "Kiwion Chat уже запущен! 🥝";
      return;
    }
    setTimeout(tick, 1000 - (Date.now() % 1000));
  };
  tick();
});
