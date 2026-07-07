-- Reparación: alinear detalles impagos, saldo_acumulado e historial.
-- Corrige perfiles desincronizados (ej. crédito consumido en historial pero no en profiles).

-- Marca partidos cubiertos según el snapshot del historial al registrar el partido.
CREATE OR REPLACE FUNCTION public.alinear_detalles_con_historico(p_jugador_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  filas integer := 0;
BEGIN
  IF p_jugador_id IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.detalles_partido dp
  SET
    pagado = true,
    fecha_pago = coalesce(dp.fecha_pago, sh.fecha, now()),
    monto_pagado = dp.monto_pagado,
    comprobante_validado = coalesce(dp.comprobante_validado, true),
    comprobante_url = null,
    monto_pago_declarado = null,
    pago_es_abono = null
  FROM public.saldos_historicos sh
  WHERE sh.jugador_id = p_jugador_id
    AND sh.partido_id = dp.partido_id
    AND dp.jugador_id = p_jugador_id
    AND dp.asistio = true
    AND dp.pagado = false
    AND sh.cargo_partido > 0.005
    AND greatest(
      greatest(
        sh.cargo_partido - CASE
          WHEN sh.saldo_anterior < 0
            THEN least(-sh.saldo_anterior, sh.cargo_partido)
          ELSE 0
        END,
        0
      ) - dp.monto_pagado,
      0
    ) <= 0.005;

  GET DIAGNOSTICS filas = ROW_COUNT;
  RETURN filas;
END;
$$;

-- Reconcilia detalles impagos con saldo a favor (consume crédito en orden cronológico).
CREATE OR REPLACE FUNCTION public.reconciliar_detalles_jugador(p_jugador_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  saldo_actual numeric;
  saldo_inicial numeric;
  r record;
  favor numeric;
  neto numeric;
  pend numeric;
  detalles_cerrados integer := 0;
BEGIN
  IF p_jugador_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'jugador nulo');
  END IF;

  SELECT coalesce(p.saldo_acumulado, 0)
  INTO saldo_actual
  FROM public.profiles p
  WHERE p.id = p_jugador_id;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'jugador no encontrado');
  END IF;

  saldo_inicial := saldo_actual;

  IF saldo_actual <= 0 THEN
    FOR r IN
      SELECT
        dp.id,
        dp.total,
        dp.monto_pagado
      FROM public.detalles_partido dp
      INNER JOIN public.partidos p ON p.id = dp.partido_id
      WHERE dp.jugador_id = p_jugador_id
        AND dp.asistio = true
        AND dp.pagado = false
      ORDER BY p.fecha ASC, dp.partido_id ASC
    LOOP
      favor := CASE
        WHEN saldo_actual >= 0 THEN 0
        ELSE least(-saldo_actual, r.total)
      END;
      neto := greatest(r.total - favor, 0);
      pend := greatest(neto - r.monto_pagado, 0);

      IF pend <= 0.005 THEN
        UPDATE public.detalles_partido
        SET
          pagado = true,
          fecha_pago = coalesce(fecha_pago, now()),
          monto_pagado = r.monto_pagado,
          comprobante_validado = coalesce(comprobante_validado, true),
          comprobante_url = null,
          monto_pago_declarado = null,
          pago_es_abono = null
        WHERE id = r.id;

        saldo_actual := round((saldo_actual + r.total - r.monto_pagado)::numeric, 2);
        detalles_cerrados := detalles_cerrados + 1;
      END IF;
    END LOOP;

    IF abs(saldo_actual - saldo_inicial) > 0.005 THEN
      UPDATE public.profiles
      SET saldo_acumulado = saldo_actual
      WHERE id = p_jugador_id;
    END IF;
  END IF;

  PERFORM public.recalcular_saldo_jugador(p_jugador_id);

  SELECT coalesce(p.saldo_acumulado, 0)
  INTO saldo_actual
  FROM public.profiles p
  WHERE p.id = p_jugador_id;

  RETURN json_build_object(
    'ok', true,
    'jugador_id', p_jugador_id,
    'saldo_inicial', saldo_inicial,
    'saldo_final', saldo_actual,
    'detalles_cerrados', detalles_cerrados
  );
END;
$$;

-- Repara un jugador: historial → detalles → reconciliar → recalcular saldo.
CREATE OR REPLACE FUNCTION public.reparar_jugador_cobros(p_jugador_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  alineados integer;
  rec json;
  saldo_final numeric;
BEGIN
  IF p_jugador_id IS NULL THEN
    RETURN json_build_object('ok', false, 'error', 'jugador nulo');
  END IF;

  alineados := public.alinear_detalles_con_historico(p_jugador_id);
  rec := public.reconciliar_detalles_jugador(p_jugador_id);
  saldo_final := public.recalcular_saldo_jugador(p_jugador_id);

  RETURN json_build_object(
    'ok', true,
    'jugador_id', p_jugador_id,
    'detalles_alineados_historico', alineados,
    'reconciliacion', rec,
    'saldo_final', saldo_final
  );
END;
$$;

-- Repara todos los jugadores vinculados a partidos del organizador autenticado.
CREATE OR REPLACE FUNCTION public.reparar_cobros_organizador()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jid uuid;
  resultados json[] := '{}';
  rep json;
  total integer := 0;
BEGIN
  IF NOT public.is_organizer() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  FOR jid IN
    SELECT DISTINCT dp.jugador_id
    FROM public.detalles_partido dp
    INNER JOIN public.partidos p ON p.id = dp.partido_id
    WHERE p.organizador_id = auth.uid()
       OR dp.jugador_id IN (
         SELECT cj.jugador_id
         FROM public.convocatoria_jugadores cj
         INNER JOIN public.partidos p2 ON p2.id = cj.partido_id
         WHERE p2.organizador_id = auth.uid()
       )
  LOOP
    rep := public.reparar_jugador_cobros(jid);
    resultados := array_append(resultados, rep);
    total := total + 1;
  END LOOP;

  RETURN json_build_object(
    'ok', true,
    'jugadores_reparados', total,
    'detalle', resultados
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.alinear_detalles_con_historico(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconciliar_detalles_jugador(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reparar_jugador_cobros(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reparar_cobros_organizador() TO authenticated;

-- Reparación puntual (emails del reporte). Idempotente.
DO $$
DECLARE
  emails text[] := ARRAY[
    'fparram13@gmail.com',
    'catitaboni2012@gmail.com'
  ];
  em text;
  jid uuid;
BEGIN
  FOREACH em IN ARRAY emails
  LOOP
    SELECT p.id INTO jid
    FROM public.profiles p
    WHERE lower(trim(coalesce(p.email, ''))) = lower(trim(em))
    LIMIT 1;

    IF jid IS NOT NULL THEN
      PERFORM public.reparar_jugador_cobros(jid);
      RAISE NOTICE 'Reparado jugador % (%)', em, jid;
    ELSE
      RAISE NOTICE 'No encontrado: %', em;
    END IF;
  END LOOP;
END;
$$;
