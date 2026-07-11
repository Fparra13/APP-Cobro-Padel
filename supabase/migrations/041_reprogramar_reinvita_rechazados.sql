-- Al reprogramar, todos los titulares vuelven a invitado y deben confirmar de nuevo.

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
