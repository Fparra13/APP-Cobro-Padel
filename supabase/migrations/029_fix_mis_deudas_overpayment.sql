-- Mis deudas: listar por pendiente del partido (no deuda encadenada).
-- Reconciliar: aplicar abono virtual cuando sum(impagos) > saldo_acumulado.

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
        (
          dp.comprobante_url IS NOT NULL
          AND coalesce(dp.comprobante_validado, false) = false
        )
        OR greatest(dp.total - dp.monto_pagado, 0::numeric) > 0.005
      )
    ORDER BY p.fecha DESC, dp.partido_id DESC
  ) t;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.aplicar_abono_virtual_detalles(
  p_jugador_id uuid,
  p_monto numeric,
  p_fecha timestamptz DEFAULT now()
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  restante numeric;
  pendiente numeric;
  aplicar numeric;
  nuevo_monto numeric;
  cubierto boolean;
  filas integer := 0;
BEGIN
  IF p_jugador_id IS NULL OR coalesce(p_monto, 0) <= 0.005 THEN
    RETURN 0;
  END IF;

  restante := round(p_monto::numeric, 2);

  FOR r IN
    SELECT
      dp.id,
      dp.total,
      dp.monto_pagado
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = p_jugador_id
      AND dp.asistio = true
      AND dp.pagado = false
    ORDER BY p.fecha ASC, dp.partido_id ASC
  LOOP
    EXIT WHEN restante <= 0.005;

    pendiente := round(greatest(r.total - r.monto_pagado, 0::numeric), 2);
    IF pendiente <= 0.005 THEN
      UPDATE public.detalles_partido
      SET
        pagado = true,
        fecha_pago = coalesce(fecha_pago, p_fecha),
        comprobante_validado = coalesce(comprobante_validado, true),
        comprobante_url = null,
        monto_pago_declarado = null,
        pago_es_abono = null
      WHERE id = r.id;
      filas := filas + 1;
      CONTINUE;
    END IF;

    aplicar := CASE
      WHEN restante >= pendiente THEN pendiente
      ELSE restante
    END;
    nuevo_monto := round(r.monto_pagado + aplicar, 2);
    cubierto := nuevo_monto >= r.total - 0.005;

    UPDATE public.detalles_partido
    SET
      monto_pagado = nuevo_monto,
      pagado = cubierto,
      fecha_pago = CASE WHEN cubierto THEN coalesce(fecha_pago, p_fecha) ELSE fecha_pago END,
      comprobante_validado = CASE WHEN cubierto THEN coalesce(comprobante_validado, true) ELSE comprobante_validado END,
      comprobante_url = CASE WHEN cubierto THEN null ELSE comprobante_url END,
      monto_pago_declarado = CASE WHEN cubierto THEN null ELSE monto_pago_declarado END,
      pago_es_abono = CASE WHEN cubierto THEN null ELSE pago_es_abono END
    WHERE id = r.id;

    restante := round(restante - aplicar, 2);
    filas := filas + 1;
  END LOOP;

  RETURN filas;
END;
$$;

CREATE OR REPLACE FUNCTION public.reconciliar_detalles_jugador(p_jugador_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  saldo_actual numeric;
  saldo_inicial numeric;
  sum_pendiente numeric;
  diff numeric;
  r record;
  favor numeric;
  neto numeric;
  pend numeric;
  detalles_cerrados integer := 0;
  virtual_aplicados integer := 0;
BEGIN
  IF p_jugador_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'jugador nulo');
  END IF;

  SELECT coalesce(p.saldo_acumulado, 0)
  INTO saldo_actual
  FROM public.profiles p
  WHERE p.id = p_jugador_id;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'jugador no encontrado');
  END IF;

  saldo_inicial := saldo_actual;

  IF saldo_actual <= 0 THEN
    FOR r IN
      SELECT
        dp.id,
        dp.total,
        dp.monto_pagado
      FROM public.detalles_partido dp
      INNER JOIN public.partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = p_jugador_id
        AND dp.asistio = true
        AND dp.pagado = false
      ORDER BY p.fecha ASC, dp.partido_id ASC
    LOOP
      favor := CASE
        WHEN saldo_actual >= 0 THEN 0
        ELSE least(-saldo_actual, r.total)
      END;
      neto := greatest(r.total - favor, 0);
      pend := greatest(neto - r.monto_pagado, 0);

      IF pend <= 0.005 THEN
        UPDATE public.detalles_partido
        SET
          pagado = true,
          fecha_pago = coalesce(fecha_pago, now()),
          monto_pagado = r.monto_pagado,
          comprobante_validado = coalesce(comprobante_validado, true),
          comprobante_url = null,
          monto_pago_declarado = null,
          pago_es_abono = null
        WHERE id = r.id;

        saldo_actual := round((saldo_actual + r.total - r.monto_pagado)::numeric, 2);
        detalles_cerrados := detalles_cerrados + 1;
      END IF;
    END LOOP;

    IF abs(saldo_actual - saldo_inicial) > 0.005 THEN
      UPDATE public.profiles
      SET saldo_acumulado = saldo_actual
      WHERE id = p_jugador_id;
    END IF;
  ELSE
    SELECT coalesce(
      sum(greatest(dp.total - dp.monto_pagado, 0::numeric)),
      0::numeric
    )
    INTO sum_pendiente
    FROM public.detalles_partido dp
    WHERE dp.jugador_id = p_jugador_id
      AND dp.asistio = true
      AND dp.pagado = false;

    diff := round(sum_pendiente - saldo_actual, 2);

    IF diff > 0.01 THEN
      virtual_aplicados := public.aplicar_abono_virtual_detalles(
        p_jugador_id,
        diff,
        now()
      );
    END IF;
  END IF;

  PERFORM public.recalcular_saldo_jugador(p_jugador_id);

  SELECT coalesce(p.saldo_acumulado, 0)
  INTO saldo_actual
  FROM public.profiles p
  WHERE p.id = p_jugador_id;

  RETURN json_build_object(
    'ok', true,
    'jugador_id', p_jugador_id,
    'saldo_inicial', saldo_inicial,
    'saldo_final', saldo_actual,
    'detalles_cerrados', detalles_cerrados,
    'virtual_aplicados', virtual_aplicados
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.aplicar_abono_virtual_detalles(uuid, numeric, timestamptz) TO authenticated;
