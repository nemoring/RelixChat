// Kiwion Admin panel. Uses the same session as the web app; every API call is checked server-side (role=admin).
import { api, ApiError, auth, deviceId } from "/js/api.js";

const root = document.getElementById("root");
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const num = (n) => Number(n || 0).toLocaleString("ru-RU");
const dt = (s) => (s ? new Date(s).toLocaleString("ru-RU") : "—");
const dark = matchMedia("(prefers-color-scheme: dark)").matches;
document.documentElement.dataset.theme = dark ? "dark" : "light";

function toast(msg, bad) {
  const t = document.createElement("div");
  t.className = "toasts";
  t.innerHTML = `<div class="toast ${bad ? "bad" : ""}"><span class="t-icon">${bad ? "⚠️" : "✅"}</span><div>${esc(msg)}</div></div>`;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3500);
}

const PAGES = [["dashboard", "Обзор"], ["inference", "Модель и очередь"], ["users", "Пользователи"], ["referrals", "Рефералы"],
  ["settings", "Лимиты и доступность"], ["mail", "Почта"], ["errors", "Системные ошибки"], ["audit", "Журнал действий"]];

function loginForm(msg) {
  root.innerHTML = `<div class="screen"><div class="auth-wrap"><div class="auth-head"><img src="/assets/kiwi/logo.png" width="84" height="84" style="border-radius:22px" alt="">
    <h1 class="brand-title">Kiwion <span>Admin</span></h1></div><form class="card" id="f">
    ${msg ? `<div class="notice warn">${esc(msg)}</div>` : ""}
    <div class="field"><label>Email</label><input class="input" id="email" type="email" required></div>
    <div class="field"><label>Пароль</label><input class="input" id="pw" type="password" required></div>
    <div class="error-text"></div><button class="btn block" type="submit">Войти</button></form></div></div>`;
  $("#f").addEventListener("submit", async (e) => {
    e.preventDefault();
    try {
      const r = await api("/api/auth/login", { method: "POST", body: { email: $("#email").value, password: $("#pw").value, device_id: deviceId(), device_name: "Kiwion Admin" } });
      auth.token = r.token;
      boot();
    } catch (err) { $(".error-text").textContent = err.message; }
  });
}

function layout(page) {
  root.innerHTML = `<div class="adm"><nav><div class="brand"><img src="/assets/kiwi/logo.png" alt=""><span>Kiwion Admin</span></div>
    ${PAGES.map(([k, v]) => `<a href="#/${k}" class="${k === page ? "active" : ""}">${v}</a>`).join("")}
    <a href="/" style="margin-top:auto">← В приложение</a></nav><main id="main"><p class="hint">Загрузка…</p></main></div>`;
  return $("#main");
}

function barChart(title, rows, valueKey, labelKey = "date", unit = "") {
  if (!rows.length) return `<div class="card"><h3>${esc(title)}</h3><p class="hint">Нет данных</p></div>`;
  const max = Math.max(1, ...rows.map((r) => r[valueKey]));
  return `<div class="card"><h3 style="margin-top:0">${esc(title)}</h3><div class="chart"><span class="max">макс. ${num(max)}</span>
    <div class="plot" role="img" aria-label="${esc(title)}">${rows.map((r) => `<div class="bar" style="height:${(r[valueKey] / max) * 100}%">
      <span class="tip">${esc(r[labelKey])}: ${num(r[valueKey])}${unit}</span></div>`).join("")}</div>
    <div class="axis"><span>${esc(rows[0][labelKey])}</span><span>${esc(rows[rows.length - 1][labelKey])}</span></div></div>
    <details><summary>Таблица</summary><table class="data">${rows.map((r) => `<tr><td>${esc(r[labelKey])}</td><td>${num(r[valueKey])}</td></tr>`).join("")}</table></details></div>`;
}

function fillDays(rows, days, key) {
  const map = Object.fromEntries(rows.map((r) => [r.date, r[key]]));
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(Date.now() - i * 864e5).toISOString().slice(0, 10);
    out.push({ date: d, [key]: map[d] || 0 });
  }
  return out;
}

