-- =============================================================================
-- Seed DEMO PESADO — varios partidos grandes (20–30 jugadores)
-- =============================================================================
-- Uso:
--   1. Abre Supabase → SQL Editor
--   2. Cambia v_org_email por el email de TU organizador
--   3. Ejecuta TODO el script
--   4. Recarga la app (pull to refresh / reinicia)
--
-- Limpieza: supabase/scripts/cleanup_demo_pesado.sql
--
-- Qué crea:
--   • 40 jugadores [Demo] (emails *@matchpay.demo, sin auth)
--   • 7 partidos con circunstancias distintas (fútbol grande + pádel + cobros)
-- =============================================================================

DO $$
DECLARE
  -- >>> CAMBIA ESTO <<<
  v_org_email text := 'fparram13@gmail.com';

  v_org uuid;
  v_player_ids uuid[] := ARRAY[]::uuid[];
  v_id uuid;
  v_partido_id bigint;
  v_i int;
  v_estado text;
  v_es_suplente boolean;
  v_orden int;
  v_limite timestamptz := now() + interval '20 hours';
  v_cargo numeric(10,2);
  v_pagado boolean;
  v_monto numeric(10,2);
BEGIN
  SELECT id INTO v_org
  FROM public.profiles
  WHERE lower(trim(coalesce(email, ''))) = lower(trim(v_org_email))
  LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'No encontré organizador con email %. Cámbialo al inicio del script.', v_org_email;
  END IF;

  UPDATE public.profiles
  SET role = 'organizer'
  WHERE id = v_org AND role IS DISTINCT FROM 'organizer';

  -- -------------------------------------------------------------------------
  -- Limpia demo anterior (idempotente)
  -- -------------------------------------------------------------------------
  DELETE FROM public.partidos
  WHERE organizador_id = v_org
    AND (
      coalesce(notas, '') LIKE '[Demo]%'
      OR coalesce(recinto, '') LIKE '[Demo]%'
    );

  DELETE FROM public.profiles
  WHERE role = 'jugador'
    AND (
      nombre LIKE '[Demo]%'
      OR lower(coalesce(email, '')) LIKE '%@matchpay.demo'
    );

  -- -------------------------------------------------------------------------
  -- 40 jugadores demo
  -- -------------------------------------------------------------------------
  FOR v_i IN 1..40 LOOP
    INSERT INTO public.profiles (nombre, email, telefono, activo, role, saldo_acumulado)
    VALUES (
      format('[Demo] Jugador %s', lpad(v_i::text, 2, '0')),
      format('demo.jugador.%s@matchpay.demo', lpad(v_i::text, 2, '0')),
      format('+5690000%04s', v_i),
      true,
      'jugador',
      0
    )
    RETURNING id INTO v_id;
    v_player_ids := array_append(v_player_ids, v_id);

    INSERT INTO public.organizador_jugadores (organizador_id, jugador_id)
    VALUES (v_org, v_id)
    ON CONFLICT DO NOTHING;
  END LOOP;

  -- =========================================================================
  -- 1) Fútbol 30 cupos — casi lleno (22 conf / 5 pend / 3 rech) + 8 suplentes
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id
  ) VALUES (
    now() + interval '3 days' + interval '20 hours',
    120000, 15000,
    '[Demo] Estadio Norte',
    '[Demo] Fútbol 30 — mixto (conf/pend/rech + suplentes)',
    'organizando',
    30, 24, 'football', v_org
  ) RETURNING id INTO v_partido_id;

  FOR v_i IN 1..38 LOOP
    v_es_suplente := v_i > 30;
    v_orden := CASE WHEN v_es_suplente THEN v_i - 30 ELSE NULL END;
    IF v_es_suplente THEN
      v_estado := 'invitado';
    ELSIF v_i <= 22 THEN
      v_estado := 'confirmado';
    ELSIF v_i <= 27 THEN
      v_estado := 'invitado';
    ELSE
      v_estado := 'rechazado';
    END IF;

    INSERT INTO public.convocatoria_jugadores (
      partido_id, jugador_id, estado_confirmacion, es_suplente, orden_espera, tiempo_limite
    ) VALUES (
      v_partido_id, v_player_ids[v_i], v_estado, v_es_suplente, v_orden,
      CASE WHEN v_es_suplente THEN NULL ELSE v_limite END
    );
  END LOOP;

  -- =========================================================================
  -- 2) Fútbol 22 cupos — COMPLETO (22 confirmados)
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id
  ) VALUES (
    now() + interval '5 days' + interval '19 hours',
    90000, 10000,
    '[Demo] Cancha Municipal',
    '[Demo] Fútbol 22 — cupo completo',
    'confirmado',
    22, 24, 'football', v_org
  ) RETURNING id INTO v_partido_id;

  FOR v_i IN 1..22 LOOP
    INSERT INTO public.convocatoria_jugadores (
      partido_id, jugador_id, estado_confirmacion, es_suplente, tiempo_limite
    ) VALUES (
      v_partido_id, v_player_ids[v_i], 'confirmado', false, v_limite
    );
  END LOOP;

  -- =========================================================================
  -- 3) Fútbol 20 cupos — EN RIESGO (solo 7 confirmados, fecha cerca)
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id
  ) VALUES (
    now() + interval '10 hours',
    80000, 8000,
    '[Demo] Complejo Sur',
    '[Demo] Fútbol 20 — partido en riesgo',
    'organizando',
    20, 12, 'football', v_org
  ) RETURNING id INTO v_partido_id;

  FOR v_i IN 1..20 LOOP
    IF v_i <= 7 THEN
      v_estado := 'confirmado';
    ELSIF v_i <= 14 THEN
      v_estado := 'invitado';
    ELSE
      v_estado := 'rechazado';
    END IF;

    INSERT INTO public.convocatoria_jugadores (
      partido_id, jugador_id, estado_confirmacion, es_suplente, tiempo_limite
    ) VALUES (
      v_partido_id, v_player_ids[v_i + 5], v_estado, false, now() + interval '2 hours'
    );
  END LOOP;

  -- =========================================================================
  -- 4) Fútbol 28 — REPROGRAMADO (todos deben reconfirmar)
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id,
    reprogramado_en
  ) VALUES (
    now() + interval '6 days' + interval '18 hours',
    110000, 12000,
    '[Demo] Arena Centro',
    '[Demo] Fútbol 28 — reprogramado',
    'organizando',
    28, 24, 'football', v_org,
    now() - interval '1 hour'
  ) RETURNING id INTO v_partido_id;

  FOR v_i IN 1..28 LOOP
    INSERT INTO public.convocatoria_jugadores (
      partido_id, jugador_id, estado_confirmacion, es_suplente, tiempo_limite
    ) VALUES (
      v_partido_id, v_player_ids[v_i], 'invitado', false, now() + interval '24 hours'
    );
  END LOOP;

  -- =========================================================================
  -- 5) Fútbol 25 — CANCELADO (25 habían confirmado → popup/historial)
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id,
    resuelto_en
  ) VALUES (
    now() + interval '2 days' + interval '21 hours',
    95000, 9000,
    '[Demo] Parque Oeste',
    '[Demo] Fútbol 25 — cancelado',
    'cancelado',
    25, 24, 'football', v_org,
    now() - interval '30 minutes'
  ) RETURNING id INTO v_partido_id;

  FOR v_i IN 1..25 LOOP
    INSERT INTO public.convocatoria_jugadores (
      partido_id, jugador_id, estado_confirmacion, es_suplente, tiempo_limite
    ) VALUES (
      v_partido_id, v_player_ids[v_i], 'confirmado', false, NULL
    );
  END LOOP;

  -- =========================================================================
  -- 6) Pádel 4 — contraste chico (2 conf / 2 pend)
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id
  ) VALUES (
    now() + interval '1 day' + interval '20 hours',
    28000, 4000,
    '[Demo] Club Pádel',
    '[Demo] Pádel 4 — convocatoria chica',
    'organizando',
    4, 24, 'padel', v_org
  ) RETURNING id INTO v_partido_id;

  FOR v_i IN 1..4 LOOP
    INSERT INTO public.convocatoria_jugadores (
      partido_id, jugador_id, estado_confirmacion, es_suplente, tiempo_limite
    ) VALUES (
      v_partido_id,
      v_player_ids[30 + v_i],
      CASE WHEN v_i <= 2 THEN 'confirmado' ELSE 'invitado' END,
      false,
      v_limite
    );
  END LOOP;

  -- =========================================================================
  -- 7) Fútbol 20 — JUGADO con cobros (mitad pagó / mitad debe)
  -- =========================================================================
  INSERT INTO public.partidos (
    fecha, costo_cancha, costo_pelotas, recinto, notas, estado,
    cupos_max, horas_limite_respuesta, sport_type, organizador_id,
    resuelto_en
  ) VALUES (
    now() - interval '2 days',
    100000, 10000,
    '[Demo] Campo Viejo',
    '[Demo] Fútbol 20 — jugado con deudas',
    'jugado',
    20, 24, 'football', v_org,
    now() - interval '2 days'
  ) RETURNING id INTO v_partido_id;

  v_cargo := round((100000 + 10000) / 20.0, 2);

  FOR v_i IN 1..20 LOOP
    v_pagado := (v_i % 2 = 0);
    v_monto := CASE WHEN v_pagado THEN v_cargo ELSE 0 END;

    INSERT INTO public.detalles_partido (
      partido_id, jugador_id, asistio, prorrateo_fijo, total_variables, total,
      pagado, monto_pagado, fecha_pago
    ) VALUES (
      v_partido_id,
      v_player_ids[v_i],
      true,
      v_cargo,
      0,
      v_cargo,
      v_pagado,
      v_monto,
      CASE WHEN v_pagado THEN now() - interval '1 day' ELSE NULL END
    );

    INSERT INTO public.saldos_historicos (
      jugador_id, partido_id, saldo_anterior, cargo_partido, abono, saldo_nuevo, concepto
    ) VALUES (
      v_player_ids[v_i],
      v_partido_id,
      0,
      v_cargo,
      v_monto,
      v_cargo - v_monto,
      '[Demo] Cargo partido fútbol'
    );

    IF NOT v_pagado THEN
      UPDATE public.profiles
      SET saldo_acumulado = saldo_acumulado + v_cargo
      WHERE id = v_player_ids[v_i];
    END IF;
  END LOOP;

  RAISE NOTICE 'Demo pesado OK. Organizador=%s | 40 jugadores | 7 partidos', v_org_email;
END $$;

-- Verificación rápida
SELECT
  p.id,
  p.estado,
  p.cupos_max,
  p.sport_type,
  p.recinto,
  p.fecha,
  (SELECT count(*) FROM public.convocatoria_jugadores cj WHERE cj.partido_id = p.id) AS roster,
  (SELECT count(*) FROM public.convocatoria_jugadores cj
     WHERE cj.partido_id = p.id AND cj.estado_confirmacion = 'confirmado' AND cj.es_suplente = false) AS confirmados
FROM public.partidos p
WHERE coalesce(p.notas, '') LIKE '[Demo]%'
ORDER BY p.fecha DESC;

SELECT count(*) AS jugadores_demo
FROM public.profiles
WHERE nombre LIKE '[Demo]%';
