-- Confirmación convocatoria: mismo criterio de identidad que get_mi_convocatoria_jugador.

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
  user_email text;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN false;
  END IF;

  user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  PERFORM public.relink_convocatorias_por_email();

  estado_txt := CASE WHEN p_confirmo THEN 'confirmado' ELSE 'rechazado' END;

  UPDATE public.convocatoria_jugadores cj
  SET estado_confirmacion = estado_txt
  FROM public.profiles pr
  WHERE cj.partido_id = p_partido_id
    AND cj.jugador_id = pr.id
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

  GET DIAGNOSTICS updated_rows = ROW_COUNT;
  RETURN updated_rows > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.actualizar_confirmacion_jugador(bigint, boolean) TO authenticated;
