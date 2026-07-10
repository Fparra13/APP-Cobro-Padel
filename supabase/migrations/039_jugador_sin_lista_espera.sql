-- El jugador no ve convocatorias mientras está en lista de espera (es_suplente).
-- Solo aparece cuando se promueve a titular invitado.

CREATE OR REPLACE FUNCTION public.get_mis_convocatorias_jugador()
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
    WHERE p.estado IN ('organizando', 'confirmado')
      AND cj.es_suplente = false
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
    ORDER BY p.fecha ASC
  ) t;

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_mi_convocatoria_jugador(p_partido_id bigint)
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
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN NULL;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  SELECT row_to_json(t)
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
    WHERE cj.partido_id = p_partido_id
      AND cj.es_suplente = false
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
    LIMIT 1
  ) t;

  RETURN result;
END;
$$;
