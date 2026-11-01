// Kiwion mascot ("Fluffy Kiwi") and the secret Kiwi Easter Egg 🥝
// Works fully offline: pure SVG + Web Animations API + Web Audio (no assets to download).

const MASCOT_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 200" width="220" height="200" role="img" aria-label="Fluffy Kiwi — маскот Kiwion Chat">
  <title>Fluffy Kiwi</title>
  <defs>
    <radialGradient id="kw-body" cx="42%" cy="38%" r="70%">
      <stop offset="0" stop-color="#B9875A"/>
      <stop offset="0.6" stop-color="#94643C"/>
      <stop offset="1" stop-color="#6E4627"/>
    </radialGradient>
    <radialGradient id="kw-belly" cx="50%" cy="40%" r="60%">
      <stop offset="0" stop-color="#E2C29A"/>
      <stop offset="1" stop-color="#C79E70" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="kw-beak" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#F3DDB8"/>
      <stop offset="1" stop-color="#D9B07E"/>
    </linearGradient>
    <linearGradient id="kw-leaf" x1="0" y1="1" x2="1" y2="0">
      <stop offset="0" stop-color="#3E9B3A"/>
      <stop offset="1" stop-color="#8FD14F"/>
    </linearGradient>
  </defs>
  <ellipse class="kw-shadow" cx="104" cy="186" rx="58" ry="8" fill="#000" opacity="0.12"/>
  <g class="kw-legs" stroke="#C98E4F" stroke-width="6" stroke-linecap="round" fill="none">
    <path d="M86 158 L82 180 M82 180 L70 184 M82 180 L84 186 M82 180 L92 184"/>
    <path d="M118 158 L120 180 M120 180 L108 184 M120 180 L122 186 M120 180 L131 183"/>
  </g>
  <g class="kw-bird">
    <g class="kw-fluff" fill="#8A5B35">
      <circle cx="44" cy="112" r="14"/><circle cx="50" cy="92" r="14"/><circle cx="64" cy="76" r="14"/>
      <circle cx="84" cy="66" r="14"/><circle cx="106" cy="62" r="14"/><circle cx="40" cy="132" r="13"/>
      <circle cx="48" cy="150" r="13"/><circle cx="66" cy="162" r="13"/><circle cx="90" cy="168" r="13"/>
      <circle cx="116" cy="166" r="13"/><circle cx="138" cy="156" r="13"/>
    </g>
    <g class="kw-wing kw-wing-back">
      <ellipse cx="78" cy="86" rx="10" ry="17" fill="#6E4627" transform="rotate(-30 78 86)"/>
    </g>
    <ellipse class="kw-body" cx="100" cy="118" rx="60" ry="52" fill="url(#kw-body)"/>
    <ellipse cx="108" cy="134" rx="36" ry="28" fill="url(#kw-belly)" opacity="0.8"/>
    <g class="kw-fur" stroke="#6B4425" stroke-width="2" stroke-linecap="round" opacity="0.45" fill="none">
      <path d="M62 104 q6 -4 10 2"/><path d="M70 126 q6 -4 10 2"/><path d="M58 140 q6 -4 10 2"/>
      <path d="M90 90 q6 -4 10 2"/><path d="M84 150 q6 -4 10 2"/>
    </g>
    <g class="kw-head">
      <circle cx="140" cy="92" r="32" fill="url(#kw-body)"/>
      <g class="kw-sprout">
        <path d="M134 62 q-2 -10 2 -16" stroke="#3E8E37" stroke-width="3" fill="none" stroke-linecap="round"/>
        <path d="M136 48 q-16 -8 -22 4 q12 6 22 -4z" fill="url(#kw-leaf)"/>
        <path d="M136 48 q12 -14 24 -6 q-10 12 -24 6z" fill="url(#kw-leaf)"/>
      </g>
      <path class="kw-beak" d="M164 96 q20 6 40 34 q2 4 -3 3 q-22 -20 -40 -26z" fill="url(#kw-beak)" stroke="#C49563" stroke-width="1"/>
      <ellipse class="kw-blush" cx="152" cy="104" rx="7" ry="4.5" fill="#F29B9B" opacity="0.7"/>
      <g class="kw-eye">
        <ellipse class="kw-eye-open" cx="150" cy="86" rx="6" ry="7" fill="#1E1410"/>
        <circle class="kw-eye-open" cx="152" cy="83.5" r="2.2" fill="#fff"/>
        <path class="kw-eye-closed" d="M143 87 q7 6 14 0" stroke="#1E1410" stroke-width="2.6" fill="none" stroke-linecap="round" opacity="0"/>
      </g>
    </g>
    <g class="kw-wing kw-wing-front">
      <ellipse cx="96" cy="120" rx="13" ry="20" fill="#86562F" transform="rotate(-18 96 120)"/>
      <path d="M90 112 q6 6 4 16" stroke="#6B4425" stroke-width="1.6" fill="none" opacity="0.6"/>
    </g>
  </g>
