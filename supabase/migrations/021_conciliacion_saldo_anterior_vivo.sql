-- Conciliación: deuda anterior viva (no snapshot congelado al crear partido).

CREATE OR REPLACE FUNCTION public.saldo_anterior_vivo_partido(
  p_jugador_id uuid,
  p_partido_id bigint,
  p_fecha_partido timestamptz
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    sum(greatest(dp.total - dp.monto_pagado, 0::numeric)),
    0::numeric
  )
  FROM public.detalles_partido dp
  INNER JOIN public.partidos p ON p.id = dp.partido_id
  WHERE dp.jugador_id = p_jugador_id
    AND dp.asistio = true
    AND dp.pagado = false
    AND dp.partido_id <> p_partido_id
    AND (
      p.fecha < p_fecha_partido
      OR (p.fecha = p_fecha_partido AND dp.partido_id < p_partido_id)
    );
$$;

GRANT EXECUTE ON FUNCTION public.saldo_anterior_vivo_partido(uuid, bigint, timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_mi_desglose_partido(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
  v_fecha timestamptz;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  SELECT p.fecha INTO v_fecha
  FROM public.partidos p
  WHERE p.id = p_partido_id;

  IF v_fecha IS NULL THEN
    v_fecha := now();
  END IF;

  SELECT row_to_json(t)
  INTO result
  FROM (
    SELECT
      pr.nombre,
      public.saldo_anterior_vivo_partido(auth.uid(), p_partido_id, v_fecha) AS saldo_anterior,
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
    WHERE dp.partido_id = p_partido_id
      AND dp.jugador_id = auth.uid()
  ) t;

  RETURN result;
END;
$$;

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
      p.estado AS partido_estado
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
