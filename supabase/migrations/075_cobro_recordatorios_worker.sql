-- 075: Worker de recordatorios — claim/lease, backoff y RPCs service_role.
-- Idempotencia: FOR UPDATE SKIP LOCKED + claim_until (lease 5 min).
-- Backoff temporal FCM: 15m → 1h → 6h → frecuencia normal (fail_count).

ALTER TABLE public.cobro_recordatorio
  ADD COLUMN IF NOT EXISTS claim_until timestamptz;

ALTER TABLE public.cobro_recordatorio
  ADD COLUMN IF NOT EXISTS fail_count integer NOT NULL DEFAULT 0
    CHECK (fail_count >= 0 AND fail_count <= 100);

COMMENT ON COLUMN public.cobro_recordatorio.claim_until IS
  'Lease del worker. NULL/pasado = disponible. Evita envíos duplicados concurrentes.';
COMMENT ON COLUMN public.cobro_recordatorio.fail_count IS
  'Fallos FCM temporales consecutivos. 0 tras envío OK. Backoff: 15m/1h/6h/frecuencia.';

CREATE INDEX IF NOT EXISTS idx_cobro_recordatorio_claim
  ON public.cobro_recordatorio (claim_until)
  WHERE activo = true;

-- ---------------------------------------------------------------------------
-- Claim batch (SKIP LOCKED + lease)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_cobro_recordatorios_due(
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id bigint,
  detalle_partido_id bigint,
  partido_id bigint,
  organizador_id uuid,
  jugador_id uuid,
  next_send_at timestamptz,
  ultimo_envio timestamptz,
  fail_count integer,
  frecuencia_dias integer,
  timezone text,
  hora_local time,
  pendiente numeric,
  fcm_token text,
  preferred_locale text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
BEGIN
  RETURN QUERY
  WITH picked AS (
    SELECT cr.id
    FROM public.cobro_recordatorio cr
    WHERE cr.activo = true
      AND cr.next_send_at <= now()
      AND (cr.claim_until IS NULL OR cr.claim_until < now())
    ORDER BY cr.next_send_at ASC
    FOR UPDATE OF cr SKIP LOCKED
    LIMIT v_limit
  ),
  claimed AS (
    UPDATE public.cobro_recordatorio cr
    SET
      claim_until = now() + interval '5 minutes',
      updated_at = now()
    FROM picked
    WHERE cr.id = picked.id
    RETURNING
      cr.id,
      cr.detalle_partido_id,
      cr.partido_id,
      cr.organizador_id,
      cr.jugador_id,
      cr.next_send_at,
      cr.ultimo_envio,
      cr.fail_count
  )
  SELECT
    c.id,
    c.detalle_partido_id,
    c.partido_id,
    c.organizador_id,
    c.jugador_id,
    c.next_send_at,
    c.ultimo_envio,
    c.fail_count,
    coalesce(prefs.frecuencia_dias, 3)::integer AS frecuencia_dias,
    coalesce(prefs.timezone, 'America/Santiago') AS timezone,
    coalesce(prefs.hora_local, time '10:00') AS hora_local,
    public.detalle_monto_pendiente_recordatorio(c.detalle_partido_id) AS pendiente,
    pr.fcm_token,
    coalesce(nullif(btrim(pr.preferred_locale), ''), 'es') AS preferred_locale
  FROM claimed c
  LEFT JOIN public.organizador_recordatorio_prefs prefs
    ON prefs.organizador_id = c.organizador_id
  LEFT JOIN public.profiles pr
    ON pr.id = c.jugador_id;
END;
$$;

COMMENT ON FUNCTION public.claim_cobro_recordatorios_due(integer) IS
  'Lease atómico de recordatorios vencidos (SKIP LOCKED). Solo service_role.';

-- ---------------------------------------------------------------------------
-- Elegibilidad
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
  v_en_revision := public.detalle_tiene_comprobante_en_revision(
    v_dp.comprobante_estado,
    v_dp.comprobante_url,
    v_dp.comprobante_validado
  );

  RETURN coalesce(v_partido.generar_recordatorios_cobro, false)
    AND coalesce(v_prefs.activo, false)
    AND v_pendiente > 0.005
    AND NOT v_en_revision
    AND coalesce(v_dp.comprobante_estado, '') IS DISTINCT FROM 'aprobado';
END;
$$;

-- ---------------------------------------------------------------------------
-- Éxito: solo tras FCM OK — avanza schedule y resetea backoff
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.completar_cobro_recordatorio_envio(
  p_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.cobro_recordatorio%ROWTYPE;
  v_prefs public.organizador_recordatorio_prefs%ROWTYPE;
  v_next timestamptz;
BEGIN
  SELECT * INTO v_row
  FROM public.cobro_recordatorio
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO v_prefs
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = v_row.organizador_id;

  v_next := public.cobro_recordatorio_next_send_at(
    coalesce(v_prefs.timezone, 'America/Santiago'),
    coalesce(v_prefs.hora_local, time '10:00'),
    now(),
    coalesce(v_prefs.frecuencia_dias, 3)
  );

  UPDATE public.cobro_recordatorio
  SET
    ultimo_envio = now(),
    next_send_at = v_next,
    fail_count = 0,
    claim_until = null,
    updated_at = now()
  WHERE id = p_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Fallo temporal FCM: backoff 15m → 1h → 6h → frecuencia
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reintentar_cobro_recordatorio_backoff(
  p_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.cobro_recordatorio%ROWTYPE;
  v_prefs public.organizador_recordatorio_prefs%ROWTYPE;
  v_new_fail integer;
  v_next timestamptz;
  v_delay text;
BEGIN
  SELECT * INTO v_row
  FROM public.cobro_recordatorio
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_row.activo THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_found_or_inactive');
  END IF;

  SELECT * INTO v_prefs
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = v_row.organizador_id;

  v_new_fail := least(coalesce(v_row.fail_count, 0) + 1, 100);

  IF v_new_fail = 1 THEN
    v_next := now() + interval '15 minutes';
    v_delay := '15m';
  ELSIF v_new_fail = 2 THEN
    v_next := now() + interval '1 hour';
    v_delay := '1h';
  ELSIF v_new_fail = 3 THEN
    v_next := now() + interval '6 hours';
    v_delay := '6h';
  ELSE
    v_next := public.cobro_recordatorio_next_send_at(
      coalesce(v_prefs.timezone, 'America/Santiago'),
      coalesce(v_prefs.hora_local, time '10:00'),
      now(),
      coalesce(v_prefs.frecuencia_dias, 3)
    );
    v_delay := 'frecuencia';
  END IF;

  UPDATE public.cobro_recordatorio
  SET
    fail_count = v_new_fail,
    next_send_at = v_next,
    claim_until = null,
    updated_at = now()
  WHERE id = p_id;

  RETURN jsonb_build_object(
    'ok', true,
    'fail_count', v_new_fail,
    'delay', v_delay,
    'next_send_at', v_next
  );
END;
$$;

-- ---------------------------------------------------------------------------
-- Token inválido / ausente: limpiar token + diferir a frecuencia (no martillar)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.diferir_cobro_recordatorio_sin_token(
  p_id bigint,
  p_clear_token boolean DEFAULT true
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.cobro_recordatorio%ROWTYPE;
  v_prefs public.organizador_recordatorio_prefs%ROWTYPE;
  v_next timestamptz;
BEGIN
  SELECT * INTO v_row
  FROM public.cobro_recordatorio
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF coalesce(p_clear_token, true) THEN
    UPDATE public.profiles
    SET fcm_token = null
    WHERE id = v_row.jugador_id
      AND fcm_token IS NOT NULL;
  END IF;

  SELECT * INTO v_prefs
  FROM public.organizador_recordatorio_prefs
  WHERE organizador_id = v_row.organizador_id;

  v_next := public.cobro_recordatorio_next_send_at(
    coalesce(v_prefs.timezone, 'America/Santiago'),
    coalesce(v_prefs.hora_local, time '10:00'),
    now(),
    coalesce(v_prefs.frecuencia_dias, 3)
  );

  -- No incrementa fail_count de red: es un problema de token, no de FCM transient.
  UPDATE public.cobro_recordatorio
  SET
    next_send_at = v_next,
    claim_until = null,
    updated_at = now()
  WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.liberar_cobro_recordatorio_ineligible(
  p_id bigint
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.cobro_recordatorio
  SET
    activo = false,
    claim_until = null,
    updated_at = now()
  WHERE id = p_id;
END;
$$;

-- Grants: solo service_role
REVOKE ALL ON FUNCTION public.claim_cobro_recordatorios_due(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_cobro_recordatorios_due(integer) FROM anon;
REVOKE ALL ON FUNCTION public.claim_cobro_recordatorios_due(integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.claim_cobro_recordatorios_due(integer) TO service_role;

REVOKE ALL ON FUNCTION public.cobro_recordatorio_sigue_elegible(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cobro_recordatorio_sigue_elegible(bigint) TO service_role;

REVOKE ALL ON FUNCTION public.completar_cobro_recordatorio_envio(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.completar_cobro_recordatorio_envio(bigint) TO service_role;

REVOKE ALL ON FUNCTION public.reintentar_cobro_recordatorio_backoff(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reintentar_cobro_recordatorio_backoff(bigint) TO service_role;

REVOKE ALL ON FUNCTION public.diferir_cobro_recordatorio_sin_token(bigint, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.diferir_cobro_recordatorio_sin_token(bigint, boolean) TO service_role;

REVOKE ALL ON FUNCTION public.liberar_cobro_recordatorio_ineligible(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.liberar_cobro_recordatorio_ineligible(bigint) TO service_role;

-- ---------------------------------------------------------------------------
-- pg_cron cada 15 min (pg_cron/pg_net ya deben existir en el proyecto)
-- ---------------------------------------------------------------------------
-- Nota: no ejecutar CREATE EXTENSION aquí (puede fallar por grants en hosted).

DO $do$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'cobro_reminders: pg_cron no disponible';
    RETURN;
  END IF;

  BEGIN
    SELECT ds.decrypted_secret INTO v_url
    FROM vault.decrypted_secrets ds
    WHERE ds.name = 'project_url'
    LIMIT 1;

    SELECT ds.decrypted_secret INTO v_key
    FROM vault.decrypted_secrets ds
    WHERE ds.name = 'reminders_cron_secret'
    LIMIT 1;

    IF v_key IS NULL OR v_key = '' THEN
      SELECT ds.decrypted_secret INTO v_key
      FROM vault.decrypted_secrets ds
      WHERE ds.name = 'purge_cron_secret'
      LIMIT 1;
    END IF;

    IF v_key IS NULL OR v_key = '' THEN
      SELECT ds.decrypted_secret INTO v_key
      FROM vault.decrypted_secrets ds
      WHERE ds.name = 'service_role_key'
      LIMIT 1;
    END IF;
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'cobro_reminders: vault no disponible';
      RETURN;
    WHEN OTHERS THEN
      RAISE NOTICE 'cobro_reminders: no se pudo leer vault (%)', SQLERRM;
      RETURN;
  END;

  IF v_url IS NULL OR v_url = '' THEN
    v_url := 'https://efcfxfcypdsrmbultnkl.supabase.co';
  END IF;

  IF v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE
      'cobro_reminders: crear vault secret reminders_cron_secret (o service_role_key)';
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'kloovi_process_cobro_reminders';

  PERFORM cron.schedule(
    'kloovi_process_cobro_reminders',
    '*/15 * * * *',
    format(
      $cron$
      SELECT net.http_post(
        url := %L || '/functions/v1/process-cobro-reminders',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || %L
        ),
        body := '{}'::jsonb
      );
      $cron$,
      rtrim(v_url, '/'),
      v_key
    )
  );
END;
$do$;