</svg>`;

let _uid = 0;
export function mascot(cls = "") {
  // make gradient ids unique so several mascots can live on one page
  const n = ++_uid;
  const svg = MASCOT_SVG.replace(/id="kw-/g, `id="kw${n}-`).replace(/url\(#kw-/g, `url(#kw${n}-`);
  const wrap = document.createElement("span");
  wrap.innerHTML = svg;
  const el = wrap.firstElementChild;
  if (cls) el.setAttribute("class", cls);
  return el;
}

export function mascotHTML(cls = "") {
  return mascot(cls).outerHTML;
}

export const prefersReducedMotion = () =>
  window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Counts quick consecutive taps; fires on the N-th tap when gaps are <= maxGapMs. */
export class TapCounter {
  constructor(required = 5, maxGapMs = 1500, now = () => performance.now()) {
    this.required = required; this.maxGapMs = maxGapMs; this.now = now; this.count = 0; this.last = -Infinity;
  }
  tap() {
    const t = this.now();
    if (t - this.last > this.maxGapMs) this.count = 0;
    this.last = t;
    this.count += 1;
    if (this.count >= this.required) { this.count = 0; this.last = -Infinity; return true; }
    return false;
  }
}

// ---------------------------------------------------------------- sound
function chirp() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return;
    const ctx = new Ctx();
    const notes = [[1250, 1750, 0], [1500, 2100, 0.16], [1900, 1600, 0.34]];
    for (const [f0, f1, at] of notes) {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.type = "sine";
      o.frequency.setValueAtTime(f0, ctx.currentTime + at);
      o.frequency.exponentialRampToValueAtTime(f1, ctx.currentTime + at + 0.12);
      g.gain.setValueAtTime(0.0001, ctx.currentTime + at);
      g.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + at + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + at + 0.14);
      o.connect(g).connect(ctx.destination);
      o.start(ctx.currentTime + at); o.stop(ctx.currentTime + at + 0.16);
    }
    setTimeout(() => ctx.close(), 900);
  } catch (_) { /* sound is optional */ }
}

