-- Cleanup before Auth user deletion (FK RESTRICT + organizer-owned rows).
-- Called by Edge Function delete-account with service role.

CREATE OR REPLACE FUNCTION public.purge_user_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id required';
  END IF;

  -- Cost assignments
  DELETE FROM public.asignaciones_costo WHERE jugador_id = p_user_id;

  -- Roster / invites
  DELETE FROM public.convocatoria_jugadores WHERE jugador_id = p_user_id;

  -- Receipts history (if present)
  IF to_regclass('public.comprobantes_pago') IS NOT NULL THEN
    DELETE FROM public.comprobantes_pago
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  -- Per-organizer roster / balances
  IF to_regclass('public.organizador_jugador') IS NOT NULL THEN
    DELETE FROM public.organizador_jugador
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  -- Historical balances
  DELETE FROM public.saldos_historicos WHERE jugador_id = p_user_id;

  -- Match line items (RESTRICT on profiles)
  DELETE FROM public.detalles_partido WHERE jugador_id = p_user_id;

  -- Matches this user organized (cascade to remaining child rows)
  DELETE FROM public.partidos WHERE organizador_id = p_user_id;

  -- Venues
  IF to_regclass('public.recintos') IS NOT NULL THEN
    DELETE FROM public.recintos WHERE organizador_id = p_user_id;
  END IF;

  -- Profile row (auth.users deleted next by Edge Function)
  DELETE FROM public.profiles WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_user_account_data(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_user_account_data(uuid) TO service_role;

COMMENT ON FUNCTION public.purge_user_account_data(uuid) IS
  'Service-role only. Purges app data before auth.admin.deleteUser for Play account deletion.';
