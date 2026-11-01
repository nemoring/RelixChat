# Kiwion Chat для Android

Java + Android framework (minSdk 24 / Android 7.0, targetSdk 34), без сторонних библиотек: интерфейс
строится кодом, маскот и пасхалка рисуются на Canvas, звук синтезируется `AudioTrack`.

## Сборка без Android Studio

```bash
# Ubuntu/Debian
sudo apt install aapt apksigner zipalign dalvik-exchange android-sdk-platform-23 openjdk-17-jdk
KIWION_SERVER_URL=https://chat.example.com ./build_apk.sh
# -> build/KiwionChat-1.0.0.apk
```

С установленным Android SDK скрипт сам возьмёт `$ANDROID_HOME/build-tools` (d8) и `platforms`.
Релизная подпись: `KIWION_KEYSTORE=/path/release.jks KIWION_KEYSTORE_PASS=… KIWION_KEY_ALIAS=kiwion ./build_apk.sh`
(без этих переменных создаётся debug-ключ в `keystore/`, он не коммитится).
Для теста с локальным http-сервером: `KIWION_ALLOW_CLEARTEXT=1 KIWION_SERVER_URL=http://192.168.1.10:8080 ./build_apk.sh`.

## Android Studio

Откройте каталог `mobile/` — это обычный Gradle-проект (`app/build.gradle`, AGP 8.5).

## Экраны

`SplashActivity` (маскот + Kiwion Chat, проверка сервера/сессии, экран ошибки) → `AuthActivity`
(вход, регистрация с proof-of-work и кодом приглашения, восстановление пароля, подтверждение email
кодом из письма, адрес сервера) → `ChatsActivity` (диалоги, статус модели, новый чат, долгое нажатие —
переименовать/удалить) → `ChatActivity` (стриминг, стоп, повтор, копирование, редактирование
долгим нажатием, Markdown с подсветкой кода, черновики, очередь, подсказка при медленной модели) и
`SettingsActivity` (профиль и лимиты, тема, пароль и устройства, удаление аккаунта, API-ключи со
статистикой, рефералы, «О приложении» с пасхалкой, адрес сервера, выход).

Ссылка `kiwion://register?ref=KIWI…` открывает регистрацию с кодом приглашения.
