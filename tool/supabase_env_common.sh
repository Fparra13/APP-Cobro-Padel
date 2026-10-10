#!/usr/bin/env bash
# Helpers compartidos para builds que inyectan Supabase via --dart-define.
# Sin secretos. Los valores viven fuera del repo (~/.config/kloovi/*.env).
#
# Contrato usado por tool/build_apk.sh y tool/build_store.sh:
#   kloovi_load_prod_env
#   kloovi_firebase_dart_defines
#
# Uso: source "$(dirname "$0")/supabase_env_common.sh"

# shellcheck disable=SC2034
KLOOVI_SUPABASE_DEV_REF="qduybfdxpyfjzosakdlq"
KLOOVI_SUPABASE_PROD_REF="efcfxfcypdsrmbultnkl"

KLOOVI_SUPABASE_PROD_ENV="${KLOOVI_SUPABASE_PROD_ENV:-${HOME}/.config/kloovi/supabase-prod.env}"

# Carga SUPABASE_URL + SUPABASE_ANON_KEY de PROD. Aborta si falta o si ve DEV.
# No exporta SUPABASE_SERVICE_ROLE_KEY al entorno del build.
kloovi_load_prod_env() {
  if [[ ! -f "$KLOOVI_SUPABASE_PROD_ENV" ]]; then
    echo "Falta $KLOOVI_SUPABASE_PROD_ENV (SUPABASE_URL / SUPABASE_ANON_KEY de PROD)." >&2
    echo "Ver config/supabase-prod.env.example (placeholders; sin secretos en el repo)." >&2
    return 1
  fi

  # shellcheck disable=SC1090
  set -a
  # shellcheck source=/dev/null
  source "$KLOOVI_SUPABASE_PROD_ENV"
  set +a

  unset SUPABASE_SERVICE_ROLE_KEY || true

  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
    echo "supabase-prod.env debe definir SUPABASE_URL y SUPABASE_ANON_KEY." >&2
    return 1
  fi

  if [[ "$SUPABASE_URL" == *"$KLOOVI_SUPABASE_DEV_REF"* ]]; then
    echo "ABORT: SUPABASE_URL contiene ref DEV ($KLOOVI_SUPABASE_DEV_REF). No se construye PROD." >&2
    return 1
  fi

  if [[ "$SUPABASE_URL" != *"$KLOOVI_SUPABASE_PROD_REF"* ]]; then
    echo "ABORT: SUPABASE_URL no apunta a PROD ($KLOOVI_SUPABASE_PROD_REF): $SUPABASE_URL" >&2
    return 1
  fi

  return 0
}

# Dart-defines Firebase / Google OAuth (mismos valores públicos que build_store_dev).
# Imprime una línea con tokens --dart-define=... (para array +=).
kloovi_firebase_dart_defines() {
  printf '%s\n' \
    --dart-define=FIREBASE_API_KEY=AIzaSyCkgdPZrbDVJmvnmjx5WfVe4NUUGyiujiw \
    --dart-define=FIREBASE_APP_ID=1:1018372483361:android:1327a7f02a8a578aca7660 \
    --dart-define=FIREBASE_MESSAGING_SENDER_ID=1018372483361 \
    --dart-define=FIREBASE_PROJECT_ID=padel-cobro \
    --dart-define=GOOGLE_WEB_CLIENT_ID=1018372483361-j3kffsnkj7esf244evoqp0d6492j6jlb.apps.googleusercontent.com
}
