-- Códigos de grupo: solo 6 dígitos. Sin legacy KLOOVI.
-- Regenera todos los códigos activos de organizadores al nuevo formato.

CREATE OR REPLACE FUNCTION public.normalizar_codigo_grupo(p_codigo text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v_digits text;
BEGIN
  v_digits := regexp_replace(trim(coalesce(p_codigo, '')), '[^0-9]', '', 'g');
  IF length(v_digits) = 6 THEN
    RETURN v_digits;
  END IF;
  RETURN NULL;
END;
$$;

-- Regenera códigos de organizadores (y cualquier perfil con código no-numérico).
DO $$
DECLARE
  r record;
  v_code text;
BEGIN
  FOR r IN
    SELECT id
    FROM public.profiles
    WHERE role IN ('organizer', 'organizador')
       OR (codigo_grupo IS NOT NULL AND btrim(codigo_grupo) <> '')
    ORDER BY id
  LOOP
    -- Libera el valor actual para que no bloquee unicidad al regenerar.
    UPDATE public.profiles
    SET codigo_grupo = NULL
    WHERE id = r.id;

    v_code := public.generar_codigo_grupo_unico();

    UPDATE public.profiles
    SET codigo_grupo = v_code
    WHERE id = r.id;
  END LOOP;
END;
$$;
