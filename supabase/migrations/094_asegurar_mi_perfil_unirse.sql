-- 094: Identidad jugador — asegurar profile antes de FKs (DEV-first).
-- - asegurar_mi_perfil(): crea profiles para auth.uid() sin tocar role existente
-- - backfill orphans auth.users → profiles
-- - unirse_con_codigo_grupo: PERFORM asegurar_mi_perfil() antes de INSERT oj

CREATE OR REPLACE FUNCTION public.asegurar_mi_perfil()
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.profiles%ROWTYPE;
  v_email text;
  v_nombre text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT * INTO v_row
  FROM public.profiles
  WHERE id = v_uid;

  IF FOUND THEN
    RETURN v_row;
  END IF;

  SELECT
    lower(trim(coalesce(u.email, ''))),
    coalesce(
      nullif(trim(u.raw_user_meta_data->>'nombre'), ''),
      nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
      nullif(trim(u.raw_user_meta_data->>'name'), ''),
      nullif(split_part(lower(trim(coalesce(u.email, ''))), '@', 1), ''),
      'Sin nombre'
    )
  INTO v_email, v_nombre
  FROM auth.users u
  WHERE u.id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  -- Evitar chocar unique parcial profiles_email_lower_unique.
  IF v_email <> '' AND EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id IS DISTINCT FROM v_uid
      AND lower(trim(coalesce(p.email, ''))) = v_email
  ) THEN
    v_email := '';
  END IF;

  INSERT INTO public.profiles (id, nombre, email, telefono, role)
  VALUES (
    v_uid,
    v_nombre,
    nullif(v_email, ''),
    NULL,
    'jugador'
  )
  ON CONFLICT (id) DO NOTHING;

  SELECT * INTO v_row
  FROM public.profiles
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'perfil_no_asegurado';
  END IF;

  RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION public.asegurar_mi_perfil() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.asegurar_mi_perfil() FROM anon;
GRANT EXECUTE ON FUNCTION public.asegurar_mi_perfil() TO authenticated;
GRANT EXECUTE ON FUNCTION public.asegurar_mi_perfil() TO service_role;

COMMENT ON FUNCTION public.asegurar_mi_perfil() IS
  'Garantiza profiles.id = auth.uid(). No cambia role existente. Solo auth.uid().';

-- Backfill: auth sin profiles (no sobrescribe, role fijo jugador solo en alta).
INSERT INTO public.profiles (id, nombre, email, telefono, role)
SELECT
  u.id,
  coalesce(
    nullif(trim(u.raw_user_meta_data->>'nombre'), ''),
    nullif(trim(u.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(u.raw_user_meta_data->>'name'), ''),
    nullif(split_part(lower(trim(coalesce(u.email, ''))), '@', 1), ''),
    'Sin nombre'
  ),
  CASE
    WHEN nullif(lower(trim(coalesce(u.email, ''))), '') IS NULL THEN NULL
    WHEN EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE lower(trim(coalesce(p.email, ''))) = lower(trim(u.email))
    ) THEN NULL
    ELSE lower(trim(u.email))
  END,
  NULL,
  'jugador'
FROM auth.users u
WHERE NOT EXISTS (
  SELECT 1 FROM public.profiles p WHERE p.id = u.id
)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.unirse_con_codigo_grupo(p_codigo text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_norm text;
  v_org uuid;
  v_nombre text;
  v_ya_activo boolean;
  v_existia boolean;
  v_otros int;
  v_cuenta_adicional boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  -- Identidad: FK organizador_jugadores.jugador_id → profiles(id)
  PERFORM public.asegurar_mi_perfil();

  v_norm := public.normalizar_codigo_grupo(p_codigo);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'codigo_grupo_invalido';
  END IF;

  SELECT id, nombre
  INTO v_org, v_nombre
  FROM public.profiles
  WHERE codigo_grupo = v_norm
    AND role IN ('organizer', 'organizador')
  LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'codigo_grupo_no_encontrado';
  END IF;

  IF v_org = auth.uid() THEN
    RAISE EXCEPTION 'codigo_grupo_propio';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.organizador_jugadores
    WHERE organizador_id = v_org AND jugador_id = auth.uid()
  ) INTO v_existia;

  SELECT EXISTS (
    SELECT 1 FROM public.organizador_jugadores
    WHERE organizador_id = v_org AND jugador_id = auth.uid() AND activo = true
  ) INTO v_ya_activo;

  SELECT count(*)::int INTO v_otros
  FROM public.organizador_jugadores
  WHERE jugador_id = auth.uid()
    AND organizador_id IS DISTINCT FROM v_org;

  v_cuenta_adicional := (v_otros > 0) AND (NOT v_ya_activo);

  INSERT INTO public.organizador_jugadores (
    organizador_id, jugador_id, saldo_acumulado, activo, left_at
  ) VALUES (
    v_org, auth.uid(), 0, true, NULL
  )
  ON CONFLICT (organizador_id, jugador_id) DO NOTHING;

  UPDATE public.organizador_jugadores
  SET activo = true, left_at = NULL
  WHERE organizador_id = v_org
    AND jugador_id = auth.uid();

  RETURN json_build_object(
    'organizador_id', v_org,
    'nombre', coalesce(nullif(trim(v_nombre), ''), 'Organizador'),
    'codigo', v_norm,
    'ya_estaba', v_ya_activo,
    'reabierto', v_existia AND NOT v_ya_activo,
    'es_cuenta_adicional', v_cuenta_adicional
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.unirse_con_codigo_grupo(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.unirse_con_codigo_grupo(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.unirse_con_codigo_grupo(text) TO service_role;
