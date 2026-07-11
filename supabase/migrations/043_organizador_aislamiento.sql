-- Aislamiento multi-organizador:
-- cada organizador solo ve/gestiona SUS partidos y SUS jugadores.

-- ---------------------------------------------------------------------------
-- 1) Roster del organizador (un jugador puede estar en varios clubs)
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

-- ---------------------------------------------------------------------------
-- 2) Helpers
-- ---------------------------------------------------------------------------
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

GRANT EXECUTE ON FUNCTION public.es_mi_jugador(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_jugador_organizador(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) Backfill vínculos desde partidos existentes
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
-- 4) RLS: organizador_jugadores
-- ---------------------------------------------------------------------------
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
-- 5) RLS: profiles (ya no “todos ven todos”)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Todos ven perfiles activos" ON public.profiles;
DROP POLICY IF EXISTS "Organizador ve jugadores" ON public.profiles;
DROP POLICY IF EXISTS "Organizador puede crear jugadores" ON public.profiles;
DROP POLICY IF EXISTS "Organizador actualiza jugadores" ON public.profiles;
DROP POLICY IF EXISTS "Organizador elimina jugadores" ON public.profiles;
DROP POLICY IF EXISTS "Cada uno edita su propio perfil" ON public.profiles;
DROP POLICY IF EXISTS "Perfil propio visible" ON public.profiles;
DROP POLICY IF EXISTS "Organizador ve su roster" ON public.profiles;

CREATE POLICY "Perfil propio visible"
  ON public.profiles
  FOR SELECT
  USING (profiles.id = auth.uid());

CREATE POLICY "Organizador ve su roster"
  ON public.profiles
  FOR SELECT
  USING (
    public.is_organizer()
    AND profiles.role = 'jugador'
    AND public.es_mi_jugador(profiles.id)
  );

CREATE POLICY "Cada uno edita su propio perfil"
  ON public.profiles
  FOR UPDATE
  USING (profiles.id = auth.uid())
  WITH CHECK (profiles.id = auth.uid());

CREATE POLICY "Organizador puede crear jugadores"
  ON public.profiles
  FOR INSERT
  WITH CHECK (public.is_organizer() AND role = 'jugador');

CREATE POLICY "Organizador actualiza jugadores"
  ON public.profiles
  FOR UPDATE
  USING (
    public.is_organizer()
    AND profiles.role = 'jugador'
    AND public.es_mi_jugador(profiles.id)
  )
  WITH CHECK (
    public.is_organizer()
    AND profiles.role = 'jugador'
    AND public.es_mi_jugador(profiles.id)
  );

CREATE POLICY "Organizador elimina jugadores"
  ON public.profiles
  FOR DELETE
  USING (
    public.is_organizer()
    AND profiles.role = 'jugador'
    AND public.es_mi_jugador(profiles.id)
  );

-- ---------------------------------------------------------------------------
-- 6) RLS: partidos (solo los propios del organizador)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Jugadores ven sus partidos" ON public.partidos;
DROP POLICY IF EXISTS "Solo organizador crea/edita/elimina partidos" ON public.partidos;
DROP POLICY IF EXISTS "Organizador gestiona sus partidos" ON public.partidos;

CREATE POLICY "Jugadores ven sus partidos"
  ON public.partidos
  FOR SELECT
  USING (
    partidos.organizador_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.convocatoria_jugadores cj
      WHERE cj.partido_id = partidos.id AND cj.jugador_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1
      FROM public.convocatoria_jugadores cj
      INNER JOIN public.profiles pr ON pr.id = cj.jugador_id
      WHERE cj.partido_id = partidos.id
        AND coalesce(auth.jwt() ->> 'email', '') <> ''
        AND (
          lower(trim(coalesce(pr.email, ''))) =
            lower(trim(coalesce(auth.jwt() ->> 'email', '')))
          OR lower(trim(coalesce(pr.telefono, ''))) =
            lower(trim(coalesce(auth.jwt() ->> 'email', '')))
        )
    )
    OR EXISTS (
      SELECT 1 FROM public.detalles_partido dp
      WHERE dp.partido_id = partidos.id AND dp.jugador_id = auth.uid()
    )
  );

