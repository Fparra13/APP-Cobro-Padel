-- Gate Pro INSERT — matriz de pruebas (ejecutar en DEV con rol admin / MCP).
-- No aplica a PROD. Limpia filas de prueba al final.
--
-- Usuarios DEV esperados (ajustar si cambian):
--   org    = b382c4c1-1c45-4d1a-87e8-3c584fd3a462  (organizer, sin staff)
--   staff  = b419795e-c8b1-4885-84fe-4dadade794e0  (organizer, acceso_ilimitado)
--   player = 1001799f-6234-4461-b899-7f5f771cca63  (jugador)

CREATE TEMP TABLE gate_pro_results (
  caso text PRIMARY KEY,
  esperado text,
  resultado text,
  detalle text
);

CREATE OR REPLACE FUNCTION pg_temp.set_auth(p_uid uuid, p_role text DEFAULT 'authenticated')
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
  PERFORM set_config(
    'request.jwt.claims',
    CASE
      WHEN p_uid IS NULL THEN '{}'
      ELSE json_build_object('sub', p_uid::text, 'role', p_role)::text
    END,
    true
  );
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.clear_auth()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claims', '{}', true);
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.try_insert_partido(
  p_org uuid,
  p_estado text DEFAULT 'organizando'
)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_id bigint;
BEGIN
  INSERT INTO public.partidos (
    fecha, organizador_id, estado, costo_cancha, costo_pelotas, cupos_max
  )
  VALUES (now() + interval '7 days', p_org, p_estado, 0, 0, 4)
  RETURNING id INTO v_id;
  RETURN 'OK id=' || v_id::text;
EXCEPTION WHEN others THEN
  RETURN SQLSTATE || ':' || SQLERRM;
END;
$$;

DO $$
DECLARE
  org uuid := 'b382c4c1-1c45-4d1a-87e8-3c584fd3a462';
  staff uuid := 'b419795e-c8b1-4885-84fe-4dadade794e0';
  player uuid := '1001799f-6234-4461-b899-7f5f771cca63';
  other_org uuid := '6c0c7d11-0345-45e5-9391-a99a1ec8b325';
  r text;
  v_partido_id bigint;
  v_upd_ok boolean;
  v_prev_status text;
  v_prev_expires timestamptz;
  v_prev_revoked timestamptz;
  v_prev_product text;
  v_had_sub boolean := false;
  v_id1 bigint;
  v_id2 bigint;
