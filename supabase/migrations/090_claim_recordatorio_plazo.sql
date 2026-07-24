-- =============================================================================
-- 090: Claim atómico del recordatorio de plazo (<1 h) de convocatoria
-- =============================================================================
-- Evita doble push cuando varios clientes sincronizan en paralelo:
--   UPDATE ... WHERE recordatorio_plazo_enviado = false RETURNING id
-- Solo el caller que recibe id debe enviar la notificación.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.claim_recordatorio_plazo(
  p_partido_id bigint,
  p_jugador_id uuid
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated'
      USING ERRCODE = '42501';
  END IF;

  IF p_partido_id IS NULL OR p_jugador_id IS NULL THEN
    RAISE EXCEPTION 'invalid_args'
      USING ERRCODE = '22023';
  END IF;

  -- Organizador del partido o el propio jugador (mismo alcance que sync lista espera).
  IF NOT (
    public.owns_partido(p_partido_id)
    OR auth.uid() = p_jugador_id
  ) THEN
    RAISE EXCEPTION 'permission_denied'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.convocatoria_jugadores
  SET recordatorio_plazo_enviado = true
  WHERE partido_id = p_partido_id
    AND jugador_id = p_jugador_id
    AND recordatorio_plazo_enviado = false
    AND estado_confirmacion = 'invitado'
    AND coalesce(es_suplente, false) = false
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.claim_recordatorio_plazo(bigint, uuid) IS
  'Claim atómico: marca recordatorio_plazo_enviado. Devuelve id si ganó el claim; null si ya enviado.';

REVOKE ALL ON FUNCTION public.claim_recordatorio_plazo(bigint, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_recordatorio_plazo(bigint, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.claim_recordatorio_plazo(bigint, uuid) TO authenticated;
