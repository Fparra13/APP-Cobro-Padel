-- =============================================================================
-- Hardening seguridad crítica (C1–C5 + cancel ownership + storage)
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helpers de autorización
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.puede_gestionar_cobros_jugador(p_jugador_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL
    AND p_jugador_id IS NOT NULL
    AND (
      auth.uid() = p_jugador_id
      OR (
        public.is_organizer()
        AND public.es_mi_jugador(p_jugador_id)
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.assert_puede_gestionar_cobros_jugador(p_jugador_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.puede_gestionar_cobros_jugador(p_jugador_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- C1: jugador solo puede tocar campos de comprobante en detalles_partido
-- (escrituras vía SECURITY DEFINER / postgres siguen permitidas)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_detalles_partido_update_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- RPCs / service role (owner): sin restricción de columnas
  IF current_user IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;

  IF public.owns_partido(NEW.partido_id) THEN
    RETURN NEW;
  END IF;

  IF NEW.jugador_id = auth.uid() THEN
    IF NEW.partido_id IS DISTINCT FROM OLD.partido_id
       OR NEW.jugador_id IS DISTINCT FROM OLD.jugador_id
       OR NEW.total IS DISTINCT FROM OLD.total
       OR NEW.monto_pagado IS DISTINCT FROM OLD.monto_pagado
       OR NEW.pagado IS DISTINCT FROM OLD.pagado
       OR NEW.asistio IS DISTINCT FROM OLD.asistio
       OR NEW.comprobante_validado IS DISTINCT FROM OLD.comprobante_validado
       OR NEW.fecha_pago IS DISTINCT FROM OLD.fecha_pago
    THEN
      RAISE EXCEPTION
        'permission_denied: solo puedes subir o actualizar tu comprobante'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_detalles_partido_update_guard ON public.detalles_partido;
CREATE TRIGGER trg_detalles_partido_update_guard
  BEFORE UPDATE ON public.detalles_partido
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_detalles_partido_update_guard();

-- ---------------------------------------------------------------------------
-- C4: no auto-cambiar role ni saldo_acumulado vía UPDATE de cliente
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_profiles_protect_privileged()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS DISTINCT FROM OLD.id THEN
    -- Organizador editando jugador de su roster: no tocar role/saldo
    IF NEW.role IS DISTINCT FROM OLD.role
       OR NEW.saldo_acumulado IS DISTINCT FROM OLD.saldo_acumulado THEN
      RAISE EXCEPTION
        'permission_denied: no puedes cambiar role ni saldo de otro perfil'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  -- Self-update
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION
      'permission_denied: usa promover_a_organizador() para cambiar rol'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.saldo_acumulado IS DISTINCT FROM OLD.saldo_acumulado THEN
    RAISE EXCEPTION
      'permission_denied: no puedes modificar tu saldo acumulado'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_protect_privileged ON public.profiles;
CREATE TRIGGER trg_profiles_protect_privileged
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_profiles_protect_privileged();

CREATE OR REPLACE FUNCTION public.promover_a_organizador()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  UPDATE public.profiles
  SET role = 'organizer'
  WHERE id = auth.uid()
    AND role IS DISTINCT FROM 'organizer';
END;
$$;

GRANT EXECUTE ON FUNCTION public.promover_a_organizador() TO authenticated;

-- ---------------------------------------------------------------------------
-- C5: vincular_jugador_organizador siempre exige caller = org + is_organizer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vincular_jugador_organizador(
  p_jugador_id uuid,
  p_organizador_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := coalesce(p_organizador_id, auth.uid());
BEGIN
  IF auth.uid() IS NULL OR p_jugador_id IS NULL OR v_org IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF v_org <> auth.uid() OR NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
  VALUES (v_org, p_jugador_id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- ---------------------------------------------------------------------------
-- C2: authz en RPCs de cobro / reparación
-- ---------------------------------------------------------------------------
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

  SELECT sh.saldo_nuevo
  INTO nuevo
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
  ORDER BY sh.fecha DESC, sh.id DESC
  LIMIT 1;

  nuevo := coalesce(nuevo, 0);

  UPDATE public.profiles
  SET saldo_acumulado = nuevo
  WHERE id = p_jugador_id;

  RETURN nuevo;
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
  PERFORM public.assert_puede_gestionar_cobros_jugador(p_jugador_id);

  IF p_jugador_id IS NULL OR coalesce(p_monto, 0) <= 0.005 THEN
    RETURN 0;
  END IF;

  -- Solo organizador del jugador (no self-service de abono virtual)
  IF NOT (public.is_organizer() AND public.es_mi_jugador(p_jugador_id)) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
      AND p.organizador_id = auth.uid()
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

CREATE OR REPLACE FUNCTION public.alinear_detalles_con_historico(p_jugador_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  filas integer := 0;
BEGIN
  PERFORM public.assert_puede_gestionar_cobros_jugador(p_jugador_id);

  IF p_jugador_id IS NULL THEN
    RETURN 0;
  END IF;

  IF NOT (public.is_organizer() AND public.es_mi_jugador(p_jugador_id)) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  UPDATE public.detalles_partido dp
  SET
    pagado = true,
    fecha_pago = coalesce(dp.fecha_pago, sh.fecha, now()),
    monto_pagado = dp.monto_pagado,
    comprobante_validado = coalesce(dp.comprobante_validado, true),
    comprobante_url = null,
    monto_pago_declarado = null,
    pago_es_abono = null
  FROM public.saldos_historicos sh
  INNER JOIN public.partidos p ON p.id = sh.partido_id
  WHERE sh.jugador_id = p_jugador_id
    AND sh.partido_id = dp.partido_id
    AND dp.jugador_id = p_jugador_id
    AND dp.asistio = true
    AND dp.pagado = false
    AND p.organizador_id = auth.uid()
    AND sh.cargo_partido > 0.005
    AND greatest(
      greatest(
        sh.cargo_partido - CASE
          WHEN sh.saldo_anterior < 0
            THEN least(-sh.saldo_anterior, sh.cargo_partido)
          ELSE 0
        END,
        0
      ) - dp.monto_pagado,
      0
    ) <= 0.005;

  GET DIAGNOSTICS filas = ROW_COUNT;
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
  PERFORM public.assert_puede_gestionar_cobros_jugador(p_jugador_id);

  IF p_jugador_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'jugador nulo');
  END IF;

  IF NOT (public.is_organizer() AND public.es_mi_jugador(p_jugador_id)) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
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
        AND p.organizador_id = auth.uid()
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
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = p_jugador_id
      AND dp.asistio = true
      AND dp.pagado = false
      AND p.organizador_id = auth.uid();

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

CREATE OR REPLACE FUNCTION public.reparar_jugador_cobros(p_jugador_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  alineados integer;
  rec json;
  saldo_final numeric;
BEGIN
  PERFORM public.assert_puede_gestionar_cobros_jugador(p_jugador_id);

  IF p_jugador_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'jugador nulo');
  END IF;

  IF NOT (public.is_organizer() AND public.es_mi_jugador(p_jugador_id)) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  alineados := public.alinear_detalles_con_historico(p_jugador_id);
  rec := public.reconciliar_detalles_jugador(p_jugador_id);
  saldo_final := public.recalcular_saldo_jugador(p_jugador_id);

  RETURN json_build_object(
    'ok', true,
    'jugador_id', p_jugador_id,
    'detalles_alineados_historico', alineados,
    'reconciliacion', rec,
    'saldo_final', saldo_final
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- C3: preparar_reemplazo + eliminar_partido exigen owns_partido
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preparar_reemplazo_partido(p_partido_id bigint)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jugador_ids uuid[];
  jid uuid;
BEGIN
  IF NOT public.is_organizer() OR NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.partidos WHERE id = p_partido_id) THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = p_partido_id;

  DELETE FROM public.saldos_historicos WHERE partido_id = p_partido_id;
  DELETE FROM public.detalles_partido WHERE partido_id = p_partido_id;
  DELETE FROM public.costos_variables WHERE partido_id = p_partido_id;

  IF jugador_ids IS NOT NULL THEN
    FOREACH jid IN ARRAY jugador_ids LOOP
      INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
      VALUES (auth.uid(), jid)
      ON CONFLICT DO NOTHING;
      PERFORM public.recalcular_saldo_jugador(jid);
    END LOOP;
  END IF;

  RETURN jugador_ids;
END;
$$;

CREATE OR REPLACE FUNCTION public.eliminar_partido_completo(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jugador_ids uuid[];
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

  IF jugador_ids IS NOT NULL THEN
    FOR i IN 1..coalesce(array_length(jugador_ids, 1), 0) LOOP
      INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
      VALUES (auth.uid(), jugador_ids[i])
      ON CONFLICT DO NOTHING;
      PERFORM public.recalcular_saldo_jugador(jugador_ids[i]);
    END LOOP;
  END IF;

  RETURN json_build_object('jugadores', jugador_ids);
END;
$$;

-- ---------------------------------------------------------------------------
-- Cancel / reprogram: exigir organizador_id = auth.uid() (no NULL)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancelar_convocatoria_organizador(p_partido_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
  v_org uuid;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RAISE EXCEPTION 'Solo el organizador puede cancelar';
  END IF;

  SELECT estado, organizador_id
  INTO v_estado, v_org
  FROM public.partidos
  WHERE id = p_partido_id
  FOR UPDATE;

  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  IF v_estado NOT IN ('organizando', 'confirmado') THEN
    RAISE EXCEPTION 'El partido no está en convocatoria activa';
  END IF;

  IF v_org IS NULL OR v_org <> auth.uid() THEN
    RAISE EXCEPTION 'No eres el organizador de este partido';
  END IF;

  UPDATE public.partidos
  SET estado = 'cancelado',
      resuelto_en = now()
  WHERE id = p_partido_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reprogramar_convocatoria_organizador(
  p_partido_id bigint,
  p_nueva_fecha timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_estado text;
  v_org uuid;
  v_horas integer;
  v_limite timestamptz;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RAISE EXCEPTION 'Solo el organizador puede reprogramar';
  END IF;

  IF p_nueva_fecha <= now() THEN
    RAISE EXCEPTION 'La nueva fecha debe ser futura';
  END IF;

  SELECT estado, organizador_id, horas_limite_respuesta
  INTO v_estado, v_org, v_horas
  FROM public.partidos
  WHERE id = p_partido_id
  FOR UPDATE;

  IF v_estado IS NULL THEN
    RAISE EXCEPTION 'Partido no encontrado';
  END IF;

  IF v_estado NOT IN ('organizando', 'confirmado') THEN
    RAISE EXCEPTION 'El partido no está en convocatoria activa';
  END IF;

  IF v_org IS NULL OR v_org <> auth.uid() THEN
    RAISE EXCEPTION 'No eres el organizador de este partido';
  END IF;

  v_horas := coalesce(v_horas, 24);
  v_limite := now() + make_interval(hours => v_horas);

  UPDATE public.partidos
  SET fecha = p_nueva_fecha,
      estado = 'organizando',
      resuelto_en = NULL,
      reprogramado_en = now()
  WHERE id = p_partido_id;

  -- Todos los titulares deben volver a confirmar la nueva fecha.
  UPDATE public.convocatoria_jugadores
  SET estado_confirmacion = 'invitado',
      tiempo_limite = v_limite,
      notificado_vencimiento = false,
      recordatorio_plazo_enviado = false
  WHERE partido_id = p_partido_id
    AND es_suplente = false;
END;
$$;

-- ---------------------------------------------------------------------------
-- Storage: organizador solo ve comprobantes de su roster
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Ver comprobantes propios o ser organizador" ON storage.objects;

CREATE POLICY "Ver comprobantes propios o de mis jugadores"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'comprobantes'
    AND (
      auth.uid()::text = (storage.foldername(name))[1]
      OR (
        public.is_organizer()
        AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
        AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
      )
    )
  );

GRANT EXECUTE ON FUNCTION public.puede_gestionar_cobros_jugador(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assert_puede_gestionar_cobros_jugador(uuid) TO authenticated;
