# Развёртывание

Целевая схема: **backend на недорогом VPS** (1 vCPU, 512 МБ–1 ГБ RAM) + **инференс на домашнем ПК**,
связанные защищённым каналом. Всё можно запустить и на одной машине.

## 1. Домашний узел инференса

```bash
sudo apt install -y git cmake build-essential python3-venv
sudo useradd -r -m -d /opt/kiwion-chat kiwion && sudo -u kiwion -i
git clone <ваш репозиторий> /opt/kiwion-chat-src && cp -r /opt/kiwion-chat-src/kiwion-chat/. /opt/kiwion-chat/
cd /opt/kiwion-chat
python3 -m venv .venv && .venv/bin/pip install -e ".[inference]"
JOBS=2 scripts/build_llamacpp.sh        # собирать на этой же машине (GGML_NATIVE)
scripts/download_model.sh               # исходные веса -> GGUF Q4_K_M
cp .env.example .env                    # KIWION_INFERENCE_SECRET, KIWION_THREADS=2, KIWION_INFERENCE_HOST=10.8.0.2
.venv/bin/kiwion server start --wait 300 && .venv/bin/kiwion benchmark
.venv/bin/kiwion server stop
sudo cp deploy/systemd/kiwion-inference.service /etc/systemd/system/ && sudo systemctl enable --now kiwion-inference
```

Docker-вариант: `docker compose --env-file .env -f deploy/docker-compose.inference.yml up -d --build` (сборка llama.cpp
внутри образа; собирайте образ на той же машине).

## 2. Канал VPS ↔ дом

Варианты (можно совмещать):

- **WireGuard** (рекомендуется): `deploy/wireguard-example.conf`. Домашний ПК сам подключается к VPS,
  проброс портов на роутере не нужен. Инференс слушает только `10.8.0.2`.
- **mTLS**: `scripts/gen_certs.sh <имя> <ip>` создаёт свой CA, серверный и клиентский сертификаты.
  На узле: `KIWION_INFERENCE_SSL_CERT/KEY/CLIENT_CA`; на VPS: `KIWION_INFERENCE_URL=https://…`,
  `KIWION_INFERENCE_CA_CERT`, `KIWION_INFERENCE_CLIENT_CERT/KEY`. Без клиентского сертификата
  TLS-рукопожатие отклоняется.
- В любом случае каждый запрос подписан HMAC-SHA256 (`KIWION_INFERENCE_SECRET`) с меткой времени и
  nonce: подделка и повтор запросов отклоняются.

## 3. VPS

Быстрый путь — одна команда на свежем Ubuntu/Debian VPS (DNS-запись домена уже указывает на сервер):

```bash
sudo bash deploy/install_vps.sh chat.example.com you@example.com https://github.com/<owner>/<repo>.git <branch>
```

Один запуск ставит всё: секреты, файрвол, HTTPS, контейнеры и учётную запись администратора (пароль
выводится в конце и сохраняется в `/root/kiwion-admin.txt`). Почта настраивается потом в админке:
`https://<домен>/admin/` → **Почта** → шаблон Gmail/Яндекс → логин и пароль приложения → «Проверить
подключение» → «Отправить тестовое письмо». Проверка подскажет, если хостинг блокирует порты 465/587.

### Модель на этом же VPS (без домашнего ПК)

```bash
sudo WITH_MODEL=1 bash deploy/install_vps.sh chat.example.com you@example.com <git-url> <branch>
```

Скрипт соберёт llama.cpp, скачает исходные веса OLMo 2 1B Instruct, сконвертирует их в GGUF Q4_K_M и
запустит контейнер `inference` во внутренней сети Docker (наружу порт не открывается). Нужно
≥ 4 ГБ RAM и 2+ vCPU; WireGuard и `KIWION_INFERENCE_SECRET` на другом компьютере не нужны.
Вручную: `KIWION_INFERENCE_URL=http://inference:8090` в `.env` и
`docker compose --env-file .env -f deploy/docker-compose.vps.yml --profile model up -d --build`.

Вручную:

```bash
cp .env.example .env
# KIWION_ENV=production, KIWION_SECRET_KEY=$(kiwion secret), KIWION_INFERENCE_SECRET=<как на узле>,
# KIWION_PUBLIC_URL=https://chat.example.com, KIWION_DOMAIN=chat.example.com,
# KIWION_INFERENCE_URL=http://10.8.0.2:8090, KIWION_MAIL_MODE=smtp + SMTP-параметры
docker compose --env-file .env -f deploy/docker-compose.vps.yml up -d --build
docker compose --env-file .env -f deploy/docker-compose.vps.yml exec backend python -m kiwion_backend create-admin --email you@example.com
```

Caddy автоматически получает сертификат Let's Encrypt (HTTPS), не буферизует SSE (`flush_interval -1`).
Без Docker: `pip install -e ".[backend]"`, `deploy/systemd/kiwion-backend.service` + Caddy/nginx
(обязательно отключить буферизацию для `/api/chats/*/messages` и `/v1/chat/completions`).

В production backend **не стартует**, если не заданы `KIWION_SECRET_KEY` (≥ 32 символов),
`KIWION_INFERENCE_SECRET` и SMTP.

### PostgreSQL (по желанию)

`KIWION_DATABASE_URL=postgresql+psycopg://kiwion:pass@db/kiwion` и `pip install ".[postgres]"`.
Таблицы создаются при старте. Для одного VPS хватает SQLite (WAL-режим).

### Бэкапы

SQLite: `sqlite3 data/kiwion.db ".backup data/backup-$(date +%F).db"` по cron. Храните `.env` отдельно.

## 4. Android

`KIWION_SERVER_URL=https://chat.example.com mobile/build_apk.sh` — приложение работает только с этим
сервером, сменить адрес в приложении нельзя. Для релиза укажите свой keystore
(`KIWION_KEYSTORE`, `KIWION_KEYSTORE_PASS`, `KIWION_KEY_ALIAS`) и храните его в надёжном месте.

## 5. Страница ожидания релиза

`https://chat.example.com/launch`, дата — `KIWION_LAUNCH_AT` (ISO-8601 с часовым поясом). Для
предпросмотра: `/launch?at=2027-01-01T00:00:00Z`.

## Обновление

`git pull`, `pip install -e .`, перезапуск сервисов. Схема БД создаётся автоматически (новые таблицы);
для изменений существующих колонок в будущих версиях рекомендуется Alembic.
