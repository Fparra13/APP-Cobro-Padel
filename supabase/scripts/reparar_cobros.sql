-- Reparación manual de cobros/saldos (organizador o jugadores concretos).
-- Uso: supabase db query -f supabase/scripts/reparar_cobros.sql --linked --yes

-- Todos los jugadores de partidos del organizador autenticado (desde la app):
-- SELECT public.reparar_cobros_organizador();

-- Jugadores puntuales por email:
DO $$
DECLARE
  emails text[] := ARRAY[
    'fparram13@gmail.com',
    'catitaboni2012@gmail.com'
  ];
  em text;
  jid uuid;
  rep json;
BEGIN
  FOREACH em IN ARRAY emails
  LOOP
    SELECT p.id INTO jid
    FROM public.profiles p
    WHERE lower(trim(coalesce(p.email, ''))) = lower(trim(em))
    LIMIT 1;

    IF jid IS NOT NULL THEN
      rep := public.reparar_jugador_cobros(jid);
      RAISE NOTICE '% → %', em, rep;
    END IF;
  END LOOP;
END;
$$;
