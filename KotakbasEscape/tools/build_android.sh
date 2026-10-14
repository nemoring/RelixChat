#!/bin/sh
# Сборка «Котакбас побег от ТЦК» для Android.
#   tools/build_android.sh debug     — отладочный APK (подписан debug-ключом)
#   tools/build_android.sh release   — релизный APK (нужен свой ключ, см. ниже)
#   tools/build_android.sh aab       — Android App Bundle (нужен Gradle-шаблон и полный Android SDK)
#
# Переменные окружения:
#   GODOT                     — путь к Godot 4.4.x (по умолчанию: godot)
#   ANDROID_SDK               — путь к Android SDK (build-tools с apksigner, platform-tools)
#   Для release/aab ключ НЕ хранится в проекте, а передаётся через окружение:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH, GODOT_ANDROID_KEYSTORE_RELEASE_USER,
#   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
set -e
cd "$(dirname "$0")/.."
MODE=${1:-debug}
GODOT=${GODOT:-godot}
mkdir -p build

echo "== Проверка окружения"
command -v "$GODOT" >/dev/null || { echo "Godot не найден (переменная GODOT)"; exit 1; }
"$GODOT" --version
command -v java >/dev/null || { echo "Не найден JDK (нужен OpenJDK 17)"; exit 1; }
java -version 2>&1 | head -1
if [ -n "$ANDROID_SDK" ] && [ ! -d "$ANDROID_SDK/build-tools" ]; then
	echo "В ANDROID_SDK нет build-tools"; exit 1
fi

echo "== Импорт ресурсов и проверка скриптов"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . res://tests/compile_all.tscn 2>&1 | grep -E "FAIL|Скриптов" || true

echo "== Автотесты"
"$GODOT" --headless --path . res://tests/run_tests.tscn 2>&1 | grep -E "FAIL|ИТОГО"

case "$MODE" in
	debug)
		"$GODOT" --headless --path . --export-debug "Android Debug APK" build/KotakbasEscape-debug.apk
		OUT=build/KotakbasEscape-debug.apk ;;
	release)
		[ -n "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ] || { echo "Укажите релизный ключ через GODOT_ANDROID_KEYSTORE_RELEASE_*"; exit 1; }
		"$GODOT" --headless --path . --export-release "Android Release APK" build/KotakbasEscape-release.apk
		OUT=build/KotakbasEscape-release.apk ;;
	aab)
		[ -d android/build ] || { echo "Установите Android build template: Проект → Установить шаблон сборки Android"; exit 1; }
		"$GODOT" --headless --path . --export-release "Android AAB (Google Play)" build/KotakbasEscape.aab
		OUT=build/KotakbasEscape.aab ;;
	*) echo "Режим: debug | release | aab"; exit 1 ;;
esac

echo "== Проверка результата"
[ -f "$OUT" ] || { echo "Файл $OUT не создан"; exit 1; }
ls -la "$OUT"
if [ "${OUT##*.}" = "apk" ] && command -v apksigner >/dev/null; then
	apksigner verify --print-certs "$OUT" | head -3
fi
echo "Готово: $OUT"
