-- =============================================================================
-- Seed: 10 usuarios de prueba para UI de cápsulas (DEV)
-- =============================================================================
-- Marcadores:
--   email: *@kloovi.capsule.dev
--   (sin auth; perfiles pre-registro como el resto de seeds)
--
-- Idempotente: borra/recrea solo estos 10 emails.
-- Vincula al organizador (v_org_email).
-- =============================================================================

DO $$
DECLARE
  v_org_email text := 'fparram13@gmail.com';
  v_org uuid;
  v_id uuid;
  r record;
BEGIN
  SELECT id INTO v_org
  FROM public.profiles
  WHERE lower(trim(coalesce(email, ''))) = lower(trim(v_org_email))
  LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'No encontré organizador con email %.', v_org_email;
  END IF;

  -- Limpia seed previo de cápsulas (solo este marcador)
  DELETE FROM public.organizador_jugadores oj
  USING public.profiles p
  WHERE oj.jugador_id = p.id
    AND lower(coalesce(p.email, '')) LIKE '%@kloovi.capsule.dev';

  DELETE FROM public.profiles
  WHERE lower(coalesce(email, '')) LIKE '%@kloovi.capsule.dev';

  FOR r IN
    SELECT *
    FROM (
      VALUES
        (1,  'Ana Ruiz',                              'ana.ruiz@kloovi.capsule.dev',                 '+56971000001'),
        (2,  'Ben Allen',                             'ben.allen@kloovi.capsule.dev',                '+56971000002'),
        (3,  'Sofía Méndez',                          'sofia.mendez@kloovi.capsule.dev',             '+56971000003'),
        (4,  'Camila Rojas',                          'camila.rojas@kloovi.capsule.dev',             '+56971000004'),
        (5,  'Diego Salamanca',                       'diego.salamanca@kloovi.capsule.dev',          '+56971000005'),
        (6,  'Valentina Paz Gutiérrez',               'valentina.gutierrez@kloovi.capsule.dev',      '+56971000006'),
        (7,  'José-Luis Fernández Prieto',            'jose.luis.fernandez@kloovi.capsule.dev',      '+56971000007'),
        (8,  'María José Valenzuela Contreras',       'maria.jose.valenzuela@kloovi.capsule.dev',    '+56971000008'),
        (9,  'Francisco Matus De La Parra',           'francisco.matus@kloovi.capsule.dev',          '+56971000009'),
        (10, 'Cristóbal Ignacio Donoso Villanueva',   'cristobal.donoso@kloovi.capsule.dev',         '+56971000010')
    ) AS t(ord, nombre, email, telefono)
    ORDER BY ord
  LOOP
    INSERT INTO public.profiles (nombre, email, telefono, activo, role)
    VALUES (r.nombre, r.email, r.telefono, true, 'jugador')
    RETURNING id INTO v_id;

    INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
    VALUES (v_org, v_id)
    ON CONFLICT DO NOTHING;
  END LOOP;

  RAISE NOTICE 'Seed cápsulas OK: 10 usuarios vinculados a %', v_org_email;
END $$;

SELECT id, nombre, email, telefono, role, created_at
FROM public.profiles
WHERE lower(coalesce(email, '')) LIKE '%@kloovi.capsule.dev'
ORDER BY email;
