-- Convocatorias: relink robusto + lectura por email (no solo auth.uid).
-- Ejecutar si el jugador recibe push pero la app no encuentra la convocatoria.

CREATE OR REPLACE FUNCTION public.relink_convocatorias_por_email()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
  moved_cj integer := 0;
  moved_dp integer := 0;
  moved_sh integer := 0;
BEGIN
  user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  IF user_email = '' OR auth.uid() IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.convocatoria_jugadores cj
  SET jugador_id = auth.uid()
  FROM public.profiles p
  WHERE cj.jugador_id = p.id
    AND p.id <> auth.uid()
    AND (
      lower(trim(coalesce(p.email, ''))) = user_email
      OR lower(trim(coalesce(p.telefono, ''))) = user_email
    );

  GET DIAGNOSTICS moved_cj = ROW_COUNT;

  UPDATE public.detalles_partido dp
  SET jugador_id = auth.uid()
  FROM public.profiles p
  WHERE dp.jugador_id = p.id
    AND p.id <> auth.uid()
    AND (
      lower(trim(coalesce(p.email, ''))) = user_email
      OR lower(trim(coalesce(p.telefono, ''))) = user_email
    );

  GET DIAGNOSTICS moved_dp = ROW_COUNT;

  UPDATE public.saldos_historicos sh
  SET jugador_id = auth.uid()
  FROM public.profiles p
  WHERE sh.jugador_id = p.id
    AND p.id <> auth.uid()
    AND (
      lower(trim(coalesce(p.email, ''))) = user_email
      OR lower(trim(coalesce(p.telefono, ''))) = user_email
    );

  GET DIAGNOSTICS moved_sh = ROW_COUNT;

  RETURN moved_cj + moved_dp + moved_sh;
END;
$$;

GRANT EXECUTE ON FUNCTION public.relink_convocatorias_por_email() TO authenticated;

-- Perfil canónico para convocatorias: prioriza cuenta con login (auth.users).
CREATE OR REPLACE FUNCTION public.resolve_profile_id_for_email(p_email text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  normalized text;
  found_id uuid;
BEGIN
  normalized := lower(trim(coalesce(p_email, '')));
  IF normalized = '' THEN
    RETURN NULL;
  END IF;

  SELECT p.id INTO found_id
  FROM public.profiles p
  INNER JOIN auth.users u ON u.id = p.id
  WHERE lower(trim(coalesce(p.email, p.telefono, ''))) = normalized
  LIMIT 1;

  IF found_id IS NOT NULL THEN
    RETURN found_id;
  END IF;

  SELECT p.id INTO found_id
  FROM public.profiles p
  WHERE lower(trim(coalesce(p.email, p.telefono, ''))) = normalized
  ORDER BY p.created_at ASC
  LIMIT 1;

  RETURN found_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_profile_id_for_email(text) TO authenticated;

-- Lista convocatorias del jugador actual (relink + match por uid o email).
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

GRANT EXECUTE ON FUNCTION public.get_mis_convocatorias_jugador() TO authenticated;

-- Una convocatoria concreta (p. ej. al abrir desde push).
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

GRANT EXECUTE ON FUNCTION public.get_mi_convocatoria_jugador(bigint) TO authenticated;
