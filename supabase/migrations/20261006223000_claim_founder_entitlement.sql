-- Billing V1: claim Founder atómico (FOR UPDATE + insert + incremento).
-- Solo service_role / Edge Function. No expuesto a anon/authenticated.

CREATE OR REPLACE FUNCTION public.claim_founder_entitlement(
  p_user_id uuid,
  p_purchase_token text
)
RETURNS TABLE (
  ok boolean,
  claim_number integer,
  error_code text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quota public.founder_quota%ROWTYPE;
  v_by_user public.founder_claims%ROWTYPE;
  v_by_token public.founder_claims%ROWTYPE;
  v_next integer;
BEGIN
  IF p_user_id IS NULL OR p_purchase_token IS NULL OR length(trim(p_purchase_token)) = 0 THEN
    ok := false;
    claim_number := NULL;
    error_code := 'invalid_request';
    RETURN NEXT;
    RETURN;
  END IF;

  -- Idempotencia: mismo usuario + mismo token.
  SELECT *
  INTO v_by_user
  FROM public.founder_claims fc
  WHERE fc.user_id = p_user_id;

  IF FOUND THEN
    IF v_by_user.purchase_token = p_purchase_token THEN
      ok := true;
      claim_number := v_by_user.claim_number;
      error_code := NULL;
      RETURN NEXT;
      RETURN;
    END IF;
    ok := false;
    claim_number := NULL;
    error_code := 'founder_already_claimed';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT *
  INTO v_by_token
  FROM public.founder_claims fc
  WHERE fc.purchase_token = p_purchase_token;

  IF FOUND THEN
    ok := false;
    claim_number := NULL;
    error_code := 'founder_token_taken';
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT *
  INTO v_quota
  FROM public.founder_quota fq
  WHERE fq.id = 1
  FOR UPDATE;

  IF NOT FOUND THEN
    ok := false;
    claim_number := NULL;
    error_code := 'founder_quota_missing';
    RETURN NEXT;
    RETURN;
  END IF;

  IF v_quota.claimed_count >= v_quota.max_claims THEN
    ok := false;
    claim_number := NULL;
    error_code := 'founder_sold_out';
    RETURN NEXT;
    RETURN;
  END IF;

  v_next := v_quota.claimed_count + 1;

  UPDATE public.founder_quota
  SET claimed_count = v_next,
      updated_at = now()
  WHERE id = 1;

  INSERT INTO public.founder_claims (user_id, purchase_token, claim_number)
  VALUES (p_user_id, p_purchase_token, v_next);

  ok := true;
  claim_number := v_next;
  error_code := NULL;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.claim_founder_entitlement(uuid, text) IS
  'Claim Founder atómico (service_role). Idempotente por user+token; FOR UPDATE en founder_quota.';

REVOKE ALL ON FUNCTION public.claim_founder_entitlement(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_founder_entitlement(uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.claim_founder_entitlement(uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_founder_entitlement(uuid, text) TO service_role;
