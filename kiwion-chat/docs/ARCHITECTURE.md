# Архитектура Kiwion Chat

## Компоненты и процессы

| Процесс | Где | Порт | Назначение |
|---|---|---|---|
| `kiwion_backend` | VPS | 8080 (за Caddy :443) | REST + SSE API, раздача web/admin/docs, БД |
| `kiwion_inference` | домашний ПК | 8090 (только WireGuard/mTLS) | очередь, учёт токенов, шаблон чата, управление llama-server |
| `llama-server` | домашний ПК | 8091, только `127.0.0.1` | llama.cpp: загрузка GGUF и генерация |

Инференс полностью отделён от API: backend никогда не загружает модель, а узел инференса не хранит
пользователей, пароли и историю — он получает только текст текущего диалога.

## Поток сообщения в чате

1. Клиент (web/Android) `POST /api/chats/{id}/messages` с Bearer-сессией.
2. Backend проверяет сессию, бан, подтверждение email, режим обслуживания, дневную квоту токенов,
   лимит одновременных генераций на пользователя (1) и rate-limit.
3. Backend открывает поток к инференсу (`POST /v1/generate`, HMAC-подпись) и **ждёт первого события**.
   - `503 overloaded` → клиенту `503 {"code":"overloaded"}`; в БД ничего не записано — текст
     остаётся у пользователя в поле ввода («Птичка киви немного устала…»).
4. Только после успешного старта backend сохраняет сообщение пользователя и пустой ответ
   (`status=streaming`) и транслирует клиенту SSE: `meta`, `queued{position}`, `start`, `token`, `done`.
5. Каждые 3 с частичный ответ сохраняется (защита от падений); в конце — финальный статус
   (`complete` / `stopped` / `error`), реальные токены от llama.cpp и запись `usage_events`.
6. Остановка: `POST /api/chats/{id}/stop` (или разрыв соединения) — backend закрывает поток к
   инференсу, тот закрывает соединение с llama-server, и генерация на CPU прекращается сразу.

## Очередь и перегрузка

`AdmissionQueue` (inference/kiwion_inference/queue.py): `KIWION_PARALLEL` слотов (= слоты llama.cpp),
FIFO-ожидание до `KIWION_MAX_QUEUE` запросов, клиент получает свою позицию. Если ожидающих уже
`max_queue` — немедленный `503 overloaded`. Ожидание дольше `KIWION_QUEUE_TIMEOUT` → `overloaded`.
Отключившийся из очереди клиент освобождает место.

## Шаблон OLMo 2

`shared/kiwion_shared/prompt.py` воспроизводит Jinja-шаблон `tokenizer_config.json` модели
`allenai/OLMo-2-0425-1B-Instruct` (`<|endoftext|><|system|>…<|user|>…<|assistant|>…`), поэтому промпт не
зависит от метаданных GGUF. При старте инференс выясняет, добавляет ли llama.cpp BOS сам, чтобы не было
двойного BOS. История обрезается по бюджету контекста (системный промпт сохраняется).

## Данные (SQLAlchemy, SQLite или PostgreSQL)

`users`, `sessions` (хеш токена, устройство, IP, срок), `email_tokens` (хеш, тип, срок, одноразовые),
`chats`, `messages` (seq, статус, токены), `api_keys` (только хеш + префикс), `usage_events`,
`referrals` (риск-оценка и причины), `referral_rewards` (уникально: referral × получатель × тип),
`device_sightings`, `settings` (настройки админки), `error_logs`, `audit_logs`.

## Аутентификация

- Сессии — непрозрачные токены `kws_…` (256 бит), в БД только HMAC-SHA256 с серверным секретом.
- API-ключи `kw-…` — так же; полный ключ показывается один раз.
- Пароли — Argon2id (`time_cost=3, memory_cost=64 МБ`), автоматический rehash при смене параметров.
- Регистрация — hashcash proof-of-work (`KIWION_POW_DIFFICULTY` бит), одноразовый, подписанный сервером.

## Клиенты

- **Web** — ES-модули без сборщика, строгий CSP (`script-src 'self'`), Markdown через marked + DOMPurify,
  подсветка highlight.js, всё локально (`web/vendor`).
- **Android** — Java + Android framework (без AppCompat/Compose), `HttpURLConnection` + SSE, маскот и
  пасхалка нарисованы на Canvas, звук синтезируется `AudioTrack`.
- **CLI** — Python, работает напрямую с узлом инференса (подписанные запросы) или через Developer API.
