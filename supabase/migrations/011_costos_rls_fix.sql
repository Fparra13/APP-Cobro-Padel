-- Fix RLS: INSERT en costos_variables / asignaciones_costo (FOR ALL sin WITH CHECK explícito).
-- También acepta role 'organizador' y dueño del partido (organizador_id).

CREATE OR REPLACE FUNCTION public.is_organizer()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND role IN ('organizer', 'organizador')
  );
$$;

CREATE OR REPLACE FUNCTION public.owns_partido(p_partido_id bigint)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.partidos
    WHERE id = p_partido_id
      AND organizador_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_partido_costs(p_partido_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.is_organizer() OR public.owns_partido(p_partido_id);
$$;

-- COSTOS VARIABLES
DROP POLICY IF EXISTS "Ver costos de partidos propios" ON public.costos_variables;
DROP POLICY IF EXISTS "Organizador gestiona costos variables" ON public.costos_variables;

CREATE POLICY "Ver costos de partidos propios"
  ON public.costos_variables FOR SELECT
  USING (
    public.is_organizer()
    OR public.owns_partido(partido_id)
    OR EXISTS (
      SELECT 1 FROM public.convocatoria_jugadores cj
      WHERE cj.partido_id = costos_variables.partido_id
        AND cj.jugador_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.detalles_partido dp
      WHERE dp.partido_id = costos_variables.partido_id
        AND dp.jugador_id = auth.uid()
    )
  );

CREATE POLICY "Organizador inserta costos variables"
  ON public.costos_variables FOR INSERT
  WITH CHECK (public.can_manage_partido_costs(partido_id));

CREATE POLICY "Organizador actualiza costos variables"
  ON public.costos_variables FOR UPDATE
  USING (public.can_manage_partido_costs(partido_id))
  WITH CHECK (public.can_manage_partido_costs(partido_id));

CREATE POLICY "Organizador elimina costos variables"
  ON public.costos_variables FOR DELETE
  USING (public.can_manage_partido_costs(partido_id));

-- ASIGNACIONES COSTO
DROP POLICY IF EXISTS "Ver asignaciones de partidos propios" ON public.asignaciones_costo;
DROP POLICY IF EXISTS "Organizador gestiona asignaciones" ON public.asignaciones_costo;

CREATE POLICY "Ver asignaciones de partidos propios"
  ON public.asignaciones_costo FOR SELECT
  USING (
    public.is_organizer()
    OR jugador_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = asignaciones_costo.costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );

CREATE POLICY "Organizador inserta asignaciones"
  ON public.asignaciones_costo FOR INSERT
  WITH CHECK (
    public.is_organizer()
    OR EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );

CREATE POLICY "Organizador actualiza asignaciones"
  ON public.asignaciones_costo FOR UPDATE
  USING (
    public.is_organizer()
    OR EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  )
  WITH CHECK (
    public.is_organizer()
    OR EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );

CREATE POLICY "Organizador elimina asignaciones"
  ON public.asignaciones_costo FOR DELETE
  USING (
    public.is_organizer()
    OR EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );
