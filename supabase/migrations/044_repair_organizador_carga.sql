-- Bootstrap + repair aislamiento multi-organizador.
-- Seguro si 043 no se aplicó: crea la tabla y luego repara datos.

-- ---------------------------------------------------------------------------
-- 1) Tabla roster (si falta)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizador_jugadores (
  organizador_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  jugador_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organizador_id, jugador_id)
);

CREATE INDEX IF NOT EXISTS idx_organizador_jugadores_jugador
  ON public.organizador_jugadores(jugador_id);

CREATE INDEX IF NOT EXISTS idx_organizador_jugadores_org
  ON public.organizador_jugadores(organizador_id);

ALTER TABLE public.organizador_jugadores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizador gestiona su roster" ON public.organizador_jugadores;
CREATE POLICY "Organizador gestiona su roster"
  ON public.organizador_jugadores
  FOR ALL
  USING (organizador_id = auth.uid() AND public.is_organizer())
  WITH CHECK (organizador_id = auth.uid() AND public.is_organizer());

DROP POLICY IF EXISTS "Jugador ve sus vínculos" ON public.organizador_jugadores;
CREATE POLICY "Jugador ve sus vínculos"
  ON public.organizador_jugadores
  FOR SELECT
  USING (jugador_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) Partidos huérfanos → único organizador (si aplica)
-- ---------------------------------------------------------------------------
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3) Backfill vínculos
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 4) Helpers + RPC
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owns_partido(p_partido_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.partidos
    WHERE id = p_partido_id
      AND organizador_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.es_mi_jugador(p_jugador_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p_jugador_id IS NOT NULL
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.organizador_jugadores oj
      WHERE oj.organizador_id = auth.uid()
        AND oj.jugador_id = p_jugador_id
    );
$$;

CREATE OR REPLACE FUNCTION public.vincular_jugador_organizador(
  p_jugador_id uuid,
  p_organizador_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := coalesce(p_organizador_id, auth.uid());
BEGIN
  IF v_org IS NULL OR p_jugador_id IS NULL THEN
    RETURN;
  END IF;
  IF p_organizador_id IS NULL AND NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
  VALUES (v_org, p_jugador_id)
  ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_mis_jugadores_organizador(p_solo_activos boolean DEFAULT NULL)
RETURNS SETOF public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT pr.*
  FROM public.organizador_jugadores oj
  INNER JOIN public.profiles pr ON pr.id = oj.jugador_id
  WHERE oj.organizador_id = auth.uid()
    AND pr.role = 'jugador'
    AND (p_solo_activos IS NULL OR pr.activo = p_solo_activos)
  ORDER BY lower(pr.nombre);
END;
$$;

GRANT EXECUTE ON FUNCTION public.owns_partido(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.es_mi_jugador(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_jugador_organizador(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_mis_jugadores_organizador(boolean) TO authenticated;

-- Verificación
SELECT
  (SELECT count(*) FROM public.organizador_jugadores) AS vinculos_roster,
  (SELECT count(*) FROM public.partidos WHERE organizador_id IS NULL) AS partidos_sin_org;