async function dashboard(main) {
  const s = await api("/api/admin/stats");
  const byDay = {};
  s.tokens_by_day.forEach((r) => { byDay[r.date] = (byDay[r.date] || 0) + r.prompt_tokens + r.completion_tokens; });
  const tokens = Object.entries(byDay).map(([date, v]) => ({ date, v }));
  const inf = s.inference || {};
  main.innerHTML = `<h1>Обзор</h1><div class="stat-grid">
    <div class="stat"><b>${num(s.users_total)}</b><span>пользователей (${num(s.users_verified)} подтв.)</span></div>
    <div class="stat"><b>${num(s.registrations_24h)}</b><span>регистраций за 24 ч (${num(s.registrations_7d)} за 7 дн.)</span></div>
    <div class="stat"><b>${num(s.active_chats_24h)}</b><span>активных диалогов за 24 ч</span></div>
    <div class="stat"><b>${num(s.messages_24h)}</b><span>сообщений за 24 ч</span></div>
    <div class="stat"><b>${num(s.tokens_24h)}</b><span>токенов за 24 ч</span></div>
    <div class="stat"><b>${num(s.active_streams)}</b><span>генераций сейчас</span></div>
    <div class="stat"><b>${inf.queue ? `${inf.queue.active}/${inf.queue.parallel} · ${inf.queue.waiting}` : "—"}</b><span>слоты · очередь</span></div>
    <div class="stat"><b>${esc(inf.state || "offline")}</b><span>состояние модели</span></div>
    <div class="stat"><b>${num(s.errors_24h)}</b><span>ошибок за 24 ч</span></div>
    <div class="stat"><b>${num(s.referrals_review)}</b><span>рефералов на проверке</span></div>
    <div class="stat"><b>${num(s.api_keys_active)}</b><span>активных API-ключей</span></div>
    <div class="stat"><b>${num(s.users_banned)}</b><span>заблокировано</span></div></div>
    <div class="grid2">${barChart("Регистрации по дням (30 дн.)", fillDays(s.registrations_by_day, 30, "count"), "count")}
    ${barChart("Токены по дням (14 дн.)", fillDays(tokens, 14, "v"), "v", "date", " ток.")}</div>`;
}

async function inference(main) {
  const s = await api("/api/admin/inference");
  const q = s.queue || {};
  main.innerHTML = `<h1>Модель и очередь</h1>
    ${s.reachable === false ? `<div class="notice bad">Сервер инференса недоступен (${esc(s.error)})</div>` : ""}
    <div class="stat-grid">
      <div class="stat"><b>${esc(s.state)}</b><span>состояние · движок ${esc(s.engine || "—")}</span></div>
      <div class="stat"><b>${num(q.active)} / ${num(q.parallel)}</b><span>занято слотов</span></div>
      <div class="stat"><b>${num(q.waiting)} / ${num(q.max_queue)}</b><span>в очереди</span></div>
      <div class="stat"><b>${num(q.total_served)}</b><span>обслужено запросов</span></div>
      <div class="stat"><b>${num(q.total_rejected)}</b><span>отклонено (перегрузка)</span></div>
      <div class="stat"><b>${q.avg_wait_seconds ?? "—"} с</b><span>среднее ожидание</span></div>
      <div class="stat"><b>${s.last_tokens_per_second ?? "—"}</b><span>ток/с (последний ответ)</span></div>
      <div class="stat"><b>${num(s.total_prompt_tokens)}</b><span>токенов запросов</span></div>
      <div class="stat"><b>${num(s.total_completion_tokens)}</b><span>токенов ответов</span></div></div>
    <div class="card"><table class="data">
      <tr><td>Модель</td><td>${esc(s.model_name)} (${esc(s.model_file || "—")})</td></tr>
      <tr><td>Контекст</td><td>${num(s.ctx_size)} токенов</td></tr><tr><td>Потоки CPU</td><td>${num(s.threads)}</td></tr>
      <tr><td>Аптайм</td><td>${Math.round((s.uptime_seconds || 0) / 60)} мин</td></tr>
      ${s.error ? `<tr><td>Ошибка</td><td>${esc(s.error)}</td></tr>` : ""}</table>
      <button class="btn ghost small" id="refresh" style="margin-top:10px">Обновить</button></div>`;
  $("#refresh").addEventListener("click", () => inference(main));
}

