-- 050: Abono y validación de comprobante atómicos (anti lost-update).
-- Serializa por profiles FOR UPDATE + historial + recalc en una sola TX.

CREATE OR REPLACE FUNCTION public.pendiente_neto_detalle(
  p_saldo_anterior numeric,
  p_cargo numeric,
  p_monto_pagado numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN round(
      coalesce(p_saldo_anterior, 0) + coalesce(p_cargo, 0) - coalesce(p_monto_pagado, 0),
      2
    ) > 0.005
    THEN round(
      coalesce(p_saldo_anterior, 0) + coalesce(p_cargo, 0) - coalesce(p_monto_pagado, 0),
      2
    )
    ELSE 0::numeric
  END;
$$;

CREATE OR REPLACE FUNCTION public.snapshot_saldo_anterior_cargo(
  p_jugador_id uuid,
  p_partido_id bigint
)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT sh.saldo_anterior
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
    AND sh.partido_id = p_partido_id
    AND coalesce(sh.cargo_partido, 0) > 0
  ORDER BY sh.fecha ASC, sh.id ASC
  LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Abono manual del organizador (FIFO detalles + historial + saldo)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.registrar_abono_jugador(
  p_jugador_id uuid,
  p_monto numeric,
  p_concepto text DEFAULT 'Abono manual'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_saldo_anterior numeric;
  v_saldo_nuevo numeric;
  v_monto numeric;
  v_restante numeric;
  v_fecha timestamptz := now();
  r record;
  v_snap numeric;
  v_pendiente numeric;
  v_aplicar numeric;
  v_nuevo_monto numeric;
  v_cubierto boolean;
  v_detalles integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  PERFORM public.assert_puede_gestionar_cobros_jugador(p_jugador_id);

  IF NOT (public.is_organizer() AND public.es_mi_jugador(p_jugador_id)) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_monto := round(coalesce(p_monto, 0)::numeric, 2);
  IF v_monto <= 0.005 THEN
    RAISE EXCEPTION 'monto_invalido' USING ERRCODE = 'P0001';
  END IF;

  -- Serializa abonos concurrentes del mismo jugador.
  SELECT coalesce(saldo_acumulado, 0)
  INTO v_saldo_anterior
  FROM public.profiles
  WHERE id = p_jugador_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'jugador_no_encontrado' USING ERRCODE = 'P0001';
  END IF;

  v_restante := v_monto;

  FOR r IN
    SELECT
      dp.id,
      dp.partido_id,
      dp.total,
      dp.monto_pagado,
      p.fecha AS partido_fecha
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = p_jugador_id
      AND dp.asistio = true
      AND p.organizador_id = auth.uid()
    ORDER BY p.fecha ASC, dp.partido_id ASC
    FOR UPDATE OF dp
  LOOP
    EXIT WHEN v_restante <= 0.005;

    v_snap := coalesce(
      public.snapshot_saldo_anterior_cargo(p_jugador_id, r.partido_id),
      0
    );
    v_pendiente := public.pendiente_neto_detalle(
      v_snap,
      r.total,
      coalesce(r.monto_pagado, 0)
    );

    IF v_pendiente <= 0.005 THEN
      UPDATE public.detalles_partido
      SET
        pagado = true,
        fecha_pago = coalesce(fecha_pago, v_fecha),
        comprobante_validado = coalesce(comprobante_validado, true),
        comprobante_url = null,
        monto_pago_declarado = null,
        pago_es_abono = null
      WHERE id = r.id;
      v_detalles := v_detalles + 1;
      CONTINUE;
    END IF;

    v_aplicar := CASE
      WHEN v_restante >= v_pendiente THEN v_pendiente
      ELSE v_restante
    END;
    v_nuevo_monto := round(coalesce(r.monto_pagado, 0) + v_aplicar, 2);
    v_cubierto := public.pendiente_neto_detalle(v_snap, r.total, v_nuevo_monto) <= 0.005;

    UPDATE public.detalles_partido
    SET
      monto_pagado = v_nuevo_monto,
      pagado = v_cubierto,
      fecha_pago = v_fecha,
      comprobante_validado = CASE
        WHEN v_cubierto THEN coalesce(comprobante_validado, true)
        ELSE comprobante_validado
      END,
      comprobante_url = CASE WHEN v_cubierto THEN null ELSE comprobante_url END,
      monto_pago_declarado = CASE WHEN v_cubierto THEN null ELSE monto_pago_declarado END,
      pago_es_abono = CASE WHEN v_cubierto THEN null ELSE pago_es_abono END
    WHERE id = r.id;

    v_restante := round(v_restante - v_aplicar, 2);
    v_detalles := v_detalles + 1;
  END LOOP;

  v_saldo_nuevo := round(v_saldo_anterior - v_monto, 2);

  INSERT INTO public.saldos_historicos (
    jugador_id,
    saldo_anterior,
    cargo_partido,
    abono,
    saldo_nuevo,
    fecha,
    concepto
  ) VALUES (
    p_jugador_id,
    v_saldo_anterior,
    0,
    v_monto,
    v_saldo_nuevo,
    v_fecha,
    coalesce(nullif(trim(p_concepto), ''), 'Abono manual')
  );

  PERFORM public.recalcular_saldo_jugador(p_jugador_id);

  RETURN json_build_object(
    'ok', true,
    'jugador_id', p_jugador_id,
    'monto', v_monto,
    'saldo_anterior', v_saldo_anterior,
    'saldo_nuevo', v_saldo_nuevo,
    'detalles_tocados', v_detalles
  );
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_abono_jugador(uuid, numeric, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.registrar_abono_jugador(uuid, numeric, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.registrar_abono_jugador(uuid, numeric, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Validar / rechazar comprobante (detalle + historial + saldo en una TX)
-- ---------------------------------------------------------------------------
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
  v_nombre text;
  v_snap numeric;
  v_pendiente numeric;
  v_saldo_anterior numeric;
  v_saldo_nuevo numeric;
  v_abono numeric;
  v_aplicar numeric;
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

  PERFORM public.assert_puede_gestionar_cobros_jugador(v_dp.jugador_id);

  SELECT coalesce(nombre, 'Jugador') INTO v_nombre
  FROM public.profiles
  WHERE id = v_dp.jugador_id;

  SELECT coalesce(saldo_acumulado, 0)
  INTO v_saldo_anterior
  FROM public.profiles
  WHERE id = v_dp.jugador_id
  FOR UPDATE;

  v_comprobante_url := v_dp.comprobante_url;

  v_snap := public.snapshot_saldo_anterior_cargo(v_dp.jugador_id, v_dp.partido_id);
  IF v_snap IS NULL THEN
    RAISE EXCEPTION 'datos_inconsistentes'
      USING ERRCODE = 'P0001';
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

  v_aplicar := CASE
    WHEN v_abono >= v_pendiente THEN v_pendiente
    ELSE v_abono
  END;
  v_nuevo_monto := round(coalesce(v_dp.monto_pagado, 0) + v_aplicar, 2);
  v_cubierto := public.pendiente_neto_detalle(v_snap, v_dp.total, v_nuevo_monto) <= 0.005;
  v_saldo_nuevo := round(v_saldo_anterior - v_abono, 2);
  v_concepto := CASE
    WHEN coalesce(v_dp.pago_es_abono, false) THEN 'Abono validado por organizador'
    ELSE 'Pago validado por organizador'
  END;

  UPDATE public.detalles_partido
  SET
    comprobante_validado = true,
    comprobante_url = null,
    pagado = v_cubierto,
    monto_pagado = v_nuevo_monto,
    fecha_pago = v_fecha,
    monto_pago_declarado = null,
    pago_es_abono = null
  WHERE id = v_dp.id;

  INSERT INTO public.saldos_historicos (
    jugador_id,
    partido_id,
    saldo_anterior,
    cargo_partido,
    abono,
    saldo_nuevo,
    fecha,
    concepto
  ) VALUES (
    v_dp.jugador_id,
    v_dp.partido_id,
    v_saldo_anterior,
    0,
    v_abono,
    v_saldo_nuevo,
    v_fecha,
    v_concepto
  );

  PERFORM public.recalcular_saldo_jugador(v_dp.jugador_id);

  RETURN json_build_object(
    'ok', true,
    'accion', 'abonar_pendiente',
    'detalle_id', v_dp.id,
    'partido_id', v_dp.partido_id,
    'jugador_id', v_dp.jugador_id,
    'jugador_nombre', v_nombre,
    'abono', v_abono,
    'saldo_anterior', v_saldo_anterior,
    'saldo_nuevo', v_saldo_nuevo,
    'pendiente_neto', v_pendiente,
    'fecha_partido', v_partido.fecha,
    'comprobante_url', v_comprobante_url
  );
END;
$$;

REVOKE ALL ON FUNCTION public.validar_comprobante_pago(bigint, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.validar_comprobante_pago(bigint, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.validar_comprobante_pago(bigint, boolean) TO authenticated;
