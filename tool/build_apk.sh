#!/usr/bin/env bash
# Genera APK release y la guarda en build/app/outputs/flutter-apk/
# Uso: ./tool/build_apk.sh [version] [build_number]
# Ejemplo: ./tool/build_apk.sh 3.9 39

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-3.9}"
BUILD_NUMBER="${2:-39}"
OUT_DIR="build/app/outputs/flutter-apk"
APK_NAME="padelcobrov${VERSION}.apk"

flutter build apk --release \
  --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw \
  --dart-define=FIREBASE_APP_ID=1:1018372483361:android:dcdceabf580b3647ca7660 \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361 \
  --dart-define=FIREBASE_PROJECT_ID=padel-cobro \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

cp "$OUT_DIR/app-release.apk" "$OUT_DIR/$APK_NAME"
echo ""
echo "APK lista: $OUT_DIR/$APK_NAME"
