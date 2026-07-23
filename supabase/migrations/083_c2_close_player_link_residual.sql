-- =============================================================================
-- 083: C2 follow-up — cerrar residual player→asegurar vía recalcular
-- =============================================================================
-- Hallazgo post-082 (FASE 5):
--   recalcular_saldo_cuenta permite auth.uid() = p_jugador_id sin vínculo previo,
--   luego asegurar_fila → asegurar_cuenta crea el vínculo (bypass del código de grupo).
--   Evidencia live: before_n=0 → after_n=1 con JWT de jugador sobre org ajena.
--
-- Estrategia (mínima, sin tocar recalcular/vincular):
--   - En asegurar/reabrir: si auth.uid() = jugador_id y el vínculo NO existe,
--     exigir GUC local kloovi.allow_player_cuenta_link=1.
--   - unirse_con_codigo_grupo (único flujo legítimo de alta como jugador) setea
--     esa GUC justo antes de reabrir. Cambio mínimo de 1 línea + comentario.
--   - Reactivar vínculo existente como jugador: NO requiere GUC.
--   - Organizador / service_role: sin cambio de comportamiento.
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
  v_player_link_ok boolean := (
    nullif(current_setting('kloovi.allow_player_cuenta_link', true), '') = '1'
  );
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
    IF v_exists OR v_player_link_ok THEN
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
  v_player_link_ok boolean := (
    nullif(current_setting('kloovi.allow_player_cuenta_link', true), '') = '1'
  );
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
    IF v_exists OR v_player_link_ok THEN
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

-- C2 residual: habilitar alta como jugador SOLO tras validar código de grupo.
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

  -- C2: autoriza INSERT de vínculo nuevo como jugador (transaction-local).
  PERFORM set_config('kloovi.allow_player_cuenta_link', '1', true);
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
  'C2 hardened (+083). Alta nueva como jugador requiere GUC kloovi.allow_player_cuenta_link (unirse).';

COMMENT ON FUNCTION public.reabrir_cuenta_organizador_jugador(uuid, uuid) IS
  'C2 hardened (+083). Misma regla de alta nueva como jugador que asegurar.';

-- =============================================================================
-- DOWN: restaurar cuerpos 082 (sin GUC) y unirse sin set_config.
-- =============================================================================
