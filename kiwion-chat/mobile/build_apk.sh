#!/usr/bin/env bash
# Build the Kiwion Chat APK without Gradle, using the plain Android build tools:
#   aapt (resources) -> javac (Java 8 bytecode) -> d8/dx (dex) -> zipalign -> apksigner
#
# Works with either a full Android SDK (ANDROID_HOME) or Debian/Ubuntu packages:
#   sudo apt install aapt apksigner zipalign dalvik-exchange android-sdk-platform-23 openjdk-17-jdk
#
# Env:
#   KIWION_SERVER_URL      default backend URL baked into the app (default https://kiwion.example.com)
#   KIWION_ALLOW_CLEARTEXT=1  allow http:// servers (local testing only)
#   KIWION_KEYSTORE, KIWION_KEYSTORE_PASS, KIWION_KEY_ALIAS  release signing key (otherwise a debug key is generated)
set -euo pipefail
cd "$(dirname "$0")"
MOBILE="$(pwd)"
SRC="$MOBILE/app/src/main"
OUT="$MOBILE/build"
APP_VERSION="1.0.0"

find_tool() { for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { command -v "$c"; return; }; done; return 1; }
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -n "$SDK" ] && [ -d "$SDK/build-tools" ]; then
  BT="$(ls -d "$SDK"/build-tools/* | sort -V | tail -1)"
  AAPT="$BT/aapt"; ZIPALIGN="$BT/zipalign"; APKSIGNER="$BT/apksigner"; D8="$BT/d8"; DX=""
  ANDROID_JAR="$(ls -d "$SDK"/platforms/android-* | sort -V | tail -1)/android.jar"
else
  AAPT="$(find_tool aapt)"; ZIPALIGN="$(find_tool zipalign)"; APKSIGNER="$(find_tool apksigner)"
  D8="$(find_tool d8 || true)"; DX="$(find_tool dalvik-exchange dx || true)"
  ANDROID_JAR="$(ls /usr/lib/android-sdk/platforms/android-*/android.jar 2>/dev/null | sort -V | tail -1)"
fi
[ -f "$ANDROID_JAR" ] || { echo "android.jar not found (install android-sdk-platform-23 or set ANDROID_HOME)"; exit 1; }
echo "using android.jar: $ANDROID_JAR"

rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/src"
cp -r "$SRC/java/." "$OUT/src/"
cp "$SRC/AndroidManifest.xml" "$OUT/AndroidManifest.xml"
# what Gradle would merge in: package name, version and SDK levels
sed -i 's#<manifest xmlns:android="http://schemas.android.com/apk/res/android">#<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="dev.kiwifuzzy.kiwion" android:versionCode="1" android:versionName="'"$APP_VERSION"'">\n    <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="34" />#' "$OUT/AndroidManifest.xml"

# build-time configuration
SERVER="${KIWION_SERVER_URL:-https://kiwion.example.com}"
sed -i "s#DEFAULT_SERVER = \".*\";#DEFAULT_SERVER = \"${SERVER}\";#" "$OUT/src/dev/kiwifuzzy/kiwion/BuildConfigKiwion.java"
if [ "${KIWION_ALLOW_CLEARTEXT:-0}" = "1" ]; then
  sed -i 's/android:usesCleartextTraffic="false"/android:usesCleartextTraffic="true"/' "$OUT/AndroidManifest.xml"
  echo "WARNING: cleartext http allowed (testing build)"
fi

echo "[1/5] resources"
"$AAPT" package -f -m -J "$OUT/gen" -M "$OUT/AndroidManifest.xml" -S "$SRC/res" -I "$ANDROID_JAR"

echo "[2/5] javac"
find "$OUT/src" "$OUT/gen" -name '*.java' > "$OUT/sources.txt"
javac -nowarn -encoding UTF-8 --release 8 -classpath "$ANDROID_JAR" -d "$OUT/classes" @"$OUT/sources.txt" 2>&1 | grep -v "^warning: \[options\]\|^Note:\|^1 warning" || true
[ -f "$OUT/classes/dev/kiwifuzzy/kiwion/KiwionApp.class" ] || { echo "javac failed"; exit 1; }

echo "[3/5] dex"
if [ -n "$D8" ]; then
  "$D8" --min-api 24 --lib "$ANDROID_JAR" --output "$OUT" $(find "$OUT/classes" -name '*.class')
else
  "$DX" --dex --min-sdk-version=24 --output="$OUT/classes.dex" "$OUT/classes"
fi

echo "[4/5] package"
"$AAPT" package -f -M "$OUT/AndroidManifest.xml" -S "$SRC/res" -I "$ANDROID_JAR" -F "$OUT/kiwion-unsigned.apk"
(cd "$OUT" && "$AAPT" add kiwion-unsigned.apk classes.dex >/dev/null)
"$ZIPALIGN" -f -p 4 "$OUT/kiwion-unsigned.apk" "$OUT/kiwion-aligned.apk"

echo "[5/5] sign"
KS="${KIWION_KEYSTORE:-$MOBILE/keystore/debug.keystore}"
PASS="${KIWION_KEYSTORE_PASS:-kiwion-debug}"
ALIAS="${KIWION_KEY_ALIAS:-kiwion}"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass "$PASS" -keypass "$PASS" -alias "$ALIAS" -keyalg RSA -keysize 2048 \
    -validity 10000 -dname "CN=Kiwion Chat Debug, O=Kiwi_Fuzzy" >/dev/null 2>&1
  echo "generated debug keystore $KS (use KIWION_KEYSTORE for release builds)"
fi
"$APKSIGNER" sign --ks "$KS" --ks-pass "pass:$PASS" --ks-key-alias "$ALIAS" --out "$OUT/KiwionChat-$APP_VERSION.apk" "$OUT/kiwion-aligned.apk"
"$APKSIGNER" verify "$OUT/KiwionChat-$APP_VERSION.apk"
rm -f "$OUT/kiwion-unsigned.apk" "$OUT/kiwion-aligned.apk"
ls -la "$OUT/KiwionChat-$APP_VERSION.apk"
sha256sum "$OUT/KiwionChat-$APP_VERSION.apk"