CREATE POLICY "Organizador gestiona sus partidos"
  ON public.partidos
  FOR ALL
  USING (public.is_organizer() AND organizador_id = auth.uid())
  WITH CHECK (public.is_organizer() AND organizador_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_partidos_organizador_estado
  ON public.partidos(organizador_id, estado, fecha);

-- ---------------------------------------------------------------------------
-- 7) RLS: convocatoria / detalles / saldos acotados al dueño del partido
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Ver convocatoria propia o ser organizador" ON public.convocatoria_jugadores;
DROP POLICY IF EXISTS "Organizador gestiona convocatoria" ON public.convocatoria_jugadores;
DROP POLICY IF EXISTS "Jugador actualiza su propia confirmación" ON public.convocatoria_jugadores;
DROP POLICY IF EXISTS "Organizador borra convocatoria" ON public.convocatoria_jugadores;

CREATE POLICY "Ver convocatoria propia o dueño partido"
  ON public.convocatoria_jugadores
  FOR SELECT
  USING (
    jugador_id = auth.uid()
    OR public.owns_partido(partido_id)
  );

CREATE POLICY "Organizador gestiona convocatoria de sus partidos"
  ON public.convocatoria_jugadores
  FOR INSERT
  WITH CHECK (public.owns_partido(partido_id));

CREATE POLICY "Organizador actualiza convocatoria de sus partidos"
  ON public.convocatoria_jugadores
  FOR UPDATE
  USING (public.owns_partido(partido_id) OR jugador_id = auth.uid())
  WITH CHECK (public.owns_partido(partido_id) OR jugador_id = auth.uid());

CREATE POLICY "Organizador borra convocatoria de sus partidos"
  ON public.convocatoria_jugadores
  FOR DELETE
  USING (public.owns_partido(partido_id));

DROP POLICY IF EXISTS "Ver propio detalle o ser organizador" ON public.detalles_partido;
DROP POLICY IF EXISTS "Organizador gestiona detalles" ON public.detalles_partido;
DROP POLICY IF EXISTS "Jugador sube su comprobante" ON public.detalles_partido;

CREATE POLICY "Ver propio detalle o dueño partido"
  ON public.detalles_partido
  FOR SELECT
  USING (jugador_id = auth.uid() OR public.owns_partido(partido_id));

CREATE POLICY "Organizador gestiona detalles de sus partidos"
  ON public.detalles_partido
  FOR ALL
  USING (public.owns_partido(partido_id))
  WITH CHECK (public.owns_partido(partido_id));

CREATE POLICY "Jugador sube su comprobante"
  ON public.detalles_partido
  FOR UPDATE
  USING (jugador_id = auth.uid())
  WITH CHECK (jugador_id = auth.uid());

DROP POLICY IF EXISTS "Ver propio historial o ser organizador" ON public.saldos_historicos;
DROP POLICY IF EXISTS "Solo organizador escribe historial" ON public.saldos_historicos;

CREATE POLICY "Ver propio historial o dueño partido"
  ON public.saldos_historicos
  FOR SELECT
  USING (
    jugador_id = auth.uid()
    OR (partido_id IS NOT NULL AND public.owns_partido(partido_id))
    OR public.es_mi_jugador(jugador_id)
  );

CREATE POLICY "Organizador escribe historial de sus jugadores"
  ON public.saldos_historicos
  FOR ALL
  USING (
    public.is_organizer()
    AND (
      public.es_mi_jugador(jugador_id)
      OR (partido_id IS NOT NULL AND public.owns_partido(partido_id))
    )
  )
  WITH CHECK (
    public.is_organizer()
    AND (
      public.es_mi_jugador(jugador_id)
      OR (partido_id IS NOT NULL AND public.owns_partido(partido_id))
    )
  );

