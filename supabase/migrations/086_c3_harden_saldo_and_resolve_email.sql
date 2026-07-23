-- =============================================================================
-- 086: C3 — harden get_saldo_cuenta + resolve_profile_id_for_email
-- =============================================================================
-- Evidencia previa (live):
--   get_saldo_cuenta: SECURITY DEFINER, sin auth. Anon REST → HTTP 200 + saldo
--     real (ej. 18500.00) para cualquier (organizador_id, jugador_id).
--   resolve_profile_id_for_email: SECURITY DEFINER, sin auth. Con email válido
--     devuelve UUID (probe SQL: anon_equivalent_resolve_leaks_uuid=true).
--   EXECUTE ambas: anon=true, authenticated=true, PUBLIC=true, service_role=true.
--
-- Callers legítimos:
--   get_saldo_cuenta:
--     - Flutter: NO (lee organizador_jugadores vía RLS)
--     - Edge / otras RPC / triggers: NO
--   resolve_profile_id_for_email:
--     - Flutter:
--         lib/repositories/convocatoria_repository_remote.dart
--           → _resolveJugadorIdsBatch()
--         lib/repositories/partido_repository_remote.dart
--           → _resolveJugadorIdForCobro()
--       Flujo: organizador ya ve email de un perfil de su roster y resuelve
--       al perfil con login (mismo email).
--     - Edge / nested SQL: NO
--
-- Estrategia:
--   1) Mantener SECURITY DEFINER (bypass RLS necesario para resolve auth.users /
--      lectura puntual de oj).
--   2) get_saldo_cuenta: exigir JWT autenticado y
--      auth.uid() ∈ {p_organizador_id, p_jugador_id}; REVOKE anon/PUBLIC.
--   3) resolve_profile_id_for_email: exigir JWT; solo resolver si el caller
--      tiene scope sobre ese email (perfil propio O jugador en su roster oj).
--      REVOKE anon/PUBLIC. authenticated conserva EXECUTE (Flutter).
--   4) No toca C1 ni C2 ni otras RPC.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_saldo_cuenta(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_jwt_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
  v_uid uuid := coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
BEGIN
  -- C3: service_role OK; sesión SQL sin JWT OK; resto solo participante del vínculo.
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL
        AND (v_uid = p_organizador_id OR v_uid = p_jugador_id) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'forbidden: get_saldo_cuenta'
      USING ERRCODE = '42501';
  END IF;

  RETURN coalesce(
    (
      SELECT oj.saldo_acumulado
      FROM public.organizador_jugadores oj
      WHERE oj.organizador_id = p_organizador_id
        AND oj.jugador_id = p_jugador_id
    ),
    0::numeric
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_saldo_cuenta(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_saldo_cuenta(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_saldo_cuenta(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_saldo_cuenta(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.get_saldo_cuenta(uuid, uuid) IS
  'C3 hardened. DEFINER; EXECUTE authenticated+service_role; solo org/jugador del vínculo.';

CREATE OR REPLACE FUNCTION public.resolve_profile_id_for_email(p_email text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  normalized text;
  found_id uuid;
  v_jwt_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
  v_uid uuid := coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
  v_scoped boolean;
BEGIN
  -- C3: service_role / SQL admin OK; JWT requiere scope sobre el email.
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NULL THEN
    RAISE EXCEPTION 'forbidden: resolve_profile_id_for_email'
      USING ERRCODE = '42501';
  END IF;

  normalized := lower(trim(coalesce(p_email, '')));
  IF normalized = '' THEN
    RETURN NULL;
  END IF;

  -- Scope: propio email O algún perfil del roster del caller con ese contacto.
  IF v_jwt_role IS DISTINCT FROM 'service_role'
     AND NOT (v_jwt_role IS NULL AND v_uid IS NULL) THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE lower(trim(coalesce(p.email, p.telefono, ''))) = normalized
        AND (
          p.id = v_uid
          OR EXISTS (
            SELECT 1
            FROM public.organizador_jugadores oj
            WHERE oj.organizador_id = v_uid
              AND oj.jugador_id = p.id
          )
        )
    ) INTO v_scoped;

    IF NOT coalesce(v_scoped, false) THEN
      -- No enumerar: misma respuesta que "no existe".
      RETURN NULL;
    END IF;
  END IF;

  SELECT p.id INTO found_id
  FROM public.profiles p
  INNER JOIN auth.users u ON u.id = p.id
  WHERE lower(trim(coalesce(p.email, p.telefono, ''))) = normalized
  LIMIT 1;

  IF found_id IS NOT NULL THEN
    RETURN found_id;
  END IF;

  SELECT p.id INTO found_id
  FROM public.profiles p
  WHERE lower(trim(coalesce(p.email, p.telefono, ''))) = normalized
  ORDER BY p.created_at ASC
  LIMIT 1;

  RETURN found_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_profile_id_for_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.resolve_profile_id_for_email(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.resolve_profile_id_for_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_profile_id_for_email(text) TO service_role;

COMMENT ON FUNCTION public.resolve_profile_id_for_email(text) IS
  'C3 hardened. Solo authenticated con scope (propio o roster); anon revoked.';

-- =============================================================================
-- DOWN (rollback consciente — reabre C3):
--   Restaurar cuerpos 010/056 sin guards y GRANT EXECUTE TO anon, authenticated.
-- =============================================================================
