-- Billing: estados grace / on_hold alineados con Google Play Subscriptions v2.
-- Solo ampliar CHECK + reglas de entitlement. No toca datos de usuarios.
-- Destino previsto: DEV (qduybfdxpyfjzosakdlq).

ALTER TABLE public.billing_subscriptions
  DROP CONSTRAINT IF EXISTS billing_subscriptions_status_check;

ALTER TABLE public.billing_subscriptions
  ADD CONSTRAINT billing_subscriptions_status_check CHECK (
    status = ANY (
      ARRAY[
        'active'::text,
        'trial'::text,
        'canceled'::text,
        'expired'::text,
        'revoked'::text,
        'pending'::text,
        'grace'::text,
        'on_hold'::text
      ]
    )
  );

COMMENT ON COLUMN public.billing_subscriptions.status IS
  'active|trial|canceled|expired|revoked|pending|grace|on_hold. '
  'Pro comercial válido: active/trial/canceled/grace, revoked_at null, expires_at futura/null.';

-- Pro comercial incluye período de gracia de pago (Google IN_GRACE_PERIOD).
CREATE OR REPLACE FUNCTION public.user_has_pro_entitlement(
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := p_user_id;
  v_jwt_role text := nullif(
    current_setting('request.jwt.claim.role', true),
    ''
  );
  v_staff boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    RETURN false;
  END IF;

  IF v_jwt_role IS NOT NULL AND v_jwt_role IS DISTINCT FROM 'service_role' THEN
    IF auth.uid() IS NULL OR v_uid IS DISTINCT FROM auth.uid() THEN
      RETURN false;
    END IF;
  END IF;

  SELECT coalesce(p.acceso_ilimitado, false)
  INTO v_staff
  FROM public.profiles p
  WHERE p.id = v_uid;

  IF coalesce(v_staff, false) THEN
    RETURN true;
  END IF;

  RETURN EXISTS (
    SELECT 1
    FROM public.billing_subscriptions bs
    WHERE bs.user_id = v_uid
      AND bs.revoked_at IS NULL
      AND bs.status IN ('active', 'trial', 'canceled', 'grace')
      AND (bs.expires_at IS NULL OR bs.expires_at > now())
  );
END;
$$;

COMMENT ON FUNCTION public.user_has_pro_entitlement(uuid) IS
  'True si p_user_id tiene Pro: acceso_ilimitado o billing_subscriptions vigente '
  '(active|trial|canceled|grace con expires_at futura/null y revoked_at null). '
  'Authenticated solo self; no escribe Billing.';

-- Alinear get_my_billing_entitlement con la misma regla (v_valid incluye grace).
CREATE OR REPLACE FUNCTION public.get_my_billing_entitlement()
RETURNS TABLE (
  is_pro boolean,
  source text,
  status text,
  product_id text,
  expires_at timestamptz,
  is_trial boolean,
  is_founder boolean,
  auto_renewing boolean,
  last_verified_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_staff boolean := false;
  v_sub public.billing_subscriptions%ROWTYPE;
  v_has_sub boolean := false;
  v_valid boolean := false;
  v_founder boolean := false;
BEGIN
  IF v_uid IS NULL THEN
    is_pro := false;
    source := 'none';
    status := NULL;
    product_id := NULL;
    expires_at := NULL;
    is_trial := false;
    is_founder := false;
    auto_renewing := NULL;
    last_verified_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT coalesce(p.acceso_ilimitado, false)
  INTO v_staff
  FROM public.profiles p
  WHERE p.id = v_uid;

  IF NOT FOUND THEN
    v_staff := false;
  END IF;

  v_founder := EXISTS (
    SELECT 1
    FROM public.founder_claims fc
    WHERE fc.user_id = v_uid
  );

  SELECT *
  INTO v_sub
  FROM public.billing_subscriptions bs
  WHERE bs.user_id = v_uid;

  v_has_sub := FOUND;

  IF v_has_sub THEN
    v_valid :=
      v_sub.revoked_at IS NULL
      AND v_sub.status IN ('active', 'trial', 'canceled', 'grace')
      AND (v_sub.expires_at IS NULL OR v_sub.expires_at > now());
  END IF;

  is_pro := public.user_has_pro_entitlement(v_uid);

  IF v_staff THEN
    source := 'staff';
    status := NULL;
    product_id := NULL;
    expires_at := NULL;
    is_trial := false;
    is_founder := v_founder;
    auto_renewing := NULL;
    last_verified_at := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_valid THEN
    source := 'subscription';
    status := v_sub.status;
    product_id := v_sub.product_id;
    expires_at := v_sub.expires_at;
    is_trial := v_sub.is_trial;
    is_founder := v_founder OR v_sub.is_founder;
    auto_renewing := v_sub.auto_renewing;
    last_verified_at := v_sub.last_verified_at;
    RETURN NEXT;
    RETURN;
  END IF;

  source := 'none';
  IF v_has_sub THEN
    status := v_sub.status;
    product_id := v_sub.product_id;
    expires_at := v_sub.expires_at;
    is_trial := v_sub.is_trial;
    is_founder := v_founder OR v_sub.is_founder;
    auto_renewing := v_sub.auto_renewing;
    last_verified_at := v_sub.last_verified_at;
  ELSE
    status := NULL;
    product_id := NULL;
    expires_at := NULL;
    is_trial := false;
    is_founder := v_founder;
    auto_renewing := NULL;
    last_verified_at := NULL;
  END IF;

  RETURN NEXT;
END;
$$;
