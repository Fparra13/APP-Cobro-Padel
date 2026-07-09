-- Roster de convocatoria visible para jugadores invitados (sin ser organizador).

CREATE OR REPLACE FUNCTION public.get_convocatoria_roster_jugador(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
  es_miembro boolean;
  result json;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN NULL;
  END IF;

  user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));

  PERFORM public.relink_convocatorias_por_email();

  SELECT EXISTS (
    SELECT 1
    FROM public.convocatoria_jugadores cj
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
  ) INTO es_miembro;

  IF NOT es_miembro THEN
    RETURN NULL;
  END IF;

  SELECT json_build_object(
    'confirmados',
    (
      SELECT count(*)::int
      FROM public.convocatoria_jugadores cj
      WHERE cj.partido_id = p_partido_id
        AND cj.es_suplente = false
        AND cj.estado_confirmacion = 'confirmado'
    ),
    'pendientes',
    (
      SELECT count(*)::int
      FROM public.convocatoria_jugadores cj
      WHERE cj.partido_id = p_partido_id
        AND cj.es_suplente = false
        AND cj.estado_confirmacion = 'invitado'
    ),
    'titulares',
    coalesce(
      (
        SELECT json_agg(
          json_build_object(
            'jugador_id', cj.jugador_id,
            'nombre', pr.nombre,
            'foto_url', pr.foto_url,
            'estado_confirmacion', cj.estado_confirmacion,
            'es_suplente', cj.es_suplente
          )
          ORDER BY
            CASE cj.estado_confirmacion
              WHEN 'confirmado' THEN 0
              WHEN 'invitado' THEN 1
              ELSE 2
            END,
            pr.nombre
        )
        FROM public.convocatoria_jugadores cj
        INNER JOIN public.profiles pr ON pr.id = cj.jugador_id
        WHERE cj.partido_id = p_partido_id
          AND cj.es_suplente = false
      ),
      '[]'::json
    )
  )
  INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_convocatoria_roster_jugador(bigint) TO authenticated;
