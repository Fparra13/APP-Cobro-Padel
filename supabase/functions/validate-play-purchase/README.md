# validate-play-purchase

Edge Function (Kloovi DEV) that validates Google Play subscription purchases and upserts Billing entitlement.

## Secret requerido (configurar manualmente en DEV)

```text
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
```

Valor: JSON completo de la Service Account de Google Play (`kloovi-play-api@...`).

**No** commitear el JSON. Configurar en un paso posterior con:

```bash
# Solo cuando se indique explícitamente (no en esta fase):
supabase secrets set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON='...'
```

Supabase ya inyecta `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Endpoint

`POST /functions/v1/validate-play-purchase`  
`Authorization: Bearer <user JWT>`

Body:

```json
{ "purchase_token": "...", "product_id": "kloovi_pro_monthly" }
```

## Setup completo (product IDs + secretos)

Ver [docs/PLAY_BILLING_SETUP.md](../../../docs/PLAY_BILLING_SETUP.md).

## Tests de lógica pura

```bash
node --test supabase/functions/validate-play-purchase/logic_test.mjs
```
