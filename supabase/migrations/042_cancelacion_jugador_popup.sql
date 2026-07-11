-- Cancelación: conservar roster para aviso in-app al jugador confirmado.

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
END;
$$;

-- Partidos cancelados donde el jugador era titular confirmado (popup in-app).
CREATE OR REPLACE FUNCTION public.get_cancelaciones_jugador()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
  result json;
BEGIN
  user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  IF auth.uid() IS NULL THEN
    RETURN '[]'::json;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json)
  INTO result
  FROM (
    SELECT
      cj.id,
      cj.partido_id,
      cj.jugador_id,
      cj.estado_confirmacion,
      cj.es_suplente,
      cj.orden_espera,
      cj.tiempo_limite,
      cj.notificado_vencimiento,
      row_to_json(p) AS partidos
    FROM public.convocatoria_jugadores cj
    INNER JOIN public.partidos p ON p.id = cj.partido_id
    INNER JOIN public.profiles pr ON pr.id = cj.jugador_id
    WHERE p.estado = 'cancelado'
      AND cj.es_suplente = false
      AND cj.estado_confirmacion = 'confirmado'
      AND (
        cj.jugador_id = auth.uid()
        OR (
          user_email <> ''
          AND (
            lower(trim(coalesce(pr.email, ''))) = user_email
            OR lower(trim(coalesce(pr.telefono, ''))) = user_email
          )
        )
      )
    ORDER BY coalesce(p.resuelto_en, p.fecha) DESC
  ) t;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cancelaciones_jugador() TO authenticated;
