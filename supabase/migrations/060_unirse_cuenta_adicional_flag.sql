-- Flag es_cuenta_adicional al unirse a un segundo+ organizador.

CREATE OR REPLACE FUNCTION public.unirse_con_codigo_grupo(p_codigo text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    RAISE EXCEPTION 'Código inválido. Usa un código de 6 dígitos';
  END IF;

  SELECT id, nombre
  INTO v_org, v_nombre
  FROM public.profiles
  WHERE codigo_grupo = v_norm
    AND role IN ('organizer', 'organizador')
  LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'No encontramos un organizador con ese código';
  END IF;

  IF v_org = auth.uid() THEN
    RAISE EXCEPTION 'No puedes unirte a tu propio grupo con este código';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.organizador_jugadores
    WHERE organizador_id = v_org AND jugador_id = auth.uid()
  ) INTO v_existia;

  SELECT EXISTS (
    SELECT 1 FROM public.organizador_jugadores
    WHERE organizador_id = v_org AND jugador_id = auth.uid() AND activo = true
  ) INTO v_ya_activo;

  -- Otros organizadores distintos de este, antes de vincular/reabrir.
  SELECT count(*)::int INTO v_otros
  FROM public.organizador_jugadores
  WHERE jugador_id = auth.uid()
    AND organizador_id IS DISTINCT FROM v_org;

  -- Solo en unión nueva (no rejoin activo): explica cuentas separadas.
  v_cuenta_adicional := (v_otros > 0) AND (NOT v_ya_activo);

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
$$;
