# Play Billing setup (Kloovi Pro)

Checklist de product IDs, base plans y secretos para Google Play Billing + Edge Functions.  
**No** commitear JSON de service accounts ni Bearer secrets. **No** tocar PROD en setup inicial (solo DEV).

## Package

| Campo | Valor |
| --- | --- |
| Android package | `com.kloovi.app` |

## Product IDs (Play Console)

| Product ID | Uso | Base plan | Offer |
| --- | --- | --- | --- |
| `kloovi_pro_monthly` | Pro mensual (+ trial) | `monthly` | `trial-14d` (14 días free trial) |
| `kloovi_pro_founder_annual` | Founder anual | **`founder-annual-v2`** (compra) | (sin trial) |

Notas Founder:

- El cliente **solo compra** `founder-annual-v2`.
- El plan legacy `annual` (mal configurado como mensual) **no** se ofrece en la app; el backend aún lo acepta al revalidar compras antiguas.
- Precio UI: precio localizado de la oferta `founder-annual-v2` (no el del plan legacy).

Deben coincidir con `lib/core/billing/play_product_ids.dart` y `ALLOWED_PRODUCT_IDS` en `logic.mjs`.

## Edge Functions

| Función | JWT | Auth | Rol |
| --- | --- | --- | --- |
| `validate-play-purchase` | `verify_jwt = true` | Bearer user JWT | Validación cliente + ack + upsert entitlement |
| `play-billing-rtdn` | `verify_jwt = false` | Bearer `PLAY_BILLING_RTDN_SECRET` | RTDN Pub/Sub → re-verify Google → upsert |

Detalles:

- [validate-play-purchase/README.md](../supabase/functions/validate-play-purchase/README.md)
- [play-billing-rtdn/README.md](../supabase/functions/play-billing-rtdn/README.md)

## Secrets checklist (Supabase DEV)

Configurar con `supabase secrets set` **solo cuando se indique** (no en commits):

| Secret | Usado por | Notas |
| --- | --- | --- |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | `validate-play-purchase`, `play-billing-rtdn` | JSON completo de la SA con acceso a Play Developer API |
| `PLAY_BILLING_RTDN_SECRET` | `play-billing-rtdn` | Bearer para Pub/Sub push; ≥ 16 chars; rotar si se filtra |

Inyectados automáticamente por Supabase (no set manual):

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY` (validate)
- `SUPABASE_SERVICE_ROLE_KEY`

## Google Cloud / Play Console checklist

- [ ] Service Account creada y vinculada a Play Console (Users and permissions → API access)
- [ ] Play Developer API habilitada en el proyecto GCP
- [ ] Productos `kloovi_pro_monthly` y `kloovi_pro_founder_annual` activos (o en license testing)
- [ ] Base plan `monthly` + offer `trial-14d` en mensual
- [ ] Base plan `founder-annual-v2` activo en Founder (legacy `annual` puede quedar, no se compra)
- [ ] Topic Pub/Sub para RTDN
- [ ] Play Console → Monetization setup → RTDN apuntando al topic
- [ ] Push subscription → `POST .../functions/v1/play-billing-rtdn` con Bearer secret
- [ ] Secrets seteados en proyecto Supabase **DEV** (no PROD)

## Seguridad

- Nunca loguear `purchase_token`, JWT, Bearer RTDN ni el JSON de la service account.
- RTDN no otorga Pro sin fila previa en `billing_purchases` (token → `user_id`).
- Founder cap / claim solo en `validate-play-purchase` (RPC `claim_founder_entitlement`).

## Tests locales

```bash
node --test supabase/functions/validate-play-purchase/logic_test.mjs
flutter test test/play_purchase_validation_fase8c4_test.dart \
  test/subscription_founder_access_test.dart \
  test/play_billing_client_ack_test.dart
dart analyze lib/core/subscription_service.dart lib/core/billing \
  lib/core/feature_gate.dart lib/widgets/paywall_sheet.dart
```
