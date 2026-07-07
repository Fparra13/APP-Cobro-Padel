-- RPC de cobros alineadas al SSOT: snapshot al registrar (cargo_partido > 0).

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
      coalesce((
        SELECT sh.saldo_anterior
        FROM public.saldos_historicos sh
        WHERE sh.jugador_id = auth.uid()
          AND sh.partido_id = p_partido_id
          AND sh.cargo_partido > 0.005
        ORDER BY sh.fecha ASC, sh.id ASC
        LIMIT 1
      ), 0::numeric) AS saldo_anterior,
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
      p.estado AS partido_estado,
      p.sport_type AS partido_sport_type
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = auth.uid()
      AND dp.asistio = true
      AND (
        (
          dp.comprobante_url IS NOT NULL
          AND coalesce(dp.comprobante_validado, false) = false
        )
        OR greatest(
          coalesce((
            SELECT sh.saldo_anterior
            FROM public.saldos_historicos sh
            WHERE sh.jugador_id = dp.jugador_id
              AND sh.partido_id = dp.partido_id
              AND sh.cargo_partido > 0.005
            ORDER BY sh.fecha ASC, sh.id ASC
            LIMIT 1
          ), 0::numeric)
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
