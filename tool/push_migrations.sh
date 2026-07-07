#!/usr/bin/env bash
# Aplica migraciones nuevas al proyecto Supabase enlazado.
# Uso: ./tool/push_migrations.sh

set -eo pipefail
cd "$(dirname "$0")/.."

echo "→ Comprobando historial local vs remoto..."
supabase migration list --linked

echo ""
echo "→ Aplicando migraciones pendientes..."
supabase db push --linked --yes

echo ""
echo "✓ Listo."