// ---------------------------------------------------------------- easter egg
const EGG_CSS = `
.kiwi-egg{position:fixed;inset:0;z-index:1000;display:flex;align-items:flex-end;justify-content:center;overflow:hidden;
  background:rgba(8,16,6,0);transition:background .5s ease;font-family:inherit}
.kiwi-egg.dim{background:rgba(8,16,6,.55)}
.kiwi-egg .egg-close{position:absolute;top:14px;right:14px;width:42px;height:42px;border-radius:50%;border:0;cursor:pointer;
  background:rgba(255,255,255,.9);color:#1c2419;font-size:22px;line-height:1;box-shadow:0 4px 14px rgba(0,0,0,.25)}
.kiwi-egg .egg-stage{position:relative;width:min(320px,80vw);height:min(560px,88vh);display:flex;flex-direction:column;
  align-items:center;justify-content:flex-end;padding-bottom:12vh}
.kiwi-egg .egg-title{position:absolute;top:8%;left:50%;transform:translateX(-50%) scale(.6);opacity:0;white-space:nowrap;
  background:#fff;color:#1f5f2a;font-weight:800;font-size:clamp(16px,4.6vw,22px);padding:10px 16px;border-radius:16px;
  box-shadow:0 8px 24px rgba(0,0,0,.25)}
.kiwi-egg .egg-title:after{content:"";position:absolute;left:50%;bottom:-8px;margin-left:-8px;border:8px solid transparent;border-bottom:0;border-top-color:#fff}
.kiwi-egg .egg-bird{width:min(240px,62vw);transform:translateY(120vh);transform-origin:50% 100%}
.kiwi-egg .egg-bird svg{width:100%;height:auto;overflow:visible}
.kiwi-egg .kw-wing-front,.kiwi-egg .kw-wing-back,.kiwi-egg .kw-head{transform-box:fill-box;transform-origin:50% 10%}
.kiwi-egg .kw-head{transform-origin:30% 80%}
.kiwi-egg .egg-pet{margin-top:22px;opacity:0;transform:translateY(12px);pointer-events:none;border:0;cursor:pointer;
  background:#4caf50;color:#fff;font-weight:700;font-size:16px;padding:12px 22px;border-radius:14px;box-shadow:0 6px 18px rgba(76,175,80,.45);
  transition:opacity .4s ease,transform .4s ease}
.kiwi-egg .egg-pet.show{opacity:1;transform:none;pointer-events:auto}
.kiwi-egg .egg-happy{position:absolute;top:18%;left:50%;transform:translateX(-50%);color:#fff;font-weight:800;font-size:20px;
  opacity:0;text-shadow:0 2px 8px rgba(0,0,0,.4);white-space:nowrap}
.kiwi-egg .egg-particle{position:absolute;border-radius:50%;pointer-events:none}
.kiwi-egg .egg-heart{position:absolute;pointer-events:none;font-size:22px}
`;

function injectCss() {
  if (document.getElementById("kiwi-egg-css")) return;
  const s = document.createElement("style");
  s.id = "kiwi-egg-css";
  s.textContent = EGG_CSS;
  document.head.appendChild(s);
}

const sleep = (ms, signal) => new Promise((res, rej) => {
  const t = setTimeout(res, ms);
  signal?.addEventListener("abort", () => { clearTimeout(t); rej(new DOMException("closed", "AbortError")); });
});

export class KiwiEasterEgg {
  constructor({ onClose } = {}) { this.onClose = onClose; this.root = null; this.ctrl = null; this.anims = []; }

  get isOpen() { return !!this.root; }

  open() {
    if (this.root) return;
    injectCss();
    this.reduced = prefersReducedMotion();
    this.ctrl = new AbortController();
    this.lastFocus = document.activeElement;
    const root = document.createElement("div");
    root.className = "kiwi-egg";
    root.setAttribute("role", "dialog");
    root.setAttribute("aria-modal", "true");
    root.setAttribute("aria-label", "Fluffy Kiwi");
    root.innerHTML = `
      <button class="egg-close" aria-label="Закрыть">×</button>
      <div class="egg-stage">
        <div class="egg-title" aria-live="polite">You've found the Fluffy Kiwi! 🥝</div>
        <div class="egg-happy" aria-live="polite">Kiwi is happy!</div>
        <div class="egg-bird"></div>
        <button class="egg-pet" tabindex="-1">Погладить киви</button>
      </div>`;
    root.querySelector(".egg-bird").appendChild(mascot());
    this.root = root;
    this.$ = (sel) => root.querySelector(sel);
    root.querySelector(".egg-close").addEventListener("click", () => this.close());
    root.addEventListener("click", (e) => { if (e.target === root) this.close(); });
    this.$(".egg-pet").addEventListener("click", () => this.pet());
    this._onKey = (e) => { if (e.key === "Escape") this.close(); };
    document.addEventListener("keydown", this._onKey);
    document.body.appendChild(root);
    root.querySelector(".egg-close").focus({ preventScroll: true });
    this.run().catch((e) => { if (e.name !== "AbortError") console.error(e); });
  }

  close() {
    if (!this.root) return;
    this.ctrl.abort();
    this.anims.forEach((a) => { try { a.cancel(); } catch (_) {} });
    this.anims = [];
    clearInterval(this.blinkTimer);
    document.removeEventListener("keydown", this._onKey);
    this.root.remove();
    this.root = null;
    if (this.lastFocus && this.lastFocus.focus) this.lastFocus.focus({ preventScroll: true });
    this.onClose && this.onClose();
  }

