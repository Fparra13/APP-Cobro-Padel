-- Al registrar un encuentro donde el organizador también asiste,
-- recalcular_saldo_cuenta llamaba a asegurar_cuenta_organizador_jugador(org, org)
-- y fallaba con "No puedes vincularte a tu propio grupo" (HTTP 400).
-- Dual: el organizador no tiene cuenta de cobro consigo mismo; el detalle/
-- historial sí se guardan. Recalcular debe ser no-op en ese caso.

CREATE OR REPLACE FUNCTION public.recalcular_saldo_cuenta(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nuevo numeric := 0;
BEGIN
  IF p_organizador_id IS NULL OR p_jugador_id IS NULL THEN
    RETURN 0;
  END IF;

  -- Dual: sin cuenta org↔org. No hay saldo de cuenta que actualizar.
  IF p_organizador_id = p_jugador_id THEN
    RETURN 0;
  END IF;

  -- Authz: org dueño, o el propio jugador, o owner/migración (sin jwt).
  IF auth.uid() IS NOT NULL THEN
    IF auth.uid() IS DISTINCT FROM p_jugador_id
       AND NOT (
         public.is_organizer()
         AND auth.uid() = p_organizador_id
         AND EXISTS (
           SELECT 1 FROM public.organizador_jugadores oj
           WHERE oj.organizador_id = p_organizador_id
             AND oj.jugador_id = p_jugador_id
         )
       )
    THEN
      RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
    END IF;
  END IF;

  PERFORM public.asegurar_cuenta_organizador_jugador(p_organizador_id, p_jugador_id);

  SELECT sh.saldo_nuevo
  INTO nuevo
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
    AND sh.organizador_id = p_organizador_id
  ORDER BY sh.id DESC
  LIMIT 1;

  nuevo := coalesce(nuevo, 0);

  UPDATE public.organizador_jugadores
  SET saldo_acumulado = nuevo
  WHERE organizador_id = p_organizador_id
    AND jugador_id = p_jugador_id;

  RETURN nuevo;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalcular_saldos_cuentas(
  p_organizador_id uuid,
  p_jugador_ids uuid[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_organizador_id IS NULL OR p_jugador_ids IS NULL THEN
    RETURN;
  END IF;
  FOREACH v_id IN ARRAY p_jugador_ids LOOP
    IF v_id IS DISTINCT FROM p_organizador_id THEN
      PERFORM public.recalcular_saldo_cuenta(p_organizador_id, v_id);
    END IF;
  END LOOP;
END;
$$;
