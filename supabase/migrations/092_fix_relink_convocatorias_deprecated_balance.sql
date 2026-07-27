-- Fix: relink_convocatorias_por_email ya no llama a recalcular_saldo_jugador
-- (stub deprecated desde 056). Bloqueaba confirmar asistencia y otros RPCs
-- que hacen PERFORM relink. La lógica de relink y limpieza de huérfanos se
-- mantiene intacta respecto a 015.

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
