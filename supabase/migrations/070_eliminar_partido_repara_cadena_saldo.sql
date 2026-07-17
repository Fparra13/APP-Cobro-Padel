-- Al borrar un partido (esp. cuenta dual org=jugador), si no se recalcula el
-- saldo o queda un salto en la cadena de historicos, el home del jugador sigue
-- mostrando deuda fantasma. Repara saltos solo en filas de CARGO (no reescribe
-- abonos) y asegura recalc + CASCADE en partido_id.

CREATE OR REPLACE FUNCTION public.reparar_saltos_cargo_cadena_saldo(
  p_organizador_id uuid,
  p_jugador_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_prev numeric;
  v_nuevo numeric;
BEGIN
  IF p_organizador_id IS NULL OR p_jugador_id IS NULL THEN
    RETURN;
  END IF;

  v_prev := NULL;

  FOR r IN
    SELECT id, cargo_partido, abono, saldo_anterior, saldo_nuevo
    FROM public.saldos_historicos
    WHERE organizador_id = p_organizador_id
      AND jugador_id = p_jugador_id
    ORDER BY id ASC
    FOR UPDATE
  LOOP
    IF v_prev IS NOT NULL
       AND abs(coalesce(r.saldo_anterior, 0) - v_prev) > 0.01
       AND coalesce(r.cargo_partido, 0) > 0.005
    THEN
      v_nuevo := round(
        v_prev + coalesce(r.cargo_partido, 0) - coalesce(r.abono, 0),
        2
      );
      UPDATE public.saldos_historicos
      SET
        saldo_anterior = v_prev,
        saldo_nuevo = v_nuevo
      WHERE id = r.id;
      v_prev := v_nuevo;
    ELSE
      v_prev := r.saldo_nuevo;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.eliminar_partido_completo(p_partido_id bigint)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := auth.uid();
  jugador_ids uuid[];
  jid uuid;
BEGIN
  IF NOT public.is_organizer() OR NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = p_partido_id;

  DELETE FROM public.saldos_historicos WHERE partido_id = p_partido_id;
  DELETE FROM public.partidos WHERE id = p_partido_id;

  IF jugador_ids IS NOT NULL AND v_org IS NOT NULL THEN
    FOREACH jid IN ARRAY jugador_ids LOOP
      -- Incluye self (dual): el organizador también puede tener deuda de su cupo.
      PERFORM public.reparar_saltos_cargo_cadena_saldo(v_org, jid);
      PERFORM public.recalcular_saldo_cuenta(v_org, jid);
    END LOOP;
  END IF;

  RETURN json_build_object('jugadores', jugador_ids);
END;
$$;

-- Si el partido se borra fuera del RPC, limpiar historicos y recalcular.
CREATE OR REPLACE FUNCTION public.cleanup_saldos_on_partido_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jugador_ids uuid[];
  jid uuid;
BEGIN
  SELECT coalesce(array_agg(DISTINCT dp.jugador_id), '{}'::uuid[])
  INTO jugador_ids
  FROM public.detalles_partido dp
  WHERE dp.partido_id = OLD.id;

  DELETE FROM public.saldos_historicos WHERE partido_id = OLD.id;

  IF OLD.organizador_id IS NOT NULL AND jugador_ids IS NOT NULL THEN
    FOREACH jid IN ARRAY jugador_ids LOOP
      PERFORM public.reparar_saltos_cargo_cadena_saldo(OLD.organizador_id, jid);
      PERFORM public.recalcular_saldo_cuenta(OLD.organizador_id, jid);
    END LOOP;
  END IF;

  RETURN OLD;
END;
$$;

-- Evita huérfanos con partido_id NULL (SET NULL) que dejan deuda en la cadena.
ALTER TABLE public.saldos_historicos
  DROP CONSTRAINT IF EXISTS saldos_historicos_partido_id_fkey;

ALTER TABLE public.saldos_historicos
  ADD CONSTRAINT saldos_historicos_partido_id_fkey
  FOREIGN KEY (partido_id) REFERENCES public.partidos(id) ON DELETE CASCADE;

-- Reparación one-shot: saltos de cargo ya existentes + sync oj.saldo_acumulado.
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT DISTINCT organizador_id, jugador_id
    FROM public.saldos_historicos
  LOOP
    PERFORM public.reparar_saltos_cargo_cadena_saldo(r.organizador_id, r.jugador_id);
    PERFORM public.recalcular_saldo_cuenta(r.organizador_id, r.jugador_id);
  END LOOP;

  -- Cuentas con saldo pero sin historicos → 0.
  UPDATE public.organizador_jugadores oj
  SET saldo_acumulado = 0
  WHERE abs(coalesce(oj.saldo_acumulado, 0)) > 0.005
    AND NOT EXISTS (
      SELECT 1
      FROM public.saldos_historicos sh
      WHERE sh.organizador_id = oj.organizador_id
        AND sh.jugador_id = oj.jugador_id
    );
END;
$$;
