-- Cobros visibles para jugadores: relink ampliado + RPC de deudas pendientes.

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
  moved_ac integer := 0;
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

  UPDATE public.asignaciones_costo ac
  SET jugador_id = auth.uid()
  FROM public.profiles p
  WHERE ac.jugador_id = p.id
    AND p.id <> auth.uid()
    AND (
      lower(trim(coalesce(p.email, ''))) = user_email
      OR lower(trim(coalesce(p.telefono, ''))) = user_email
    );

  GET DIAGNOSTICS moved_ac = ROW_COUNT;

  RETURN moved_cj + moved_dp + moved_sh + moved_ac;
END;
$$;

GRANT EXECUTE ON FUNCTION public.relink_convocatorias_por_email() TO authenticated;

-- Deudas del jugador autenticado (relink + lectura sin depender de RLS en partidos).
CREATE OR REPLACE FUNCTION public.get_mis_deudas_pendientes()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN '[]'::json;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json)
  INTO result
  FROM (
    SELECT
      dp.*,
      p.fecha AS partido_fecha,
      p.recinto AS partido_recinto,
      p.estado AS partido_estado
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE dp.jugador_id = auth.uid()
      AND dp.pagado = false
    ORDER BY dp.partido_id DESC
  ) t;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_mis_deudas_pendientes() TO authenticated;

-- Confirmación de convocatoria con relink previo.
CREATE OR REPLACE FUNCTION public.actualizar_confirmacion_jugador(
  p_partido_id bigint,
  p_confirmo boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_rows integer;
  estado_txt text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  PERFORM public.relink_convocatorias_por_email();

  estado_txt := CASE WHEN p_confirmo THEN 'confirmado' ELSE 'rechazado' END;

  UPDATE public.convocatoria_jugadores
  SET estado_confirmacion = estado_txt
  WHERE partido_id = p_partido_id
    AND jugador_id = auth.uid();

  GET DIAGNOSTICS updated_rows = ROW_COUNT;
  RETURN updated_rows > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.actualizar_confirmacion_jugador(bigint, boolean) TO authenticated;
