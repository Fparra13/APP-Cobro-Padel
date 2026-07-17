-- Datos de pago del organizador visibles para jugadores de su grupo.
-- UX: el jugador los ve en el cobro de ESA cuenta (multi-grupo = por organizador).

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS pago_titular text,
  ADD COLUMN IF NOT EXISTS pago_detalle text,
  ADD COLUMN IF NOT EXISTS pago_nota text;

-- ¿El jugador tiene vínculo con este organizador?
CREATE OR REPLACE FUNCTION public.jugador_vinculado_a_organizador(
  p_organizador_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    auth.uid() IS NOT NULL
    AND p_organizador_id IS NOT NULL
    AND (
      auth.uid() = p_organizador_id
      OR EXISTS (
        SELECT 1
        FROM public.organizador_jugadores oj
        WHERE oj.organizador_id = p_organizador_id
          AND oj.jugador_id = auth.uid()
      )
      OR EXISTS (
        SELECT 1
        FROM public.detalles_partido dp
        INNER JOIN public.partidos p ON p.id = dp.partido_id
        WHERE dp.jugador_id = auth.uid()
          AND p.organizador_id = p_organizador_id
      )
    );
$$;

CREATE OR REPLACE FUNCTION public.get_datos_pago_organizador(
  p_organizador_id uuid
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.profiles%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  IF NOT public.jugador_vinculado_a_organizador(p_organizador_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_row
  FROM public.profiles
  WHERE id = p_organizador_id;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false);
  END IF;

  RETURN json_build_object(
    'ok', true,
    'organizador_id', v_row.id,
    'organizador_nombre', coalesce(v_row.nombre, ''),
    'pago_titular', coalesce(v_row.pago_titular, ''),
    'pago_detalle', coalesce(v_row.pago_detalle, ''),
    'pago_nota', coalesce(v_row.pago_nota, '')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.guardar_datos_pago_organizador(
  p_titular text,
  p_detalle text,
  p_nota text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sesión requerida';
  END IF;

  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
  SET
    pago_titular = nullif(trim(coalesce(p_titular, '')), ''),
    pago_detalle = nullif(trim(coalesce(p_detalle, '')), ''),
    pago_nota = nullif(trim(coalesce(p_nota, '')), '')
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'perfil_no_encontrado' USING ERRCODE = 'P0001';
  END IF;

  RETURN json_build_object(
    'ok', true,
    'pago_titular', coalesce(p_titular, ''),
    'pago_detalle', coalesce(p_detalle, ''),
    'pago_nota', coalesce(p_nota, '')
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.jugador_vinculado_a_organizador(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_datos_pago_organizador(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.guardar_datos_pago_organizador(text, text, text) TO authenticated;
