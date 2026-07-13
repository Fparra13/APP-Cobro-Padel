-- Batch recalcular saldos tras cobro (evita N updates client-side bloqueados por
-- trg_profiles_protect_privileged). SECURITY DEFINER actualiza profiles.

CREATE OR REPLACE FUNCTION public.recalcular_saldos_jugadores(p_jugador_ids uuid[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_count integer := 0;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_jugador_ids IS NULL OR cardinality(p_jugador_ids) = 0 THEN
    RETURN 0;
  END IF;

  FOREACH v_id IN ARRAY p_jugador_ids LOOP
    IF v_id IS NULL THEN
      CONTINUE;
    END IF;
    PERFORM public.recalcular_saldo_jugador(v_id);
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.recalcular_saldos_jugadores(uuid[]) TO authenticated;
