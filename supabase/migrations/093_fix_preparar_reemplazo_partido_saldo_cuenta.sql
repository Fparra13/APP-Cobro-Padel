-- Fix: preparar_reemplazo_partido usa recalcular_saldo_cuenta (modelo post-056)
-- en lugar de recalcular_saldo_jugador (stub deprecated). Resto de la lógica
-- respecto a 045 se mantiene intacta.

CREATE OR REPLACE FUNCTION public.preparar_reemplazo_partido(p_partido_id bigint)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jugador_ids uuid[];
  jid uuid;
BEGIN
  IF NOT public.is_organizer() OR NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.partidos WHERE id = p_partido_id) THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = p_partido_id;

  DELETE FROM public.saldos_historicos WHERE partido_id = p_partido_id;
  DELETE FROM public.detalles_partido WHERE partido_id = p_partido_id;
  DELETE FROM public.costos_variables WHERE partido_id = p_partido_id;

  IF jugador_ids IS NOT NULL THEN
    FOREACH jid IN ARRAY jugador_ids LOOP
      INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
      VALUES (auth.uid(), jid)
      ON CONFLICT DO NOTHING;
      PERFORM public.recalcular_saldo_cuenta(auth.uid(), jid);
    END LOOP;
  END IF;

  RETURN jugador_ids;
END;
$$;
