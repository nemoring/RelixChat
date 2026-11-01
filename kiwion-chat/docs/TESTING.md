# Тестирование

```bash
pip install -e ".[backend,inference,dev]"
python -m pytest                    # все тесты
python -m pytest tests/e2e          # браузерные сценарии (Playwright + Chromium)
mobile/build_apk.sh && python -m pytest tests/mobile
```

## Что покрыто автотестами

| Набор | Что проверяется |
|---|---|
| `tests/backend/test_auth.py` | proof-of-work и его одноразовость, регистрация → письмо → подтверждение, сессии и отзыв устройств, Argon2id, блокировка перебора, восстановление пароля без раскрытия существования email, псевдонимы gmail, временная почта, лимит аккаунтов на устройство, удаление аккаунта с данными, заголовки безопасности, SQL-инъекции |
| `tests/backend/test_chats.py` | CRUD чатов, потоковый ответ (SSE), заголовок чата, переименование, повторная генерация, редактирование, учёт токенов, изоляция пользователей, перегрузка/недоступность модели без потери данных, квоты, режим обслуживания, статус модели, method override для Android |
| `tests/backend/test_referrals.py` | подтверждение и награды, ожидание email, общий IP не считается мошенничеством, общее устройство, одноразовость наград, скорость, потолок скидки, ручное одобрение |
| `tests/backend/test_developer_api.py` | ключи (хеш, показ один раз, отзыв), `/v1/chat/completions` обычный и потоковый в формате OpenAI, ошибки в формате OpenAI, RPM и дневная квота ключа, изоляция ключей |
| `tests/backend/test_admin.py` | обычный пользователь не имеет доступа, статистика, лимиты, бан, настройки, аудит, редактирование секретов в журнале ошибок |
| `tests/inference/test_inference.py` | шаблон OLMo 2, обрезка истории, HMAC (подмена, повтор), отказ без подписи, поток событий, FIFO-очередь, отмена, 503 при переполнении |
| `tests/inference/test_llamacpp_integration.py` | **настоящий llama-server** (llama.cpp) с GGUF архитектуры `olmo2`: запуск, стриминг, учёт токенов, остановка процесса |
| `tests/inference/test_mtls.py` | mTLS + HMAC между backend и инференсом, отказ без клиентского сертификата и по http |
| `tests/cli/test_cli.py` | `kiwion server start/stop`, `status`, `chat`, `benchmark`, `secret`, `--version` |
| `tests/e2e/test_web_e2e.py` | браузер: регистрация с PoW → ссылка из письма → чат со стримингом и подсветкой кода → остановка → повтор → восстановление истории и черновика → API-ключ и реальный вызов `/v1` → рефералы → тёмная тема → **пасхалка** (4 нажатия не срабатывают, пауза сбрасывает, 5-е срабатывает, «Погладить киви», закрытие, повторный запуск, Esc) → мобильная вёрстка → страница релиза; сообщение «Птичка киви немного устала» с сохранением текста; админка (запрет для обычного пользователя, все разделы, изменение настроек) |
| `tests/mobile/test_mobile.py` | JVM-тесты логики Android (`TapCounter` пасхалки, `Pow` с перекрёстной проверкой на сервере), проверка собранного APK (пакет, версия, launcher, разрешения, подпись) |

## Что НЕ удалось проверить в среде разработки и как проверить

| Что | Причина | Как проверить |
|---|---|---|
| Ответы настоящей модели OLMo 2 1B | доступ к huggingface.co из песочницы заблокирован, веса не скачать. Конвейер проверен на настоящем llama.cpp с маленькой GGUF той же архитектуры `olmo2` и случайными весами (`scripts/make_tiny_test_model.py`) | `scripts/download_model.sh && kiwion server start --wait 300 && kiwion chat`; затем `KIWION_TEST_GGUF=models/olmo-2-1b-instruct-Q4_K_M.gguf pytest tests/inference/test_llamacpp_integration.py` |
| Скорость на Pentium 4417U / Intel HD 620 | такого железа нет | `kiwion benchmark` и `kiwion benchmark --llama-bench` на целевой машине (см. WEAK_HARDWARE.md) |
| Запуск APK на устройстве/эмуляторе | Android SDK, эмулятор и Google Maven недоступны; APK собран из apt-пакетов (aapt, dx, apksigner, android.jar API 23), проверены манифест, подпись и JVM-логика | установить `mobile/build/KiwionChat-1.0.0.apk` на Android 7+ (`adb install`), пройти: регистрация → письмо → код → чат → стоп → настройки → 5 нажатий по версии |
| Gradle-сборка (`mobile/app/build.gradle`) | Google Maven (Android Gradle Plugin) недоступен | открыть `mobile/` в Android Studio → Build APK |
| Docker-образы и Caddy | нет Docker-демона | `docker compose -f deploy/docker-compose.vps.yml up --build` на VPS |
| Реальная отправка писем по SMTP | нет SMTP-сервера; проверен режим `file` (письма в `data/outbox`) | задать `KIWION_MAIL_MODE=smtp` и параметры SMTP, зарегистрироваться |
