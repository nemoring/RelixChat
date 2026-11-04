// Kiwion Chat — web client
import { api, ApiError, auth, deviceId, solvePow, store, stream } from "./api.js";
import { KiwiEasterEgg, mascotHTML, TapCounter } from "./kiwi.js";

const OVERLOADED = "Птичка киви немного устала 🥝. Сейчас слишком много запросов. Попробуйте отправить сообщение позже";
const LOGO = "/assets/kiwi/logo.png";
const root = document.getElementById("root");
const S = { user: null, config: null, chats: [], chatId: null, messages: [], streaming: null, model: null,
            settingsTab: "profile", search: "" };

// ------------------------------------------------------------------ helpers
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const $ = (sel, el = document) => el.querySelector(sel);
const $$ = (sel, el = document) => Array.from(el.querySelectorAll(sel));
const fmtDate = (iso) => iso ? new Date(iso).toLocaleString("ru-RU", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";
const fmtNum = (n) => Number(n || 0).toLocaleString("ru-RU");
const I = {
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  send: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h13M13 6l6 6-6 6"/></svg>',
  stop: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2.5"/></svg>',
  copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/></svg>',
  redo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/></svg>',
  edit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 20h4L19 9l-4-4L4 16v4z"/></svg>',
  trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/></svg>',
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></svg>',
  back: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M15 18l-6-6 6-6"/></svg>',
  sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M5 19l1.5-1.5M17.5 6.5L19 5"/></svg>',
};

function toast(msg, kind = "ok", icon) {
  let box = $(".toasts");
  if (!box) { box = document.createElement("div"); box.className = "toasts"; box.setAttribute("aria-live", "polite"); document.body.appendChild(box); }
  const t = document.createElement("div");
  t.className = `toast ${kind}`;
  t.innerHTML = `<span class="t-icon">${icon || (kind === "bad" ? "⚠️" : kind === "warn" ? "🥝" : "✅")}</span><div>${esc(msg)}</div>`;
  box.appendChild(t);
  setTimeout(() => t.remove(), kind === "ok" ? 3000 : 7000);
}

function modal({ title, body = "", input = null, confirm = "OK", danger = false, cancel = "Отмена" }) {
  return new Promise((resolve) => {
    const back = document.createElement("div");
    back.className = "modal-back";
    back.innerHTML = `<div class="modal card" role="dialog" aria-modal="true"><h3>${esc(title)}</h3>
      ${body ? `<p>${body}</p>` : ""}
      ${input ? `<input class="input" type="${input.type || "text"}" value="${esc(input.value || "")}" placeholder="${esc(input.placeholder || "")}" maxlength="${input.max || 120}">` : ""}
      <div class="row"><button class="btn ghost" data-a="no">${esc(cancel)}</button><button class="btn ${danger ? "danger" : ""}" data-a="yes">${esc(confirm)}</button></div></div>`;
    const done = (v) => { back.remove(); resolve(v); };
    back.addEventListener("click", (e) => { if (e.target === back) done(null); });
    $('[data-a="no"]', back).addEventListener("click", () => done(null));
    const inp = $("input", back);
    const ok = () => done(inp ? inp.value : true);
    $('[data-a="yes"]', back).addEventListener("click", ok);
    back.addEventListener("keydown", (e) => { if (e.key === "Enter") ok(); if (e.key === "Escape") done(null); });
    document.body.appendChild(back);
    (inp || $('[data-a="yes"]', back)).focus();
    if (inp) inp.select();
  });
}

function errMsg(e) {
  if (e instanceof ApiError) {
    if (e.code === "overloaded") return OVERLOADED;
    if (e.code === "validation_error" && e.extra.errors?.length) return `${e.message}: ${e.extra.errors.map((x) => x.field).join(", ")}`;
    return e.message;
  }
  return "Что-то пошло не так";
}

// ------------------------------------------------------------------ theme
function applyTheme(pref) {
  pref = pref || store.get("kiwion.theme") || "system";
  const dark = pref === "dark" || (pref === "system" && matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.theme = dark ? "dark" : "light";
  $("#hljs-theme")?.setAttribute("href", dark ? "/vendor/hljs-dark.css" : "/vendor/hljs-light.css");
}
matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", () => applyTheme());

// ------------------------------------------------------------------ markdown
function renderMarkdown(text) {
  const html = window.marked ? window.marked.parse(text || "", { gfm: true, breaks: true }) : esc(text);
  const clean = window.DOMPurify ? window.DOMPurify.sanitize(html, { USE_PROFILES: { html: true } }) : esc(text);
  const div = document.createElement("div");
  div.className = "md";
  div.innerHTML = clean;
  $$("a", div).forEach((a) => { a.target = "_blank"; a.rel = "noopener noreferrer nofollow"; });
  $$("pre code", div).forEach((code) => {
    const lang = (code.className.match(/language-([\w+-]+)/) || [])[1] || "";
    try { if (window.hljs) window.hljs.highlightElement(code); } catch (_) {}
    const head = document.createElement("div");
    head.className = "code-head";
    head.innerHTML = `<span class="lang">${esc(lang)}</span><button class="copy-code" type="button">Копировать</button>`;
    code.parentElement.appendChild(head);
  });
  return div;
}

async function copyText(text, btn) {
  try {
    await navigator.clipboard.writeText(text);
  } catch (_) {
    const ta = document.createElement("textarea"); ta.value = text; document.body.appendChild(ta); ta.select();
    document.execCommand("copy"); ta.remove();
  }
  if (btn) { const old = btn.innerHTML; btn.textContent = "✓"; setTimeout(() => (btn.innerHTML = old), 1200); }
  else toast("Скопировано");
}
document.addEventListener("click", (e) => {
  const b = e.target.closest(".copy-code");
  if (b) copyText(b.closest("pre").querySelector("code").innerText, b);
});

// ------------------------------------------------------------------ router
function route() {
  const h = location.hash.replace(/^#\/?/, "");
  const [path, qs] = h.split("?");
  const parts = path.split("/").filter(Boolean);
  return { name: parts[0] || "", parts, params: new URLSearchParams(qs || "") };
}
const go = (hash) => { if (location.hash !== hash) location.hash = hash; else render(); };
window.addEventListener("hashchange", () => render());
window.addEventListener("kiwion:logout", () => { S.user = null; go("#/login"); });

// referral code from ?ref=... (kept until registration)
const refParam = new URLSearchParams(location.search).get("ref");
if (refParam) store.set("kiwion.ref", refParam.toUpperCase().slice(0, 16));

// ------------------------------------------------------------------ screens
function splash(text = "Загружаем птичку киви…") {
  root.innerHTML = `<div class="screen splash" role="status">${mascotHTML("mascot")}
    <h1 class="brand-title">Kiwion <span>Chat</span></h1><p class="brand-sub">${esc(text)}</p>
    <div class="loader-dots"><i></i><i></i><i></i></div></div>`;
}

function errorScreen(code, title, text, action = "Попробовать снова") {
  root.innerHTML = `<div class="screen error-screen">${mascotHTML("mascot")}<p class="code">${esc(code)}</p>
    <h2>${esc(title)}</h2><p class="brand-sub">${esc(text)}</p><button class="btn" id="retry">${esc(action)}</button></div>`;
  $("#retry").addEventListener("click", () => boot());
}

function authShell(title, inner, sub = "") {
  root.innerHTML = `<div class="screen"><div class="auth-wrap">
    <div class="auth-head"><img src="${LOGO}" alt="Kiwion Chat" width="84" height="84" style="border-radius:22px">
    <h1 class="brand-title">Kiwion <span>Chat</span></h1><p class="brand-sub">${esc(sub || "ИИ-помощник от Kiwi_Fuzzy")}</p></div>
    <div class="card"><h2 style="margin-top:0">${esc(title)}</h2>${S.config?.maintenance ? `<div class="notice warn">${esc(S.config.maintenance_message)}</div>` : ""}${inner}</div>
    </div></div>`;
}

function formErr(form, msg) { $(".error-text", form).textContent = msg || ""; }
async function submitting(form, fn) {
  const btn = $("button[type=submit]", form);
  btn.disabled = true; formErr(form, "");
  try { await fn(); } catch (e) { formErr(form, errMsg(e)); } finally { btn.disabled = false; }
}

function loginScreen(params) {
  authShell("Вход", `<form id="f" novalidate>
    ${params.get("msg") ? `<div class="notice">${esc(params.get("msg"))}</div>` : ""}
    <div class="field"><label for="email">Email</label><input class="input" id="email" type="email" autocomplete="email" required></div>
    <div class="field"><label for="pw">Пароль</label><input class="input" id="pw" type="password" autocomplete="current-password" required></div>
    <div class="error-text" role="alert"></div>
    <button class="btn block" type="submit">Войти</button>
    <div class="auth-links"><a href="#/register">Создать аккаунт</a><a href="#/forgot">Забыли пароль?</a></div></form>`);
  const f = $("#f");
  f.addEventListener("submit", (e) => { e.preventDefault(); submitting(f, async () => {
    const r = await api("/api/auth/login", { method: "POST", body: { email: $("#email").value.trim(), password: $("#pw").value,
      device_id: deviceId(), device_name: browserName() } });
    auth.token = r.token; S.user = r.user; await enterApp();
  }); });
  $("#email").focus();
}

function browserName() {
  const ua = navigator.userAgent;
  const b = /Edg\//.test(ua) ? "Edge" : /Firefox\//.test(ua) ? "Firefox" : /Chrome\//.test(ua) ? "Chrome" : /Safari\//.test(ua) ? "Safari" : "Браузер";
  const os = /Android/.test(ua) ? "Android" : /iPhone|iPad/.test(ua) ? "iOS" : /Windows/.test(ua) ? "Windows" : /Mac/.test(ua) ? "macOS" : /Linux/.test(ua) ? "Linux" : "";
  return `${b}${os ? " · " + os : ""}`;
}

function registerScreen() {
  const ref = store.get("kiwion.ref") || "";
  if (S.config && !S.config.registration_open) {
    authShell("Регистрация", `<div class="notice warn">Регистрация временно закрыта. Загляните позже 🥝</div><a href="#/login">Войти</a>`);
    return;
  }
  authShell("Регистрация", `<form id="f" novalidate>
    ${ref ? `<div class="notice">Вас пригласили! Код приглашения: <b>${esc(ref)}</b></div>` : ""}
    <div class="field"><label for="name">Как вас зовут</label><input class="input" id="name" maxlength="64" autocomplete="nickname"></div>
    <div class="field"><label for="email">Email</label><input class="input" id="email" type="email" autocomplete="email" required></div>
    <div class="field"><label for="pw">Пароль</label><input class="input" id="pw" type="password" autocomplete="new-password" minlength="8" required>
      <span class="hint">Минимум 8 символов, буквы и цифры</span></div>
    <label class="hint" style="display:flex;gap:8px;align-items:center;margin-bottom:12px"><input type="checkbox" id="terms" checked> Я принимаю условия использования</label>
    <div class="error-text" role="alert"></div>
    <button class="btn block" type="submit">Создать аккаунт</button>
    <p class="hint" id="pow-state">Защита от ботов: готовим проверку…</p>
    <div class="auth-links"><a href="#/login">Уже есть аккаунт? Войти</a></div></form>`);
  const f = $("#f");
  let pow = null;
  const ctrl = new AbortController();
  const preparePow = async () => {
    const ch = await api("/api/auth/challenge");
    const nonce = await solvePow(ch.challenge, ch.difficulty, ctrl.signal);
    pow = { challenge: ch.challenge, nonce };
    const st = $("#pow-state"); if (st) st.textContent = "Защита от ботов: проверка пройдена ✓";
  };
  let powPromise = preparePow().catch(() => {});
  window.addEventListener("hashchange", () => ctrl.abort(), { once: true });
  f.addEventListener("submit", (e) => { e.preventDefault(); submitting(f, async () => {
    if (!$("#terms").checked) throw new ApiError(400, "terms", "Необходимо принять условия использования");
    await powPromise;
    if (!pow) { powPromise = preparePow(); await powPromise; }
    const body = { email: $("#email").value.trim(), password: $("#pw").value, display_name: $("#name").value.trim(),
      device_id: deviceId(), device_name: browserName(), pow, referral_code: ref || null, accept_terms: true };
    try {
      const r = await api("/api/auth/register", { method: "POST", body });
      store.set("kiwion.ref", null);
      auth.token = r.token; S.user = r.user;
      go("#/verify-pending");
    } catch (err) {
      pow = null; powPromise = preparePow().catch(() => {});  // a proof can be used only once
      throw err;
    }
  }); });
}

function verifyPendingScreen() {
  authShell("Подтвердите email", `<div class="notice">Мы отправили письмо на <b>${esc(S.user?.email || "")}</b>. Перейдите по ссылке из письма, чтобы начать общение с киви.</div>
    <div class="error-text" role="alert"></div>
    <button class="btn block" id="check">Я подтвердил(а)</button>
    <div class="auth-links"><a href="#" id="resend">Отправить письмо ещё раз</a><a href="#" id="logout">Выйти</a></div>`);
  $("#check").addEventListener("click", async () => {
    const me = await api("/api/account/me").catch(() => null);
    if (me?.is_verified) { S.user = me; enterApp(); } else $(".error-text").textContent = "Email ещё не подтверждён — проверьте почту (и папку «Спам»)";
  });
  $("#resend").addEventListener("click", async (e) => { e.preventDefault();
    try { const r = await api("/api/auth/resend-verification", { method: "POST" }); toast(r.message); } catch (err) { toast(errMsg(err), "bad"); } });
  $("#logout").addEventListener("click", (e) => { e.preventDefault(); logout(); });
}

async function verifyScreen(params) {
  splash("Подтверждаем email…");
  try {
    const r = await api("/api/auth/verify", { method: "POST", body: { token: params.get("token") || "" } });
    toast(r.message, "ok", "🥝");
    if (auth.token) { S.user = await api("/api/account/me"); return enterApp(); }
    go("#/login?msg=" + encodeURIComponent("Email подтверждён! Теперь войдите."));
  } catch (e) {
    authShell("Подтверждение email", `<div class="notice bad">${esc(errMsg(e))}</div><a href="#/login">Ко входу</a>`);
  }
}

function forgotScreen() {
  authShell("Восстановление пароля", `<form id="f" novalidate>
    <p class="hint">Введите email — пришлём ссылку для смены пароля.</p>
    <div class="field"><label for="email">Email</label><input class="input" id="email" type="email" required></div>
    <div class="error-text" role="alert"></div><button class="btn block" type="submit">Отправить ссылку</button>
    <div class="auth-links"><a href="#/login">Назад ко входу</a></div></form>`);
  const f = $("#f");
  f.addEventListener("submit", (e) => { e.preventDefault(); submitting(f, async () => {
    const r = await api("/api/auth/forgot", { method: "POST", body: { email: $("#email").value.trim() } });
    f.innerHTML = `<div class="notice">${esc(r.message)}</div><a href="#/login">Назад ко входу</a>`;
  }); });
}

function resetScreen(params) {
  authShell("Новый пароль", `<form id="f" novalidate>
    <div class="field"><label for="pw">Новый пароль</label><input class="input" id="pw" type="password" autocomplete="new-password" required></div>
    <div class="field"><label for="pw2">Повторите пароль</label><input class="input" id="pw2" type="password" autocomplete="new-password" required></div>
    <div class="error-text" role="alert"></div><button class="btn block" type="submit">Сохранить</button></form>`);
  const f = $("#f");
  f.addEventListener("submit", (e) => { e.preventDefault(); submitting(f, async () => {
    if ($("#pw").value !== $("#pw2").value) throw new ApiError(400, "mismatch", "Пароли не совпадают");
    const r = await api("/api/auth/reset", { method: "POST", body: { token: params.get("token") || "", new_password: $("#pw").value } });
    auth.token = null;
    go("#/login?msg=" + encodeURIComponent(r.message));
  }); });
}

// ------------------------------------------------------------------ app shell
function shell() {
  if ($(".app")) return;
  root.innerHTML = `<div class="app">
    <aside class="sidebar" aria-label="Диалоги">
      <div class="sidebar-head"><img class="logo" src="${LOGO}" alt="" style="border-radius:10px"><b>Kiwion Chat</b>
        <span style="flex:1"></span><button class="icon-btn" id="new-chat" title="Новый чат" aria-label="Новый чат">${I.plus}</button></div>
      <div class="chat-search"><input class="input" id="search" placeholder="Поиск по чатам" aria-label="Поиск по чатам"></div>
      <nav class="chat-list" id="chat-list"></nav>
      <div class="sidebar-foot"><div class="avatar" id="avatar">K</div>
        <div class="user-mini"><div id="u-name"></div><div class="muted" id="u-quota"></div></div>
        <a class="icon-btn" href="#/settings" title="Настройки" aria-label="Настройки">${I.gear}</a></div>
    </aside>
    <div class="scrim" id="scrim"></div>
    <main class="main" id="main"></main></div>`;
  $("#new-chat").addEventListener("click", () => newChat());
  $("#scrim").addEventListener("click", () => $(".app").classList.remove("nav-open"));
  $("#search").addEventListener("input", (e) => { S.search = e.target.value.toLowerCase(); renderChatList(); });
  renderUserMini();
}

function renderUserMini() {
  if (!S.user || !$("#u-name")) return;
  $("#u-name").textContent = S.user.display_name || S.user.email;
  $("#avatar").textContent = (S.user.display_name || S.user.email || "K")[0].toUpperCase();
  const q = S.user.quota;
  $("#u-quota").textContent = q ? `Осталось сегодня: ${fmtNum(q.remaining)} ток.` : S.user.email;
}

function renderChatList() {
  const list = $("#chat-list");
  if (!list) return;
  const chats = S.chats.filter((c) => !S.search || c.title.toLowerCase().includes(S.search));
  if (!chats.length) { list.innerHTML = `<p class="hint" style="padding:10px">${S.search ? "Ничего не найдено" : "Пока нет диалогов"}</p>`; return; }
  list.innerHTML = `<div class="list-label">Диалоги</div>` + chats.map((c) => `
    <a class="chat-item ${c.id === S.chatId ? "active" : ""}" href="#/chat/${c.id}" data-id="${c.id}">
      <span class="title">${esc(c.title)}</span>
      <span class="actions"><button class="icon-btn" data-act="rename" title="Переименовать" aria-label="Переименовать">${I.edit}</button>
      <button class="icon-btn" data-act="delete" title="Удалить" aria-label="Удалить">${I.trash}</button></span></a>`).join("");
  $$(".chat-item", list).forEach((el) => {
    el.addEventListener("click", (e) => {
      const act = e.target.closest("[data-act]")?.dataset.act;
      if (act) { e.preventDefault(); act === "rename" ? renameChat(el.dataset.id) : deleteChat(el.dataset.id); }
      $(".app").classList.remove("nav-open");
    });
  });
}

async function loadChats() {
  S.chats = await api("/api/chats");
  renderChatList();
}

async function refreshUser() {
  try { S.user = await api("/api/account/me"); renderUserMini(); } catch (_) {}
}

async function newChat() {
  if (S.streaming) return toast("Дождитесь окончания ответа", "warn");
  try {
    const c = await api("/api/chats", { method: "POST", body: {} });
    S.chats.unshift(c);
    go(`#/chat/${c.id}`);
  } catch (e) { toast(errMsg(e), "bad"); }
}

async function renameChat(id) {
  const c = S.chats.find((x) => x.id === id);
  const title = await modal({ title: "Переименовать чат", input: { value: c?.title || "" }, confirm: "Сохранить" });
  if (!title || !title.trim()) return;
  try { const r = await api(`/api/chats/${id}`, { method: "PATCH", body: { title: title.trim() } });
    Object.assign(c, r); renderChatList(); if (id === S.chatId) $("#chat-title").textContent = r.title; }
  catch (e) { toast(errMsg(e), "bad"); }
}

async function deleteChat(id) {
  const ok = await modal({ title: "Удалить чат?", body: "Диалог будет удалён на всех устройствах.", confirm: "Удалить", danger: true });
  if (!ok) return;
  try {
    await api(`/api/chats/${id}`, { method: "DELETE" });
    S.chats = S.chats.filter((c) => c.id !== id);
    store.set("kiwion.draft." + id, null);
    if (id === S.chatId) go("#/chat"); else renderChatList();
  } catch (e) { toast(errMsg(e), "bad"); }
}

// ------------------------------------------------------------------ model status
async function pollModel() {
  try { S.model = await api("/api/model/status"); } catch (_) { S.model = { state: "offline" }; }
  renderModelPill();
}
function renderModelPill() {
  const el = $("#model-pill");
  if (!el || !S.model) return;
  const m = S.model;
  let cls = "bad", text = "Модель офлайн";
  if (m.state === "online") {
    cls = m.busy ? "warn" : "ok";
    text = m.queue_waiting ? `Очередь: ${m.queue_waiting}` : `${m.model || "Модель"} · онлайн`;
    if (m.engine === "mock") text += " (тест)";
  } else if (m.state === "loading") { cls = "warn"; text = "Модель загружается…"; }
  el.className = `pill ${cls}`;
  el.innerHTML = `<span class="dot"></span>${esc(text)}`;
  el.title = m.tokens_per_second ? `Скорость: ${m.tokens_per_second} ток/с` : "";
}

// ------------------------------------------------------------------ chat view
const SUGGESTIONS = ["Объясни, почему киви не умеют летать", "Напиши функцию на Python для сортировки списка",
  "Придумай 5 идей для выходных", "Помоги составить письмо коллеге"];

async function chatView(id) {
  shell();
  const main = $("#main");
  if (!id) {
    const last = store.get("kiwion.lastChat");
    if (last && S.chats.some((c) => c.id === last)) return go(`#/chat/${last}`);
  }
  S.chatId = id || null;
  renderChatList();
  const chat = S.chats.find((c) => c.id === id);
  main.innerHTML = `<header class="topbar">
      <button class="icon-btn menu-btn" id="menu" aria-label="Меню">${I.menu}</button>
      <div class="chat-title" id="chat-title">${esc(chat?.title || "Kiwion Chat")}</div>
      <span class="pill" id="model-pill"><span class="dot"></span>…</span></header>
    <section class="messages" id="messages" aria-live="polite"><div class="messages-inner" id="msgs"></div></section>
    <div class="composer-wrap"><form class="composer" id="composer">
      <textarea id="input" rows="1" placeholder="Напишите сообщение…" aria-label="Сообщение" maxlength="${S.config?.max_message_chars || 8000}"></textarea>
      <button class="btn send" type="submit" id="send" aria-label="Отправить">${I.send}</button></form>
      <div class="composer-note"><span id="queue-note"></span><span>Kiwion может ошибаться. Проверяйте важное.</span></div></div>`;
  $("#menu").addEventListener("click", () => $(".app").classList.toggle("nav-open"));
  renderModelPill();
  const input = $("#input");
  const draftKey = () => "kiwion.draft." + (S.chatId || "new");
  input.value = store.get(draftKey()) || "";
  autosize(input);
  input.addEventListener("input", () => { store.set(draftKey(), input.value || null); autosize(input); });
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); $("#composer").requestSubmit(); }
  });
  $("#composer").addEventListener("submit", (e) => { e.preventDefault(); S.streaming ? stopGeneration() : send(); });
  if (!id) { S.messages = []; renderMessages(); input.focus(); return; }
  store.set("kiwion.lastChat", id);
  $("#msgs").innerHTML = `<div class="typing"><span class="hops"><i></i><i></i><i></i></span>Загружаем историю…</div>`;
  try {
    const data = await api(`/api/chats/${id}`);
    if (S.chatId !== id) return;
    S.messages = data.messages;
    $("#chat-title").textContent = data.title;
    renderMessages();
  } catch (e) {
    if (e.status === 404) { store.set("kiwion.lastChat", null); toast("Чат не найден", "warn"); return go("#/chat"); }
    $("#msgs").innerHTML = `<div class="notice bad">${esc(errMsg(e))}</div>`;
  }
  updateComposer();
  if (matchMedia("(min-width: 861px)").matches) input.focus();
}

