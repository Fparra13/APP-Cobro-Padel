-- Etapa 1 (QA): comprobantes de gastos visibles para participantes.
-- 1) Extiende get_mi_desglose_partido con URLs de cancha/pelotas y variables
--    enriquecidas [{concepto, monto, comprobante_url}].
-- 2) Storage SELECT path-exacto para participantes del partido.
-- No elimina datos. No cambia montos SSOT.

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
      p.comprobante_cancha_url,
      p.comprobante_pelotas_url,
      coalesce(
        (
          SELECT json_agg(
            json_build_object(
              'concepto', cv.concepto,
              'monto', ac.monto,
              'comprobante_url', cv.comprobante_url
            )
            ORDER BY cv.id ASC
          )
          FROM public.asignaciones_costo ac
          INNER JOIN public.costos_variables cv ON cv.id = ac.costo_variable_id
          WHERE cv.partido_id = p_partido_id
            AND ac.jugador_id = auth.uid()
        ),
        '[]'::json
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

COMMENT ON FUNCTION public.get_mi_desglose_partido(bigint) IS
  'Desglose del jugador autenticado para un partido; incluye URLs de comprobantes de gastos (cancha/pelotas/variables).';

GRANT EXECUTE ON FUNCTION public.get_mi_desglose_partido(bigint) TO authenticated;

-- Participantes: SELECT solo si el objeto coincide exactamente con un
-- comprobante de gasto registrado en ese partido (no lista carpetas).
DROP POLICY IF EXISTS "Participantes ven comprobantes de gastos del partido"
  ON storage.objects;

CREATE POLICY "Participantes ven comprobantes de gastos del partido"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'comprobantes'
    AND EXISTS (
      SELECT 1
      FROM public.detalles_partido dp
      INNER JOIN public.partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = auth.uid()
        AND (
          (
            p.comprobante_cancha_url IS NOT NULL
            AND length(trim(p.comprobante_cancha_url)) > 0
            AND p.comprobante_cancha_url = name
          )
          OR (
            p.comprobante_pelotas_url IS NOT NULL
            AND length(trim(p.comprobante_pelotas_url)) > 0
            AND p.comprobante_pelotas_url = name
          )
          OR EXISTS (
            SELECT 1
            FROM public.costos_variables cv
            WHERE cv.partido_id = p.id
              AND cv.comprobante_url IS NOT NULL
              AND length(trim(cv.comprobante_url)) > 0
              AND cv.comprobante_url = name
          )
        )
    )
  );
