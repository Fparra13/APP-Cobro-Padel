-- Corrige perfiles de jugadores que quedaron con role organizer por error.
-- Revisar antes de ejecutar (SELECT) y ajustar el email.

-- Ver estado actual:
-- SELECT id, email, nombre, role, created_at
-- FROM public.profiles
-- WHERE lower(trim(email)) = lower(trim('CORREO@EJEMPLO.COM'));

-- Restaurar solo jugador (sin borrar datos de partidos/cobros):
-- UPDATE public.profiles
-- SET role = 'jugador'
-- WHERE lower(trim(email)) = lower(trim('CORREO@EJEMPLO.COM'))
--   AND role IN ('organizer', 'organizador');

-- Listar sospechosos: jugadores en convocatorias/detalle pero marcados organizer
-- SELECT p.id, p.email, p.nombre, p.role
-- FROM public.profiles p
-- WHERE p.role IN ('organizer', 'organizador')
--   AND EXISTS (
--     SELECT 1 FROM public.convocatoria_jugadores cj WHERE cj.jugador_id = p.id
--   )
--   AND NOT EXISTS (
--     SELECT 1 FROM public.partidos pt WHERE pt.organizador_id = p.id
--   );
