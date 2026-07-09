-- Alinea expiración de convocatoria con la app: vence al pasar la hora del partido.

CREATE OR REPLACE FUNCTION public.partido_convocatoria_expirada(p_fecha timestamptz)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT p_fecha <= now();
$$;
