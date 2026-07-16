-- 069: Retención 14 días de comprobantes (pago + gastos) en Storage.
-- Edge Function `purge-comprobantes` + pg_cron diario.

CREATE OR REPLACE FUNCTION public.listar_comprobantes_storage_expirados(
  p_dias integer DEFAULT 14
)
RETURNS TABLE(storage_path text, created_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, storage
AS $$
  SELECT o.name::text AS storage_path, o.created_at
  FROM storage.objects o
  WHERE o.bucket_id = 'comprobantes'
    AND o.created_at < (now() - make_interval(days => greatest(p_dias, 1)))
  ORDER BY o.created_at ASC
  LIMIT 500;
$$;

COMMENT ON FUNCTION public.listar_comprobantes_storage_expirados(integer) IS
  'Paths en bucket comprobantes más antiguos que p_dias (service_role / edge).';

CREATE OR REPLACE FUNCTION public.limpiar_refs_comprobantes(p_paths text[])
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_detalles integer := 0;
  v_cancha integer := 0;
  v_pelotas integer := 0;
  v_costos integer := 0;
BEGIN
  IF p_paths IS NULL OR cardinality(p_paths) = 0 THEN
    RETURN json_build_object(
      'detalles', 0,
      'cancha', 0,
      'pelotas', 0,
      'costos', 0
    );
  END IF;

  UPDATE public.detalles_partido
  SET comprobante_url = null
  WHERE comprobante_url = ANY (p_paths);
  GET DIAGNOSTICS v_detalles = ROW_COUNT;

  UPDATE public.partidos
  SET comprobante_cancha_url = null
  WHERE comprobante_cancha_url = ANY (p_paths);
  GET DIAGNOSTICS v_cancha = ROW_COUNT;

  UPDATE public.partidos
  SET comprobante_pelotas_url = null
  WHERE comprobante_pelotas_url = ANY (p_paths);
  GET DIAGNOSTICS v_pelotas = ROW_COUNT;

  UPDATE public.costos_variables
  SET comprobante_url = null
  WHERE comprobante_url = ANY (p_paths);
  GET DIAGNOSTICS v_costos = ROW_COUNT;

  RETURN json_build_object(
    'detalles', v_detalles,
    'cancha', v_cancha,
    'pelotas', v_pelotas,
    'costos', v_costos
  );
END;
$$;

COMMENT ON FUNCTION public.limpiar_refs_comprobantes(text[]) IS
  'Anula paths de comprobantes en DB tras borrar Storage (service_role / edge).';

REVOKE ALL ON FUNCTION public.listar_comprobantes_storage_expirados(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.listar_comprobantes_storage_expirados(integer) FROM anon;
REVOKE ALL ON FUNCTION public.listar_comprobantes_storage_expirados(integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.listar_comprobantes_storage_expirados(integer) TO service_role;

REVOKE ALL ON FUNCTION public.limpiar_refs_comprobantes(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.limpiar_refs_comprobantes(text[]) FROM anon;
REVOKE ALL ON FUNCTION public.limpiar_refs_comprobantes(text[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.limpiar_refs_comprobantes(text[]) TO service_role;

-- Cron diario 06:00 UTC si hay vault + pg_cron + pg_net.
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $do$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE 'purge_comprobantes: pg_cron no disponible';
    RETURN;
  END IF;

  BEGIN
    SELECT ds.decrypted_secret INTO v_url
    FROM vault.decrypted_secrets ds
    WHERE ds.name = 'project_url'
    LIMIT 1;
    -- Prefer dedicated cron secret; fallback service_role_key.
    SELECT ds.decrypted_secret INTO v_key
    FROM vault.decrypted_secrets ds
    WHERE ds.name = 'purge_cron_secret'
    LIMIT 1;
    IF v_key IS NULL OR v_key = '' THEN
      SELECT ds.decrypted_secret INTO v_key
      FROM vault.decrypted_secrets ds
      WHERE ds.name = 'service_role_key'
      LIMIT 1;
    END IF;
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'purge_comprobantes: vault no disponible';
      RETURN;
    WHEN OTHERS THEN
      RAISE NOTICE 'purge_comprobantes: no se pudo leer vault (%)', SQLERRM;
      RETURN;
  END;

  IF v_url IS NULL OR v_url = '' THEN
    v_url := 'https://efcfxfcypdsrmbultnkl.supabase.co';
  END IF;

  IF v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE
      'purge_comprobantes: crear vault secret purge_cron_secret (o service_role_key) y Edge secret PURGE_CRON_SECRET';
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid)
  FROM cron.job
  WHERE jobname = 'kloovi_purge_comprobantes';

  PERFORM cron.schedule(
    'kloovi_purge_comprobantes',
    '0 6 * * *',
    format(
      $cron$
      SELECT net.http_post(
        url := %L || '/functions/v1/purge-comprobantes',
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
