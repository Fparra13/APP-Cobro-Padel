-- Persistencia server-side de popups de cancelación (sobrevive reinstall).

ALTER TABLE public.convocatoria_jugadores
  ADD COLUMN IF NOT EXISTS cancelacion_vista_en timestamptz;

COMMENT ON COLUMN public.convocatoria_jugadores.cancelacion_vista_en IS
  'Cuando el jugador cerró el popup in-app de partido cancelado.';

-- Cancelaciones ya ocurridas: no volver a bombardear al reinstalar.
UPDATE public.convocatoria_jugadores cj
SET cancelacion_vista_en = coalesce(p.resuelto_en, p.fecha, now())
FROM public.partidos p
WHERE p.id = cj.partido_id
  AND p.estado = 'cancelado'
  AND cj.es_suplente = false
  AND cj.estado_confirmacion = 'confirmado'
  AND cj.cancelacion_vista_en IS NULL;

-- Popups pendientes (no vistas).
CREATE OR REPLACE FUNCTION public.get_cancelaciones_jugador_pendientes()
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
      AND cj.cancelacion_vista_en IS NULL
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

-- Marca el popup como cerrado (por partido del usuario autenticado).
CREATE OR REPLACE FUNCTION public.marcar_cancelacion_vista(p_partido_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  PERFORM public.relink_convocatorias_por_email();

  UPDATE public.convocatoria_jugadores cj
  SET cancelacion_vista_en = now()
  FROM public.profiles pr
  WHERE cj.partido_id = p_partido_id
    AND cj.jugador_id = pr.id
    AND cj.es_suplente = false
    AND cj.estado_confirmacion = 'confirmado'
    AND cj.cancelacion_vista_en IS NULL
    AND (
      cj.jugador_id = auth.uid()
      OR (
        user_email <> ''
        AND (
          lower(trim(coalesce(pr.email, ''))) = user_email
          OR lower(trim(coalesce(pr.telefono, ''))) = user_email
        )
      )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cancelaciones_jugador_pendientes() TO authenticated;
GRANT EXECUTE ON FUNCTION public.marcar_cancelacion_vista(bigint) TO authenticated;