function autosize(t) { t.style.height = "auto"; t.style.height = Math.min(t.scrollHeight, 220) + "px"; }

function renderMessages() {
  const box = $("#msgs");
  if (!box) return;
  if (!S.messages.length) {
    box.innerHTML = `<div class="empty">${mascotHTML("mascot")}<h2>Привет! Я киви 🥝</h2>
      <p>Спросите что-нибудь — я отвечу с помощью модели ${esc(S.config?.model || "")}.</p>
      <div class="suggestions">${SUGGESTIONS.map((s) => `<button class="suggestion" type="button">${esc(s)}</button>`).join("")}</div></div>`;
    $$(".suggestion", box).forEach((b) => b.addEventListener("click", () => { $("#input").value = b.textContent; send(); }));
    return;
  }
  box.innerHTML = "";
  const lastAssistant = [...S.messages].reverse().find((m) => m.role === "assistant");
  S.messages.forEach((m) => box.appendChild(messageEl(m, m === lastAssistant)));
  scrollDown(true);
}

function messageEl(m, isLast) {
  const el = document.createElement("div");
  el.className = `msg ${m.role}${isLast ? " last" : ""}`;
  el.dataset.id = m.id;
  if (m.role === "user") {
    el.innerHTML = `<div class="user-col"><div class="bubble"></div>
      <div class="msg-tools"><button class="icon-btn" data-act="copy" title="Копировать" aria-label="Копировать">${I.copy}</button>
      <button class="icon-btn" data-act="edit" title="Редактировать" aria-label="Редактировать">${I.edit}</button></div></div>`;
    $(".bubble", el).textContent = m.content;
  } else {
    el.innerHTML = `<div class="kiwi-avatar">${mascotHTML()}</div><div class="bubble"><div class="content"></div>
      <div class="status-note"></div>
      <div class="msg-tools"><button class="icon-btn" data-act="copy" title="Копировать ответ" aria-label="Копировать ответ">${I.copy}</button>
      ${isLast ? `<button class="icon-btn" data-act="regen" title="Сгенерировать заново" aria-label="Сгенерировать заново">${I.redo}</button>` : ""}
      <span class="msg-meta">${m.completion_tokens ? m.completion_tokens + " ток." : ""}</span></div></div>`;
    $(".content", el).appendChild(renderMarkdown(m.content));
    const note = { stopped: "⏹ Генерация остановлена", error: "⚠️ Ответ не получен" }[m.status];
    if (note) $(".status-note", el).textContent = note;
  }
  el.addEventListener("click", (e) => {
    const act = e.target.closest("[data-act]")?.dataset.act;
    if (act === "copy") copyText(m.content, e.target.closest("button"));
    if (act === "regen") regenerate();
    if (act === "edit") editMessage(el, m);
  });
  return el;
}

