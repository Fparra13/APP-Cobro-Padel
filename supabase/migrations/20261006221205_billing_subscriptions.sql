-- Billing V1: entitlement comercial vigente por usuario.
-- UNIQUE(user_id): V1 permite un solo Pro comercial activo por cuenta.
-- Escrituras: solo service_role / Edge Function. Cliente: SELECT propio.

CREATE TABLE public.billing_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  purchase_token text,
  product_id text NOT NULL,
  base_plan text,
  status text NOT NULL,
  starts_at timestamptz,
  expires_at timestamptz,
  auto_renewing boolean,
  is_trial boolean NOT NULL DEFAULT false,
  is_founder boolean NOT NULL DEFAULT false,
  revoked_at timestamptz,
  last_verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT billing_subscriptions_user_id_key UNIQUE (user_id),
  CONSTRAINT billing_subscriptions_status_check CHECK (
    status = ANY (
      ARRAY[
        'active'::text,
        'trial'::text,
        'canceled'::text,
        'expired'::text,
        'revoked'::text,
        'pending'::text
      ]
    )
  )
);

CREATE INDEX billing_subscriptions_status_idx
  ON public.billing_subscriptions (status);

CREATE INDEX billing_subscriptions_expires_at_idx
  ON public.billing_subscriptions (expires_at);

COMMENT ON TABLE public.billing_subscriptions IS
  'Suscripción comercial actual por usuario. UNIQUE(user_id) = un Pro comercial a la vez.';

COMMENT ON COLUMN public.billing_subscriptions.status IS
  'active|trial|canceled|expired|revoked|pending. Entitlement válido: active/trial/canceled no revocado y no expirado.';

ALTER TABLE public.billing_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_subscriptions FORCE ROW LEVEL SECURITY;

CREATE POLICY billing_subscriptions_select_own
  ON public.billing_subscriptions
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON TABLE public.billing_subscriptions FROM anon;
REVOKE ALL ON TABLE public.billing_subscriptions FROM authenticated;
GRANT SELECT ON TABLE public.billing_subscriptions TO authenticated;
