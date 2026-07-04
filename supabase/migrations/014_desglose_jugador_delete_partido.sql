-- Desglose jugador (SECURITY DEFINER) + limpieza de saldos al borrar partido.

CREATE OR REPLACE FUNCTION public.get_mi_desglose_partido(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  SELECT row_to_json(t)
  INTO result
  FROM (
    SELECT
      pr.nombre,
      coalesce(sh.saldo_anterior, 0::numeric) AS saldo_anterior,
      dp.prorrateo_fijo,
      dp.total_variables,
      dp.total,
      dp.monto_pagado,
      dp.pagado,
      p.costo_cancha,
      p.costo_pelotas,
      coalesce(
        (
          SELECT json_object_agg(cv.concepto, ac.monto)
          FROM public.asignaciones_costo ac
          INNER JOIN public.costos_variables cv ON cv.id = ac.costo_variable_id
          WHERE cv.partido_id = p_partido_id
            AND ac.jugador_id = auth.uid()
        ),
        '{}'::json
      ) AS variables
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    LEFT JOIN public.profiles pr ON pr.id = dp.jugador_id
    LEFT JOIN LATERAL (
      SELECT sh2.saldo_anterior
      FROM public.saldos_historicos sh2
      WHERE sh2.partido_id = dp.partido_id
        AND sh2.jugador_id = dp.jugador_id
      ORDER BY sh2.fecha DESC, sh2.id DESC
      LIMIT 1
    ) sh ON true
    WHERE dp.partido_id = p_partido_id
      AND dp.jugador_id = auth.uid()
  ) t;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_mi_desglose_partido(bigint) TO authenticated;

CREATE OR REPLACE FUNCTION public.cleanup_saldos_on_partido_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.saldos_historicos WHERE partido_id = OLD.id;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_partido_delete_saldos ON public.partidos;

CREATE TRIGGER trg_partido_delete_saldos
  BEFORE DELETE ON public.partidos
  FOR EACH ROW
  EXECUTE FUNCTION public.cleanup_saldos_on_partido_delete();
