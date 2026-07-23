-- =============================================================================
-- 085: C2 — authz robusta (JWT sub directo) + unirse sin depender de reabrir
-- =============================================================================
-- Hallazgo: con SET search_path=public, la rama jugador en reabrir fallaba aún
-- con vínculo existente (mismo mensaje forbidden). Mitigación:
--   - Leer sub desde request.jwt.claim.sub / request.jwt.claims (no solo auth.uid()).
--   - search_path = public, auth.
--   - unirse: INSERT + UPDATE directo (DEFINER); ya no requiere reabrir para alta/rejoin.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.asegurar_cuenta_organizador_jugador(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_jwt_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
  v_uid uuid := coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
  v_exists boolean;
BEGIN
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL AND v_uid = p_organizador_id THEN
    NULL;
  ELSIF v_uid IS NOT NULL AND v_uid = p_jugador_id THEN
    SELECT EXISTS (
      SELECT 1 FROM public.organizador_jugadores oj
      WHERE oj.organizador_id = p_organizador_id
        AND oj.jugador_id = p_jugador_id
    ) INTO v_exists;
    IF coalesce(v_exists, false) THEN
      NULL;
    END IF;
    RAISE EXCEPTION 'forbidden: asegurar_cuenta_organizador_jugador'
      USING ERRCODE = '42501';
  ELSE
    RAISE EXCEPTION 'forbidden: asegurar_cuenta_organizador_jugador'
      USING ERRCODE = '42501';
  END IF;

  IF p_organizador_id IS NULL OR p_jugador_id IS NULL THEN
    RAISE EXCEPTION 'cuenta_invalida' USING ERRCODE = 'P0001';
  END IF;
  IF p_organizador_id = p_jugador_id THEN
    RAISE EXCEPTION 'No puedes vincularte a tu propio grupo' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.organizador_jugadores (
    organizador_id, jugador_id, saldo_acumulado, activo, left_at
  ) VALUES (
    p_organizador_id, p_jugador_id, 0, true, NULL
  )
  ON CONFLICT (organizador_id, jugador_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.reabrir_cuenta_organizador_jugador(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_jwt_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
  v_uid uuid := coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
  v_exists boolean;
BEGIN
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL AND v_uid = p_organizador_id THEN
    NULL;
  ELSIF v_uid IS NOT NULL AND v_uid = p_jugador_id THEN
    SELECT EXISTS (
      SELECT 1 FROM public.organizador_jugadores oj
      WHERE oj.organizador_id = p_organizador_id
        AND oj.jugador_id = p_jugador_id
    ) INTO v_exists;
    IF coalesce(v_exists, false) THEN
      NULL;
    END IF;
    RAISE EXCEPTION 'forbidden: reabrir_cuenta_organizador_jugador'
      USING ERRCODE = '42501';
  ELSE
    RAISE EXCEPTION 'forbidden: reabrir_cuenta_organizador_jugador'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public.asegurar_cuenta_organizador_jugador(p_organizador_id, p_jugador_id);
  UPDATE public.organizador_jugadores
  SET activo = true, left_at = NULL
  WHERE organizador_id = p_organizador_id AND jugador_id = p_jugador_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bloquear_salida_cuenta_si_necesario(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_jwt_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'
  );
  v_uid uuid := coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
BEGIN
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL
        AND (v_uid = p_organizador_id OR v_uid = p_jugador_id) THEN
    NULL;
  ELSE
    RAISE EXCEPTION 'forbidden: bloquear_salida_cuenta_si_necesario'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.organizador_jugadores
  SET activo = false, left_at = now()
  WHERE organizador_id = p_organizador_id
    AND jugador_id = p_jugador_id
    AND activo = true;
END;
$$;

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

  -- C2: alta/rejoin tras validar código (DEFINER). No depende de reabrir.
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

REVOKE ALL ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bloquear_salida_cuenta_si_necesario(uuid, uuid) TO service_role;
