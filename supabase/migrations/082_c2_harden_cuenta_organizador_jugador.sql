-- =============================================================================
-- 082: C2 — harden asegurar / reabrir / bloquear cuenta organizador-jugador
-- =============================================================================
-- Evidencia previa (live):
--   - Las tres son SECURITY DEFINER sin auth.uid()/ownership.
--   - EXECUTE: anon=true, authenticated=true, PUBLIC=true, service_role=true.
--   - Anon podía invocar bloquear (HTTP 204) y asegurar/reabrir (llegaban al INSERT).
--
-- Callers legítimos:
--   asegurar_cuenta_organizador_jugador:
--     - Interno: reabrir_cuenta_*, asegurar_fila_saldo_cuenta (DEFINER nested)
--     - Flutter: NO llama directo
--     - Edge: NO
--   reabrir_cuenta_organizador_jugador:
--     - Interno: unirse_con_codigo_grupo(v_org, auth.uid()),
--                vincular_jugador_organizador(v_org, p_jugador_id)
--     - Flutter: NO directo (usa unirse / vincular)
--   bloquear_salida_cuenta_si_necesario:
--     - Flutter: lib/repositories/jugador_repository_remote.dart → delete()
--       rpc(p_organizador_id: currentUserId, p_jugador_id: id)
--     - Edge/triggers: NO
--
-- Estrategia:
--   1) Mantener SECURITY DEFINER (escriben organizador_jugadores bypasseando RLS).
--   2) Exigir: service_role JWT, O auth.uid() ∈ {organizador_id, jugador_id},
--      O sesión SQL sin JWT (ops). Rechazar anon / JWT sin ownership.
--   3) REVOKE EXECUTE de PUBLIC + anon en las tres.
--   4) REVOKE authenticated en asegurar y reabrir (solo nested DEFINER / service_role).
--   5) GRANT authenticated SOLO en bloquear (Flutter lo invoca directo).
--   6) No toca C1 ni otras RPC (unirse/vincular/recalcular sin cambios).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- asegurar_cuenta_organizador_jugador
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.asegurar_cuenta_organizador_jugador(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jwt_role text := nullif(current_setting('request.jwt.claim.role', true), '');
  v_uid uuid := auth.uid();
BEGIN
  -- Autorización (C2): service_role, participante del vínculo, o SQL sin JWT.
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL; -- ok
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL; -- ok: sesión admin SQL
  ELSIF v_uid IS NOT NULL
        AND (v_uid = p_organizador_id OR v_uid = p_jugador_id) THEN
    NULL; -- ok: organizador o jugador del vínculo
  ELSE
    RAISE EXCEPTION 'forbidden: asegurar_cuenta_organizador_jugador'
      USING ERRCODE = '42501';
  END IF;

  IF p_organizador_id IS NULL OR p_jugador_id IS NULL THEN
    RAISE EXCEPTION 'cuenta_invalida' USING ERRCODE = 'P0001';
  END IF;
  IF p_organizador_id = p_jugador_id THEN
    RAISE EXCEPTION 'No puedes vincularte a tu propio grupo' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.organizador_jugadores (
    organizador_id, jugador_id, saldo_acumulado, activo, left_at
  ) VALUES (
    p_organizador_id, p_jugador_id, 0, true, NULL
  )
  ON CONFLICT (organizador_id, jugador_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) IS
  'C2 hardened. DEFINER helper; EXECUTE no expuesto a anon/authenticated. Ownership o service_role.';

-- ---------------------------------------------------------------------------
-- reabrir_cuenta_organizador_jugador
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reabrir_cuenta_organizador_jugador(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jwt_role text := nullif(current_setting('request.jwt.claim.role', true), '');
  v_uid uuid := auth.uid();
BEGIN
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL
        AND (v_uid = p_organizador_id OR v_uid = p_jugador_id) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'forbidden: reabrir_cuenta_organizador_jugador'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.asegurar_cuenta_organizador_jugador(p_organizador_id, p_jugador_id);
  UPDATE public.organizador_jugadores
  SET activo = true, left_at = NULL
  WHERE organizador_id = p_organizador_id AND jugador_id = p_jugador_id;
END;
$$;

REVOKE ALL ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) IS
  'C2 hardened. Usada por unirse_con_codigo_grupo / vincular_jugador_organizador (nested). No EXECUTE para anon/authenticated.';

-- ---------------------------------------------------------------------------
-- bloquear_salida_cuenta_si_necesario
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bloquear_salida_cuenta_si_necesario(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jwt_role text := nullif(current_setting('request.jwt.claim.role', true), '');
  v_uid uuid := auth.uid();
BEGIN
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL
        AND (v_uid = p_organizador_id OR v_uid = p_jugador_id) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'forbidden: bloquear_salida_cuenta_si_necesario'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.organizador_jugadores
  SET activo = false, left_at = now()
  WHERE organizador_id = p_organizador_id
    AND jugador_id = p_jugador_id
    AND activo = true;
END;
$$;

REVOKE ALL ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) FROM anon;
-- Flutter (organizador) llama este RPC directo → authenticated mantiene EXECUTE.
GRANT EXECUTE ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) IS
  'C2 hardened. Soft-leave roster. EXECUTE authenticated + ownership (org o jugador). Anon revoked.';

-- =============================================================================
-- DOWN (rollback consciente — reabre superficie C2; no usar en prod):
-- Restaurar cuerpos 056 sin guards y:
--   GRANT EXECUTE ... TO authenticated;  -- (+ anon si se replica estado previo inseguro)
-- =============================================================================
