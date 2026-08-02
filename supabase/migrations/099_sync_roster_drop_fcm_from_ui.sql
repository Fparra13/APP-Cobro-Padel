-- 099: Roster incremental (A3) + quitar fcm_token de contratos UI (A6).
-- DEV: cambio incompatible intencional; no preserva datos de prueba.

-- ---------------------------------------------------------------------------
-- 1) Sync atómico del roster: insert / update de rol-orden / delete
--    NUNCA sobrescribe estado_confirmacion, tiempo_limite ni flags de aviso.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sincronizar_roster_convocatoria(
  p_partido_id bigint,
  p_jugadores jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partido public.partidos%ROWTYPE;
  v_enviada boolean := false;
  v_horas integer;
  v_titulares integer;
  v_item jsonb;
  v_jugador_id uuid;
  v_es_suplente boolean;
  v_orden integer;
  v_desired uuid[] := ARRAY[]::uuid[];
  v_existing public.convocatoria_jugadores%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  IF p_jugadores IS NULL OR jsonb_typeof(p_jugadores) <> 'array' THEN
    RAISE EXCEPTION 'invalid_roster: p_jugadores debe ser un array JSON'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_partido
  FROM public.partidos
  WHERE id = p_partido_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: partido %', p_partido_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Convoca enviada si algún titular ya tiene plazo.
  SELECT EXISTS (
    SELECT 1
    FROM public.convocatoria_jugadores
    WHERE partido_id = p_partido_id
      AND es_suplente = false
      AND tiempo_limite IS NOT NULL
  ) INTO v_enviada;

  v_horas := greatest(coalesce(v_partido.horas_limite_respuesta, 24), 1);

  -- Bloquear filas actuales del partido.
  PERFORM 1
  FROM public.convocatoria_jugadores
  WHERE partido_id = p_partido_id
  FOR UPDATE;

  -- Upsert / update incremental.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_jugadores)
  LOOP
    v_jugador_id := NULLIF(trim(v_item->>'jugador_id'), '')::uuid;
    IF v_jugador_id IS NULL THEN
      CONTINUE;
    END IF;

    IF v_jugador_id = ANY (v_desired) THEN
      RAISE EXCEPTION 'invalid_roster: jugador duplicado %', v_jugador_id
        USING ERRCODE = '23505';
    END IF;
    v_desired := array_append(v_desired, v_jugador_id);

    v_es_suplente := coalesce((v_item->>'es_suplente')::boolean, false);
    IF v_es_suplente THEN
      v_orden := NULLIF(v_item->>'orden_espera', '')::integer;
      IF v_orden IS NULL OR v_orden < 1 THEN
        RAISE EXCEPTION 'invalid_roster: suplente % sin orden_espera válido',
          v_jugador_id
          USING ERRCODE = '22023';
      END IF;
    ELSE
      v_orden := NULL;
    END IF;

    SELECT * INTO v_existing
    FROM public.convocatoria_jugadores
    WHERE partido_id = p_partido_id
      AND jugador_id = v_jugador_id;

    IF FOUND THEN
      -- Solo rol / orden. Preserva estado, plazos y recordatorios.
      IF v_existing.es_suplente IS DISTINCT FROM v_es_suplente
         OR v_existing.orden_espera IS DISTINCT FROM v_orden THEN
        UPDATE public.convocatoria_jugadores
        SET es_suplente = v_es_suplente,
            orden_espera = v_orden
        WHERE id = v_existing.id;
      END IF;
    ELSE
      INSERT INTO public.convocatoria_jugadores (
        partido_id,
        jugador_id,
        estado_confirmacion,
        es_suplente,
        orden_espera,
        tiempo_limite,
        notificado_vencimiento,
        recordatorio_plazo_enviado
      ) VALUES (
        p_partido_id,
        v_jugador_id,
        'invitado',
        v_es_suplente,
        v_orden,
        CASE
          WHEN v_enviada AND NOT v_es_suplente
            THEN now() + make_interval(hours => v_horas)
          ELSE NULL
        END,
        false,
        false
      );
    END IF;
  END LOOP;

  -- Quitar quienes ya no están en el roster deseado.
  DELETE FROM public.convocatoria_jugadores cj
  WHERE cj.partido_id = p_partido_id
    AND (
      cardinality(v_desired) = 0
      OR NOT (cj.jugador_id = ANY (v_desired))
    );

  -- Cupo: titulares activos (invitado|confirmado) no pueden superar cupos_max.
  SELECT count(*)::integer INTO v_titulares
  FROM public.convocatoria_jugadores
  WHERE partido_id = p_partido_id
    AND es_suplente = false
    AND estado_confirmacion IN ('invitado', 'confirmado');

  IF v_titulares > coalesce(v_partido.cupos_max, 0) THEN
    RAISE EXCEPTION 'cupo_excedido: % titulares activos > cupos_max %',
      v_titulares, v_partido.cupos_max
      USING ERRCODE = '23514';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.sincronizar_roster_convocatoria(bigint, jsonb) IS
  'Sincroniza roster de una convocatoria de forma incremental y atómica. '
  'Inserta nuevos, actualiza solo es_suplente/orden_espera, elimina ausentes. '
  'No modifica estado_confirmacion, tiempo_limite ni flags de recordatorio '
  'en filas existentes.';

REVOKE ALL ON FUNCTION public.sincronizar_roster_convocatoria(bigint, jsonb)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sincronizar_roster_convocatoria(bigint, jsonb)
  FROM anon;
GRANT EXECUTE ON FUNCTION public.sincronizar_roster_convocatoria(bigint, jsonb)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 2) Roster UI sin fcm_token (usa app_last_seen_at / usa_app)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_mis_jugadores_organizador(
  p_solo_activos boolean DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result json;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_organizer() THEN
    RETURN '[]'::json;
  END IF;

  SELECT coalesce(json_agg(row_to_json(t)), '[]'::json)
  INTO result
  FROM (
    SELECT
      pr.id,
      pr.nombre,
      pr.email,
      pr.telefono,
      pr.activo AS perfil_activo,
      pr.role,
      pr.foto_url,
      pr.app_last_seen_at,
      (pr.app_last_seen_at IS NOT NULL) AS usa_app,
      pr.created_at,
      oj.saldo_acumulado,
      oj.activo AS en_grupo_activo,
      oj.left_at
    FROM public.organizador_jugadores oj
    INNER JOIN public.profiles pr ON pr.id = oj.jugador_id
    WHERE oj.organizador_id = auth.uid()
      AND oj.activo = true
      AND (p_solo_activos IS NULL OR pr.activo = p_solo_activos)
    ORDER BY pr.nombre
  ) t;

  RETURN result;
END;
$$;

COMMENT ON FUNCTION public.get_mis_jugadores_organizador(boolean) IS
  'Roster del organizador autenticado sin fcm_token. '
  'usa_app / app_last_seen_at indican si el perfil abrió Kloovi.';

GRANT EXECUTE ON FUNCTION public.get_mis_jugadores_organizador(boolean)
  TO authenticated;
