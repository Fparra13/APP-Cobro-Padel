-- =============================================================================
-- 084: C2 — reemplazar GUC frágil por INSERT en unirse + EXISTS en asegurar/reabrir
-- =============================================================================
-- Motivo: set_config('kloovi.allow_player_cuenta_link') no era visible de forma
-- fiable dentro de las RPC SECURITY DEFINER (validación falló con GUC=1).
--
-- Estrategia:
--   1) Jugador solo puede pasar authz en asegurar/reabrir si el vínculo YA existe.
--   2) unirse_con_codigo_grupo (DEFINER) hace INSERT del vínculo tras validar código,
--      luego llama reabrir (reactivación / asegurar idempotente).
--   3) Residual recalcular→asegurar queda bloqueado (sin fila previa → forbidden).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.asegurar_cuenta_organizador_jugador(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jwt_role text := nullif(current_setting('request.jwt.claim.role', true), '');
  v_uid uuid := auth.uid();
  v_exists boolean;
BEGIN
  IF v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role' THEN
    NULL;
  ELSIF v_jwt_role IS NULL AND v_uid IS NULL THEN
    NULL;
  ELSIF v_uid IS NOT NULL AND v_uid = p_organizador_id THEN
    NULL;
  ELSIF v_uid IS NOT NULL AND v_uid = p_jugador_id THEN
    -- Jugador: solo vínculos ya existentes (alta nueva = unirse INSERT + código).
    SELECT EXISTS (
      SELECT 1 FROM public.organizador_jugadores oj
      WHERE oj.organizador_id = p_organizador_id
        AND oj.jugador_id = p_jugador_id
    ) INTO v_exists;
    IF v_exists THEN
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
SET search_path = public
AS $$
DECLARE
  v_jwt_role text := nullif(current_setting('request.jwt.claim.role', true), '');
  v_uid uuid := auth.uid();
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
    IF v_exists THEN
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

CREATE OR REPLACE FUNCTION public.unirse_con_codigo_grupo(p_codigo text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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

  -- C2: alta nueva tras validar código (DEFINER). Luego reabrir reactiva.
  INSERT INTO public.organizador_jugadores (
    organizador_id, jugador_id, saldo_acumulado, activo, left_at
  ) VALUES (
    v_org, auth.uid(), 0, true, NULL
  )
  ON CONFLICT (organizador_id, jugador_id) DO NOTHING;

  PERFORM public.reabrir_cuenta_organizador_jugador(v_org, auth.uid());

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

COMMENT ON FUNCTION public.asegurar_cuenta_organizador_jugador(uuid, uuid) IS
  'C2 hardened (+084). Jugador solo si vínculo existe; alta nueva vía unirse+código.';

COMMENT ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) IS
  'C2 hardened (+084). Misma regla de alta nueva como jugador que asegurar.';

-- =============================================================================
-- DOWN: restaurar 083 (GUC) o 082 según rollback deseado.
-- =============================================================================
