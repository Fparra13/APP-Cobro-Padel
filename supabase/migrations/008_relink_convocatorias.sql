-- Vincula convocatorias/cobros del perfil pre-registro (mismo email) al auth.uid() actual.
-- Ejecutar si los jugadores reciben push pero no ven convocatorias pendientes.

CREATE OR REPLACE FUNCTION public.relink_convocatorias_por_email()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
  moved integer;
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
    AND lower(trim(coalesce(p.email, ''))) = user_email;

  UPDATE public.detalles_partido dp
  SET jugador_id = auth.uid()
  FROM public.profiles p
  WHERE dp.jugador_id = p.id
    AND p.id <> auth.uid()
    AND lower(trim(coalesce(p.email, ''))) = user_email;

  UPDATE public.saldos_historicos sh
  SET jugador_id = auth.uid()
  FROM public.profiles p
  WHERE sh.jugador_id = p.id
    AND p.id <> auth.uid()
    AND lower(trim(coalesce(p.email, ''))) = user_email;

  GET DIAGNOSTICS moved = ROW_COUNT;
  RETURN moved;
END;
$$;

GRANT EXECUTE ON FUNCTION public.relink_convocatorias_por_email() TO authenticated;
