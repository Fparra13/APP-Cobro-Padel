-- 076: ultimo_delivery_id para trazabilidad de intentos (sin tabla de auditoría aún).
-- V2 futuro: cobro_recordatorio_delivery (attempt_number, status, fcm_message_id).

ALTER TABLE public.cobro_recordatorio
  ADD COLUMN IF NOT EXISTS ultimo_delivery_id uuid;

COMMENT ON COLUMN public.cobro_recordatorio.ultimo_delivery_id IS
  'UUID del último INTENTO de entrega confirmado por el worker (FCM OK a nivel API). '
  'No garantiza que el usuario haya visto la notificación; FCM es at-least-once externo.';

DROP FUNCTION IF EXISTS public.completar_cobro_recordatorio_envio(bigint);

CREATE OR REPLACE FUNCTION public.completar_cobro_recordatorio_envio(
  p_id bigint,
  p_delivery_id uuid DEFAULT NULL
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
    ultimo_delivery_id = coalesce(p_delivery_id, ultimo_delivery_id),
    next_send_at = v_next,
    fail_count = 0,
    claim_until = null,
    updated_at = now()
  WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.completar_cobro_recordatorio_envio(bigint, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.completar_cobro_recordatorio_envio(bigint, uuid) TO service_role;
