#!/bin/bash
# Сборка Five Nights at ПВЗ: Windows (x86_64) и Android (arm64-v8a).
# Требуется Godot 4.3 и установленные шаблоны экспорта 4.3.stable.
#   GODOT=/путь/к/godot tools/build.sh [windows|android|all]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TARGET="${1:-all}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

if [ "$TARGET" = "windows" ] || [ "$TARGET" = "all" ]; then
	mkdir -p build/windows
	"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/FiveNightsAtPVZ.exe
	echo "Windows: build/windows/FiveNightsAtPVZ.exe"
fi

if [ "$TARGET" = "android" ] || [ "$TARGET" = "all" ]; then
	mkdir -p build/android
	# Обычный путь: Android SDK + keystore в настройках редактора, package/signed=true.
	if "$GODOT" --headless --path . --export-release "Android" build/android/FiveNightsAtPVZ.apk; then
		echo "Android: build/android/FiveNightsAtPVZ.apk"
	else
		echo "Экспорт Android не удался: проверьте Android SDK и keystore в Editor Settings." >&2
		echo "Без SDK можно экспортировать неподписанный APK (package/signed=false) и подписать" >&2
		echo "его tools/sign_apk_v2.py (схема v2, Android 7.0+)." >&2
		exit 1
	fi
fi
