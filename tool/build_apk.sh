#!/usr/bin/env bash
# Genera APK release (split por arquitectura) → Supabase PROD (explícito).
# Uso: ./tool/build_apk.sh [version] [build_number]
# Ejemplo: ./tool/build_apk.sh 1.0.0 1
#
# Requiere ~/.config/kloovi/supabase-prod.env (ver config/supabase-prod.env.example).
# No usa defaults del código.
#
# Salida principal: klooviv{version}.apk  (arm64-v8a, teléfonos actuales)
# También: klooviv{version}-arm32.apk       (dispositivos viejos)
#          klooviv{version}-x64.apk        (emuladores x86_64)

set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=supabase_env_common.sh
source "$(dirname "$0")/supabase_env_common.sh"

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
OUT_DIR="build/app/outputs/flutter-apk"
APK_ARM64="klooviv${VERSION}.apk"
APK_ARM32="klooviv${VERSION}-arm32.apk"
APK_X64="klooviv${VERSION}-x64.apk"

kloovi_load_prod_env || exit 1

DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=KLOOVI_ENV=prod
)
# shellcheck disable=SC2207
DART_DEFINES+=($(kloovi_firebase_dart_defines))

echo "==> Building APK release v${VERSION}+${BUILD_NUMBER} [PROD]"
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
