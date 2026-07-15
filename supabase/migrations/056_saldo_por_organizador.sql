-- =============================================================================
-- Saldo particionado por relación organizador ↔ jugador
-- DB de prueba: se vacía historial y se resetean cuentas (sin backfill).
--
-- Invariante (NO netear entre orgs):
--   Un crédito con Org A NUNCA reduce deuda con Org B.
--   Home jugador = SUM(deudas > 0 por cuenta), no suma neta global.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Cuenta en el vínculo
-- ---------------------------------------------------------------------------
ALTER TABLE public.organizador_jugadores
  ADD COLUMN IF NOT EXISTS saldo_acumulado numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS left_at timestamptz;

COMMENT ON COLUMN public.organizador_jugadores.saldo_acumulado IS
  'SSOT de deuda/crédito de este jugador CON este organizador. >0 debe, <0 crédito. Nunca mezclar entre orgs.';
COMMENT ON COLUMN public.organizador_jugadores.activo IS
  'false = soft-leave: conservamos saldo y ledger; no aparece en roster activo.';
COMMENT ON COLUMN public.organizador_jugadores.left_at IS
  'Cuándo el jugador dejó el grupo (soft-leave).';

-- ---------------------------------------------------------------------------
-- 2) Ledger: organizador_id explícito (reset de prueba)
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS public.cobros_resumen;

TRUNCATE public.saldos_historicos RESTART IDENTITY;

ALTER TABLE public.saldos_historicos
  DROP COLUMN IF EXISTS organizador_id;

ALTER TABLE public.saldos_historicos
  ADD COLUMN organizador_id uuid NOT NULL REFERENCES public.profiles(id);

CREATE INDEX IF NOT EXISTS idx_saldos_hist_cuenta_id
  ON public.saldos_historicos (jugador_id, organizador_id, id DESC);

CREATE INDEX IF NOT EXISTS idx_saldos_hist_org_jugador_id
  ON public.saldos_historicos (organizador_id, jugador_id, id DESC);

COMMENT ON COLUMN public.saldos_historicos.organizador_id IS
  'Organizador dueño de este movimiento. Explícito: no inferir solo por partido_id.';

-- Coherencia partido ↔ organizador del movimiento
CREATE OR REPLACE FUNCTION public.trg_saldos_historicos_org_coherente()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF NEW.organizador_id IS NULL THEN
    RAISE EXCEPTION 'organizador_id_requerido' USING ERRCODE = 'P0001';
  END IF;
  IF NEW.partido_id IS NOT NULL THEN
    SELECT organizador_id INTO v_org
    FROM public.partidos
    WHERE id = NEW.partido_id;
    IF v_org IS NULL OR v_org IS DISTINCT FROM NEW.organizador_id THEN
      RAISE EXCEPTION 'organizador_partido_incoherente' USING ERRCODE = 'P0001';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_saldos_historicos_org_coherente ON public.saldos_historicos;
CREATE TRIGGER trg_saldos_historicos_org_coherente
  BEFORE INSERT OR UPDATE ON public.saldos_historicos
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_saldos_historicos_org_coherente();

-- ---------------------------------------------------------------------------
-- 3) Reset cuentas + quitar SSOT global de profiles
-- ---------------------------------------------------------------------------
UPDATE public.organizador_jugadores
SET saldo_acumulado = 0,
    activo = coalesce(activo, true),
    left_at = CASE WHEN coalesce(activo, true) THEN NULL ELSE left_at END;

-- Quitar columna global (rompe lectores viejos a propósito hasta Flutter).
ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS saldo_acumulado;

