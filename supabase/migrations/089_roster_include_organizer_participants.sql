-- BLOQUE 1: Participante = vínculo en organizador_jugadores, no profiles.role.
--
-- Un organizador puede ser participante de otro organizador.
-- El roster y la RLS de lectura deben basarse en la relación, no en role='jugador'.
--
-- No cambia: saldo, CREATE de perfiles externos (siguen naciendo como jugador),
-- UPDATE/DELETE de fichas (solo role jugador editables por el org), billing, onboarding.

-- ---------------------------------------------------------------------------
-- 1) RPC roster: incluir cualquier perfil vinculado (jugador u organizer)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_mis_jugadores_organizador(
  p_solo_activos boolean DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RETURN '[]'::json;
  END IF;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json)
  INTO result
  FROM (
    SELECT
      pr.id,
      pr.nombre,
      pr.email,
      pr.telefono,
      pr.activo AS perfil_activo,
      pr.role,
      pr.foto_url,
      pr.fcm_token,
      pr.app_last_seen_at,
      pr.created_at,
      oj.saldo_acumulado,
      oj.activo AS en_grupo_activo,
      oj.left_at
    FROM public.organizador_jugadores oj
    INNER JOIN public.profiles pr ON pr.id = oj.jugador_id
    WHERE oj.organizador_id = auth.uid()
      AND oj.activo = true
      AND (p_solo_activos IS NULL OR pr.activo = p_solo_activos)
    ORDER BY pr.nombre
  ) t;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.get_mis_jugadores_organizador(boolean) IS
  'Roster del organizador autenticado: todos los vínculos activos en '
  'organizador_jugadores (incluye participantes con role organizer). '
  'Sin listado global; filtrado por organizador_id = auth.uid().';

GRANT EXECUTE ON FUNCTION public.get_mis_jugadores_organizador(boolean)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) RLS SELECT roster: ver perfiles vinculados, sin exigir role=jugador
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Organizador ve su roster" ON public.profiles;
CREATE POLICY "Organizador ve su roster"
  ON public.profiles
  FOR SELECT
  USING (
    public.is_organizer()
    AND public.es_mi_jugador(profiles.id)
  );

COMMENT ON POLICY "Organizador ve su roster" ON public.profiles IS
  'Organizador ve perfiles de su roster (organizador_jugadores), '
  'independiente de profiles.role. Sin directorio global.';