function scrollDown(force) {
  const s = $("#messages");
  if (!s) return;
  const near = s.scrollHeight - s.scrollTop - s.clientHeight < 160;
  if (force || near) s.scrollTop = s.scrollHeight;
}

function updateComposer() {
  const btn = $("#send");
  if (!btn) return;
  const busy = S.streaming && S.streaming.chatId === S.chatId;
  btn.innerHTML = busy ? I.stop : I.send;
  btn.setAttribute("aria-label", busy ? "Остановить" : "Отправить");
  btn.title = busy ? "Остановить генерацию" : "Отправить";
}

function editMessage(el, m) {
  if (S.streaming) return toast("Дождитесь окончания ответа", "warn");
  const bubble = $(".bubble", el);
  const wrap = bubble.parentElement;
  wrap.style.width = "100%";
  wrap.innerHTML = `<div class="edit-box" style="width:100%"><textarea class="input">${esc(m.content)}</textarea>
    <div class="row"><button class="btn ghost small" data-e="cancel">Отмена</button><button class="btn small" data-e="save">Отправить</button></div></div>`;
  const ta = $("textarea", wrap); ta.focus();
  $('[data-e="cancel"]', wrap).addEventListener("click", (e) => { e.stopPropagation(); renderMessages(); });
  $('[data-e="save"]', wrap).addEventListener("click", (e) => {
    e.stopPropagation();
    const text = ta.value.trim();
    if (!text) return;
    generate(`/api/chats/${S.chatId}/messages/${m.id}`, "PUT", { content: text }, { editId: m.id, text });
  });
}

