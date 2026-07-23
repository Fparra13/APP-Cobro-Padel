-- 074: Recordatorios automáticos de cobro (MVP V1 — solo schema/RPC/triggers).
-- Lógica de envío: Edge Function + pg_cron (etapa 2). Sin auditoría ni digest.

-- ---------------------------------------------------------------------------
-- 1) Preferencias globales del organizador
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizador_recordatorio_prefs (
  organizador_id uuid PRIMARY KEY
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  activo boolean NOT NULL DEFAULT false,
  dias_primer integer NOT NULL DEFAULT 3
    CHECK (dias_primer >= 0 AND dias_primer <= 90),
  frecuencia_dias integer NOT NULL DEFAULT 3
    CHECK (frecuencia_dias >= 1 AND frecuencia_dias <= 90),
  hora_local time NOT NULL DEFAULT time '10:00',
  timezone text NOT NULL DEFAULT 'America/Santiago',
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.organizador_recordatorio_prefs IS
  'Preferencias globales de recordatorios automáticos de cobro (por organizador).';

ALTER TABLE public.organizador_recordatorio_prefs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS organizador_recordatorio_prefs_select
  ON public.organizador_recordatorio_prefs;
CREATE POLICY organizador_recordatorio_prefs_select
  ON public.organizador_recordatorio_prefs
  FOR SELECT
  TO authenticated
  USING (organizador_id = auth.uid());

DROP POLICY IF EXISTS organizador_recordatorio_prefs_insert
  ON public.organizador_recordatorio_prefs;
CREATE POLICY organizador_recordatorio_prefs_insert
  ON public.organizador_recordatorio_prefs
  FOR INSERT
  TO authenticated
  WITH CHECK (organizador_id = auth.uid());

DROP POLICY IF EXISTS organizador_recordatorio_prefs_update
  ON public.organizador_recordatorio_prefs;
CREATE POLICY organizador_recordatorio_prefs_update
  ON public.organizador_recordatorio_prefs
  FOR UPDATE
  TO authenticated
  USING (organizador_id = auth.uid())
  WITH CHECK (organizador_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) Flag por partido (decisión al cerrar / generar cobros)
-- ---------------------------------------------------------------------------
ALTER TABLE public.partidos
  ADD COLUMN IF NOT EXISTS generar_recordatorios_cobro boolean;

COMMENT ON COLUMN public.partidos.generar_recordatorios_cobro IS
  'NULL=no decidido; true=crear/mantener schedules; false=no generar para este partido.';

-- ---------------------------------------------------------------------------
-- 3) Cola: un schedule por deuda (detalle_partido)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cobro_recordatorio (
  id bigserial PRIMARY KEY,
  detalle_partido_id bigint NOT NULL UNIQUE
    REFERENCES public.detalles_partido(id) ON DELETE CASCADE,
  partido_id bigint NOT NULL
    REFERENCES public.partidos(id) ON DELETE CASCADE,
  organizador_id uuid NOT NULL
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  jugador_id uuid NOT NULL
    REFERENCES public.profiles(id) ON DELETE CASCADE,
  activo boolean NOT NULL DEFAULT true,
  next_send_at timestamptz NOT NULL,
  ultimo_envio timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cobro_recordatorio IS
  'Cola de recordatorios automáticos de cobro. Máximo una fila por detalle_partido.';
COMMENT ON COLUMN public.cobro_recordatorio.ultimo_envio IS
  'Último push enviado (nullable). Evita duplicados y habilita UI/estadísticas futuras.';

CREATE INDEX IF NOT EXISTS idx_cobro_recordatorio_due
  ON public.cobro_recordatorio (next_send_at)
  WHERE activo = true;

CREATE INDEX IF NOT EXISTS idx_cobro_recordatorio_org
  ON public.cobro_recordatorio (organizador_id, activo);

CREATE INDEX IF NOT EXISTS idx_cobro_recordatorio_partido
  ON public.cobro_recordatorio (partido_id);

ALTER TABLE public.cobro_recordatorio ENABLE ROW LEVEL SECURITY;

-- Lectura: organizador dueño o jugador destinatario.
DROP POLICY IF EXISTS cobro_recordatorio_select ON public.cobro_recordatorio;
CREATE POLICY cobro_recordatorio_select
  ON public.cobro_recordatorio
  FOR SELECT
  TO authenticated
  USING (
    organizador_id = auth.uid()
    OR jugador_id = auth.uid()
  );

-- Escrituras solo vía SECURITY DEFINER (sin policies INSERT/UPDATE/DELETE para authenticated).

-- ---------------------------------------------------------------------------
-- 4) Helpers de tiempo y elegibilidad
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cobro_recordatorio_next_send_at(
  p_timezone text,
  p_hora time,
  p_from timestamptz,
  p_dias_offset integer
)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_tz text := coalesce(nullif(btrim(p_timezone), ''), 'America/Santiago');
  v_hora time := coalesce(p_hora, time '10:00');
  v_offset integer := greatest(coalesce(p_dias_offset, 0), 0);
  v_local_from timestamp;
  v_target_local timestamp;
  v_now_local timestamp;