-- ---------------------------------------------------------------------------
-- 8) crear_jugador_organizador: crea + vincula (o solo vincula si ya existe)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crear_jugador_organizador(
  p_nombre text,
  p_email text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_activo boolean DEFAULT TRUE
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.profiles;
  v_email text;
  v_tel text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF nullif(trim(p_nombre), '') IS NULL THEN
    RAISE EXCEPTION 'nombre_requerido';
  END IF;

  v_email := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_tel := nullif(trim(coalesce(p_telefono, '')), '');

  IF v_email IS NOT NULL THEN
    SELECT * INTO v_row
    FROM public.profiles
    WHERE lower(trim(coalesce(email, ''))) = v_email
    LIMIT 1;

    IF FOUND THEN
      UPDATE public.profiles
      SET
        nombre = CASE
          WHEN role = 'jugador' THEN trim(p_nombre)
          ELSE nombre
        END,
        telefono = coalesce(v_tel, telefono),
        activo = CASE
          WHEN role = 'jugador' THEN coalesce(p_activo, activo)
          ELSE activo
        END
      WHERE id = v_row.id
      RETURNING * INTO v_row;

      PERFORM public.vincular_jugador_organizador(v_row.id, auth.uid());
      RETURN v_row;
    END IF;
  END IF;

  INSERT INTO public.profiles (nombre, email, telefono, activo, role)
  VALUES (
    trim(p_nombre),
    v_email,
    v_tel,
    coalesce(p_activo, TRUE),
    'jugador'
  )
  RETURNING * INTO v_row;

  PERFORM public.vincular_jugador_organizador(v_row.id, auth.uid());
  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.crear_jugador_organizador(text, text, text, boolean)
  TO authenticated;

-- Al invitar a un partido, asegurar vínculo con el organizador dueño.
CREATE OR REPLACE FUNCTION public.trg_convocatoria_vincular_organizador()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT organizador_id INTO v_org
  FROM public.partidos
  WHERE id = NEW.partido_id;

  IF v_org IS NOT NULL THEN
    INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
    VALUES (v_org, NEW.jugador_id)
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_convocatoria_vincular_organizador
  ON public.convocatoria_jugadores;
CREATE TRIGGER trg_convocatoria_vincular_organizador
  AFTER INSERT ON public.convocatoria_jugadores
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_convocatoria_vincular_organizador();

COMMENT ON TABLE public.organizador_jugadores IS
  'Roster por organizador. Un jugador puede pertenecer a varios clubs.';

-- ---------------------------------------------------------------------------
-- 9) Costos: quitar is_organizer() global (solo dueño del partido)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.can_manage_partido_costs(p_partido_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT public.owns_partido(p_partido_id);
$$;

DROP POLICY IF EXISTS "Ver costos de partidos propios" ON public.costos_variables;
CREATE POLICY "Ver costos de partidos propios"
  ON public.costos_variables FOR SELECT
  USING (
    public.owns_partido(partido_id)
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

DROP POLICY IF EXISTS "Ver asignaciones de partidos propios" ON public.asignaciones_costo;
CREATE POLICY "Ver asignaciones de partidos propios"
  ON public.asignaciones_costo FOR SELECT
  USING (
    jugador_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = asignaciones_costo.costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );

DROP POLICY IF EXISTS "Organizador inserta asignaciones" ON public.asignaciones_costo;
CREATE POLICY "Organizador inserta asignaciones"
  ON public.asignaciones_costo FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );

DROP POLICY IF EXISTS "Organizador actualiza asignaciones" ON public.asignaciones_costo;
CREATE POLICY "Organizador actualiza asignaciones"
  ON public.asignaciones_costo FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );

DROP POLICY IF EXISTS "Organizador elimina asignaciones" ON public.asignaciones_costo;
CREATE POLICY "Organizador elimina asignaciones"
  ON public.asignaciones_costo FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.costos_variables cv
      WHERE cv.id = costo_variable_id
        AND public.owns_partido(cv.partido_id)
    )
  );
