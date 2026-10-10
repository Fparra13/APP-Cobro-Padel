-- =============================================================================
-- Gate Pro server-side: BEFORE INSERT on public.partidos (DEV-first).
-- =============================================================================
-- Regla comercial:
--   - CREAR partido nuevo → requiere Pro vigente o profiles.acceso_ilimitado
--   - EDITAR / cancelar / roster / RSVP / gastos → NO requiere Pro
--
-- NO modificar la policy ALL "Organizador gestiona sus partidos" WITH CHECK
-- (meter Pro ahí bloquearía UPDATE).
--
-- PROD: no aplicar hasta tener billing_subscriptions + get_my_billing_entitlement.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Helper: misma semántica de is_pro que get_my_billing_entitlement()
-- ---------------------------------------------------------------------------
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

  -- Clientes authenticated solo pueden consultar su propio entitlement.
  -- service_role / sesión SQL sin JWT pueden evaluar cualquier uid (tests/admin).
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

  -- Misma regla que get_my_billing_entitlement (subscription vigente).
  RETURN EXISTS (
    SELECT 1
    FROM public.billing_subscriptions bs
    WHERE bs.user_id = v_uid
      AND bs.revoked_at IS NULL
      AND bs.status IN ('active', 'trial', 'canceled')
      AND (bs.expires_at IS NULL OR bs.expires_at > now())
  );
END;
$$;

COMMENT ON FUNCTION public.user_has_pro_entitlement(uuid) IS
  'True si p_user_id tiene Pro: acceso_ilimitado o billing_subscriptions vigente '
  '(active|trial|canceled con expires_at futura/null y revoked_at null). '
  'Authenticated solo self; no escribe Billing.';

REVOKE ALL ON FUNCTION public.user_has_pro_entitlement(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.user_has_pro_entitlement(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.user_has_pro_entitlement(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.user_has_pro_entitlement(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 2) Alinear get_my_billing_entitlement.is_pro con el helper (evitar divergencia)
-- ---------------------------------------------------------------------------
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

  -- Fuente única de verdad booleana (misma lógica que el Gate INSERT).
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

REVOKE ALL ON FUNCTION public.get_my_billing_entitlement() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_billing_entitlement() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_my_billing_entitlement() TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) Trigger BEFORE INSERT — solo creación nueva
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_partido_pro_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Mismo patrón que purge_user_account_data (081).
  v_jwt_role text := nullif(
    current_setting('request.jwt.claim.role', true),
    ''
  );
BEGIN
  -- Bypass admin: JWT service_role, o sesión SQL sin JWT (postgres/migrations).
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF v_jwt_role IS NULL AND auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'pro_required'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.organizador_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'permission_denied'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.user_has_pro_entitlement(auth.uid()) THEN
    RAISE EXCEPTION 'pro_required'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_partido_pro_on_insert() IS
  'BEFORE INSERT partidos: exige auth + owner + is_organizer + Pro '
  '(o acceso_ilimitado). No aplica a UPDATE. Bypass service_role / SQL admin.';

REVOKE ALL ON FUNCTION public.enforce_partido_pro_on_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enforce_partido_pro_on_insert() FROM anon;
REVOKE ALL ON FUNCTION public.enforce_partido_pro_on_insert() FROM authenticated;

DROP TRIGGER IF EXISTS trg_partidos_enforce_pro_on_insert ON public.partidos;
CREATE TRIGGER trg_partidos_enforce_pro_on_insert
  BEFORE INSERT ON public.partidos
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_partido_pro_on_insert();