BEGIN
  BEGIN
    v_local_from := p_from AT TIME ZONE v_tz;
    v_now_local := now() AT TIME ZONE v_tz;
  EXCEPTION
    WHEN others THEN
      v_tz := 'America/Santiago';
      v_local_from := p_from AT TIME ZONE v_tz;
      v_now_local := now() AT TIME ZONE v_tz;
  END;

  v_target_local :=
    (v_local_from::date + v_offset) + v_hora;

  -- Si el instante ya pasó, pasar al próximo slot de hora_local.
  IF (v_target_local AT TIME ZONE v_tz) <= now() THEN
    v_target_local := (v_now_local::date) + v_hora;
    IF (v_target_local AT TIME ZONE v_tz) <= now() THEN
      v_target_local := v_target_local + interval '1 day';
    END IF;
  END IF;

  RETURN v_target_local AT TIME ZONE v_tz;
END;
$$;

COMMENT ON FUNCTION public.cobro_recordatorio_next_send_at(text, time, timestamptz, integer) IS
  'Calcula next_send_at en UTC a partir de timezone + hora local + offset en días.';

CREATE OR REPLACE FUNCTION public.detalle_monto_pendiente_recordatorio(
  p_detalle_id bigint
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dp public.detalles_partido%ROWTYPE;
  v_snap numeric;
BEGIN
  SELECT * INTO v_dp
  FROM public.detalles_partido
  WHERE id = p_detalle_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF coalesce(v_dp.pagado, false) THEN
    RETURN 0;
  END IF;

  v_snap := public.snapshot_saldo_anterior_cargo(v_dp.jugador_id, v_dp.partido_id);
  IF v_snap IS NULL THEN
    RETURN CASE
      WHEN round(coalesce(v_dp.total, 0) - coalesce(v_dp.monto_pagado, 0), 2) > 0.005
      THEN round(coalesce(v_dp.total, 0) - coalesce(v_dp.monto_pagado, 0), 2)
      ELSE 0::numeric
    END;
  END IF;

  RETURN public.pendiente_fifo_detalle(
    v_snap,
    v_dp.total,
    coalesce(v_dp.monto_pagado, 0)
  );
END;
$$;

COMMENT ON FUNCTION public.detalle_monto_pendiente_recordatorio(bigint) IS
  'Monto pendiente de un detalle para decidir si el schedule sigue activo.';

CREATE OR REPLACE FUNCTION public.detalle_tiene_comprobante_en_revision(
  p_estado text,
  p_url text,
  p_validado boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    p_estado = 'en_revision'
    OR (
      p_estado IS NULL
      AND p_url IS NOT NULL
      AND coalesce(p_validado, false) = false
    );
$$;

-- ---------------------------------------------------------------------------
-- 5) Sync de un detalle (pausa por comprobante / pago / prefs / flag partido)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_cobro_recordatorio_detalle(
  p_detalle_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dp public.detalles_partido%ROWTYPE;
  v_partido public.partidos%ROWTYPE;
  v_prefs public.organizador_recordatorio_prefs%ROWTYPE;
  v_pendiente numeric;
  v_en_revision boolean;
  v_elegible boolean;
  v_existing public.cobro_recordatorio%ROWTYPE;
  v_next timestamptz;
  v_has_existing boolean;
BEGIN
  SELECT * INTO v_dp
  FROM public.detalles_partido
  WHERE id = p_detalle_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO v_partido
  FROM public.partidos
  WHERE id = v_dp.partido_id;

  IF NOT FOUND OR v_partido.organizador_id IS NULL THEN
    RETURN;
  END IF;

  SELECT * INTO v_prefs
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = v_partido.organizador_id;

  v_pendiente := public.detalle_monto_pendiente_recordatorio(v_dp.id);
  v_en_revision := public.detalle_tiene_comprobante_en_revision(
    v_dp.comprobante_estado,
    v_dp.comprobante_url,
    v_dp.comprobante_validado
  );

  v_elegible :=
    coalesce(v_partido.generar_recordatorios_cobro, false)
    AND coalesce(v_prefs.activo, false)
    AND v_pendiente > 0.005
    AND NOT v_en_revision
    AND coalesce(v_dp.comprobante_estado, '') IS DISTINCT FROM 'aprobado';

  SELECT * INTO v_existing
  FROM public.cobro_recordatorio
  WHERE detalle_partido_id = v_dp.id;
  v_has_existing := FOUND;

  IF NOT v_elegible THEN
    IF v_has_existing THEN
      UPDATE public.cobro_recordatorio
      SET
        activo = false,
        updated_at = now()
      WHERE id = v_existing.id
        AND activo = true;
    END IF;
    RETURN;
  END IF;

  -- Elegible: crear o reactivar.
  IF NOT v_has_existing THEN
    v_next := public.cobro_recordatorio_next_send_at(
      v_prefs.timezone,
      v_prefs.hora_local,
      now(),
      v_prefs.dias_primer
    );
    INSERT INTO public.cobro_recordatorio (
      detalle_partido_id,
      partido_id,
      organizador_id,
      jugador_id,
      activo,
      next_send_at
    ) VALUES (
      v_dp.id,
      v_dp.partido_id,
      v_partido.organizador_id,
      v_dp.jugador_id,
      true,
      v_next
    );
    RETURN;
  END IF;

  IF v_existing.activo THEN
    UPDATE public.cobro_recordatorio
    SET updated_at = now()
    WHERE id = v_existing.id;
    RETURN;
  END IF;

  -- Reactivación (p. ej. comprobante rechazado): próximo slot de hora_local.
  v_next := public.cobro_recordatorio_next_send_at(
    v_prefs.timezone,
    v_prefs.hora_local,
    now(),
    0
  );

  UPDATE public.cobro_recordatorio
  SET
    activo = true,
    next_send_at = v_next,
    updated_at = now()
  WHERE id = v_existing.id;
END;
$$;

COMMENT ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) IS
  'Activa/pausa el schedule de un detalle según deuda, comprobante, prefs y flag del partido.';

REVOKE ALL ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) TO service_role;

