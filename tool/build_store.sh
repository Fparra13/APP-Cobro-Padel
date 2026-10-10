#!/usr/bin/env bash
# Genera AAB (Play Store) + APK release firmados → Supabase PROD (explícito).
# Uso: ./tool/build_store.sh [version] [build_number]
# Ejemplo: ./tool/build_store.sh 1.0.6 17
#
# Lee ~/.config/kloovi/supabase-prod.env (fuera del repo).
# NO usa defaults silenciosos de supabase_config.dart.
# NO inyecta SUPABASE_SERVICE_ROLE_KEY.
# Aborta si SUPABASE_URL apunta a DEV.
#
# Para AAB DEV / Internal Testing: ./tool/build_store_dev.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# shellcheck source=supabase_env_common.sh
source "$(dirname "$0")/supabase_env_common.sh"

VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"

APK_DIR="build/app/outputs/flutter-apk"
AAB_DIR="build/app/outputs/bundle/release"
OUT_APK="klooviv${VERSION}.apk"
OUT_AAB="klooviv${VERSION}.aab"

if [[ ! -f android/key.properties ]]; then
  echo "Falta android/key.properties (firma release)." >&2
  exit 1
fi

kloovi_load_prod_env || exit 1

DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=KLOOVI_ENV=prod
)
# shellcheck disable=SC2207
DART_DEFINES+=($(kloovi_firebase_dart_defines))

echo "==> Building App Bundle (PROD) v${VERSION}+${BUILD_NUMBER}"
echo "    Supabase PROD ref guard: $KLOOVI_SUPABASE_PROD_REF"
flutter build appbundle --release \
  "${DART_DEFINES[@]}" \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

echo "==> Building APK (arm64) v${VERSION}+${BUILD_NUMBER} [PROD]"
flutter build apk --release \
  --split-per-abi \
  "${DART_DEFINES[@]}" \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

cp "$AAB_DIR/app-release.aab" "$AAB_DIR/$OUT_AAB"
cp "$APK_DIR/app-arm64-v8a-release.apk" "$APK_DIR/$OUT_APK"

echo ""
echo "Listo [PROD]:"
ls -lh "$AAB_DIR/$OUT_AAB" "$APK_DIR/$OUT_APK"
echo ""
echo "Play Store → sube: $AAB_DIR/$OUT_AAB"
echo "Instalación directa →: $APK_DIR/$OUT_APK"
