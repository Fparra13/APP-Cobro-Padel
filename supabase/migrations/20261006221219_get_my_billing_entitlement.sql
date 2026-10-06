-- Billing V1: entitlement del llamador vía auth.uid() (nunca user_id param).
-- Prioridad: profiles.acceso_ilimitado (staff) → billing_subscriptions válida → none.
-- acceso_ilimitado es bypass administrativo; no se modifica aquí.

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
      AND v_sub.status IN ('active', 'trial', 'canceled')
      AND (v_sub.expires_at IS NULL OR v_sub.expires_at > now());
  END IF;

  -- 1) Staff bypass administrativo
  IF v_staff THEN
    is_pro := true;
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

  -- 2) Suscripción comercial válida
  IF v_valid THEN
    is_pro := true;
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

  -- 3) Sin Pro (incluye expired/revoked/pending/canceled vencido/ausencia)
  is_pro := false;
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

COMMENT ON FUNCTION public.get_my_billing_entitlement() IS
  'Entitlement Pro del auth.uid(): staff (acceso_ilimitado) o subscription vigente. No acepta user_id.';

REVOKE ALL ON FUNCTION public.get_my_billing_entitlement() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_billing_entitlement() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_billing_entitlement() TO authenticated;
