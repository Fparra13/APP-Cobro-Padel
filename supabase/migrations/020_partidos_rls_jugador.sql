-- Jugador puede leer partidos donde está en convocatoria (por uid o email) o en cobros.

DROP POLICY IF EXISTS "Jugadores ven sus partidos" ON public.partidos;

CREATE POLICY "Jugadores ven sus partidos"
  ON public.partidos FOR SELECT USING (
    public.is_organizer()
    OR EXISTS (
      SELECT 1 FROM public.convocatoria_jugadores cj
      WHERE cj.partido_id = id AND cj.jugador_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.convocatoria_jugadores cj
      INNER JOIN public.profiles p ON p.id = cj.jugador_id
      WHERE cj.partido_id = id
        AND coalesce(auth.jwt() ->> 'email', '') <> ''
        AND (
          lower(trim(coalesce(p.email, ''))) =
            lower(trim(coalesce(auth.jwt() ->> 'email', '')))
          OR lower(trim(coalesce(p.telefono, ''))) =
            lower(trim(coalesce(auth.jwt() ->> 'email', '')))
        )
    )
    OR EXISTS (
      SELECT 1 FROM public.detalles_partido dp
      WHERE dp.partido_id = id AND dp.jugador_id = auth.uid()
    )
  );