async function users(main, q = "", status = "", page = 1) {
  const d = await api(`/api/admin/users?q=${encodeURIComponent(q)}&status=${status}&page=${page}`);
  main.innerHTML = `<h1>Пользователи <span class="badge">${num(d.total)}</span></h1>
    <div class="toolbar"><input class="input" id="q" placeholder="email, имя или реф. код" value="${esc(q)}">
    <select class="input" id="st" style="max-width:180px"><option value="">Все</option><option value="unverified">Неподтверждённые</option>
    <option value="banned">Заблокированные</option><option value="admin">Администраторы</option></select>
    <button class="btn small" id="go">Найти</button></div>
    <div class="card" style="padding:0;overflow-x:auto"><table class="data"><tr><th>ID</th><th>Пользователь</th><th>Статус</th><th>Регистрация</th>
    <th>Лимит/день</th><th>Бонус</th><th>Чатов</th><th></th></tr>
    ${d.users.map((u) => `<tr><td>${u.id}</td><td><b>${esc(u.email)}</b><div class="hint">${esc(u.display_name)} · IP ${esc(u.signup_ip)}</div></td>
      <td>${u.role === "admin" ? '<span class="badge ok">admin</span> ' : ""}${u.is_banned ? `<span class="badge bad" title="${esc(u.ban_reason)}">бан</span>` : u.is_verified ? '<span class="badge ok">активен</span>' : '<span class="badge warn">не подтв.</span>'}</td>
      <td>${dt(u.created_at)}</td><td>${u.daily_token_limit == null ? '<span class="hint">по умолч.</span>' : num(u.daily_token_limit)}</td>
      <td>${num(u.bonus_tokens)}</td><td>${u.chats}</td>
      <td style="white-space:nowrap">${u.is_verified ? "" : `<button class="btn ghost small" data-resend="${u.id}" title="Отправить письмо с кодом ещё раз">Код</button>
      <button class="btn ghost small" data-verify="${u.id}" title="Подтвердить email вручную">Подтв.</button> `}<button class="btn ghost small" data-limit="${u.id}">Лимит</button>
      <button class="btn ghost small" data-bonus="${u.id}">Бонус</button>
      ${u.is_banned ? `<button class="btn small" data-unban="${u.id}">Разбанить</button>` : `<button class="btn danger small" data-ban="${u.id}">Бан</button>`}</td></tr>`).join("")}
    </table></div>
    <div class="toolbar" style="margin-top:10px">${page > 1 ? '<button class="btn ghost small" id="prev">← Назад</button>' : ""}
    ${page * d.per_page < d.total ? '<button class="btn ghost small" id="next">Вперёд →</button>' : ""}</div>`;
  $("#st").value = status;
  const reload = (p = page) => users(main, $("#q").value, $("#st").value, p);
  $("#go").addEventListener("click", () => reload(1));
  $("#q").addEventListener("keydown", (e) => e.key === "Enter" && reload(1));
  $("#prev")?.addEventListener("click", () => reload(page - 1));
  $("#next")?.addEventListener("click", () => reload(page + 1));
  const patch = async (id, body) => { try { await api(`/api/admin/users/${id}`, { method: "PATCH", body }); toast("Сохранено"); reload(); } catch (e) { toast(e.message, true); } };
  $$("[data-ban]").forEach((b) => b.addEventListener("click", () => { const r = prompt("Причина блокировки:", "Нарушение правил"); if (r !== null) patch(b.dataset.ban, { is_banned: true, ban_reason: r }); }));
  $$("[data-resend]").forEach((b) => b.addEventListener("click", async () => {
    const r = await api(`/api/admin/users/${b.dataset.resend}/resend-verification`, { method: "POST" }); toast(r.message, !r.ok); }));
  $$("[data-verify]").forEach((b) => b.addEventListener("click", () => { if (confirm("Подтвердить email этого пользователя вручную?")) patch(b.dataset.verify, { is_verified: true }); }));
  $$("[data-unban]").forEach((b) => b.addEventListener("click", () => patch(b.dataset.unban, { is_banned: false })));
  $$("[data-limit]").forEach((b) => b.addEventListener("click", () => { const v = prompt("Дневной лимит токенов (-1 = по умолчанию):", ""); if (v !== null && v.trim() !== "") patch(b.dataset.limit, { daily_token_limit: parseInt(v, 10) }); }));
  $$("[data-bonus]").forEach((b) => b.addEventListener("click", () => { const v = prompt("Бонусные токены (новое значение):", ""); if (v !== null && v.trim() !== "") patch(b.dataset.bonus, { bonus_tokens: parseInt(v, 10) }); }));
}

