# process-cobro-reminders

Worker de recordatorios automáticos de cobro.

## Auth

`Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY | REMINDERS_CRON_SECRET | PURGE_CRON_SECRET>`

`verify_jwt = false` (auth propia en el handler).

## Cron

`pg_cron` job `kloovi_process_cobro_reminders` cada 15 minutos → `net.http_post` a esta función.

## Flujo

1. `claim_cobro_recordatorios_due` (SKIP LOCKED + `claim_until`)
2. Revalidar elegibilidad
3. Generar `delivery_id` (UUID) = **ID de este intento de entrega**, no “mensaje visto por el usuario”.
   FCM no garantiza exactamente-una entrega; el ID sirve para trazabilidad del intento.
4. `send-push` (path interno; `data.delivery_id`)
5. Éxito API FCM → `completar_cobro_recordatorio_envio(id, delivery_id)` → guarda `ultimo_delivery_id`
6. Fallo temporal → `reintentar_cobro_recordatorio_backoff` (15m → 1h → 6h → frecuencia)
7. Token inválido → `diferir_cobro_recordatorio_sin_token`

## Observabilidad

Logs JSON incluyen `worker` (`worker_instance_id` de 8 chars por invocación).

## Futuro (V2)

Tabla `cobro_recordatorio_delivery`:
`id, cobro_recordatorio_id, delivery_id, attempt_number, status, claimed_at, sent_at, completed_at, fcm_message_id, error_code, worker_instance_id, created_at`
