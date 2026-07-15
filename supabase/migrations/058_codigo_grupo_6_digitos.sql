-- Código de grupo: 6 dígitos numéricos (texto, preserva ceros a la izquierda).
-- Unicidad: sin cambios (índice profiles_codigo_grupo_uidx + NOT EXISTS en generación).

COMMENT ON COLUMN public.profiles.codigo_grupo IS
  'Código público del organizador para que jugadores se unan (6 dígitos, ej. 482913). Solo organizadores. Texto para preservar ceros a la izquierda.';

CREATE OR REPLACE FUNCTION public.generar_codigo_grupo_unico()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_i int;
  v_attempt int := 0;
BEGIN
  LOOP
    -- 6 dígitos 0-9 como texto (incluye ceros a la izquierda, ej. 042913).
    v_code := '';
    FOR v_i IN 1..6 LOOP
      v_code := v_code || (floor(random() * 10)::int)::text;
    END LOOP;

    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE codigo_grupo = v_code
    );

    v_attempt := v_attempt + 1;
    IF v_attempt > 40 THEN
      RAISE EXCEPTION 'No se pudo generar un código de grupo único';
    END IF;
  END LOOP;

  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.normalizar_codigo_grupo(p_codigo text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text;
  v_digits text;
BEGIN
  -- Nuevo formato: exactamente 6 dígitos (ignora espacios/guiones).
  v_digits := regexp_replace(trim(coalesce(p_codigo, '')), '[^0-9]', '', 'g');
  IF length(v_digits) = 6 THEN
    RETURN v_digits;
  END IF;

  -- Legacy KLOOVI-XXXX mientras queden códigos antiguos en profiles.
  v := upper(regexp_replace(trim(coalesce(p_codigo, '')), '[^A-Za-z0-9]', '', 'g'));
  IF v = '' THEN
    RETURN NULL;
  END IF;
  IF v LIKE 'KLOOVI%' THEN
    v := substr(v, 7);
  END IF;
  IF length(v) = 4 AND v ~ '^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]+$' THEN
    RETURN 'KLOOVI-' || v;
  END IF;

  RETURN NULL;
END;
$$;

-- Solo el mensaje de formato (misma lógica de unión que 056).
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

  PERFORM public.reabrir_cuenta_organizador_jugador(v_org, auth.uid());

  RETURN json_build_object(
    'organizador_id', v_org,
    'nombre', coalesce(nullif(trim(v_nombre), ''), 'Organizador'),
    'codigo', v_norm,
    'ya_estaba', v_ya_activo,
    'reabierto', v_existia AND NOT v_ya_activo
  );
END;
$$;
