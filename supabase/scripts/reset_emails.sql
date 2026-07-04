-- Resetea cuentas por email (auth + perfiles + datos del jugador).
-- Ejecutar en Supabase SQL Editor o: supabase db query --file supabase/scripts/reset_emails.sql

DO $$
DECLARE
  emails text[] := ARRAY[
    'fparram13@gmail.com',
    'catitaboni2012@gmail.com'
  ];
  em text;
  pid uuid;
BEGIN
  FOREACH em IN ARRAY emails LOOP
    em := lower(trim(em));

    FOR pid IN
      SELECT p.id
      FROM public.profiles p
      WHERE lower(trim(coalesce(p.email, ''))) = em
         OR lower(trim(coalesce(p.telefono, ''))) = em
    LOOP
      DELETE FROM public.saldos_historicos WHERE jugador_id = pid;
      DELETE FROM public.asignaciones_costo WHERE jugador_id = pid;
      DELETE FROM public.detalles_partido WHERE jugador_id = pid;
      DELETE FROM public.convocatoria_jugadores WHERE jugador_id = pid;
      UPDATE public.partidos SET organizador_id = NULL WHERE organizador_id = pid;
      DELETE FROM public.profiles WHERE id = pid;
    END LOOP;

    DELETE FROM auth.identities
    WHERE user_id IN (
      SELECT id FROM auth.users WHERE lower(trim(coalesce(email, ''))) = em
    );

    DELETE FROM auth.users WHERE lower(trim(coalesce(email, ''))) = em;
  END LOOP;
END $$;

SELECT id, email FROM auth.users
WHERE lower(trim(email)) IN ('fparram13@gmail.com', 'catitaboni2012@gmail.com');

SELECT id, email, nombre, role FROM public.profiles
WHERE lower(trim(coalesce(email, ''))) IN ('fparram13@gmail.com', 'catitaboni2012@gmail.com');
