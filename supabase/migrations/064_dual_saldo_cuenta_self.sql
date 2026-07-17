-- Dual: el organizador que también asiste necesita fila en organizador_jugadores
-- (org_id = jugador_id) para que home/cobros lean el SSOT. No reabre "unirse a tu
-- propio grupo": asegurar_cuenta_organizador_jugador sigue rechazando self;
-- solo recalcular/abono/validar upsertan la fila de saldo de participación.

CREATE OR REPLACE FUNCTION public.asegurar_fila_saldo_cuenta(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_organizador_id IS NULL OR p_jugador_id IS NULL THEN
    RAISE EXCEPTION 'cuenta_invalida' USING ERRCODE = 'P0001';
  END IF;

  -- Participación del propio organizador: fila de saldo sin pasar por vínculo.
  IF p_organizador_id = p_jugador_id THEN
    INSERT INTO public.organizador_jugadores (
      organizador_id, jugador_id, saldo_acumulado, activo, left_at
    ) VALUES (
      p_organizador_id, p_jugador_id, 0, true, NULL
    )
    ON CONFLICT (organizador_id, jugador_id) DO NOTHING;
    RETURN;
  END IF;

  PERFORM public.asegurar_cuenta_organizador_jugador(p_organizador_id, p_jugador_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.recalcular_saldo_cuenta(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nuevo numeric := 0;
BEGIN
  IF p_organizador_id IS NULL OR p_jugador_id IS NULL THEN
    RETURN 0;
  END IF;

  -- Authz: org dueño (incl. self), o el propio jugador, o owner/migración (sin jwt).
  IF auth.uid() IS NOT NULL THEN
    IF auth.uid() IS DISTINCT FROM p_jugador_id
       AND NOT (
         public.is_organizer()
         AND auth.uid() = p_organizador_id
         AND (
           p_organizador_id = p_jugador_id
           OR EXISTS (
             SELECT 1 FROM public.organizador_jugadores oj
             WHERE oj.organizador_id = p_organizador_id
               AND oj.jugador_id = p_jugador_id
           )
         )
       )
    THEN
      RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
    END IF;
  END IF;

  PERFORM public.asegurar_fila_saldo_cuenta(p_organizador_id, p_jugador_id);

  SELECT sh.saldo_nuevo
  INTO nuevo
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
    AND sh.organizador_id = p_organizador_id
  ORDER BY sh.id DESC
  LIMIT 1;

  nuevo := coalesce(nuevo, 0);

  UPDATE public.organizador_jugadores
  SET saldo_acumulado = nuevo
  WHERE organizador_id = p_organizador_id
    AND jugador_id = p_jugador_id;

  RETURN nuevo;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalcular_saldos_cuentas(
  p_organizador_id uuid,
  p_jugador_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_organizador_id IS NULL OR p_jugador_ids IS NULL THEN
    RETURN;
  END IF;
  FOREACH v_id IN ARRAY p_jugador_ids LOOP
    IF v_id IS NOT NULL THEN
      PERFORM public.recalcular_saldo_cuenta(p_organizador_id, v_id);
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.eliminar_partido_completo(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := auth.uid();
  jugador_ids uuid[];
  jid uuid;
BEGIN
  IF NOT public.is_organizer() OR NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = p_partido_id;

  DELETE FROM public.saldos_historicos WHERE partido_id = p_partido_id;
  DELETE FROM public.partidos WHERE id = p_partido_id;

  IF jugador_ids IS NOT NULL AND v_org IS NOT NULL THEN
    FOREACH jid IN ARRAY jugador_ids LOOP
      PERFORM public.recalcular_saldo_cuenta(v_org, jid);
    END LOOP;
  END IF;

  RETURN json_build_object('jugadores', jugador_ids);
END;
$$;

-- Abono: permitir self (org paga su propia participación) sin es_mi_jugador previo.
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
  v_org uuid := auth.uid();
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
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  IF NOT (
    public.is_organizer()
    AND (
      p_jugador_id = v_org
      OR public.es_mi_jugador(p_jugador_id)
    )
  ) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_monto := round(coalesce(p_monto, 0)::numeric, 2);
  IF v_monto <= 0.005 THEN
    RAISE EXCEPTION 'monto_invalido' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.asegurar_fila_saldo_cuenta(v_org, p_jugador_id);

  SELECT coalesce(saldo_acumulado, 0)
  INTO v_saldo_anterior
  FROM public.organizador_jugadores
  WHERE organizador_id = v_org
    AND jugador_id = p_jugador_id
  FOR UPDATE;

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
      AND p.organizador_id = v_org
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
    organizador_id,
    jugador_id,
    saldo_anterior,
    cargo_partido,
    abono,
    saldo_nuevo,
    fecha,
    concepto
  ) VALUES (
    v_org,
    p_jugador_id,
    v_saldo_anterior,
    0,
    v_monto,
    v_saldo_nuevo,
    v_fecha,
    coalesce(nullif(trim(p_concepto), ''), 'Abono manual')
  );

  PERFORM public.recalcular_saldo_cuenta(v_org, p_jugador_id);

  RETURN json_build_object(
    'ok', true,
    'organizador_id', v_org,
    'jugador_id', p_jugador_id,
    'monto', v_monto,
    'saldo_anterior', v_saldo_anterior,
    'saldo_nuevo', v_saldo_nuevo,
    'detalles_tocados', v_detalles
  );
END;
$$;

-- validar_comprobante: misma lógica remota; solo cambia asegurar → fila saldo (self OK).
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

GRANT EXECUTE ON FUNCTION public.asegurar_fila_saldo_cuenta(uuid, uuid) TO authenticated;

-- Backfill: cuentas self faltantes + recalcular desde historial.
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