async function ensureChat() {
  if (S.chatId) return S.chatId;
  const c = await api("/api/chats", { method: "POST", body: {} });
  S.chats.unshift(c);
  S.chatId = c.id;
  history.replaceState(null, "", `#/chat/${c.id}`);
  store.set("kiwion.lastChat", c.id);
  renderChatList();
  return c.id;
}

async function send() {
  const input = $("#input");
  const text = input.value.trim();
  if (!text || S.streaming) return;
  if (!navigator.onLine) return toast("Нет подключения к интернету. Сообщение сохранено в поле ввода.", "warn", "📡");
  let id;
  try { id = await ensureChat(); } catch (e) { return toast(errMsg(e), "bad"); }
  const oldDraft = "kiwion.draft.new";
  generate(`/api/chats/${id}/messages`, "POST", { content: text }, { text, clearInput: true, draftKeys: [oldDraft, "kiwion.draft." + id] });
}

function regenerate() {
  if (S.streaming) return;
  generate(`/api/chats/${S.chatId}/regenerate`, "POST", undefined, {});
}

async function generate(path, method, body, opts) {
  const chatId = S.chatId;
  const ctrl = new AbortController();
  S.streaming = { chatId, ctrl };
  updateComposer();
  const box = $("#msgs");
  // optimistic UI
  let pendingUser = null;
  if (opts.text && !opts.editId) {
    if (!S.messages.length) box.innerHTML = "";
    pendingUser = messageEl({ id: "pending", role: "user", content: opts.text }, false);
    box.appendChild(pendingUser);
  }
  $$(".msg.last [data-act=regen]", box).forEach((b) => b.remove());
  const aEl = document.createElement("div");
  aEl.className = "msg assistant";
  aEl.innerHTML = `<div class="kiwi-avatar">${mascotHTML()}</div><div class="bubble"><div class="content">
    <span class="typing"><span class="hops"><i></i><i></i><i></i></span><span class="tlabel">Киви думает…</span></span></div></div>`;
  box.appendChild(aEl);
  scrollDown(true);
  let text = "", started = false, raf = 0, finalMsg = null, failed = null;
  const paint = () => {
    raf = 0;
    const c = $(".content", aEl);
    c.innerHTML = "";
    const md = renderMarkdown(text);
    md.lastElementChild ? md.lastElementChild.classList.add("cursor") : md.classList.add("cursor");
    c.appendChild(md);
    scrollDown();
  };
  try {
    await stream(path, { method, body, signal: ctrl.signal, onEvent: (ev) => {
      if (ev.type === "meta") {
        if (opts.clearInput) {
          const inp = $("#input"); if (inp && inp.value.trim() === opts.text) { inp.value = ""; autosize(inp); }
          (opts.draftKeys || []).forEach((k) => store.set(k, null));
        }
        const um = ev.user_message;
        if (ev.replaced_after_seq != null) S.messages = S.messages.filter((m) => m.seq <= ev.replaced_after_seq);
        if (opts.editId || ev.replaced_after_seq != null) {
          S.messages = S.messages.filter((m) => m.id !== um.id); S.messages.push(um);
          renderMessages(); $("#msgs").appendChild(aEl);
        } else {
          S.messages.push(um);
          if (pendingUser) pendingUser.dataset.id = um.id;
        }
        const c = S.chats.find((x) => x.id === ev.chat.id);
        if (c) { Object.assign(c, ev.chat); S.chats = [c, ...S.chats.filter((x) => x !== c)]; renderChatList(); }
        if (S.chatId === chatId) $("#chat-title").textContent = ev.chat.title;
      } else if (ev.type === "queued") {
        const l = $(".tlabel", aEl); if (l) l.textContent = `Вы в очереди: ${ev.position}. Киви скоро ответит…`;
        $("#queue-note") && ($("#queue-note").textContent = `Позиция в очереди: ${ev.position}`);
      } else if (ev.type === "start") {
        const l = $(".tlabel", aEl); if (l) l.textContent = "Киви печатает…";
        $("#queue-note") && ($("#queue-note").textContent = "");
      } else if (ev.type === "token") {
        started = true;
        text += ev.text;
        if (!raf) raf = requestAnimationFrame(paint);
      } else if (ev.type === "error") {
        failed = ev;
      } else if (ev.type === "done") {
        finalMsg = ev.message;
      }
    } });
  } catch (e) {
    if (e.name === "AbortError") {
      // stopped by user: server saves the partial answer; refresh to get it
    } else {
      failed = e instanceof ApiError ? { code: e.code, message: errMsg(e) } : { code: "network", message: "Соединение прервано" };
    }
  } finally {
    if (raf) cancelAnimationFrame(raf);
    S.streaming = null;
    updateComposer();
    $("#queue-note") && ($("#queue-note").textContent = "");
  }
  if (failed && !started && !finalMsg) {
    // nothing stored on the server — keep the user's text so it can be resent
    aEl.remove();
    if (pendingUser) pendingUser.remove();
    if (opts.text && !opts.editId) {
      const inp = $("#input");
      if (inp && !inp.value.trim()) { inp.value = opts.text; autosize(inp); store.set("kiwion.draft." + (S.chatId || "new"), opts.text); }
    }
    if (failed.code === "overloaded") toast(OVERLOADED, "warn", "🥝");
    else toast(failed.message || "Не удалось получить ответ", "bad");
    if (!S.messages.length) renderMessages();
    if (opts.editId) renderMessages();
    return;
  }
  if (failed) toast(failed.code === "overloaded" ? OVERLOADED : failed.message, "warn", "🥝");
  // re-sync with the server (restores exact stored state, e.g. after stop)
  if (S.chatId === chatId) {
    try {
      let data;
      for (let i = 0; i < 10; i++) {       // wait until the server has stored the final state
        data = await api(`/api/chats/${chatId}`);
        if (!data.messages.some((m) => m.status === "streaming")) break;
        await new Promise((r) => setTimeout(r, 300));
      }
      if (S.chatId === chatId) { S.messages = data.messages; renderMessages(); }
    } catch (_) { if (finalMsg) { S.messages.push(finalMsg); renderMessages(); } }
  }
  refreshUser();
}

