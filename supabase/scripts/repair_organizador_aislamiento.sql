-- Reparación post-043/044: partidos sin dueño + re-vincular roster.
-- Preferible: ejecutar también supabase/migrations/044_repair_organizador_carga.sql
--
-- Uso rápido en SQL Editor si home/cobros/jugadores fallan o salen vacíos.

DO $$
DECLARE
  v_org_count int;
  v_org uuid;
BEGIN
  SELECT count(*) INTO v_org_count
  FROM public.profiles
  WHERE role IN ('organizer', 'organizador');

  SELECT id INTO v_org
  FROM public.profiles
  WHERE role IN ('organizer', 'organizador')
  ORDER BY created_at ASC NULLS LAST, id ASC
  LIMIT 1;

  IF v_org_count = 1 AND v_org IS NOT NULL THEN
    UPDATE public.partidos
    SET organizador_id = v_org
    WHERE organizador_id IS NULL;
    RAISE NOTICE 'Partidos sin dueño asignados a %', v_org;
  ELSE
    RAISE NOTICE 'Hay % organizadores; no auto-asigno partidos huérfanos.', v_org_count;
  END IF;
END $$;

INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
SELECT DISTINCT p.organizador_id, cj.jugador_id
FROM public.partidos p
INNER JOIN public.convocatoria_jugadores cj ON cj.partido_id = p.id
WHERE p.organizador_id IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
SELECT DISTINCT p.organizador_id, dp.jugador_id
FROM public.partidos p
INNER JOIN public.detalles_partido dp ON dp.partido_id = p.id
WHERE p.organizador_id IS NOT NULL
ON CONFLICT DO NOTHING;

SELECT
  (SELECT count(*) FROM public.partidos WHERE organizador_id IS NULL) AS partidos_sin_org,
  (SELECT count(*) FROM public.organizador_jugadores) AS vinculos_roster,
  (SELECT count(*) FROM public.partidos WHERE estado IN ('organizando', 'confirmado')) AS convocatorias_activas;
