#!/usr/bin/env bash
# Ejecuta MatchPay en modo debug en el Android conectado por USB.
# Uso: ./tool/run_debug.sh [device_id]
# Hot reload: guarda un .dart y pulsa "r" en esta terminal.
#
# Supabase: lee DEV desde ~/.config/kloovi/supabase-dev.env
# (no hardcodea URL/anon). Release/store siguen en defaults PROD.

set -eo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-}"

DEV_ENV="${HOME}/.config/kloovi/supabase-dev.env"
if [[ ! -f "$DEV_ENV" ]]; then
  echo "Falta $DEV_ENV (SUPABASE_URL / SUPABASE_ANON_KEY de DEV)." >&2
  exit 1
fi
# shellcheck disable=SC1090
set -a
source "$DEV_ENV"
set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "supabase-dev.env debe definir SUPABASE_URL y SUPABASE_ANON_KEY." >&2
  exit 1
fi

DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw
  --dart-define=FIREBASE_APP_ID=1:1018372483361:android:1327a7f02a8a578aca7660
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361
  --dart-define=FIREBASE_PROJECT_ID=padel-cobro
  --dart-define=GOOGLE_WEB_CLIENT_ID=1018372483361-j3kffsnkj7esf244evoqp0d6492j6jlb.apps.googleusercontent.com
)

if [[ -n "$DEVICE" ]]; then
  flutter run -d "$DEVICE" "${DART_DEFINES[@]}"
else
  flutter run "${DART_DEFINES[@]}"
fi