-- ---------------------------------------------------------------------------
-- 6) Trigger: pago / comprobante → sync inmediato
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_detalles_partido_sync_cobro_recordatorio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    -- CASCADE borra cobro_recordatorio; nada que hacer.
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.monto_pagado IS NOT DISTINCT FROM OLD.monto_pagado
       AND NEW.pagado IS NOT DISTINCT FROM OLD.pagado
       AND NEW.total IS NOT DISTINCT FROM OLD.total
       AND NEW.comprobante_estado IS NOT DISTINCT FROM OLD.comprobante_estado
       AND NEW.comprobante_url IS NOT DISTINCT FROM OLD.comprobante_url
       AND NEW.comprobante_validado IS NOT DISTINCT FROM OLD.comprobante_validado THEN
      RETURN NEW;
    END IF;
  END IF;

  PERFORM public.sync_cobro_recordatorio_detalle(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_detalles_partido_sync_cobro_recordatorio
  ON public.detalles_partido;
CREATE TRIGGER trg_detalles_partido_sync_cobro_recordatorio
  AFTER INSERT OR UPDATE OF
    monto_pagado,
    pagado,
    total,
    comprobante_estado,
    comprobante_url,
    comprobante_validado
  ON public.detalles_partido
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_detalles_partido_sync_cobro_recordatorio();

-- ---------------------------------------------------------------------------
-- 7) RPC: decisión por partido + alta de schedules
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generar_recordatorios_partido(
  p_partido_id bigint,
  p_generar boolean
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partido public.partidos%ROWTYPE;
  v_prefs public.organizador_recordatorio_prefs%ROWTYPE;
  v_detalle record;
  v_pendiente numeric;
  v_en_revision boolean;
  v_creados integer := 0;
  v_omitidos integer := 0;
  v_next timestamptz;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  SELECT * INTO v_partido
  FROM public.partidos
  WHERE id = p_partido_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'partido_no_encontrado' USING ERRCODE = 'P0001';
  END IF;

  IF NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  UPDATE public.partidos
  SET generar_recordatorios_cobro = coalesce(p_generar, false)
  WHERE id = p_partido_id;

  IF NOT coalesce(p_generar, false) THEN
    UPDATE public.cobro_recordatorio
    SET
      activo = false,
      updated_at = now()
    WHERE partido_id = p_partido_id
      AND activo = true;

    RETURN json_build_object(
      'ok', true,
      'partido_id', p_partido_id,
      'generar', false,
      'creados', 0,
      'desactivados', true
    );
  END IF;

  SELECT * INTO v_prefs
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = auth.uid();

  IF NOT FOUND OR NOT v_prefs.activo THEN
    RETURN json_build_object(
      'ok', true,
      'partido_id', p_partido_id,
      'generar', true,
      'creados', 0,
      'omitidos', 0,
      'prefs_activo', false,
      'mensaje', 'Preferencias de recordatorio desactivadas o inexistentes'
    );
  END IF;

  FOR v_detalle IN
    SELECT dp.*
    FROM public.detalles_partido dp
    WHERE dp.partido_id = p_partido_id
  LOOP
    v_pendiente := public.detalle_monto_pendiente_recordatorio(v_detalle.id);
    v_en_revision := public.detalle_tiene_comprobante_en_revision(
      v_detalle.comprobante_estado,
      v_detalle.comprobante_url,
      v_detalle.comprobante_validado
    );

    IF v_pendiente <= 0.005
       OR v_en_revision
       OR coalesce(v_detalle.comprobante_estado, '') = 'aprobado' THEN
      v_omitidos := v_omitidos + 1;
      PERFORM public.sync_cobro_recordatorio_detalle(v_detalle.id);
      CONTINUE;
    END IF;

    v_next := public.cobro_recordatorio_next_send_at(
      v_prefs.timezone,
      v_prefs.hora_local,
      now(),
      v_prefs.dias_primer
    );

    INSERT INTO public.cobro_recordatorio (
      detalle_partido_id,
      partido_id,
      organizador_id,
      jugador_id,
      activo,
      next_send_at
    ) VALUES (
      v_detalle.id,
      v_detalle.partido_id,
      v_partido.organizador_id,
      v_detalle.jugador_id,
      true,
      v_next
    )
    ON CONFLICT (detalle_partido_id) DO UPDATE SET
      activo = true,
      next_send_at = CASE
        WHEN cobro_recordatorio.activo THEN cobro_recordatorio.next_send_at
        ELSE EXCLUDED.next_send_at
      END,
      updated_at = now();

    v_creados := v_creados + 1;
  END LOOP;

  RETURN json_build_object(
    'ok', true,
    'partido_id', p_partido_id,
    'generar', true,
    'creados', v_creados,
    'omitidos', v_omitidos,
    'prefs_activo', true
  );
END;
$$;

COMMENT ON FUNCTION public.generar_recordatorios_partido(bigint, boolean) IS
  'Decide si el partido genera recordatorios y crea/desactiva schedules (1 por deuda).';

GRANT EXECUTE ON FUNCTION public.generar_recordatorios_partido(bigint, boolean)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 8) RPC preferencias
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_organizador_recordatorio_prefs()
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.organizador_recordatorio_prefs%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  SELECT * INTO v_row
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = auth.uid();

  IF NOT FOUND THEN
    RETURN json_build_object(
      'organizador_id', auth.uid(),
      'activo', false,
      'dias_primer', 3,
      'frecuencia_dias', 3,
      'hora_local', '10:00:00',
      'timezone', 'America/Santiago',
      'exists', false
    );
  END IF;

  RETURN json_build_object(
    'organizador_id', v_row.organizador_id,
    'activo', v_row.activo,
    'dias_primer', v_row.dias_primer,
    'frecuencia_dias', v_row.frecuencia_dias,
    'hora_local', v_row.hora_local::text,
    'timezone', v_row.timezone,
    'updated_at', v_row.updated_at,
    'exists', true
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.upsert_organizador_recordatorio_prefs(
  p_activo boolean,
  p_dias_primer integer DEFAULT 3,
  p_frecuencia_dias integer DEFAULT 3,
  p_hora_local time DEFAULT time '10:00',
  p_timezone text DEFAULT 'America/Santiago'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.organizador_recordatorio_prefs%ROWTYPE;
  v_tz text := coalesce(nullif(btrim(p_timezone), ''), 'America/Santiago');
  v_dias integer := least(greatest(coalesce(p_dias_primer, 3), 0), 90);
  v_freq integer := least(greatest(coalesce(p_frecuencia_dias, 3), 1), 90);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  INSERT INTO public.organizador_recordatorio_prefs (
    organizador_id,
    activo,
    dias_primer,
    frecuencia_dias,
    hora_local,
    timezone,
    updated_at
  ) VALUES (
    auth.uid(),
    coalesce(p_activo, false),
    v_dias,
    v_freq,
    coalesce(p_hora_local, time '10:00'),
    v_tz,
    now()
  )
  ON CONFLICT (organizador_id) DO UPDATE SET
    activo = EXCLUDED.activo,
    dias_primer = EXCLUDED.dias_primer,
    frecuencia_dias = EXCLUDED.frecuencia_dias,
    hora_local = EXCLUDED.hora_local,
    timezone = EXCLUDED.timezone,
    updated_at = now()
  RETURNING * INTO v_row;

  -- Al desactivar globalmente: pausar todos los schedules del organizador.
  IF NOT v_row.activo THEN
    UPDATE public.cobro_recordatorio
    SET
      activo = false,
      updated_at = now()
    WHERE organizador_id = auth.uid()
      AND activo = true;
  END IF;

  RETURN json_build_object(
    'ok', true,
    'organizador_id', v_row.organizador_id,
    'activo', v_row.activo,
    'dias_primer', v_row.dias_primer,
    'frecuencia_dias', v_row.frecuencia_dias,
    'hora_local', v_row.hora_local::text,
    'timezone', v_row.timezone,
    'updated_at', v_row.updated_at
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_organizador_recordatorio_prefs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_organizador_recordatorio_prefs(boolean, integer, integer, time, text)
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.detalle_monto_pendiente_recordatorio(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.cobro_recordatorio_next_send_at(text, time, timestamptz, integer)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 9) Cleanup al borrar cuenta
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_user_account_data(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id required';
  END IF;

  DELETE FROM public.cobro_recordatorio
  WHERE organizador_id = p_user_id
     OR jugador_id = p_user_id;

  DELETE FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = p_user_id;

  DELETE FROM public.asignaciones_costo WHERE jugador_id = p_user_id;

  DELETE FROM public.convocatoria_jugadores WHERE jugador_id = p_user_id;

  IF to_regclass('public.comprobantes_pago') IS NOT NULL THEN
    DELETE FROM public.comprobantes_pago
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  IF to_regclass('public.organizador_jugadores') IS NOT NULL THEN
    DELETE FROM public.organizador_jugadores
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  -- Compat con typo histórico de migración 073.
  IF to_regclass('public.organizador_jugador') IS NOT NULL THEN
    DELETE FROM public.organizador_jugador
    WHERE jugador_id = p_user_id OR organizador_id = p_user_id;
  END IF;

  DELETE FROM public.saldos_historicos WHERE jugador_id = p_user_id;

  DELETE FROM public.detalles_partido WHERE jugador_id = p_user_id;

  DELETE FROM public.partidos WHERE organizador_id = p_user_id;

  IF to_regclass('public.recintos') IS NOT NULL THEN
    DELETE FROM public.recintos WHERE organizador_id = p_user_id;
  END IF;

  DELETE FROM public.profiles WHERE id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_user_account_data(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.purge_user_account_data(uuid) TO service_role;

COMMENT ON FUNCTION public.purge_user_account_data(uuid) IS
  'Service-role only. Purges app data (incl. recordatorios) before auth.admin.deleteUser.';