BEGIN
  SELECT true, status, expires_at, revoked_at, product_id
    INTO v_had_sub, v_prev_status, v_prev_expires, v_prev_revoked, v_prev_product
  FROM public.billing_subscriptions WHERE user_id = org;
  IF NOT FOUND THEN
    v_had_sub := false;
  END IF;
  DELETE FROM public.billing_subscriptions WHERE user_id = org;

  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(org);
  INSERT INTO gate_pro_results VALUES (
    'Organizer sin Pro crea', 'FAIL pro_required',
    CASE WHEN r LIKE '42501:%pro_required%' THEN 'PASS' ELSE 'FAIL' END, r
  );
  INSERT INTO gate_pro_results VALUES (
    'REST directo sin Pro', 'FAIL pro_required',
    CASE WHEN r LIKE '42501:%pro_required%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.clear_auth();
  INSERT INTO public.billing_subscriptions (
    user_id, product_id, status, expires_at, is_trial, revoked_at
  ) VALUES (org, 'kloovi_pro_gate_test', 'trial', now() + interval '7 days', true, NULL);
  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(org, 'organizando');
  INSERT INTO gate_pro_results VALUES (
    'Organizer trial crea', 'OK',
    CASE WHEN r LIKE 'OK%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.clear_auth();
  UPDATE public.billing_subscriptions
     SET status = 'active', is_trial = false,
         expires_at = now() + interval '30 days', revoked_at = NULL
   WHERE user_id = org;
  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(org, 'jugado');
  INSERT INTO gate_pro_results VALUES (
    'Organizer active crea', 'OK',
    CASE WHEN r LIKE 'OK%' THEN 'PASS' ELSE 'FAIL' END, r
  );
  INSERT INTO gate_pro_results VALUES (
    'REST directo con Pro', 'OK',
    CASE WHEN r LIKE 'OK%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  BEGIN
    INSERT INTO public.partidos (fecha, organizador_id, estado)
    VALUES (now() + interval '8 days', org, 'organizando') RETURNING id INTO v_id1;
    INSERT INTO public.partidos (fecha, organizador_id, estado)
    VALUES (now() + interval '9 days', org, 'organizando') RETURNING id INTO v_id2;
    INSERT INTO gate_pro_results VALUES (
      'Concurrencia dos INSERT con Pro', 'OK ambos', 'PASS',
      'ids=' || v_id1 || ',' || v_id2
    );
  EXCEPTION WHEN others THEN
    INSERT INTO gate_pro_results VALUES (
      'Concurrencia dos INSERT con Pro', 'OK ambos', 'FAIL',
      SQLSTATE || ':' || SQLERRM
    );
  END;

  PERFORM pg_temp.clear_auth();
  UPDATE public.billing_subscriptions
     SET status = 'canceled', expires_at = now() + interval '10 days', revoked_at = NULL
   WHERE user_id = org;
  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(org);
  INSERT INTO gate_pro_results VALUES (
    'Organizer canceled vigente crea', 'OK',
    CASE WHEN r LIKE 'OK%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.clear_auth();
  UPDATE public.billing_subscriptions
     SET status = 'canceled', expires_at = now() - interval '1 day', revoked_at = NULL
   WHERE user_id = org;
  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(org);
  INSERT INTO gate_pro_results VALUES (
    'Organizer expired crea', 'FAIL pro_required',
    CASE WHEN r LIKE '42501:%pro_required%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.clear_auth();
  UPDATE public.billing_subscriptions
     SET status = 'active', expires_at = now() + interval '30 days', revoked_at = now()
   WHERE user_id = org;
  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(org);
  INSERT INTO gate_pro_results VALUES (
    'Organizer revoked crea', 'FAIL pro_required',
    CASE WHEN r LIKE '42501:%pro_required%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.clear_auth();
  DELETE FROM public.billing_subscriptions WHERE user_id = org;
  PERFORM pg_temp.set_auth(staff, 'authenticated');
  r := pg_temp.try_insert_partido(staff);
  INSERT INTO gate_pro_results VALUES (
    'Staff crea', 'OK',
    CASE WHEN r LIKE 'OK%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.set_auth(player, 'authenticated');
  r := pg_temp.try_insert_partido(player);
  INSERT INTO gate_pro_results VALUES (
    'Player crea', 'FAIL',
    CASE WHEN r LIKE '42501:%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.set_auth(org, 'authenticated');
  r := pg_temp.try_insert_partido(other_org);
  INSERT INTO gate_pro_results VALUES (
    'Organizer falseando owner', 'FAIL',
    CASE WHEN r LIKE '42501:%' THEN 'PASS' ELSE 'FAIL' END, r
  );

  PERFORM pg_temp.clear_auth();
  DELETE FROM public.billing_subscriptions WHERE user_id = org;
  PERFORM pg_temp.set_auth(org, 'service_role');
  INSERT INTO public.partidos (fecha, organizador_id, estado)
  VALUES (now() + interval '3 days', org, 'organizando')
  RETURNING id INTO v_partido_id;

  PERFORM pg_temp.set_auth(org, 'authenticated');
  BEGIN
    UPDATE public.partidos
       SET estado = 'cancelado'
     WHERE id = v_partido_id AND organizador_id = org;
    v_upd_ok := FOUND;
    INSERT INTO gate_pro_results VALUES (
      'Organizer sin Pro edita existente', 'OK',
      CASE WHEN v_upd_ok THEN 'PASS' ELSE 'FAIL' END,
      'partido_id=' || v_partido_id || ' updated=' || v_upd_ok::text
    );
  EXCEPTION WHEN others THEN
    INSERT INTO gate_pro_results VALUES (
      'Organizer sin Pro edita existente', 'OK', 'FAIL',
      SQLSTATE || ':' || SQLERRM
    );
  END;

  PERFORM pg_temp.clear_auth();
  DELETE FROM public.partidos
   WHERE organizador_id IN (org, staff)
     AND created_at > now() - interval '5 minutes'
     AND costo_cancha = 0 AND costo_pelotas = 0;

  DELETE FROM public.billing_subscriptions WHERE user_id = org;
  IF v_had_sub THEN
    INSERT INTO public.billing_subscriptions (
      user_id, product_id, status, expires_at, revoked_at
    ) VALUES (
      org, coalesce(v_prev_product, 'restored'),
      v_prev_status, v_prev_expires, v_prev_revoked
    );
  END IF;
END;
$$;

SELECT * FROM gate_pro_results ORDER BY caso;
