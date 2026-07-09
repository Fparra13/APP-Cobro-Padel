-- Crear jugadores pre-registro (nombre + WhatsApp/email opcional) desde la app organizador.

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;
ALTER TABLE public.profiles ALTER COLUMN telefono DROP NOT NULL;
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_telefono_key;

DROP POLICY IF EXISTS "Organizador ve jugadores" ON public.profiles;
CREATE POLICY "Organizador ve jugadores"
  ON public.profiles
  FOR SELECT
  USING (public.is_organizer() AND role = 'jugador');

DROP POLICY IF EXISTS "Organizador puede crear jugadores" ON public.profiles;
CREATE POLICY "Organizador puede crear jugadores"
  ON public.profiles
  FOR INSERT
  WITH CHECK (public.is_organizer() AND role = 'jugador');

CREATE OR REPLACE FUNCTION public.crear_jugador_organizador(
  p_nombre text,
  p_email text DEFAULT NULL,
  p_telefono text DEFAULT NULL,
  p_activo boolean DEFAULT TRUE
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.profiles;
  v_email text;
  v_tel text;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF nullif(trim(p_nombre), '') IS NULL THEN
    RAISE EXCEPTION 'nombre_requerido';
  END IF;

  v_email := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_tel := nullif(trim(coalesce(p_telefono, '')), '');

  INSERT INTO public.profiles (nombre, email, telefono, activo, role)
  VALUES (
    trim(p_nombre),
    v_email,
    v_tel,
    coalesce(p_activo, TRUE),
    'jugador'
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.crear_jugador_organizador(text, text, text, boolean)
  TO authenticated;
