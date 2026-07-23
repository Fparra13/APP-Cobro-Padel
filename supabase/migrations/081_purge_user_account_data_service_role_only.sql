-- =============================================================================
-- 081: C1 — purge_user_account_data solo service_role
-- =============================================================================
-- Contexto:
--   La función es SECURITY DEFINER (owner postgres) y borra datos de cuenta.
--   Migraciones 073/074 ya pretendían: REVOKE PUBLIC + GRANT solo service_role.
--   En producción los grants se reabrieron (anon + authenticated EXECUTE=true),
--   permitiendo wipe anónimo vía PostgREST.
--
-- Único caller legítimo (comprobado en código):
--   supabase/functions/delete-account/index.ts
--     → createClient(service_role).rpc('purge_user_account_data', { p_user_id })
--   Flutter solo invoca la Edge Function delete-account (no llama este RPC).
--
-- Estrategia (mínima, sin tocar otras funciones):
--   1) Mantener SECURITY DEFINER + cuerpo de DELETE (necesario vs RLS / FKs).
--   2) REVOKE EXECUTE de PUBLIC, anon y authenticated.
--   3) GRANT EXECUTE solo a service_role.
--   4) Defensa en profundidad: si hay JWT de API y el role no es service_role,
--      rechazar. Si no hay JWT (p.ej. SQL editor como postgres), no bloquear ops.
--
-- No toca C2/C3/C4 ni otras RPC.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.purge_user_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Rol del JWT de PostgREST/Edge, si existe (null fuera de la API).
  v_jwt_role text := nullif(
    current_setting('request.jwt.claim.role', true),
    ''
  );
BEGIN
  -- Defensa API: con JWT presente, solo service_role puede purgar.
  -- Sin JWT (sesión SQL admin), se permite para operaciones internas.
  IF v_jwt_role IS NOT NULL AND v_jwt_role IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'forbidden: purge_user_account_data requires service_role'
      USING ERRCODE = '42501';
  END IF;

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id required';
  END IF;

  DELETE FROM public.cobro_recordatorio
  WHERE organizador_id = p_user_id
     OR jugador_id = p_user_id;

  DELETE FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = p_user_id;

  DELETE FROM public.asignaciones_costo WHERE jugador_id = p_user_id;

  DELETE FROM public.convocatoria_jugadores WHERE jugador_id = p_user_id;

  IF to_regclass('public.comprobantes_pago') IS NOT NULL THEN
    DELETE FROM public.comprobantes_pago
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  IF to_regclass('public.organizador_jugadores') IS NOT NULL THEN
    DELETE FROM public.organizador_jugadores
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  -- Compat con typo histórico de migración 073.
  IF to_regclass('public.organizador_jugador') IS NOT NULL THEN
    DELETE FROM public.organizador_jugador
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  DELETE FROM public.saldos_historicos WHERE jugador_id = p_user_id;

  DELETE FROM public.detalles_partido WHERE jugador_id = p_user_id;

  DELETE FROM public.partidos WHERE organizador_id = p_user_id;

  IF to_regclass('public.recintos') IS NOT NULL THEN
    DELETE FROM public.recintos WHERE organizador_id = p_user_id;
  END IF;

  DELETE FROM public.profiles WHERE id = p_user_id;
END;
$$;

-- Quitar cualquier EXECUTE heredado / re-otorgado (C1 root cause).
REVOKE ALL ON FUNCTION public.purge_user_account_data(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_user_account_data(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.purge_user_account_data(uuid) FROM authenticated;

-- Único rol de aplicación autorizado a ejecutar el RPC.
GRANT EXECUTE ON FUNCTION public.purge_user_account_data(uuid) TO service_role;

COMMENT ON FUNCTION public.purge_user_account_data(uuid) IS
  'Service-role only (C1 hardened). Called by Edge Function delete-account before auth.admin.deleteUser. EXECUTE revoked from anon/authenticated.';

-- =============================================================================
-- DOWN / reversible (NO ejecutar salvo rollback consciente del riesgo C1):
--
-- CREATE OR REPLACE FUNCTION public.purge_user_account_data(p_user_id uuid)
-- ... (cuerpo sin el IF v_jwt_role; igual que 074) ...
--
-- REVOKE ALL ON FUNCTION public.purge_user_account_data(uuid) FROM PUBLIC;
-- GRANT EXECUTE ON FUNCTION public.purge_user_account_data(uuid) TO service_role;
-- -- Estado inseguro previo a este fix (NO restaurar en prod):
-- -- GRANT EXECUTE ON FUNCTION public.purge_user_account_data(uuid) TO anon;
-- -- GRANT EXECUTE ON FUNCTION public.purge_user_account_data(uuid) TO authenticated;
-- =============================================================================
