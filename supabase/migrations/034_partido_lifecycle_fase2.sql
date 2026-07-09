-- Fase 2 ciclo de vida: cancelado, resuelto_en, reprogramar y expiración servidor.

ALTER TABLE public.partidos
  ADD COLUMN IF NOT EXISTS resuelto_en timestamptz,
  ADD COLUMN IF NOT EXISTS partido_origen_id bigint REFERENCES public.partidos(id);

CREATE INDEX IF NOT EXISTS idx_partidos_resuelto_en
  ON public.partidos(resuelto_en)
  WHERE resuelto_en IS NOT NULL;

-- Margen tras la hora del partido (debe coincidir con la app: 6 h).
CREATE OR REPLACE FUNCTION public.partido_convocatoria_expirada(p_fecha timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT p_fecha <= (now() - interval '6 hours');
$$;

-- Cancelar convocatoria sin borrar el registro (auditoría).
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

  IF v_org IS NOT NULL AND v_org <> auth.uid() THEN
    RAISE EXCEPTION 'No eres el organizador de este partido';
  END IF;

  UPDATE public.partidos
  SET estado = 'cancelado',
      resuelto_en = now()
  WHERE id = p_partido_id;

  DELETE FROM public.convocatoria_jugadores
  WHERE partido_id = p_partido_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancelar_convocatoria_organizador(bigint) TO authenticated;

-- Reprogramar: nueva fecha futura, reabre convocatoria y plazos de respuesta.
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

  IF v_org IS NOT NULL AND v_org <> auth.uid() THEN
    RAISE EXCEPTION 'No eres el organizador de este partido';
  END IF;

  v_horas := coalesce(v_horas, 24);
  v_limite := now() + make_interval(hours => v_horas);

  UPDATE public.partidos
  SET fecha = p_nueva_fecha,
      estado = 'organizando',
      resuelto_en = NULL
  WHERE id = p_partido_id;

  UPDATE public.convocatoria_jugadores
  SET tiempo_limite = v_limite,
      notificado_vencimiento = false,
      recordatorio_plazo_enviado = false
  WHERE partido_id = p_partido_id
    AND es_suplente = false
    AND estado_confirmacion = 'invitado';
END;
$$;

GRANT EXECUTE ON FUNCTION public.reprogramar_convocatoria_organizador(bigint, timestamptz) TO authenticated;

-- Marca no_respondio en convocatorias cuya hora ya pasó (cron / edge).
CREATE OR REPLACE FUNCTION public.expirar_convocatorias_pendientes()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  UPDATE public.convocatoria_jugadores cj
  SET estado_confirmacion = 'no_respondio'
  FROM public.partidos p
  WHERE cj.partido_id = p.id
    AND p.estado IN ('organizando', 'confirmado')
    AND public.partido_convocatoria_expirada(p.fecha)
    AND cj.es_suplente = false
    AND cj.estado_confirmacion = 'invitado';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- Solo service_role / cron; no exponer a authenticated por defecto.
REVOKE ALL ON FUNCTION public.expirar_convocatorias_pendientes() FROM PUBLIC;

-- Opcional: programar cada 15 min si pg_cron está habilitado en el proyecto.
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname = 'matchpay_expirar_convocatorias';

    PERFORM cron.schedule(
      'matchpay_expirar_convocatorias',
      '*/15 * * * *',
      $cron$SELECT public.expirar_convocatorias_pendientes();$cron$
    );
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$do$;