async function stopGeneration() {
  const s = S.streaming;
  if (!s) return;
  s.stopping = true;
  updateComposer();
  // ask the server to stop; it saves the partial answer and closes the stream with a "done" event.
  // If the network is stuck we abort locally as a fallback.
  api(`/api/chats/${s.chatId}/stop`, { method: "POST" }).catch(() => s.ctrl.abort());
  setTimeout(() => { if (S.streaming === s) s.ctrl.abort(); }, 4000);
}

// ------------------------------------------------------------------ settings
const TABS = [["profile", "Профиль"], ["appearance", "Оформление"], ["security", "Безопасность"], ["api", "API-ключи"],
  ["referrals", "Рефералы"], ["about", "О приложении"]];

function settingsView(tab) {
  shell();
  S.chatId = null; renderChatList();
  S.settingsTab = tab || S.settingsTab || "profile";
  const main = $("#main");
  main.innerHTML = `<header class="topbar"><button class="icon-btn menu-btn" id="menu" aria-label="Меню">${I.menu}</button>
    <a class="icon-btn" href="#/chat" aria-label="Назад к чатам">${I.back}</a><div class="chat-title">Настройки</div></header>
    <section class="settings"><div class="settings-inner">
      <div class="tabs" role="tablist">${TABS.map(([k, v]) => `<button class="tab ${k === S.settingsTab ? "active" : ""}" data-tab="${k}" role="tab">${v}</button>`).join("")}</div>
      <div id="tab-body"></div></div></section>`;
  $("#menu").addEventListener("click", () => $(".app").classList.toggle("nav-open"));
  $$(".tab", main).forEach((b) => b.addEventListener("click", () => go(`#/settings/${b.dataset.tab}`)));
  ({ profile: tabProfile, appearance: tabAppearance, security: tabSecurity, api: tabApi, referrals: tabReferrals, about: tabAbout }
    [S.settingsTab] || tabProfile)($("#tab-body"));
}

