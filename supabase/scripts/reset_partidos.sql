-- Borra TODOS los partidos y deja cuentas en cero (perfiles intactos).
-- Uso: Supabase SQL Editor, o:
--   supabase db query --linked --file supabase/scripts/reset_partidos.sql
--
-- NO borra auth ni perfiles. Solo datos de partidos/cobros.

BEGIN;

-- Comprobantes en storage quedan huérfanos; la app los ignora sin filas en BD.
DELETE FROM public.saldos_historicos;
DELETE FROM public.partidos;

-- Saldo de cuenta corriente en cero para todos los jugadores.
UPDATE public.profiles
SET saldo_acumulado = 0
WHERE role = 'jugador' OR saldo_acumulado <> 0;

COMMIT;

-- Verificación
SELECT
  (SELECT count(*) FROM public.partidos) AS partidos,
  (SELECT count(*) FROM public.detalles_partido) AS detalles,
  (SELECT count(*) FROM public.saldos_historicos) AS saldos,
  (SELECT count(*) FROM public.convocatoria_jugadores) AS convocatorias,
  (SELECT coalesce(sum(saldo_acumulado), 0) FROM public.profiles) AS suma_saldos;
