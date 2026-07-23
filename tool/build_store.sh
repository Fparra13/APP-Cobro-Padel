#!/usr/bin/env bash
# Genera AAB (Play Store) + APK release firmados.
# Uso: ./tool/build_store.sh [version] [build_number]
# Ejemplo: ./tool/build_store.sh 1.0.0 100

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"

APK_DIR="build/app/outputs/flutter-apk"
AAB_DIR="build/app/outputs/bundle/release"
OUT_APK="klooviv${VERSION}.apk"
OUT_AAB="klooviv${VERSION}.aab"

DART_DEFINES=(
  --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw
  --dart-define=FIREBASE_APP_ID=1:1018372483361:android:1327a7f02a8a578aca7660
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361
  --dart-define=FIREBASE_PROJECT_ID=padel-cobro
  --dart-define=GOOGLE_WEB_CLIENT_ID=1018372483361-j3kffsnkj7esf244evoqp0d6492j6jlb.apps.googleusercontent.com
)

if [[ ! -f android/key.properties ]]; then
  echo "Falta android/key.properties (firma release)."
  exit 1
fi

echo "==> Building App Bundle (Play Store) v${VERSION}+${BUILD_NUMBER}"
flutter build appbundle --release \
  "${DART_DEFINES[@]}" \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

echo "==> Building APK (arm64) v${VERSION}+${BUILD_NUMBER}"
flutter build apk --release \
  --split-per-abi \
  "${DART_DEFINES[@]}" \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

cp "$AAB_DIR/app-release.aab" "$AAB_DIR/$OUT_AAB"
cp "$APK_DIR/app-arm64-v8a-release.apk" "$APK_DIR/$OUT_APK"

echo ""
echo "Listo:"
ls -lh "$AAB_DIR/$OUT_AAB" "$APK_DIR/$OUT_APK"
echo ""
echo "Play Store → sube: $AAB_DIR/$OUT_AAB"
echo "Instalación directa →: $APK_DIR/$OUT_APK"
