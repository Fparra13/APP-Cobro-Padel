-- Distinguir "usa la app" de "tiene token push".
-- Antes solo fcm_token → jugadores con cuenta activa pero sin FCM
-- aparecían como "Sin app".

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS app_last_seen_at timestamptz;

COMMENT ON COLUMN public.profiles.app_last_seen_at IS
  'Última vez que el usuario abrió la app (Kloovi). Independiente de fcm_token.';

-- Backfill: quienes ya iniciaron sesión tienen la app.
UPDATE public.profiles p
SET app_last_seen_at = u.last_sign_in_at
FROM auth.users u
WHERE u.id = p.id
  AND u.last_sign_in_at IS NOT NULL
  AND p.app_last_seen_at IS NULL;

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
      AND pr.role = 'jugador'
      AND (p_solo_activos IS NULL OR pr.activo = p_solo_activos)
    ORDER BY pr.nombre
  ) t;

  RETURN result;
END;
$$;
