-- =============================================================================
-- Limpia SOLO datos del seed demo pesado ([Demo] / @matchpay.demo)
-- No toca partidos ni jugadores reales.
-- =============================================================================

BEGIN;

-- Vínculos roster antes de borrar perfiles (FK)
DELETE FROM public.organizador_jugadores oj
USING public.profiles p
WHERE oj.jugador_id = p.id
  AND p.role = 'jugador'
  AND (
    p.nombre LIKE '[Demo]%'
    OR lower(coalesce(p.email, '')) LIKE '%@matchpay.demo'
  );

DELETE FROM public.partidos
WHERE coalesce(notas, '') LIKE '[Demo]%'
   OR coalesce(recinto, '') LIKE '[Demo]%';

-- Saldos huérfanos de demo (por si quedó alguno sin partido)
DELETE FROM public.saldos_historicos
WHERE concepto LIKE '[Demo]%';

DELETE FROM public.profiles
WHERE role = 'jugador'
  AND (
    nombre LIKE '[Demo]%'
    OR lower(coalesce(email, '')) LIKE '%@matchpay.demo'
  );

-- También limpia vínculos huérfanos (por si el perfil ya no existe)
DELETE FROM public.organizador_jugadores oj
WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = oj.jugador_id);

COMMIT;

SELECT
  (SELECT count(*) FROM public.partidos WHERE coalesce(notas, '') LIKE '[Demo]%') AS partidos_demo,
  (SELECT count(*) FROM public.profiles WHERE nombre LIKE '[Demo]%') AS jugadores_demo;
