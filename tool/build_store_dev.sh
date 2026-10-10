#!/usr/bin/env bash
# Genera AAB release firmado apuntando a Supabase DEV (solo Internal Testing / QA).
# Uso: ./tool/build_store_dev.sh [version] [build_number]
# Ejemplo: ./tool/build_store_dev.sh 1.0.5 7
#
# Lee ~/.config/kloovi/supabase-dev.env (fuera del repo).
# NO usa defaults PROD. NO toca tool/build_store.sh.
# NO inyecta SUPABASE_SERVICE_ROLE_KEY.

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.5}"
BUILD_NUMBER="${2:-7}"

AAB_DIR="build/app/outputs/bundle/release"
OUT_AAB="klooviv${VERSION}-dev.aab"
DEV_ENV="${HOME}/.config/kloovi/supabase-dev.env"
DEV_REF="qduybfdxpyfjzosakdlq"
PROD_REF="efcfxfcypdsrmbultnkl"

if [[ ! -f android/key.properties ]]; then
  echo "Falta android/key.properties (firma release)." >&2
  exit 1
fi

if [[ ! -f "$DEV_ENV" ]]; then
  echo "Falta $DEV_ENV (SUPABASE_URL / SUPABASE_ANON_KEY de DEV)." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$DEV_ENV"
set +a

# Nunca propagar service role al cliente.
unset SUPABASE_SERVICE_ROLE_KEY || true

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "supabase-dev.env debe definir SUPABASE_URL y SUPABASE_ANON_KEY." >&2
  exit 1
fi

if [[ "$SUPABASE_URL" != *"$DEV_REF"* ]]; then
  echo "ABORT: SUPABASE_URL no apunta a DEV ($DEV_REF): $SUPABASE_URL" >&2
  exit 1
fi

if [[ "$SUPABASE_URL" == *"$PROD_REF"* ]]; then
  echo "ABORT: SUPABASE_URL contiene ref PROD ($PROD_REF). No se construye." >&2
  exit 1
fi

# Mismos Firebase / Google OAuth que tool/build_store.sh y tool/run_debug.sh.
DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=KLOOVI_ENV=dev
  --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw
  --dart-define=FIREBASE_APP_ID=1:1018372483361:android:1327a7f02a8a578aca7660
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361
  --dart-define=FIREBASE_PROJECT_ID=padel-cobro
  --dart-define=GOOGLE_WEB_CLIENT_ID=1018372483361-j3kffsnkj7esf244evoqp0d6492j6jlb.apps.googleusercontent.com
)

echo "==> Building App Bundle (DEV) v${VERSION}+${BUILD_NUMBER}"
echo "    Supabase DEV ref guard: $DEV_REF"
flutter build appbundle --release \
  "${DART_DEFINES[@]}" \
  --build-name="$VERSION" \
  --build-number="$BUILD_NUMBER"

cp "$AAB_DIR/app-release.aab" "$AAB_DIR/$OUT_AAB"

echo ""
echo "Listo [DEV]:"
ls -lh "$AAB_DIR/app-release.aab" "$AAB_DIR/$OUT_AAB"
echo ""
echo "Play Internal Testing (DEV backend) → sube: $AAB_DIR/$OUT_AAB"
echo "(copia idéntica de app-release.aab; no es un segundo build)"