function tabProfile(el) {
  const u = S.user, q = u.quota || {};
  el.innerHTML = `<div class="card section"><h3>Профиль</h3>
    <div class="field"><label for="dn">Имя</label><input class="input" id="dn" maxlength="64" value="${esc(u.display_name)}"></div>
    <div class="field"><label>Email</label><input class="input" value="${esc(u.email)}" disabled></div>
    <button class="btn" id="save">Сохранить</button></div>
    <div class="card section"><h3>Лимиты</h3><div class="stat-grid">
      <div class="stat"><b>${fmtNum(q.used_today)}</b><span>использовано сегодня</span></div>
      <div class="stat"><b>${fmtNum(q.daily_limit)}</b><span>дневной лимит токенов</span></div>
      <div class="stat"><b>${fmtNum(u.bonus_tokens)}</b><span>бонусных токенов</span></div>
      <div class="stat"><b>${u.discount_percent}%</b><span>накопленная скидка</span></div></div>
      <p class="hint">История диалогов хранится в аккаунте и синхронизируется между всеми вашими устройствами.</p></div>
    <div class="card section"><h3>Выход</h3><button class="btn ghost" id="logout">Выйти из аккаунта</button></div>`;
  $("#save").addEventListener("click", async () => {
    try { S.user = await api("/api/account/me", { method: "PATCH", body: { display_name: $("#dn").value.trim() } }); renderUserMini(); toast("Сохранено"); }
    catch (e) { toast(errMsg(e), "bad"); }
  });
  $("#logout").addEventListener("click", logout);
}

function tabAppearance(el) {
  const cur = store.get("kiwion.theme") || S.user.theme || "system";
  el.innerHTML = `<div class="card section"><h3>Тема</h3><div class="theme-options">
    ${[["system", "Как в системе"], ["light", "Светлая"], ["dark", "Тёмная"]].map(([k, v]) =>
      `<button class="btn ghost ${k === cur ? "active" : ""}" data-theme="${k}">${v}</button>`).join("")}</div></div>`;
  $$("[data-theme]", el).forEach((b) => b.addEventListener("click", async () => {
    store.set("kiwion.theme", b.dataset.theme); applyTheme(b.dataset.theme);
    $$("[data-theme]", el).forEach((x) => x.classList.toggle("active", x === b));
    api("/api/account/me", { method: "PATCH", body: { theme: b.dataset.theme } }).catch(() => {});
  }));
}

