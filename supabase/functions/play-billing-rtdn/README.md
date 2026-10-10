# play-billing-rtdn

Edge Function (Kloovi) that receives Google Play **Real-time Developer Notifications (RTDN)** via Pub/Sub push, re-verifies the subscription with Google Play API, and upserts `billing_purchases` / `billing_subscriptions`.

Does **not** grant Pro from the notification alone: it only updates rows for a `purchase_token` already bound to a `user_id`.

## Auth (Pub/Sub Push OIDC)

`verify_jwt = false` — la función valida el JWT OIDC de Pub/Sub en el handler.

Pub/Sub envía:

```http
Authorization: Bearer <Google-signed OIDC JWT>
```

Validación criptográfica:

1. Firma RS256 con JWKS de Google (`https://www.googleapis.com/oauth2/v3/certs`)
2. Claims: `iss` (accounts.google.com), `aud`, `exp`, `email`, `email_verified=true`
3. `email` debe coincidir exactamente con la SA configurada (allowlist de una sola cuenta)

### Secrets / config DEV (no PROD en esta fase)

```text
PLAY_BILLING_RTDN_OIDC_EMAIL      # SA de push, p.ej. pubsub-rtdn-push@padel-cobro.iam.gserviceaccount.com
PLAY_BILLING_RTDN_OIDC_AUDIENCE   # normalmente la URL del endpoint
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  # Play Developer API (ya usado)
```

Audience típica:

```text
https://qduybfdxpyfjzosakdlq.supabase.co/functions/v1/play-billing-rtdn
```

Opcional (deshabilitado por defecto; solo pruebas manuales con curl):

```text
PLAY_BILLING_RTDN_ALLOW_STATIC_BEARER=true
PLAY_BILLING_RTDN_SECRET=<secret ≥16 chars>
```

```bash
# Solo cuando se indique explícitamente:
supabase secrets set \
  PLAY_BILLING_RTDN_OIDC_EMAIL='...' \
  PLAY_BILLING_RTDN_OIDC_AUDIENCE='https://qduybfdxpyfjzosakdlq.supabase.co/functions/v1/play-billing-rtdn' \
  --project-ref qduybfdxpyfjzosakdlq
```

**No** commitear secretos. **Nunca** loguear JWT, `purchase_token` ni el Bearer.

## Endpoint

`POST /functions/v1/play-billing-rtdn`

Body: envelope Pub/Sub push (`message.data` = base64 JSON RTDN).

## Flujo

1. Validar OIDC Pub/Sub (JWKS + claims)
2. `parseRtdnPubSubBody` → `purchaseToken`, `productId`, `notificationType`
3. Lookup `billing_purchases` por token (sin binding → skip 200, no asigna Pro)
4. Google `subscriptionsv2.get` + `validateProductAgainstGoogle`
5. Upsert `billing_purchases` y `billing_subscriptions`
6. RTDN `REVOKED` (12) → `status=revoked`; `EXPIRED` (13) → `status=expired`

## Play Console / Pub/Sub setup (GCP `padel-cobro`)

1. Topic: `kloovi-play-billing-rtdn`
2. SA de push dedicada + `roles/iam.serviceAccountTokenCreator` (getOpenIdToken)
3. Subscription push `kloovi-play-billing-rtdn-sub`:
   - Endpoint: URL de esta función
   - Enable authentication → SA de push
   - Audience = `PLAY_BILLING_RTDN_OIDC_AUDIENCE`
4. Play Console → Monetization → RTDN → mismo topic

## Tests

```bash
node --test supabase/functions/play-billing-rtdn/logic_test.mjs \
  supabase/functions/play-billing-rtdn/pubsub_oidc_test.mjs
```

## Shared modules

Copia local de `logic.mjs`, `google_auth.ts`, `play_api.ts` (misma fuente que `validate-play-purchase/`).
Auth OIDC: `pubsub_oidc.mjs`. Procesamiento: `rtdn_process.mjs`.