  a(el, frames, opts) {
    if (!el || !el.animate) return { finished: Promise.resolve(), cancel() {} };
    const anim = el.animate(frames, { fill: "forwards", ...opts });
    this.anims.push(anim);
    return anim;
  }

  async run() {
    const sig = this.ctrl.signal;
    const bird = this.$(".egg-bird"), title = this.$(".egg-title"), pet = this.$(".egg-pet");
    requestAnimationFrame(() => this.root && this.root.classList.add("dim"));               // 4. dim the screen
    if (this.reduced) {
      // Reduced motion: no jumping or spinning — the kiwi simply appears.
      bird.style.transform = "none";
      this.a(bird, [{ opacity: 0 }, { opacity: 1 }], { duration: 300 });
      this.a(title, [{ opacity: 0, transform: "translateX(-50%) scale(1)" }, { opacity: 1, transform: "translateX(-50%) scale(1)" }], { duration: 300 });
      await sleep(400, sig);
      this.showPet(pet);
      return;
    }
    await sleep(250, sig);
    // 5. jump out from the bottom of the screen, 6. land
    await this.a(bird, [
      { transform: "translateY(120vh) scale(.9,1.1)", easing: "cubic-bezier(.2,.7,.3,1)" },
      { transform: "translateY(-70px) scale(.95,1.05)", offset: .65, easing: "cubic-bezier(.5,0,.8,.5)" },
      { transform: "translateY(0) scale(1.12,.86)", offset: .88 },
      { transform: "translateY(0) scale(1,1)" },
    ], { duration: 1100 }).finished;
    // blink and look at the user
    await this.blink(); await sleep(180, sig); await this.blink();
    await this.a(this.$(".kw-head"), [{ transform: "rotate(0)" }, { transform: "rotate(-8deg)" }, { transform: "rotate(0)" }],
      { duration: 700, easing: "ease-in-out" }).finished;
    // 7. funny hops while flapping the tiny wings
    const flap = { duration: 160, iterations: 14, direction: "alternate", easing: "ease-in-out" };
    this.a(this.$(".kw-wing-front"), [{ transform: "rotate(0)" }, { transform: "rotate(-55deg)" }], flap);
    this.a(this.$(".kw-wing-back"), [{ transform: "rotate(0)" }, { transform: "rotate(45deg)" }], flap);
    // 8. the label appears above the bird
    this.a(title, [{ opacity: 0, transform: "translateX(-50%) scale(.6)" },
      { opacity: 1, transform: "translateX(-50%) scale(1.08)", offset: .7 }, { opacity: 1, transform: "translateX(-50%) scale(1)" }],
      { duration: 500, easing: "ease-out" });
    for (let i = 0; i < 3; i++) {
      await this.a(bird, [
        { transform: "translateY(0) scale(1.08,.92)" }, { transform: "translateY(-46px) scale(.96,1.04)", offset: .45 },
        { transform: "translateY(0) scale(1.1,.9)", offset: .85 }, { transform: "translateY(0) scale(1,1)" },
      ], { duration: 520, easing: "ease-in-out" }).finished;
    }
    // 9. happy spin + green particles
    this.burst(30);
    await this.a(bird, [
      { transform: "translateY(0) rotate(0)" }, { transform: "translateY(-30px) rotate(180deg) scale(1.05)", offset: .5 },
      { transform: "translateY(0) rotate(360deg)" },
    ], { duration: 1000, easing: "ease-in-out" }).finished;
    this.idleBlink();
    // 10. after a few seconds the "pet the kiwi" button appears
    await sleep(1800, sig);
    this.showPet(pet);
  }

  showPet(pet) {
    pet.classList.add("show");
    pet.tabIndex = 0;
  }

  setEyes(closed) {
    if (!this.root) return;
    this.root.querySelectorAll(".kw-eye-open").forEach((e) => (e.style.opacity = closed ? "0" : "1"));
    this.root.querySelectorAll(".kw-eye-closed").forEach((e) => (e.style.opacity = closed ? "1" : "0"));
  }

