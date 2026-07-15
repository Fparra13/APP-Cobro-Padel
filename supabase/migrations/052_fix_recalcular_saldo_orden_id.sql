-- Corrige saldo a favor que no se descontaba al registrar encuentros.
--
-- Causa: saldos_historicos del cargo usaba fecha del partido (pasada) cuando
-- monto_pagado=0 (cubierto con crédito). recalcular_saldo_jugador tomaba
-- ORDER BY fecha DESC y volvía al abono antiguo (crédito intacto).
--
-- Fix: el SSOT de "último movimiento" es el id de inserción; además el
-- cliente debe grabar fecha = ahora al registrar el cobro.

CREATE OR REPLACE FUNCTION public.recalcular_saldo_jugador(p_jugador_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nuevo numeric := 0;
BEGIN
  IF p_jugador_id IS NULL THEN
    RETURN 0;
  END IF;

  PERFORM public.assert_puede_gestionar_cobros_jugador(p_jugador_id);

  -- Orden por id (inserción), no por fecha del partido: un cargo cubierto
  -- con saldo a favor puede tener fecha de encuentro anterior al abono.
  SELECT sh.saldo_nuevo
  INTO nuevo
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
  ORDER BY sh.id DESC
  LIMIT 1;

  nuevo := coalesce(nuevo, 0);

  UPDATE public.profiles
  SET saldo_acumulado = nuevo
  WHERE id = p_jugador_id;

  RETURN nuevo;
END;
$$;

GRANT EXECUTE ON FUNCTION public.recalcular_saldo_jugador(uuid) TO authenticated;

-- Repara perfiles ya desalineados (migración corre como owner; sin auth.uid).
UPDATE public.profiles p
SET saldo_acumulado = coalesce(
  (
    SELECT sh.saldo_nuevo
    FROM public.saldos_historicos sh
    WHERE sh.jugador_id = p.id
    ORDER BY sh.id DESC
    LIMIT 1
  ),
  0
)
WHERE EXISTS (
  SELECT 1
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p.id
);

-- No reabrir cobros ya cerrados (pagado=true, p.ej. cubiertos con crédito)
-- aunque el snapshot falte y coalesce a 0 invente pendiente bruto.
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
        OR (
          coalesce(dp.pagado, false) = false
          AND greatest(
            coalesce((
              SELECT sh.saldo_anterior
              FROM public.saldos_historicos sh
              WHERE sh.jugador_id = dp.jugador_id
                AND sh.partido_id = dp.partido_id
                AND sh.cargo_partido > 0.005
              ORDER BY sh.id ASC
              LIMIT 1
            ), 0::numeric)
            + dp.total
            - dp.monto_pagado,
            0::numeric
          ) > 0.005
        )
      )
    ORDER BY p.fecha DESC, dp.partido_id DESC
  ) t;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_mis_deudas_pendientes() TO authenticated;