const REASONS = { self_invite: "самоприглашение", invite_cycle: "цикл приглашений", same_device_as_referrer: "то же устройство",
  device_many_accounts: "много аккаунтов на устройстве", chain_same_device: "цепочка с одного устройства", velocity: "слишком много за сутки",
  disposable_email: "временная почта", subnet_cluster: "кластер подсети", fresh_referrer_chain: "свежая цепочка",
  same_ip_as_referrer: "тот же IP (слабый сигнал)", same_subnet_as_referrer: "та же подсеть (слабый сигнал)", referrer_banned: "пригласивший заблокирован" };

async function referrals(main, status = "review") {
  const rows = await api(`/api/admin/referrals?status=${status}`);
  main.innerHTML = `<h1>Рефералы</h1><div class="toolbar">${["review", "pending", "confirmed", "rejected", ""].map((s) =>
    `<button class="tab ${s === status ? "active" : ""}" data-s="${s}">${{ review: "На проверке", pending: "Ожидают email", confirmed: "Подтверждены", rejected: "Отклонены", "": "Все" }[s]}</button>`).join("")}</div>
    <p class="hint">Совпадение IP — только слабый сигнал и само по себе не отклоняет приглашение. Награды настраиваются в разделе «Лимиты и доступность».</p>
    <div class="card" style="padding:0;overflow-x:auto"><table class="data"><tr><th>ID</th><th>Пригласил</th><th>Приглашённый</th><th>Риск</th><th>Сигналы</th><th>Статус</th><th></th></tr>
    ${rows.map((r) => `<tr><td>${r.id}</td><td>${esc(r.referrer?.email)}</td><td>${esc(r.invitee?.email)}<div class="hint">IP ${esc(r.invitee?.signup_ip)}</div></td>
      <td><b>${r.risk_score}</b></td><td>${r.risk_reasons.map((x) => `<span class="badge">${esc(REASONS[x] || x)}</span>`).join(" ") || "—"}</td>
      <td>${esc(r.status)}</td><td style="white-space:nowrap">${["review", "pending", "rejected"].includes(r.status) ? `<button class="btn small" data-ok="${r.id}">Одобрить</button>` : ""}
      ${["review", "pending"].includes(r.status) ? `<button class="btn ghost small" data-no="${r.id}">Отклонить</button>` : ""}</td></tr>`).join("") || '<tr><td colspan="7" class="hint">Нет записей</td></tr>'}</table></div>`;
  $$("[data-s]").forEach((b) => b.addEventListener("click", () => referrals(main, b.dataset.s)));
  const decide = async (id, approve) => { await api(`/api/admin/referrals/${id}/decision`, { method: "POST", body: { approve } }); toast("Готово"); referrals(main, status); };
  $$("[data-ok]").forEach((b) => b.addEventListener("click", () => decide(b.dataset.ok, true)));
  $$("[data-no]").forEach((b) => b.addEventListener("click", () => decide(b.dataset.no, false)));
}