-- ---------------------------------------------------------------------------
-- 4) Helpers de cuenta
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.asegurar_cuenta_organizador_jugador(
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
  -- Dual: no auto-vínculo de cobro
  IF p_organizador_id = p_jugador_id THEN
    RAISE EXCEPTION 'No puedes vincularte a tu propio grupo'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.organizador_jugadores (
    organizador_id, jugador_id, saldo_acumulado, activo, left_at
  ) VALUES (
    p_organizador_id, p_jugador_id, 0, true, NULL
  )
  ON CONFLICT (organizador_id, jugador_id) DO NOTHING;
  -- No reabre soft-leave aquí: eso solo ocurre al unirse de nuevo / vincular explícito.
END;
$$;

CREATE OR REPLACE FUNCTION public.reabrir_cuenta_organizador_jugador(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.asegurar_cuenta_organizador_jugador(p_organizador_id, p_jugador_id);
  UPDATE public.organizador_jugadores
  SET activo = true,
      left_at = NULL
  WHERE organizador_id = p_organizador_id
    AND jugador_id = p_jugador_id;
  -- Conserva saldo_acumulado intacto.
END;
$$;

CREATE OR REPLACE FUNCTION public.bloquear_salida_cuenta_si_necesario(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Soft-leave: marcar inactivo; conservar saldo.
  UPDATE public.organizador_jugadores
  SET activo = false,
      left_at = now()
  WHERE organizador_id = p_organizador_id
    AND jugador_id = p_jugador_id
    AND activo = true;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) Recálculo por cuenta (SSOT)
-- ---------------------------------------------------------------------------
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

  -- Authz: org dueño, o el propio jugador, o owner/migración (sin jwt).
  IF auth.uid() IS NOT NULL THEN
    IF auth.uid() IS DISTINCT FROM p_jugador_id
       AND NOT (
         public.is_organizer()
         AND auth.uid() = p_organizador_id
         AND EXISTS (
           SELECT 1 FROM public.organizador_jugadores oj
           WHERE oj.organizador_id = p_organizador_id
             AND oj.jugador_id = p_jugador_id
         )
       )
    THEN
      RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
    END IF;
  END IF;

  PERFORM public.asegurar_cuenta_organizador_jugador(p_organizador_id, p_jugador_id);

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
    PERFORM public.recalcular_saldo_cuenta(p_organizador_id, v_id);
  END LOOP;
END;
$$;

-- Compat: firma vieja ya no es válida como SSOT global.
-- La dejamos fallando claro para no silenciar callers Flutter antiguos.
CREATE OR REPLACE FUNCTION public.recalcular_saldo_jugador(p_jugador_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION
    'recalcular_saldo_jugador_deprecado: usa recalcular_saldo_cuenta(organizador_id, jugador_id)'
    USING ERRCODE = 'P0001';
END;
$$;

CREATE OR REPLACE FUNCTION public.recalcular_saldos_jugadores(p_jugador_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION
    'recalcular_saldos_jugadores_deprecado: usa recalcular_saldos_cuentas(organizador_id, jugador_ids)'
    USING ERRCODE = 'P0001';
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) Snapshot / lectura de cuenta
-- ---------------------------------------------------------------------------
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
  INNER JOIN public.partidos p ON p.id = sh.partido_id
  WHERE sh.jugador_id = p_jugador_id
    AND sh.partido_id = p_partido_id
    AND sh.organizador_id = p.organizador_id
    AND coalesce(sh.cargo_partido, 0) > 0
  ORDER BY sh.id ASC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.get_saldo_cuenta(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(
    (
      SELECT oj.saldo_acumulado
      FROM public.organizador_jugadores oj
      WHERE oj.organizador_id = p_organizador_id
        AND oj.jugador_id = p_jugador_id
    ),
    0::numeric
  );
$$;

-- Home jugador: deudas >0 por org (SIN netear créditos de otros).
-- NO sumar créditos negativos contra deudas de otro organizador.
CREATE OR REPLACE FUNCTION public.get_mis_cuentas_saldo()
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

  SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.nombre), '[]'::json)
  INTO result
  FROM (
    SELECT
      oj.organizador_id,
      pr.nombre,
      pr.foto_url,
      oj.saldo_acumulado,
      oj.activo,
      oj.left_at,
      -- Pendiente visible solo si debe (>0). Crédito va aparte.
      CASE
        WHEN oj.saldo_acumulado > 0.005 THEN oj.saldo_acumulado
        ELSE 0::numeric
      END AS deuda,
      CASE
        WHEN oj.saldo_acumulado < -0.005 THEN -oj.saldo_acumulado
        ELSE 0::numeric
      END AS credito
    FROM public.organizador_jugadores oj
    INNER JOIN public.profiles pr ON pr.id = oj.organizador_id
    WHERE oj.jugador_id = auth.uid()
  ) t;

  RETURN result;
END;
$$;

-- Total home: SOLO suma deudas >0. Documentado: no netear créditos.
CREATE OR REPLACE FUNCTION public.get_mi_total_deuda_home()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- IMPORTANTE: no netear. Crédito con Org A no reduce deuda con Org B.
  SELECT coalesce(
    sum(CASE WHEN oj.saldo_acumulado > 0.005 THEN oj.saldo_acumulado ELSE 0 END),
    0
  )::numeric(12,2)
  FROM public.organizador_jugadores oj
  WHERE oj.jugador_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 7) Abono / validación (cuenta del org autenticado)
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

  IF NOT (public.is_organizer() AND public.es_mi_jugador(p_jugador_id)) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  v_monto := round(coalesce(p_monto, 0)::numeric, 2);
  IF v_monto <= 0.005 THEN
    RAISE EXCEPTION 'monto_invalido' USING ERRCODE = 'P0001';
  END IF;

  PERFORM public.asegurar_cuenta_organizador_jugador(v_org, p_jugador_id);

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

  -- Pagar de más → crédito SOLO con este organizador (saldo_nuevo puede ser <0).
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

  PERFORM public.asegurar_cuenta_organizador_jugador(v_org, v_dp.jugador_id);

  SELECT coalesce(nombre, 'Jugador') INTO v_nombre
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

-- ---------------------------------------------------------------------------
-- 8) cobros_resumen: solo cuentas del organizador autenticado
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.cobros_resumen
WITH (security_invoker = true)
AS
SELECT
  CASE
    WHEN public.is_organizer() THEN coalesce(
      sum(
        CASE
          WHEN oj.saldo_acumulado > 0.005 THEN oj.saldo_acumulado
          ELSE 0::numeric
        END
      ),
      0::numeric
    )
    ELSE 0::numeric
  END::numeric(12,2) AS monto_total_pendiente,
  CASE
    WHEN public.is_organizer() THEN coalesce(
      count(*) FILTER (WHERE oj.saldo_acumulado > 0.005),
      0::bigint
    )
    ELSE 0::bigint
  END::integer AS jugadores_con_deuda
