-- Permite al organizador borrar filas al actualizar convocatoria
-- Ejecutar en Supabase SQL Editor

create policy "Organizador elimina convocatoria"
  on public.convocatoria_jugadores for delete
  using (public.is_organizer());
