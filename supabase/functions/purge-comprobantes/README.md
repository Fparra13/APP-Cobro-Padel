# purge-comprobantes

Edge Function diaria: borra del bucket `comprobantes` los archivos con más de **14 días** (`storage.objects.created_at`) y anula las referencias en:

- `detalles_partido.comprobante_url` (pagos de jugador)
- `partidos.comprobante_cancha_url` / `comprobante_pelotas_url`
- `costos_variables.comprobante_url`

## Deploy

```bash
supabase functions deploy purge-comprobantes --no-verify-jwt
```

Auth: `Authorization: Bearer <PURGE_CRON_SECRET>` (secret de Edge Functions)
o, en su defecto, el `SUPABASE_SERVICE_ROLE_KEY`.

## Cron (pg_cron + pg_net)

1. `supabase secrets set PURGE_CRON_SECRET=<random>`
2. Vault: `purge_cron_secret` (mismo valor) + opcional `project_url`
3. Job `kloovi_purge_comprobantes` — `0 6 * * *` (06:00 UTC)

Ver `069_purge_comprobantes_retencion.sql`.
