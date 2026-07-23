-- 077: ETAPA 4 FASE 4 — fix elegibilidad NULL + flag generar con prefs off.
--
-- Prioridad 1: NULL en comprobante_estado no debe propagar NULL a sigue_elegible.
--   Semántica: NULL = sin comprobante (no "en revisión").
-- Prioridad 2: generar_recordatorios_partido no deja generar_recordatorios_cobro=true
--   si las prefs globales están apagadas.
-- Prioridad 3 (Hallazgo B): documentado como V1 — prefs off→on no reanuda schedules
--   automáticamente; requiere sync/detalle. V2: reactivar al habilitar prefs.

-- ---------------------------------------------------------------------------
-- 1) comprobante en revisión: booleano estricto (nunca NULL)
-- ---------------------------------------------------------------------------
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
    coalesce(p_estado IS NOT DISTINCT FROM 'en_revision', false)
    OR (
      p_estado IS NULL
      AND p_url IS NOT NULL
      AND coalesce(p_validado, false) = false
    );
$$;

COMMENT ON FUNCTION public.detalle_tiene_comprobante_en_revision(text, text, boolean) IS
  'True si hay comprobante pendiente de revisión. NULL estado + sin URL = false (sin comprobante).';

-- ---------------------------------------------------------------------------
-- 2) sigue_elegible: defensa en profundidad (boolean never null)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cobro_recordatorio_sigue_elegible(
  p_detalle_id bigint
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dp public.detalles_partido%ROWTYPE;
  v_partido public.partidos%ROWTYPE;
  v_prefs public.organizador_recordatorio_prefs%ROWTYPE;
  v_pendiente numeric;
  v_en_revision boolean;
BEGIN
  SELECT * INTO v_dp FROM public.detalles_partido WHERE id = p_detalle_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT * INTO v_partido FROM public.partidos WHERE id = v_dp.partido_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  SELECT * INTO v_prefs
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = v_partido.organizador_id;

  v_pendiente := public.detalle_monto_pendiente_recordatorio(v_dp.id);
  v_en_revision := coalesce(
    public.detalle_tiene_comprobante_en_revision(
      v_dp.comprobante_estado,
      v_dp.comprobante_url,
      v_dp.comprobante_validado
    ),
    false
  );

  RETURN coalesce(v_partido.generar_recordatorios_cobro, false)
    AND coalesce(v_prefs.activo, false)
    AND coalesce(v_pendiente, 0) > 0.005
    AND NOT v_en_revision
    AND coalesce(v_dp.comprobante_estado, '') IS DISTINCT FROM 'aprobado';
END;
$$;

COMMENT ON FUNCTION public.cobro_recordatorio_sigue_elegible(bigint) IS
  'Elegibilidad para enviar recordatorio. Siempre true/false (nunca NULL).';

-- ---------------------------------------------------------------------------
-- 3) generar: prefs off → no flag true + respuesta generar=false
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

  -- Desactivar explícitamente.
  IF NOT coalesce(p_generar, false) THEN
    UPDATE public.partidos
    SET generar_recordatorios_cobro = false
    WHERE id = p_partido_id;

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

  -- Prefs apagadas/inexistentes: no marcar flag del partido ni crear schedules.
  IF NOT FOUND OR NOT v_prefs.activo THEN
    UPDATE public.partidos
    SET generar_recordatorios_cobro = false
    WHERE id = p_partido_id;

    RETURN json_build_object(
      'ok', true,
      'partido_id', p_partido_id,
      'generar', false,
      'creados', 0,
      'omitidos', 0,
      'prefs_activo', false,
      'mensaje', 'Preferencias de recordatorio desactivadas o inexistentes'
    );
  END IF;

  UPDATE public.partidos
  SET generar_recordatorios_cobro = true
  WHERE id = p_partido_id;

  FOR v_detalle IN
    SELECT dp.*
    FROM public.detalles_partido dp
    WHERE dp.partido_id = p_partido_id
  LOOP
    v_pendiente := public.detalle_monto_pendiente_recordatorio(v_detalle.id);
    v_en_revision := coalesce(
      public.detalle_tiene_comprobante_en_revision(
        v_detalle.comprobante_estado,
        v_detalle.comprobante_url,
        v_detalle.comprobante_validado
      ),
      false
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
  'Activa/desactiva recordatorios del partido. Si prefs globales off, generar=false y flag partido=false.';

-- ---------------------------------------------------------------------------
-- 4) Hallazgo B (V1): documentar — no reanudar al reactivar prefs
-- ---------------------------------------------------------------------------
COMMENT ON FUNCTION public.upsert_organizador_recordatorio_prefs(
  boolean, integer, integer, time, text
) IS
  'Upsert prefs. activo=false pausa schedules. V1: activo=true NO reanuda schedules '
  'pausados (requiere sync/detalle). V2: reactivar elegibles al habilitar prefs.';
