-- Al validar un comprobante con monto declarado > pendiente del detalle,
-- el historial/cuenta sí registraban el exceso (saldo a favor), pero
-- detalles_partido.monto_pagado solo sumaba hasta el pendiente.
-- Eso hace que el detalle del encuentro muestre "Abonado = pendiente"
-- y "A transferir 0" sin "Saldo a favor".
-- Fix: aplicar el abono completo declarado al detalle.

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
  v_nuevo_monto numeric;
  v_cubierto boolean;
  v_fecha timestamptz := now();
  v_concepto text;
  v_comprobante_url text;
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
  v_snap := public.snapshot_saldo_anterior_cargo(v_dp.jugador_id, v_dp.partido_id);
  IF v_snap IS NULL THEN
    RAISE EXCEPTION 'datos_inconsistentes' USING ERRCODE = 'P0001';
  END IF;

  v_pendiente := public.pendiente_neto_detalle(
    v_snap,
    v_dp.total,
    coalesce(v_dp.monto_pagado, 0)
  );

  IF NOT coalesce(p_aprobado, false) THEN
    UPDATE public.detalles_partido
    SET
      comprobante_validado = false,
      comprobante_url = null,
      monto_pago_declarado = null,
      pago_es_abono = null
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

  IF coalesce(v_dp.comprobante_validado, false) THEN
    RETURN json_build_object(
      'ok', true,
      'accion', 'ignorar_ya_validado',
      'detalle_id', v_dp.id,
      'organizador_id', v_org,
      'partido_id', v_dp.partido_id,
      'jugador_id', v_dp.jugador_id
    );
  END IF;

  IF v_pendiente <= 0.005 THEN
    UPDATE public.detalles_partido
    SET
      comprobante_validado = true,
      comprobante_url = null,
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

  IF v_dp.monto_pago_declarado IS NOT NULL AND v_dp.monto_pago_declarado > 0 THEN
    v_abono := round(v_dp.monto_pago_declarado::numeric, 2);
  ELSE
    v_abono := v_pendiente;
  END IF;

  -- Abono completo en el detalle (incluye exceso → saldo a favor visible).
  v_nuevo_monto := round(coalesce(v_dp.monto_pagado, 0) + v_abono, 2);
  v_cubierto := public.pendiente_neto_detalle(v_snap, v_dp.total, v_nuevo_monto) <= 0.005;
  v_saldo_nuevo := round(v_saldo_anterior - v_abono, 2);
  v_concepto := CASE
    WHEN coalesce(v_dp.pago_es_abono, false) THEN 'Abono validado por organizador'
    ELSE 'Pago validado por organizador'
  END;

  UPDATE public.detalles_partido
  SET
    monto_pagado = v_nuevo_monto,
    pagado = v_cubierto,
    fecha_pago = v_fecha,
    comprobante_validado = true,
    comprobante_url = null,
    monto_pago_declarado = null,
    pago_es_abono = null
  WHERE id = v_dp.id;

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
    'accion', 'abonar',
    'detalle_id', v_dp.id,
    'organizador_id', v_org,
    'partido_id', v_dp.partido_id,
    'jugador_id', v_dp.jugador_id,
    'jugador_nombre', v_nombre,
    'abono', v_abono,
    'saldo_anterior', v_saldo_anterior,
    'saldo_nuevo', v_saldo_nuevo,
    'comprobante_url', v_comprobante_url
  );
END;
$$;

-- Backfill: si el historial de un partido tiene abono > monto_pagado del detalle
-- (sobrepago validado), alinear monto_pagado al abono acumulado de ese partido.
UPDATE public.detalles_partido dp
SET monto_pagado = sub.abonos
FROM (
  SELECT
    sh.partido_id,
    sh.jugador_id,
    round(sum(sh.abono), 2) AS abonos
  FROM public.saldos_historicos sh
  WHERE sh.partido_id IS NOT NULL
    AND sh.abono > 0.005
  GROUP BY sh.partido_id, sh.jugador_id
) sub
WHERE dp.partido_id = sub.partido_id
  AND dp.jugador_id = sub.jugador_id
  AND sub.abonos > dp.monto_pagado + 0.005;

-- Re-sincronizar cuentas self desalineadas con el último ledger.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT sh.organizador_id, sh.jugador_id
    FROM public.saldos_historicos sh
    WHERE sh.organizador_id = sh.jugador_id
  LOOP
    PERFORM public.recalcular_saldo_cuenta(r.organizador_id, r.jugador_id);
  END LOOP;
END;
$$;