const SETTING_LABELS = {
  maintenance_mode: "Режим обслуживания (сервис недоступен)", maintenance_message: "Сообщение об обслуживании",
  registration_open: "Регистрация открыта", chat_enabled: "Чат включён", api_enabled: "Developer API включён",
  free_daily_tokens: "Бесплатных токенов в день", max_tokens_per_reply: "Макс. токенов в ответе", max_message_chars: "Макс. длина сообщения",
  api_default_rpm: "API: запросов в минуту (по умолч.)", api_default_daily_tokens: "API: токенов в день (по умолч.)", api_max_keys_per_user: "API: ключей на пользователя",
  referral_enabled: "Реферальная программа включена", referral_referrer_bonus_tokens: "Бонус пригласившему (токены)",
  referral_invitee_bonus_tokens: "Бонус приглашённому (токены)", referral_discount_percent: "Скидка за приглашение, %",
  referral_discount_cap: "Максимальная скидка, %", referral_max_confirmed_per_day: "Макс. подтверждений в сутки на пользователя",
  referral_review_threshold: "Порог риска: ручная проверка", referral_reject_threshold: "Порог риска: отклонение",
  max_accounts_per_device: "Макс. аккаунтов с одного устройства", signups_per_ip_per_hour: "Регистраций с IP в час",
};

async function settings(main) {
  const all = await api("/api/admin/settings");
  const MAIL = ["mail_mode", "smtp_host", "smtp_port", "smtp_security", "smtp_user", "mail_from"];
  const s = Object.fromEntries(Object.entries(all).filter(([k]) => !MAIL.includes(k)));
  const bools = Object.keys(s).filter((k) => typeof s[k] === "boolean");
  const others = Object.keys(s).filter((k) => typeof s[k] !== "boolean");
  main.innerHTML = `<h1>Лимиты и доступность</h1><form class="card" id="sf">
    <h3 style="margin-top:0">Доступность сервиса</h3>${bools.map((k) => `<label class="switch"><input type="checkbox" name="${k}" ${s[k] ? "checked" : ""}> ${esc(SETTING_LABELS[k] || k)}</label>`).join("")}
    <h3>Параметры</h3><div class="settings-form">${others.map((k) => `<div class="field"><label>${esc(SETTING_LABELS[k] || k)}</label>
      <input class="input" name="${k}" type="${typeof s[k] === "number" ? "number" : "text"}" min="0" value="${esc(s[k])}"></div>`).join("")}</div>
    <button class="btn" type="submit">Сохранить</button></form>`;
  $("#sf").addEventListener("submit", async (e) => {
    e.preventDefault();
    const body = {};
    bools.forEach((k) => (body[k] = $(`[name=${k}]`).checked));
    others.forEach((k) => (body[k] = typeof s[k] === "number" ? parseInt($(`[name=${k}]`).value, 10) : $(`[name=${k}]`).value));
    try { await api("/api/admin/settings", { method: "PUT", body }); toast("Настройки сохранены"); } catch (err) { toast(err.message, true); }
  });
}

async function errors(main) {
  const rows = await api("/api/admin/errors?limit=200");
  main.innerHTML = `<h1>Системные ошибки</h1><div class="toolbar"><button class="btn ghost small" id="clr">Очистить журнал</button>
    <span class="hint">Пароли, токены и ключи вырезаются из сообщений автоматически.</span></div>
    <div class="card" style="padding:0;overflow-x:auto"><table class="data"><tr><th>Время</th><th>Источник</th><th>Путь</th><th>Сообщение</th></tr>
    ${rows.map((r) => `<tr><td style="white-space:nowrap">${dt(r.created_at)}</td><td><span class="badge">${esc(r.source)}</span></td><td>${esc(r.path)}</td>
      <td><pre class="err">${esc(r.message)}</pre></td></tr>`).join("") || '<tr><td colspan="4" class="hint">Ошибок нет 🥝</td></tr>'}</table></div>`;
  $("#clr").addEventListener("click", async () => { if (confirm("Очистить журнал ошибок?")) { await api("/api/admin/errors", { method: "DELETE" }); errors(main); } });
}

async function audit(main) {
  const rows = await api("/api/admin/audit?limit=200");
  main.innerHTML = `<h1>Журнал действий администраторов</h1><div class="card" style="padding:0;overflow-x:auto"><table class="data">
    <tr><th>Время</th><th>Админ</th><th>Действие</th><th>Объект</th><th>Детали</th></tr>
    ${rows.map((r) => `<tr><td>${dt(r.created_at)}</td><td>${esc(r.admin)}</td><td>${esc(r.action)}</td><td>${esc(r.target)}</td>
      <td><code>${esc(JSON.stringify(r.details))}</code></td></tr>`).join("") || '<tr><td colspan="5" class="hint">Пусто</td></tr>'}</table></div>`;
}

