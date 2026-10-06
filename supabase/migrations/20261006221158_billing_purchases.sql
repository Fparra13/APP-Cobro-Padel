-- Billing V1: ledger histórico de compras/tokens de Google Play.
-- purchase_token UNIQUE: idempotencia y vínculo 1:1 con el token de Play.
-- Escrituras: solo service_role / Edge Function. Cliente: SELECT propio.

CREATE TABLE public.billing_purchases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  purchase_token text NOT NULL,
  product_id text NOT NULL,
  purchase_state text,
  order_id text,
  package_name text,
  purchase_time timestamptz,
  expires_at timestamptz,
  auto_renewing boolean,
  acknowledged boolean NOT NULL DEFAULT false,
  obfuscated_account_id text,
  raw_payload jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_verified_at timestamptz,
  CONSTRAINT billing_purchases_purchase_token_key UNIQUE (purchase_token)
);

CREATE INDEX billing_purchases_user_id_idx
  ON public.billing_purchases (user_id);

CREATE INDEX billing_purchases_product_id_idx
  ON public.billing_purchases (product_id);

COMMENT ON TABLE public.billing_purchases IS
  'Ledger de purchase_token de Google Play. Fuente de verificación; no es el entitlement vigente.';

COMMENT ON COLUMN public.billing_purchases.purchase_token IS
  'Token sensible de Play; UNIQUE para idempotencia. No exponer en logs de cliente.';

ALTER TABLE public.billing_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_purchases FORCE ROW LEVEL SECURITY;

-- Cliente autenticado: solo lectura de sus propios registros.
CREATE POLICY billing_purchases_select_own
  ON public.billing_purchases
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Sin policies INSERT/UPDATE/DELETE para authenticated/anon.
REVOKE ALL ON TABLE public.billing_purchases FROM anon;
REVOKE ALL ON TABLE public.billing_purchases FROM authenticated;
GRANT SELECT ON TABLE public.billing_purchases TO authenticated;
-- service_role bypassa RLS; mantiene privilegios por defecto del rol.