FROM public.organizador_jugadores oj
WHERE oj.organizador_id = auth.uid()
  AND oj.activo = true;

GRANT SELECT ON public.cobros_resumen TO authenticated;

-- ---------------------------------------------------------------------------
-- 9) Roster: devolver saldo de la cuenta (no profiles)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_mis_jugadores_organizador(
  p_solo_activos boolean DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RETURN '[]'::json;
  END IF;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json)
  INTO result
  FROM (
    SELECT
      pr.id,
      pr.nombre,
      pr.email,
      pr.telefono,
      pr.activo AS perfil_activo,
      pr.role,
      pr.foto_url,
      pr.fcm_token,
      pr.created_at,
      -- Saldo de ESTA relación (no global).
      oj.saldo_acumulado,
      oj.activo AS en_grupo_activo,
      oj.left_at
    FROM public.organizador_jugadores oj
    INNER JOIN public.profiles pr ON pr.id = oj.jugador_id
    WHERE oj.organizador_id = auth.uid()
      AND oj.activo = true
      AND pr.role = 'jugador'
      AND (
        p_solo_activos IS NULL
        OR pr.activo = p_solo_activos
      )
    ORDER BY pr.nombre
  ) t;

  RETURN result;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10) Vincular / unirse: soft-reopen + anti auto-vínculo
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
  IF p_organizador_id IS NULL AND NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;
  IF p_organizador_id IS NOT NULL AND p_organizador_id IS DISTINCT FROM auth.uid()
     AND NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  PERFORM public.reabrir_cuenta_organizador_jugador(v_org, p_jugador_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.unirse_con_codigo_grupo(p_codigo text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_norm text;
  v_org uuid;
  v_nombre text;
  v_ya_activo boolean;
  v_existia boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  v_norm := public.normalizar_codigo_grupo(p_codigo);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'Código inválido. Usa el formato KLOOVI-XXXX';
  END IF;

  SELECT id, nombre
  INTO v_org, v_nombre
  FROM public.profiles
  WHERE codigo_grupo = v_norm
    AND role IN ('organizer', 'organizador')
  LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'No encontramos un organizador con ese código';
  END IF;

  -- Ya existía: no puedes unirte a tu propio código.
  IF v_org = auth.uid() THEN
    RAISE EXCEPTION 'No puedes unirte a tu propio grupo con este código';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.organizador_jugadores
    WHERE organizador_id = v_org AND jugador_id = auth.uid()
  ) INTO v_existia;

  SELECT EXISTS (
    SELECT 1 FROM public.organizador_jugadores
    WHERE organizador_id = v_org AND jugador_id = auth.uid() AND activo = true
  ) INTO v_ya_activo;

  -- Reabre la misma cuenta (conserva saldo) si venía de soft-leave.
  PERFORM public.reabrir_cuenta_organizador_jugador(v_org, auth.uid());

  RETURN json_build_object(
    'organizador_id', v_org,
    'nombre', coalesce(nullif(trim(v_nombre), ''), 'Organizador'),
    'codigo', v_norm,
    'ya_estaba', v_ya_activo,
    'reabierto', v_existia AND NOT v_ya_activo
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- 11) Protect: cliente no escribe saldo de la cuenta a mano
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_organizador_jugadores_protect_saldo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user IS DISTINCT FROM 'authenticated' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.saldo_acumulado IS DISTINCT FROM OLD.saldo_acumulado THEN
    RAISE EXCEPTION
      'permission_denied: no puedes modificar saldo_acumulado de la cuenta'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_organizador_jugadores_protect_saldo
  ON public.organizador_jugadores;
CREATE TRIGGER trg_organizador_jugadores_protect_saldo
  BEFORE UPDATE ON public.organizador_jugadores
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_organizador_jugadores_protect_saldo();

-- profiles: quitar chequeo de saldo_acumulado (columna ya no existe)
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
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION
        'permission_denied: no puedes cambiar role de otro perfil'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION
      'permission_denied: usa promover_a_organizador() para cambiar rol'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_saldo_cuenta(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalcular_saldos_cuentas(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_saldo_cuenta(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mis_cuentas_saldo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mi_total_deuda_home() TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_abono_jugador(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validar_comprobante_pago(bigint, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mis_jugadores_organizador(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_jugador_organizador(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unirse_con_codigo_grupo(text) TO authenticated;
