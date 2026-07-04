-- Permite al organizador editar/eliminar perfiles de jugadores (nombre, email, activo).
-- Sin esto, UPDATE en profiles solo aplica a auth.uid() = id y el cambio no se guarda.

CREATE POLICY "Organizador actualiza jugadores"
  ON public.profiles
  FOR UPDATE
  USING (public.is_organizer() AND role = 'jugador')
  WITH CHECK (public.is_organizer() AND role = 'jugador');

CREATE POLICY "Organizador elimina jugadores"
  ON public.profiles
  FOR DELETE
  USING (public.is_organizer() AND role = 'jugador');
