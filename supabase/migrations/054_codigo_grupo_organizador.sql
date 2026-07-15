-- Código de grupo por organizador (generado por el servidor, único).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS codigo_grupo text;

COMMENT ON COLUMN public.profiles.codigo_grupo IS
  'Código público del organizador para que jugadores se unan (ej. KLOOVI-7F3Q). Solo organizadores.';

CREATE UNIQUE INDEX IF NOT EXISTS profiles_codigo_grupo_uidx
  ON public.profiles (codigo_grupo)
  WHERE codigo_grupo IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Generación
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generar_codigo_grupo_unico()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Sin 0/O/1/I/L para evitar confusiones al dictar.
  v_alphabet text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_code text;
  v_i int;
  v_attempt int := 0;
BEGIN
  LOOP
    v_code := 'KLOOVI-';
    FOR v_i IN 1..4 LOOP
      v_code := v_code || substr(
        v_alphabet,
        1 + floor(random() * length(v_alphabet))::int,
        1
      );
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
BEGIN
  v := upper(regexp_replace(trim(coalesce(p_codigo, '')), '[^A-Za-z0-9]', '', 'g'));
  IF v = '' THEN
    RETURN NULL;
  END IF;
  IF v LIKE 'KLOOVI%' THEN
    v := substr(v, 7); -- quita prefijo KLOOVI
  END IF;
  IF length(v) <> 4 THEN
    RETURN NULL;
  END IF;
  RETURN 'KLOOVI-' || v;
END;
$$;

-- Asegura código del organizador autenticado (crea si falta).
CREATE OR REPLACE FUNCTION public.obtener_mi_codigo_grupo()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'Solo el organizador tiene código de grupo';
  END IF;

  SELECT codigo_grupo INTO v_code
  FROM public.profiles
  WHERE id = auth.uid();

  IF v_code IS NULL OR btrim(v_code) = '' THEN
    v_code := public.generar_codigo_grupo_unico();
    UPDATE public.profiles
    SET codigo_grupo = v_code
    WHERE id = auth.uid();
  END IF;

  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.regenerar_mi_codigo_grupo()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'Solo el organizador puede regenerar el código';
  END IF;

  v_code := public.generar_codigo_grupo_unico();
  UPDATE public.profiles
  SET codigo_grupo = v_code
  WHERE id = auth.uid();

  RETURN v_code;
END;
$$;

-- Jugador (o cualquier auth) se une al roster del organizador.
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
  v_ya boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  v_norm := public.normalizar_codigo_grupo(p_codigo);
  IF v_norm IS NULL THEN
    RAISE EXCEPTION 'Código inválido. Usa el formato KLOOVI-XXXX';
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
    SELECT 1
    FROM public.organizador_jugadores
    WHERE organizador_id = v_org
      AND jugador_id = auth.uid()
  ) INTO v_ya;

  IF NOT v_ya THEN
    INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
    VALUES (v_org, auth.uid())
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN json_build_object(
    'organizador_id', v_org,
    'nombre', coalesce(nullif(trim(v_nombre), ''), 'Organizador'),
    'codigo', v_norm,
    'ya_estaba', v_ya
  );
END;
$$;

-- Grupos a los que pertenece el jugador autenticado.
CREATE OR REPLACE FUNCTION public.listar_mis_organizadores()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT coalesce(json_agg(row_to_json(t) ORDER BY t.nombre), '[]'::json)
  INTO result
  FROM (
    SELECT
      pr.id,
      pr.nombre,
      pr.foto_url,
      oj.created_at AS unido_en
    FROM public.organizador_jugadores oj
    INNER JOIN public.profiles pr ON pr.id = oj.organizador_id
    WHERE oj.jugador_id = auth.uid()
  ) t;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generar_codigo_grupo_unico() TO authenticated;
GRANT EXECUTE ON FUNCTION public.normalizar_codigo_grupo(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obtener_mi_codigo_grupo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.regenerar_mi_codigo_grupo() TO authenticated;
GRANT EXECUTE ON FUNCTION public.unirse_con_codigo_grupo(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.listar_mis_organizadores() TO authenticated;

-- Backfill: códigos para organizadores existentes.
DO $$
DECLARE
  r record;
  v_code text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.profiles
    WHERE role IN ('organizer', 'organizador')
      AND (codigo_grupo IS NULL OR btrim(codigo_grupo) = '')
  LOOP
    v_code := public.generar_codigo_grupo_unico();
    UPDATE public.profiles
    SET codigo_grupo = v_code
    WHERE id = r.id;
  END LOOP;
END;
$$;
