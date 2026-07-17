-- Actualiza eliminar_partido_completo al modelo de saldo por organizador
-- (recalcular_saldo_cuenta). Incluye al propio organizador (cuenta dual).
-- Nota: 064/070 refuerzan self + reparación de cadena; no reintroducir skip self.

CREATE OR REPLACE FUNCTION public.eliminar_partido_completo(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := auth.uid();
  jugador_ids uuid[];
  jid uuid;
BEGIN
  IF NOT public.is_organizer() OR NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = p_partido_id;

  DELETE FROM public.saldos_historicos WHERE partido_id = p_partido_id;
  DELETE FROM public.partidos WHERE id = p_partido_id;

  IF jugador_ids IS NOT NULL AND v_org IS NOT NULL THEN
    FOREACH jid IN ARRAY jugador_ids LOOP
      PERFORM public.recalcular_saldo_cuenta(v_org, jid);
    END LOOP;
  END IF;

  RETURN json_build_object('jugadores', jugador_ids);
END;
$$;