async function tabSecurity(el) {
  el.innerHTML = `<div class="card section"><h3>Смена пароля</h3>
    <div class="field"><label for="op">Текущий пароль</label><input class="input" id="op" type="password" autocomplete="current-password"></div>
    <div class="field"><label for="np">Новый пароль</label><input class="input" id="np" type="password" autocomplete="new-password"></div>
    <button class="btn" id="chpw">Изменить пароль</button></div>
    <div class="card section"><h3>Устройства и сессии</h3><div id="sessions"><p class="hint">Загрузка…</p></div>
    <button class="btn ghost small" id="revoke-all" style="margin-top:10px">Выйти на всех других устройствах</button></div>
    <div class="card section"><h3 style="color:var(--danger)">Удаление аккаунта</h3>
    <p class="hint">Аккаунт, диалоги, API-ключи и статистика будут удалены безвозвратно.</p>
    <button class="btn danger" id="del">Удалить аккаунт</button></div>`;
  $("#chpw").addEventListener("click", async () => {
    try { const r = await api("/api/account/password", { method: "POST", body: { old_password: $("#op").value, new_password: $("#np").value } });
      toast(r.message); $("#op").value = $("#np").value = ""; loadSessions(); } catch (e) { toast(errMsg(e), "bad"); }
  });
  $("#revoke-all").addEventListener("click", async () => { await api("/api/account/sessions", { method: "DELETE" }); toast("Другие устройства отключены"); loadSessions(); });
  $("#del").addEventListener("click", async () => {
    const pw = await modal({ title: "Удалить аккаунт навсегда?", body: "Введите пароль для подтверждения.", input: { type: "password", placeholder: "Пароль" }, confirm: "Удалить", danger: true });
    if (!pw) return;
    try { await api("/api/account/delete", { method: "POST", body: { password: pw, confirm: "DELETE" } });
      auth.token = null; S.user = null; go("#/login?msg=" + encodeURIComponent("Аккаунт удалён. Птичка киви будет скучать 🥝")); }
    catch (e) { toast(errMsg(e), "bad"); }
  });
  const loadSessions = async () => {
    const list = await api("/api/account/sessions");
    $("#sessions").innerHTML = list.map((s) => `<div class="row-item"><div class="grow"><b>${esc(s.device_name || "Устройство")}</b>
      ${s.current ? '<span class="badge ok">это устройство</span>' : ""}<div class="sub">${esc(s.ip)} · активность ${fmtDate(s.last_seen_at)}</div></div>
      ${s.current ? "" : `<button class="btn ghost small" data-sid="${s.id}">Выйти</button>`}</div>`).join("");
    $$("[data-sid]", el).forEach((b) => b.addEventListener("click", async () => { await api(`/api/account/sessions/${b.dataset.sid}`, { method: "DELETE" }); loadSessions(); }));
  };
  loadSessions().catch((e) => ($("#sessions").textContent = errMsg(e)));
}

async function tabApi(el) {
  el.innerHTML = `<div class="card section"><h3>API-ключи</h3>
    <p class="hint">Совместимо с OpenAI Chat Completions. Документация и примеры: <a href="/docs" target="_blank">Kiwion Developer API</a>.</p>
    <div style="display:flex;gap:8px;margin-bottom:10px"><input class="input" id="kname" placeholder="Название ключа" maxlength="64">
    <button class="btn" id="kcreate">Создать</button></div><div id="newkey"></div><div id="keys"><p class="hint">Загрузка…</p></div></div>
    <div class="card section"><h3>Статистика за 14 дней</h3><div id="kstats"></div></div>`;
  const load = async () => {
    const keys = await api("/api/keys");
    $("#keys").innerHTML = keys.length ? keys.map((k) => `<div class="row-item"><div class="grow"><b>${esc(k.name)}</b>
      ${k.revoked ? '<span class="badge bad">отозван</span>' : '<span class="badge ok">активен</span>'}
      <div class="sub"><code>${esc(k.prefix)}…</code> · создан ${fmtDate(k.created_at)} · использован ${fmtDate(k.last_used_at)}</div>
      <div class="sub">Лимиты: ${k.rpm_limit} запр/мин, ${fmtNum(k.daily_token_limit)} ток/день · сегодня ${fmtNum(k.tokens_today)}</div></div>
      ${k.revoked ? "" : `<button class="btn ghost small" data-revoke="${k.id}">Отозвать</button>`}
      <button class="icon-btn" data-del="${k.id}" aria-label="Удалить ключ">${I.trash}</button></div>`).join("") : '<p class="hint">Ключей пока нет</p>';
    $$("[data-revoke]", el).forEach((b) => b.addEventListener("click", async () => { await api(`/api/keys/${b.dataset.revoke}/revoke`, { method: "POST" }); load(); }));
    $$("[data-del]", el).forEach((b) => b.addEventListener("click", async () => {
      if (await modal({ title: "Удалить ключ?", body: "Приложения с этим ключом перестанут работать.", confirm: "Удалить", danger: true })) {
        await api(`/api/keys/${b.dataset.del}`, { method: "DELETE" }); load(); } }));
    const u = await api("/api/keys/usage");
    $("#kstats").innerHTML = `<div class="stat-grid"><div class="stat"><b>${fmtNum(u.totals.requests)}</b><span>запросов</span></div>
      <div class="stat"><b>${fmtNum(u.totals.prompt_tokens)}</b><span>токенов запроса</span></div>
      <div class="stat"><b>${fmtNum(u.totals.completion_tokens)}</b><span>токенов ответа</span></div>
      <div class="stat"><b>${fmtNum(u.totals.errors)}</b><span>ошибок</span></div></div>`;
  };
  $("#kcreate").addEventListener("click", async () => {
    try {
      const k = await api("/api/keys", { method: "POST", body: { name: $("#kname").value.trim() || "Мой ключ" } });
      $("#newkey").innerHTML = `<div class="notice"><b>Ваш новый ключ</b> — ${esc(k.warning)}<div class="keybox" style="margin:8px 0">${esc(k.key)}</div>
        <button class="btn small" id="kcopy">Копировать</button></div>`;
      $("#kcopy").addEventListener("click", (e) => copyText(k.key, e.target));
      $("#kname").value = ""; load();
    } catch (e) { toast(errMsg(e), "bad"); }
  });
  load().catch((e) => ($("#keys").textContent = errMsg(e)));
}

