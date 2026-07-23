#!/usr/bin/env bash
# Genera APK release (split por arquitectura → ~40% más liviano que universal).
# Uso: ./tool/build_apk.sh [version] [build_number]
# Ejemplo: ./tool/build_apk.sh 1.0.0 1
#
# Salida principal: klooviv{version}.apk  (arm64-v8a, teléfonos actuales)
# También: klooviv{version}-arm32.apk       (dispositivos viejos)
#          klooviv{version}-x64.apk        (emuladores x86_64)

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
OUT_DIR="build/app/outputs/flutter-apk"
APK_ARM64="klooviv${VERSION}.apk"
APK_ARM32="klooviv${VERSION}-arm32.apk"
APK_X64="klooviv${VERSION}-x64.apk"

DART_DEFINES=(
  --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw
  --dart-define=FIREBASE_APP_ID=1:1018372483361:android:1327a7f02a8a578aca7660
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361
  --dart-define=FIREBASE_PROJECT_ID=padel-cobro
  --dart-define=GOOGLE_WEB_CLIENT_ID=1018372483361-j3kffsnkj7esf244evoqp0d6492j6jlb.apps.googleusercontent.com
)

flutter build apk --release \
  --split-per-abi \
  "${DART_DEFINES[@]}" \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

cp "$OUT_DIR/app-arm64-v8a-release.apk" "$OUT_DIR/$APK_ARM64"
cp "$OUT_DIR/app-armeabi-v7a-release.apk" "$OUT_DIR/$APK_ARM32"
cp "$OUT_DIR/app-x86_64-release.apk" "$OUT_DIR/$APK_X64"

echo ""
echo "APKs listas en $OUT_DIR:"
ls -lh "$OUT_DIR/$APK_ARM64" "$OUT_DIR/$APK_ARM32" "$OUT_DIR/$APK_X64" 2>/dev/null || true
echo ""
echo "Instala en tu teléfono: $OUT_DIR/$APK_ARM64"
echo "(arm64-v8a — la mayoría de Android actuales; ~mitad de peso vs APK universal)"
