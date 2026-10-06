-- Billing V1: cuota Founder (máx. 1000) + claims atómicos (preparación).
-- Singleton founder_quota (id=1). Claims: UNIQUE user, token y claim_number.
-- No booleano is_founder en profiles; Founder se deriva de founder_claims.

CREATE TABLE public.founder_quota (
  id integer PRIMARY KEY,
  max_claims integer NOT NULL,
  claimed_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT founder_quota_singleton_check CHECK (id = 1),
  CONSTRAINT founder_quota_max_claims_check CHECK (max_claims > 0),
  CONSTRAINT founder_quota_claimed_nonneg_check CHECK (claimed_count >= 0),
  CONSTRAINT founder_quota_claimed_lte_max_check CHECK (claimed_count <= max_claims)
);

COMMENT ON TABLE public.founder_quota IS
  'Singleton (id=1). Reservar claim con SELECT ... FOR UPDATE; max_claims=1000.';

INSERT INTO public.founder_quota (id, max_claims, claimed_count)
VALUES (1, 1000, 0);

CREATE TABLE public.founder_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  purchase_token text NOT NULL,
  claim_number integer NOT NULL,
  claimed_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT founder_claims_user_id_key UNIQUE (user_id),
  CONSTRAINT founder_claims_purchase_token_key UNIQUE (purchase_token),
  CONSTRAINT founder_claims_claim_number_key UNIQUE (claim_number),
  CONSTRAINT founder_claims_claim_number_range_check CHECK (
    claim_number >= 1 AND claim_number <= 1000
  )
);

CREATE INDEX founder_claims_claimed_at_idx
  ON public.founder_claims (claimed_at);

COMMENT ON TABLE public.founder_claims IS
  'Claim Founder efectivo. Impide multi-claim por usuario/token y claim_number duplicado.';

ALTER TABLE public.founder_quota ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_quota FORCE ROW LEVEL SECURITY;

ALTER TABLE public.founder_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.founder_claims FORCE ROW LEVEL SECURITY;

-- Cuota: no es dato propio del usuario; sin SELECT para authenticated/anon.
REVOKE ALL ON TABLE public.founder_quota FROM anon;
REVOKE ALL ON TABLE public.founder_quota FROM authenticated;

-- Claims: el usuario puede ver su propio claim; no escribir.
CREATE POLICY founder_claims_select_own
  ON public.founder_claims
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

REVOKE ALL ON TABLE public.founder_claims FROM anon;
REVOKE ALL ON TABLE public.founder_claims FROM authenticated;
GRANT SELECT ON TABLE public.founder_claims TO authenticated;