async function tabReferrals(el) {
  el.innerHTML = `<div class="card section"><p class="hint">Загрузка…</p></div>`;
  try {
    const r = await api("/api/account/referrals");
    const st = { confirmed: ["ok", "подтверждено"], pending: ["", "ждёт подтверждения email"], review: ["warn", "на проверке"], rejected: ["bad", "отклонено"] };
    el.innerHTML = `<div class="card section"><h3>Пригласите друзей 🥝</h3>
      <p>За каждого друга, который подтвердит email, вы получите <b>${fmtNum(r.rewards_config.referrer_bonus_tokens)}</b> бонусных токенов
      и скидку <b>${r.rewards_config.discount_percent}%</b> (до ${r.rewards_config.discount_cap}%), а друг — <b>${fmtNum(r.rewards_config.invitee_bonus_tokens)}</b> токенов.</p>
      ${r.enabled ? "" : '<div class="notice warn">Реферальная программа сейчас приостановлена</div>'}
      <div class="keybox" id="reflink">${esc(r.link)}</div>
      <div style="display:flex;gap:8px;margin-top:8px;flex-wrap:wrap"><button class="btn small" id="refcopy">Копировать ссылку</button>
      ${navigator.share ? '<button class="btn ghost small" id="refshare">Поделиться</button>' : ""}<span class="pill">Код: ${esc(r.code)}</span></div></div>
      <div class="card section"><div class="stat-grid"><div class="stat"><b>${r.stats.total}</b><span>приглашено</span></div>
      <div class="stat"><b>${r.stats.confirmed}</b><span>подтверждено</span></div>
      <div class="stat"><b>${fmtNum(r.bonus_tokens)}</b><span>бонусных токенов</span></div>
      <div class="stat"><b>${r.discount_percent}%</b><span>скидка</span></div></div>
      <h3>Приглашённые</h3>${r.invites.length ? r.invites.map((i) => `<div class="row-item"><div class="grow">${esc(i.invitee)}<div class="sub">${fmtDate(i.created_at)}</div></div>
        <span class="badge ${st[i.status]?.[0] || ""}">${st[i.status]?.[1] || i.status}</span></div>`).join("") : '<p class="hint">Пока никого</p>'}
      <h3 style="margin-top:16px">История начислений</h3>${r.rewards.length ? r.rewards.map((w) => `<div class="row-item"><div class="grow">${esc(w.note)}<div class="sub">${fmtDate(w.created_at)}</div></div>
        <b>${w.kind === "discount" ? "+" + w.amount + "%" : "+" + fmtNum(w.amount) + " ток."}</b></div>`).join("") : '<p class="hint">Начислений пока нет</p>'}
      <p class="hint">Бонусы начисляются только после подтверждения email приглашённым. Самоприглашения и подозрительные регистрации не засчитываются.</p></div>`;
    $("#refcopy").addEventListener("click", (e) => copyText(r.link, e.target));
    $("#refshare")?.addEventListener("click", () => navigator.share({ title: "Kiwion Chat", text: "Попробуй Kiwion Chat 🥝", url: r.link }).catch(() => {}));
  } catch (e) { el.innerHTML = `<div class="notice bad">${esc(errMsg(e))}</div>`; }
}

const egg = new KiwiEasterEgg();
const taps = new TapCounter(5, 1500);
function tabAbout(el) {
  const c = S.config || {};
  el.innerHTML = `<div class="card section" style="text-align:center"><img src="${LOGO}" alt="Kiwion Chat" width="120" height="120" style="border-radius:28px">
    <h2 style="margin:8px 0 2px">Kiwion Chat</h2><p class="hint">Разработчик: ${esc(c.developer || "Kiwi_Fuzzy")}</p></div>
    <div class="card section">
      <div class="row-item version-row" id="version-row" role="button" tabindex="0" aria-label="Версия приложения"><div class="grow">Версия приложения</div><b>${esc(c.version || "1.0.0")}</b></div>
      <div class="row-item"><div class="grow">Модель</div><b>${esc(c.model || "—")}</b></div>
      <div class="row-item"><div class="grow">Инференс</div><b>llama.cpp (собственный сервер)</b></div>
      <div class="row-item"><div class="grow">Лицензия модели</div><b>${esc(c.model_license || "—")}</b></div>
      <div class="row-item"><div class="grow">Документация API</div><a href="/docs" target="_blank">Открыть</a></div></div>`;
  const row = $("#version-row");
  const hit = () => { if (taps.tap()) egg.open(); };
  row.addEventListener("click", hit);
  row.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); hit(); } });
}

// ------------------------------------------------------------------ boot
async function logout() {
  try { await api("/api/auth/logout", { method: "POST" }); } catch (_) {}
  auth.token = null; S.user = null; S.chats = []; S.chatId = null;
  go("#/login");
}

async function enterApp() {
  if (!S.user.is_verified) return go("#/verify-pending");
  if (S.user.theme && !store.get("kiwion.theme")) applyTheme(S.user.theme);
  await loadChats();
  const r = route();
  if (!["chat", "settings"].includes(r.name)) go("#/chat"); else render();
}

let polling = null;
function startPolling() {
  if (polling) return;
  pollModel();
  polling = setInterval(() => { if (S.user && !document.hidden) pollModel(); }, 15000);
  setInterval(() => { if (S.user?.is_verified && !document.hidden && !S.streaming) loadChats().catch(() => {}); }, 30000);
  window.addEventListener("focus", () => { if (S.user?.is_verified && !S.streaming) loadChats().catch(() => {}); });
}

async function render() {
  const r = route();
  const publicRoutes = { login: loginScreen, register: registerScreen, forgot: forgotScreen, reset: resetScreen, verify: verifyScreen };
  if (publicRoutes[r.name] && !(S.user && ["login", "register"].includes(r.name))) {
    return publicRoutes[r.name](r.params);
  }
  if (!S.user) return go("#/login");
  if (r.name === "verify-pending") return verifyPendingScreen();
  if (!S.user.is_verified) return go("#/verify-pending");
  startPolling();
  if (r.name === "settings") return settingsView(r.parts[1]);
  if (r.name === "chat") return chatView(r.parts[1]);
  go("#/chat");
}

function offlineBar() {
  let bar = $(".offline-bar");
  if (!navigator.onLine) {
    if (!bar) { bar = document.createElement("div"); bar.className = "offline-bar"; bar.textContent = "Нет подключения к интернету — ждём сеть…"; document.body.prepend(bar); }
  } else if (bar) { bar.remove(); toast("Соединение восстановлено"); }
}
window.addEventListener("online", offlineBar);
window.addEventListener("offline", offlineBar);

async function boot() {
  applyTheme();
  splash();
  const t0 = performance.now();
  try {
    S.config = await api("/api/config/public");
  } catch (e) {
    return errorScreen(e.status || "⚡", "Сервер недоступен", "Не удалось связаться с Kiwion. Проверьте подключение к интернету.");
  }
  if (auth.token) {
    try { S.user = await api("/api/account/me"); } catch (e) {
      if (e.status !== 401) return errorScreen(e.status || "⚡", "Ошибка загрузки", errMsg(e));
    }
  }
  const wait = 450 - (performance.now() - t0);   // let the splash be seen for a moment
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  offlineBar();
  if (S.user && S.user.is_verified) await loadChats().catch(() => {});
  render();
}

boot();
