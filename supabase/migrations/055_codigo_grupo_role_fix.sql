-- Fix: role real es 'organizer' (también acepta 'organizador').

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

-- Backfill de códigos para organizadores sin código.
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
