-- P2 hardening (pre–Google Play): DEFINER grants, cron via Vault, search_path.
-- No cambios de lógica de negocio ni contratos Flutter.

-- =============================================================================
-- 1) SECURITY DEFINER — mínimo privilegio (helpers / worker internos)
-- =============================================================================
-- Flutter no llama estas 4 funciones (.rpc). Solo SQL interno / cron / triggers.

-- expirar_convocatorias_pendientes: worker SQL (cron). Sin auth.uid().
REVOKE ALL ON FUNCTION public.expirar_convocatorias_pendientes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expirar_convocatorias_pendientes() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expirar_convocatorias_pendientes() TO service_role;

-- sync_cobro_recordatorio_detalle: trigger + generar_recordatorios_partido (DEFINER).
REVOKE ALL ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sync_cobro_recordatorio_detalle(bigint) TO service_role;

-- saldo_anterior_vivo_partido: helper legacy sin callers actuales en RPCs vivas.
REVOKE ALL ON FUNCTION public.saldo_anterior_vivo_partido(uuid, bigint, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.saldo_anterior_vivo_partido(uuid, bigint, timestamptz) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.saldo_anterior_vivo_partido(uuid, bigint, timestamptz) TO service_role;

-- generar_codigo_grupo_unico: solo obtener_mi_codigo_grupo / regenerar_mi_codigo_grupo (DEFINER).
REVOKE ALL ON FUNCTION public.generar_codigo_grupo_unico() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generar_codigo_grupo_unico() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.generar_codigo_grupo_unico() TO service_role;

-- =============================================================================
-- 2) pg_cron: dejar de embeber Bearer; leer Vault en cada ejecución
-- =============================================================================
-- Riesgo: cron.job.command contenía el token en claro.
-- Compatibilidad: mismos secrets Vault ya existentes (project_url, purge_cron_secret,
-- service_role_key). Edge sigue aceptando PURGE_CRON_SECRET / service_role.

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'p2: pg_cron no disponible';
    RETURN;
  END IF;

  -- Purge comprobantes (diario 06:00 UTC)
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'kloovi_purge_comprobantes';

  PERFORM cron.schedule(
    'kloovi_purge_comprobantes',
    '0 6 * * *',
    $cron$
    SELECT net.http_post(
      url := rtrim(
        coalesce(
          (SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'project_url' LIMIT 1),
          'https://efcfxfcypdsrmbultnkl.supabase.co'
        ),
        '/'
      ) || '/functions/v1/purge-comprobantes',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(
          nullif((SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'purge_cron_secret' LIMIT 1), ''),
          nullif((SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'service_role_key' LIMIT 1), '')
        )
      ),
      body := '{}'::jsonb
    );
    $cron$
  );

  -- Recordatorios de aportes (cada 15 min)
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'kloovi_process_cobro_reminders';

  PERFORM cron.schedule(
    'kloovi_process_cobro_reminders',
    '*/15 * * * *',
    $cron$
    SELECT net.http_post(
      url := rtrim(
        coalesce(
          (SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'project_url' LIMIT 1),
          'https://efcfxfcypdsrmbultnkl.supabase.co'
        ),
        '/'
      ) || '/functions/v1/process-cobro-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(
          nullif((SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'reminders_cron_secret' LIMIT 1), ''),
          nullif((SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'purge_cron_secret' LIMIT 1), ''),
          nullif((SELECT ds.decrypted_secret FROM vault.decrypted_secrets ds WHERE ds.name = 'service_role_key' LIMIT 1), '')
        )
      ),
      body := '{}'::jsonb
    );
    $cron$
  );

  -- Expirar convocatorias pendientes (cada 15 min, SQL directo — sin HTTP)
  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname IN (
    'kloovi_expirar_convocatorias',
    'matchpay_expirar_convocatorias'
  );

  PERFORM cron.schedule(
    'kloovi_expirar_convocatorias',
    '*/15 * * * *',
    $cron$SELECT public.expirar_convocatorias_pendientes();$cron$
  );
END;
$do$;

-- =============================================================================
-- 3) Advisor: function_search_path_mutable (bajo riesgo, mismo cuerpo)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.partido_convocatoria_expirada(p_fecha timestamp with time zone)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $function$
  SELECT p_fecha <= now();
$function$;

CREATE OR REPLACE FUNCTION public.pendiente_neto_detalle(
  p_saldo_anterior numeric,
  p_cargo numeric,
  p_monto_pagado numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.pendiente_fifo_detalle(
  p_saldo_anterior numeric,
  p_cargo numeric,
  p_monto_pagado numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN coalesce(p_saldo_anterior, 0) < -0.005 THEN
      public.pendiente_neto_detalle(p_saldo_anterior, p_cargo, p_monto_pagado)
    ELSE
      CASE
        WHEN round(coalesce(p_cargo, 0) - coalesce(p_monto_pagado, 0), 2) > 0.005
        THEN round(coalesce(p_cargo, 0) - coalesce(p_monto_pagado, 0), 2)
        ELSE 0::numeric
      END
  END;
$function$;

CREATE OR REPLACE FUNCTION public.detalle_tiene_comprobante_en_revision(
  p_estado text,
  p_url text,
  p_validado boolean
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  SELECT
    coalesce(p_estado IS NOT DISTINCT FROM 'en_revision', false)
    OR (
      p_estado IS NULL
      AND p_url IS NOT NULL
      AND coalesce(p_validado, false) = false
    );
$function$;