  async blink() {
    this.setEyes(true);
    await sleep(120, this.ctrl.signal);
    this.setEyes(false);
  }

  idleBlink() {
    clearInterval(this.blinkTimer);
    this.blinkTimer = setInterval(() => { if (!this.petting) this.blink().catch(() => {}); }, 2600);
  }

  burst(n) {
    const stage = this.$(".egg-stage");
    const rect = this.$(".egg-bird").getBoundingClientRect(), srect = stage.getBoundingClientRect();
    const cx = rect.left - srect.left + rect.width / 2, cy = rect.top - srect.top + rect.height / 2;
    const colors = ["#8bd450", "#4caf50", "#b6e07a", "#2e8b3e", "#d7f5b0"];
    for (let i = 0; i < n; i++) {
      const p = document.createElement("span");
      const size = 6 + Math.random() * 8;
      p.className = "egg-particle";
      Object.assign(p.style, { width: size + "px", height: size + "px", left: cx + "px", top: cy + "px",
        background: colors[i % colors.length] });
      stage.appendChild(p);
      const ang = (Math.PI * 2 * i) / n + Math.random() * .4, dist = 110 + Math.random() * 110;
      const anim = this.a(p, [
        { transform: "translate(-50%,-50%) scale(.4)", opacity: 1 },
        { transform: `translate(calc(-50% + ${Math.cos(ang) * dist}px), calc(-50% + ${Math.sin(ang) * dist}px)) scale(1)`, opacity: 1, offset: .7 },
        { transform: `translate(calc(-50% + ${Math.cos(ang) * dist * 1.15}px), calc(-50% + ${Math.sin(ang) * dist * 1.15 + 30}px)) scale(.6)`, opacity: 0 },
      ], { duration: 1400 + Math.random() * 500, easing: "cubic-bezier(.15,.7,.3,1)" });
      anim.finished.then(() => p.remove()).catch(() => {});
    }
  }

  async pet() {
    if (!this.root || this.petting) return;
    this.petting = true;
    const sig = this.ctrl.signal;
    try {
      this.setEyes(true);                                  // closes the eyes
      chirp();                                             // cute sound
      const happy = this.$(".egg-happy");
      this.a(happy, [{ opacity: 0, transform: "translateX(-50%) translateY(10px)" }, { opacity: 1, transform: "translateX(-50%) translateY(0)" }],
        { duration: this.reduced ? 1 : 400, easing: "ease-out" });
      this.hearts(this.reduced ? 3 : 7);
      if (!this.reduced) {
        this.a(this.$(".egg-bird"), [{ transform: "scale(1,1)" }, { transform: "scale(1.06,.94)" }, { transform: "scale(1,1)" }],
          { duration: 600, iterations: 2, easing: "ease-in-out" });
      }
      await sleep(2400, sig);
      this.setEyes(false);
    } catch (_) { /* closed */ } finally { this.petting = false; }
  }

  hearts(n) {
    const stage = this.$(".egg-stage");
    const bird = this.$(".egg-bird").getBoundingClientRect(), s = stage.getBoundingClientRect();
    for (let i = 0; i < n; i++) {
      const h = document.createElement("span");
      h.className = "egg-heart";
      h.textContent = i % 3 === 2 ? "💚" : "❤️";
      Object.assign(h.style, { left: (bird.left - s.left + bird.width * (0.35 + Math.random() * 0.5)) + "px",
        top: (bird.top - s.top + 10) + "px" });
      stage.appendChild(h);
      const rise = this.reduced
        ? [{ opacity: 0 }, { opacity: 1, offset: .3 }, { opacity: 0 }]
        : [{ transform: "translateY(0) scale(.5)", opacity: 0 }, { transform: "translateY(-30px) scale(1.1)", opacity: 1, offset: .25 },
           { transform: `translate(${(Math.random() - .5) * 60}px, -140px) scale(.9)`, opacity: 0 }];
      const anim = this.a(h, rise, { duration: 1600 + Math.random() * 600, delay: i * 140, easing: "ease-out" });
      anim.finished.then(() => h.remove()).catch(() => {});
    }
  }
}
