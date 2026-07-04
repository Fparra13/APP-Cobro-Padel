-- Relink completo (saldo + perfiles huérfanos) + eliminar partido atómico.

CREATE OR REPLACE FUNCTION public.recalcular_saldo_jugador(p_jugador_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nuevo numeric := 0;
BEGIN
  IF p_jugador_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT sh.saldo_nuevo
  INTO nuevo
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
  ORDER BY sh.fecha DESC, sh.id DESC
  LIMIT 1;

  nuevo := coalesce(nuevo, 0);

  UPDATE public.profiles
  SET saldo_acumulado = nuevo
  WHERE id = p_jugador_id;

  RETURN nuevo;
END;
$$;

GRANT EXECUTE ON FUNCTION public.recalcular_saldo_jugador(uuid) TO authenticated;

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
  orphan_id uuid;
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

  PERFORM public.recalcular_saldo_jugador(auth.uid());

  FOR orphan_id IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.id <> auth.uid()
      AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id)
      AND (
        lower(trim(coalesce(p.email, ''))) = user_email
        OR lower(trim(coalesce(p.telefono, ''))) = user_email
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.convocatoria_jugadores cj
        WHERE cj.jugador_id = p.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.detalles_partido dp
        WHERE dp.jugador_id = p.id
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.saldos_historicos sh
        WHERE sh.jugador_id = p.id
      )
  LOOP
    DELETE FROM public.profiles WHERE id = orphan_id;
  END LOOP;

  RETURN moved_cj + moved_dp + moved_sh + moved_ac;
END;
$$;

GRANT EXECUTE ON FUNCTION public.relink_convocatorias_por_email() TO authenticated;

CREATE OR REPLACE FUNCTION public.eliminar_partido_completo(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jugador_ids uuid[];
BEGIN
  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = p_partido_id;

  DELETE FROM public.saldos_historicos WHERE partido_id = p_partido_id;
  DELETE FROM public.partidos WHERE id = p_partido_id;

  IF jugador_ids IS NOT NULL THEN
    FOR i IN 1..coalesce(array_length(jugador_ids, 1), 0) LOOP
      PERFORM public.recalcular_saldo_jugador(jugador_ids[i]);
    END LOOP;
  END IF;

  RETURN json_build_object('jugadores', jugador_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION public.eliminar_partido_completo(bigint) TO authenticated;