const STATUS_RU = { sent: ["ok", "отправлено"], failed: ["bad", "ошибка"], stored: ["warn", "в файл (тест)"], logged: ["warn", "в лог"] };

async function mail(main) {
  const d = await api("/api/admin/mail");
  const c = d.config;
  const modeNow = c.source === "env" ? "env" : c.mode;
  main.innerHTML = `<h1>Почта</h1>
    ${c.mode !== "smtp" ? `<div class="notice warn">Письма с кодами сейчас <b>не уходят на почту</b> (режим «${esc(c.mode)}»). Настройте SMTP ниже.</div>` : ""}
    <div class="stat-grid"><div class="stat"><b>${d.stats_24h.sent}</b><span>отправлено за 24 ч</span></div>
      <div class="stat"><b>${d.stats_24h.failed}</b><span>ошибок за 24 ч</span></div>
      <div class="stat"><b>${c.source === "admin" ? "админ-панель" : ".env"}</b><span>откуда настройки</span></div></div>
    <form class="card" id="mf">
      <h3 style="margin-top:0">Отправка писем (коды подтверждения и восстановления пароля)</h3>
      <div class="toolbar"><span class="hint">Шаблон:</span>${Object.keys(d.presets).map((k) => `<button type="button" class="btn ghost small" data-preset="${k}">${{ gmail: "Gmail", yandex: "Яндекс", mailru: "Mail.ru" }[k] || k}</button>`).join("")}</div>
      <p class="hint" id="phint"></p>
      <div class="settings-form">
        <div class="field"><label>Режим</label><select class="input" name="mode">
          <option value="smtp">SMTP — отправлять на почту</option><option value="file">Файл (только для тестов)</option>
          <option value="console">Лог сервера (только для тестов)</option><option value="env">Брать настройки из .env</option></select></div>
        <div class="field"><label>SMTP-сервер</label><input class="input" name="host" placeholder="smtp.gmail.com" value="${esc(c.host)}"></div>
        <div class="field"><label>Порт</label><input class="input" name="port" type="number" value="${c.port || 465}"></div>
        <div class="field"><label>Шифрование</label><select class="input" name="security">
          <option value="ssl">SSL (порт 465)</option><option value="starttls">STARTTLS (порт 587)</option><option value="none">Без шифрования</option></select></div>
        <div class="field"><label>Логин (адрес почты)</label><input class="input" name="user" autocomplete="off" value="${esc(c.user)}"></div>
        <div class="field"><label>Пароль приложения</label><input class="input" name="password" type="password" autocomplete="new-password"
          placeholder="${c.has_password ? "сохранён — оставьте пустым, чтобы не менять" : "не задан"}"></div>
        <div class="field"><label>Отправитель</label><input class="input" name="sender" placeholder="Kiwion Chat &lt;you@gmail.com&gt;" value="${esc(c.sender)}"></div>
      </div>
      <p class="hint">Пароль хранится на сервере в зашифрованном виде и никогда не показывается.</p>
      <div class="toolbar"><button class="btn" type="submit">Сохранить</button>
        <button class="btn ghost" type="button" id="mcheck">Проверить подключение</button>
        <input class="input" id="mto" type="email" placeholder="куда отправить тест" style="max-width:240px">
        <button class="btn ghost" type="button" id="mtest">Отправить тестовое письмо</button></div>
      <div id="mres"></div>
    </form>
    <div class="card" style="margin-top:14px;padding:0;overflow-x:auto"><table class="data"><tr><th>Время</th><th>Кому</th><th>Тема</th><th>Статус</th><th>Ошибка</th></tr>
      ${d.log.map((m) => `<tr><td style="white-space:nowrap">${dt(m.created_at)}</td><td>${esc(m.to)}</td><td>${esc(m.subject)}</td>
        <td><span class="badge ${STATUS_RU[m.status]?.[0] || ""}">${STATUS_RU[m.status]?.[1] || esc(m.status)}</span></td><td class="hint">${esc(m.error)}</td></tr>`).join("") || '<tr><td colspan="5" class="hint">Писем пока не было</td></tr>'}</table></div>`;
  const f = $("#mf");
  f.mode.value = modeNow; f.security.value = c.security || "ssl";
  // the sender follows the login (Gmail/Yandex replace any other sender) unless the admin edits it by hand
  const looksDefault = (v) => !v || /kiwion\.local|example\.com/.test(v) || (c.user && v === `Kiwion Chat <${c.user}>`);
  let senderTouched = !looksDefault(f.sender.value);
  if (!senderTouched && c.user) f.sender.value = `Kiwion Chat <${c.user}>`;
  f.sender.addEventListener("input", () => { senderTouched = true; });
  const syncSender = () => { if (!senderTouched) f.sender.value = f.user.value.trim() ? `Kiwion Chat <${f.user.value.trim()}>` : ""; };
  f.user.addEventListener("input", syncSender);
  $$("[data-preset]").forEach((b) => b.addEventListener("click", () => {
    const p = d.presets[b.dataset.preset];
    f.mode.value = "smtp"; f.host.value = p.smtp_host; f.port.value = p.smtp_port; f.security.value = p.smtp_security;
    $("#phint").textContent = p.hint;
    syncSender();
  }));
  f.port.addEventListener("change", () => { if (f.port.value === "465") f.security.value = "ssl"; if (f.port.value === "587") f.security.value = "starttls"; });
  const body = () => ({ mode: f.mode.value, host: f.host.value.trim(), port: parseInt(f.port.value, 10) || 465, security: f.security.value,
    user: f.user.value.trim(), sender: f.sender.value.trim() || (f.user.value.trim() ? `Kiwion Chat <${f.user.value.trim()}>` : ""),
    password: f.password.value || null });
  const show = (html) => ($("#mres").innerHTML = html);
  f.addEventListener("submit", async (e) => {
    e.preventDefault();
    try { await api("/api/admin/mail", { method: "PUT", body: body() }); toast("Сохранено"); mail(main); }
    catch (err) { toast(err.message, true); }
  });
  $("#mcheck").addEventListener("click", async () => {
    show('<p class="hint">Проверяем… (до 30 секунд)</p>');
    const r = await api("/api/admin/mail/check", { method: "POST" });
    show(`<div class="notice ${r.ok ? "" : "bad"}">${r.ok ? "✅ Подключение к почтовому серверу работает" : "Есть проблема:"}
      <ul style="margin:6px 0 0">${r.steps.map((s) => `<li>${s.ok ? "✅" : "❌"} <b>${esc(s.step)}</b>: ${esc(s.message)}${s.hint ? `<br><span class="hint">${esc(s.hint)}</span>` : ""}</li>`).join("")}</ul></div>`);
  });
  $("#mtest").addEventListener("click", async () => {
    const to = $("#mto").value.trim();
    if (!to) return toast("Укажите адрес для теста", true);
    show('<p class="hint">Отправляем…</p>');
    try { const r = await api("/api/admin/mail/test", { method: "POST", body: { to } });
      show(`<div class="notice ${r.ok ? "" : "bad"}">${esc(r.message)}</div>`); }
    catch (err) { show(`<div class="notice bad">${esc(err.message)}</div>`); }
  });
}

const HANDLERS = { dashboard, inference, users, referrals, settings, mail, errors, audit };

async function boot() {
  if (!auth.token) return loginForm();
  let me;
  try { me = await api("/api/account/me"); } catch (e) { return loginForm(); }
  if (me.role !== "admin") return loginForm("У этого аккаунта нет прав администратора");
  const page = location.hash.replace("#/", "") || "dashboard";
  const main = layout(HANDLERS[page] ? page : "dashboard");
  try { await (HANDLERS[page] || dashboard)(main); }
  catch (e) { main.innerHTML = `<div class="notice bad">${esc(e instanceof ApiError ? e.message : "Ошибка загрузки")}</div>`; }
}
window.addEventListener("hashchange", boot);
window.addEventListener("kiwion:logout", () => loginForm());
boot();
