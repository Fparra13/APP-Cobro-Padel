-- Jugador puede ver partidos donde tiene detalle de cobro (tras confirmar cobros).

DROP POLICY IF EXISTS "Jugadores ven sus partidos" ON public.partidos;

CREATE POLICY "Jugadores ven sus partidos"
  ON public.partidos FOR SELECT
  USING (
    public.is_organizer()
    OR public.owns_partido(id)
    OR EXISTS (
      SELECT 1 FROM public.convocatoria_jugadores cj
      WHERE cj.partido_id = id AND cj.jugador_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.detalles_partido dp
      WHERE dp.partido_id = id AND dp.jugador_id = auth.uid()
    )
  );
