-- 068: Estado explícito del comprobante de pago + retención al validar.
-- en_revision | aprobado | rechazado. La imagen se conserva (14 días: bloque 3).

ALTER TABLE public.detalles_partido
  ADD COLUMN IF NOT EXISTS comprobante_estado text;

ALTER TABLE public.detalles_partido
  DROP CONSTRAINT IF EXISTS detalles_partido_comprobante_estado_check;

ALTER TABLE public.detalles_partido
  ADD CONSTRAINT detalles_partido_comprobante_estado_check
  CHECK (
    comprobante_estado IS NULL
    OR comprobante_estado IN ('en_revision', 'aprobado', 'rechazado')
  );

COMMENT ON COLUMN public.detalles_partido.comprobante_estado IS
  'en_revision | aprobado | rechazado. Cola de pendientes = solo en_revision.';

-- Backfill desde columnas legacy.
UPDATE public.detalles_partido
SET comprobante_estado = CASE
  WHEN coalesce(comprobante_validado, false) THEN 'aprobado'
  WHEN comprobante_url IS NOT NULL
    OR coalesce(monto_pago_declarado, 0) > 0.005 THEN 'en_revision'
  ELSE NULL
END
WHERE comprobante_estado IS NULL;

CREATE OR REPLACE FUNCTION public.validar_comprobante_pago(
  p_detalle_id bigint,
  p_aprobado boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dp public.detalles_partido%ROWTYPE;
  v_partido public.partidos%ROWTYPE;
  v_org uuid;
  v_nombre text;
  v_snap numeric;
  v_pendiente numeric;
  v_saldo_anterior numeric;
  v_saldo_nuevo numeric;
  v_abono numeric;
  v_fecha timestamptz := now();
  v_concepto text;
  v_comprobante_url text;
  v_estado text;
  r record;
  v_restante numeric;
  v_pend_fifo numeric;
  v_aplicar numeric;
  v_nuevo_monto numeric;
  v_cubierto boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  SELECT * INTO v_dp
  FROM public.detalles_partido
  WHERE id = p_detalle_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'detalle_no_encontrado' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_partido
  FROM public.partidos
  WHERE id = v_dp.partido_id
  FOR UPDATE;

  IF NOT FOUND OR NOT public.owns_partido(v_dp.partido_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_org := v_partido.organizador_id;
  IF v_org IS NULL OR v_org IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  PERFORM public.asegurar_fila_saldo_cuenta(v_org, v_dp.jugador_id);

  SELECT coalesce(nombre, 'Participante') INTO v_nombre
  FROM public.profiles
  WHERE id = v_dp.jugador_id;

  SELECT coalesce(saldo_acumulado, 0)
  INTO v_saldo_anterior
  FROM public.organizador_jugadores
  WHERE organizador_id = v_org
    AND jugador_id = v_dp.jugador_id
  FOR UPDATE;

  v_comprobante_url := v_dp.comprobante_url;
  v_estado := v_dp.comprobante_estado;
  v_snap := public.snapshot_saldo_anterior_cargo(v_dp.jugador_id, v_dp.partido_id);
  IF v_snap IS NULL THEN
    RAISE EXCEPTION 'datos_inconsistentes' USING ERRCODE = 'P0001';
  END IF;

  v_pendiente := public.pendiente_fifo_detalle(
    v_snap,
    v_dp.total,
    coalesce(v_dp.monto_pagado, 0)
  );

  -- Ya resuelto: no reabrir cola ni borrar imagen.
  IF v_estado IN ('aprobado', 'rechazado')
     OR (v_estado IS NULL AND coalesce(v_dp.comprobante_validado, false)) THEN
    RETURN json_build_object(
      'ok', true,
      'accion', 'ignorar_ya_validado',
      'detalle_id', v_dp.id,
      'organizador_id', v_org,
      'partido_id', v_dp.partido_id,
      'jugador_id', v_dp.jugador_id
    );
  END IF;

  IF NOT coalesce(p_aprobado, false) THEN
    UPDATE public.detalles_partido
    SET
      comprobante_validado = false,
      comprobante_estado = 'rechazado',
      monto_pago_declarado = null,
      pago_es_abono = null
      -- conserva comprobante_url para retención
    WHERE id = v_dp.id;

    RETURN json_build_object(
      'ok', true,
      'accion', 'rechazar',
      'detalle_id', v_dp.id,
      'organizador_id', v_org,
      'partido_id', v_dp.partido_id,
      'jugador_id', v_dp.jugador_id,
      'jugador_nombre', v_nombre,
      'pendiente_neto', v_pendiente,
      'fecha_partido', v_partido.fecha,
      'comprobante_url', v_comprobante_url
    );
  END IF;

  IF v_pendiente <= 0.005
     AND public.pendiente_neto_detalle(
       v_snap, v_dp.total, coalesce(v_dp.monto_pagado, 0)
     ) <= 0.005 THEN
    UPDATE public.detalles_partido
    SET
      comprobante_validado = true,
      comprobante_estado = 'aprobado',
      monto_pago_declarado = null,
      pago_es_abono = null,
      fecha_pago = coalesce(fecha_pago, v_fecha),
      pagado = true
    WHERE id = v_dp.id;

    RETURN json_build_object(
      'ok', true,
      'accion', 'solo_marcar',
      'detalle_id', v_dp.id,
      'organizador_id', v_org,
      'partido_id', v_dp.partido_id,
      'jugador_id', v_dp.jugador_id,
      'comprobante_url', v_comprobante_url
    );
  END IF;

  IF v_dp.monto_pago_declarado IS NOT NULL AND v_dp.monto_pago_declarado > 0 THEN
    v_abono := round(v_dp.monto_pago_declarado::numeric, 2);
  ELSE
    v_abono := CASE
      WHEN v_pendiente > 0.005 THEN v_pendiente
      ELSE public.pendiente_neto_detalle(
        v_snap, v_dp.total, coalesce(v_dp.monto_pagado, 0)
      )
    END;
  END IF;

  IF v_abono <= 0.005 THEN
    UPDATE public.detalles_partido
    SET
      comprobante_validado = true,
      comprobante_estado = 'aprobado',
      monto_pago_declarado = null,
      pago_es_abono = null,
      fecha_pago = coalesce(fecha_pago, v_fecha)
    WHERE id = v_dp.id;

    RETURN json_build_object(
      'ok', true,
      'accion', 'solo_marcar',
      'detalle_id', v_dp.id,
      'organizador_id', v_org,
      'partido_id', v_dp.partido_id,
      'jugador_id', v_dp.jugador_id,
      'comprobante_url', v_comprobante_url
    );
  END IF;

  v_concepto := CASE
    WHEN coalesce(v_dp.pago_es_abono, false) THEN 'Abono validado por organizador'
    ELSE 'Pago validado por organizador'
  END;
  v_saldo_nuevo := round(v_saldo_anterior - v_abono, 2);

  -- Marca aprobado; conserva imagen.
  UPDATE public.detalles_partido
  SET
    comprobante_validado = true,
    comprobante_estado = 'aprobado',
    monto_pago_declarado = null,
    pago_es_abono = null,
    fecha_pago = v_fecha
  WHERE id = v_dp.id;

  v_restante := v_abono;
  FOR r IN
    SELECT
      dp.id,
      dp.partido_id,
      dp.total,
      dp.monto_pagado
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = v_dp.jugador_id
      AND dp.asistio = true
      AND p.organizador_id = v_org
    ORDER BY p.fecha ASC, dp.partido_id ASC
    FOR UPDATE OF dp
  LOOP
    EXIT WHEN v_restante <= 0.005;

    v_snap := coalesce(
      public.snapshot_saldo_anterior_cargo(v_dp.jugador_id, r.partido_id),
      0
    );
    v_pend_fifo := public.pendiente_fifo_detalle(
      v_snap,
      r.total,
      coalesce(r.monto_pagado, 0)
    );

    IF v_pend_fifo <= 0.005 THEN
      UPDATE public.detalles_partido
      SET
        pagado = true,
        fecha_pago = coalesce(fecha_pago, v_fecha),
        comprobante_validado = coalesce(comprobante_validado, true)
      WHERE id = r.id;
      CONTINUE;
    END IF;

    v_aplicar := CASE
      WHEN v_restante >= v_pend_fifo THEN v_pend_fifo
      ELSE v_restante
    END;
    v_nuevo_monto := round(coalesce(r.monto_pagado, 0) + v_aplicar, 2);
    v_cubierto := public.pendiente_fifo_detalle(v_snap, r.total, v_nuevo_monto) <= 0.005;

    UPDATE public.detalles_partido
    SET
      monto_pagado = v_nuevo_monto,
      pagado = v_cubierto,
      fecha_pago = v_fecha,
      comprobante_validado = CASE
        WHEN v_cubierto THEN coalesce(comprobante_validado, true)
        ELSE comprobante_validado
      END
    WHERE id = r.id;

    v_restante := round(v_restante - v_aplicar, 2);
  END LOOP;

  INSERT INTO public.saldos_historicos (
    organizador_id,
    jugador_id,
    partido_id,
    saldo_anterior,
    cargo_partido,
    abono,
    saldo_nuevo,
    fecha,
    concepto
  ) VALUES (
    v_org,
    v_dp.jugador_id,
    v_dp.partido_id,
    v_saldo_anterior,
    0,
    v_abono,
    v_saldo_nuevo,
    v_fecha,
    v_concepto
  );

  PERFORM public.recalcular_saldo_cuenta(v_org, v_dp.jugador_id);

  RETURN json_build_object(
    'ok', true,
    'accion', 'abonar_pendiente',
    'detalle_id', v_dp.id,
    'organizador_id', v_org,
    'partido_id', v_dp.partido_id,
    'jugador_id', v_dp.jugador_id,
    'jugador_nombre', v_nombre,
    'abono', v_abono,
    'saldo_nuevo', v_saldo_nuevo,
    'comprobante_url', v_comprobante_url
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.validar_comprobante_pago(bigint, boolean) TO authenticated;
