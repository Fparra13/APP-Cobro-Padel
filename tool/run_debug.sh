#!/usr/bin/env bash
# Ejecuta MatchPay en modo debug en el Android conectado por USB.
# Uso: ./tool/run_debug.sh [device_id]
# Hot reload: guarda un .dart y pulsa "r" en esta terminal.

set -eo pipefail
cd "$(dirname "$0")/.."

DEVICE="${1:-}"
FIREBASE_FLAGS=(
  --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw
  --dart-define=FIREBASE_APP_ID=1:1018372483361:android:465e4bd9e25e99b2ca7660
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361
  --dart-define=FIREBASE_PROJECT_ID=padel-cobro
  --dart-define=GOOGLE_WEB_CLIENT_ID=1018372483361-j3kffsnkj7esf244evoqp0d6492j6jlb.apps.googleusercontent.com
)

if [[ -n "$DEVICE" ]]; then
  flutter run -d "$DEVICE" "${FIREBASE_FLAGS[@]}"
else
  flutter run "${FIREBASE_FLAGS[@]}"
fi
