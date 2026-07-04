-- Incluye deporte del partido en deudas pendientes del jugador.
CREATE OR REPLACE FUNCTION public.get_mis_deudas_pendientes()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN '[]'::json;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json)
  INTO result
  FROM (
    SELECT
      dp.*,
      p.fecha AS partido_fecha,
      p.recinto AS partido_recinto,
      p.estado AS partido_estado,
      p.sport_type AS partido_sport_type
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = auth.uid()
      AND dp.asistio = true
      AND dp.pagado = false
      AND (
        (dp.comprobante_url IS NOT NULL AND coalesce(dp.comprobante_validado, false) = false)
        OR greatest(
          public.saldo_anterior_vivo_partido(auth.uid(), dp.partido_id, p.fecha)
          + dp.total
          - dp.monto_pagado,
          0::numeric
        ) > 0.005
      )
    ORDER BY p.fecha DESC, dp.partido_id DESC
  ) t;

  RETURN result;
END;
$$;
