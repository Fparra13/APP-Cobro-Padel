-- 048: anti-escalada signup + confirmación atómica con cupo.
-- 1) handle_new_user nunca toma role desde user_metadata.
-- 2) actualizar_confirmacion_jugador con lock + cupo + plazo.
-- 3) Jugadores ya no UPDATE directo convocatoria (solo RPC / dueño partido).
-- 4) Trigger defensa: no confirmar sobre cupo; no mutar columnas sensibles como jugador.

-- ---------------------------------------------------------------------------
-- A) Signup: siempre jugador salvo merge de cuenta auth ya existente
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
  existing_id uuid;
  existing_rec public.profiles%ROWTYPE;
  user_nombre text;
  merged_role text;
BEGIN
  user_email := lower(trim(coalesce(new.email, '')));
  user_nombre := coalesce(
    nullif(trim(new.raw_user_meta_data->>'nombre'), ''),
    nullif(split_part(user_email, '@', 1), ''),
    'Sin nombre'
  );
  -- Nunca confiar en raw_user_meta_data.role (controlado por el cliente).

  IF user_email <> '' THEN
    SELECT p.id
    INTO existing_id
    FROM public.profiles p
    WHERE p.id <> new.id
      AND (
        lower(trim(coalesce(p.email, ''))) = user_email
        OR lower(trim(coalesce(p.telefono, ''))) = user_email
      )
    ORDER BY
      CASE WHEN EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id) THEN 0 ELSE 1 END,
      p.created_at ASC
    LIMIT 1;
  END IF;

  IF existing_id IS NOT NULL THEN
    SELECT * INTO existing_rec FROM public.profiles WHERE id = existing_id;

    UPDATE public.convocatoria_jugadores
    SET jugador_id = new.id
    WHERE jugador_id = existing_id;

    UPDATE public.detalles_partido
    SET jugador_id = new.id
    WHERE jugador_id = existing_id;

    UPDATE public.asignaciones_costo
    SET jugador_id = new.id
    WHERE jugador_id = existing_id;

    UPDATE public.saldos_historicos
    SET jugador_id = new.id
    WHERE jugador_id = existing_id;

    UPDATE public.partidos
    SET organizador_id = new.id
    WHERE organizador_id = existing_id;

    DELETE FROM public.profiles WHERE id = existing_id;

    -- Solo conserva role si el perfil fusionado ya tenía cuenta auth.
    -- Pre-registros (creados por organizador) siempre entran como jugador.
    IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id = existing_id) THEN
      merged_role := coalesce(nullif(trim(existing_rec.role), ''), 'jugador');
    ELSE
      merged_role := 'jugador';
    END IF;

    INSERT INTO public.profiles (
      id, nombre, email, telefono, activo, role,
      saldo_acumulado, foto_url, fcm_token, created_at
    ) VALUES (
      new.id,
      coalesce(nullif(trim(existing_rec.nombre), ''), user_nombre),
      user_email,
      nullif(trim(coalesce(existing_rec.telefono, '')), ''),
      coalesce(existing_rec.activo, true),
      merged_role,
      coalesce(existing_rec.saldo_acumulado, 0),
      existing_rec.foto_url,
      existing_rec.fcm_token,
      coalesce(existing_rec.created_at, now())
    );
  ELSE
    INSERT INTO public.profiles (id, nombre, email, telefono, role)
    VALUES (
      new.id,
      user_nombre,
      nullif(user_email, ''),
      nullif(trim(coalesce(new.phone, '')), ''),
      'jugador'
    );
  END IF;

  RETURN new;
END;
$$;

-- ---------------------------------------------------------------------------
-- B) RLS: solo dueño del partido actualiza convocatoria por REST
--    Jugadores responden vía SECURITY DEFINER RPC.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Organizador actualiza convocatoria de sus partidos"
  ON public.convocatoria_jugadores;

CREATE POLICY "Organizador actualiza convocatoria de sus partidos"
  ON public.convocatoria_jugadores
  FOR UPDATE
  USING (public.owns_partido(partido_id))
  WITH CHECK (public.owns_partido(partido_id));

-- ---------------------------------------------------------------------------
-- C) Confirmación jugador: lock partido + cupo + plazo + no suplente
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.actualizar_confirmacion_jugador(
  p_partido_id bigint,
  p_confirmo boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_email text;
  v_partido public.partidos%ROWTYPE;
  v_row public.convocatoria_jugadores%ROWTYPE;
  v_confirmados integer;
  estado_txt text;
  updated_rows integer;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN false;
  END IF;

  user_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
  PERFORM public.relink_convocatorias_por_email();

  SELECT *
  INTO v_partido
  FROM public.partidos
  WHERE id = p_partido_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_partido.estado NOT IN ('organizando', 'confirmado') THEN
    RAISE EXCEPTION 'convocatoria_cerrada'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_partido.fecha <= now() THEN
    RAISE EXCEPTION 'convocatoria_expirada'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT cj.*
  INTO v_row
  FROM public.convocatoria_jugadores cj
  INNER JOIN public.profiles pr ON pr.id = cj.jugador_id
  WHERE cj.partido_id = p_partido_id
    AND (
      cj.jugador_id = auth.uid()
      OR (
        user_email <> ''
        AND (
          lower(trim(coalesce(pr.email, ''))) = user_email
          OR lower(trim(coalesce(pr.telefono, ''))) = user_email
        )
      )
    )
  FOR UPDATE OF cj
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_row.es_suplente THEN
    RAISE EXCEPTION 'suplente_no_responde'
      USING ERRCODE = 'P0001';
  END IF;

  estado_txt := CASE WHEN p_confirmo THEN 'confirmado' ELSE 'rechazado' END;

  -- Idempotente
  IF v_row.estado_confirmacion = estado_txt THEN
    RETURN true;
  END IF;

  IF p_confirmo THEN
    IF v_row.estado_confirmacion NOT IN ('invitado', 'no_respondio') THEN
      RAISE EXCEPTION 'respuesta_no_permitida'
        USING ERRCODE = 'P0001';
    END IF;

    IF v_row.tiempo_limite IS NOT NULL AND now() > v_row.tiempo_limite THEN
      RAISE EXCEPTION 'plazo_vencido'
        USING ERRCODE = 'P0001';
    END IF;

    SELECT count(*)::integer
    INTO v_confirmados
    FROM public.convocatoria_jugadores
    WHERE partido_id = p_partido_id
      AND es_suplente = false
      AND estado_confirmacion = 'confirmado'
      AND id IS DISTINCT FROM v_row.id;

    IF v_confirmados >= coalesce(v_partido.cupos_max, 0) THEN
      RAISE EXCEPTION 'cupo_lleno'
        USING ERRCODE = 'P0001';
    END IF;
  ELSE
    -- Rechazo: primera respuesta (invitado/no_respondio) o declinar tras confirmar.
    IF v_row.estado_confirmacion NOT IN ('invitado', 'no_respondio', 'confirmado') THEN
      RAISE EXCEPTION 'respuesta_no_permitida'
        USING ERRCODE = 'P0001';
    END IF;

    IF v_row.estado_confirmacion IN ('invitado', 'no_respondio')
       AND v_row.tiempo_limite IS NOT NULL
       AND now() > v_row.tiempo_limite THEN
      RAISE EXCEPTION 'plazo_vencido'
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.convocatoria_jugadores
  SET estado_confirmacion = estado_txt
  WHERE id = v_row.id;

  GET DIAGNOSTICS updated_rows = ROW_COUNT;
  RETURN updated_rows > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.actualizar_confirmacion_jugador(bigint, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.actualizar_confirmacion_jugador(bigint, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.actualizar_confirmacion_jugador(bigint, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- D) Trigger: cupo + columnas sensibles (defensa si alguien bypasea)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_convocatoria_jugadores_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cupos integer;
  v_confirmados integer;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.partido_id IS DISTINCT FROM OLD.partido_id
       OR NEW.jugador_id IS DISTINCT FROM OLD.jugador_id THEN
      RAISE EXCEPTION 'permission_denied: no puedes cambiar partido_id/jugador_id'
        USING ERRCODE = '42501';
    END IF;

    -- Jugador autenticado que no es dueño: solo estado_confirmacion (y flags de aviso).
    IF current_user = 'authenticated'
       AND auth.uid() IS NOT NULL
       AND auth.uid() = OLD.jugador_id
       AND NOT public.owns_partido(OLD.partido_id) THEN
      IF NEW.es_suplente IS DISTINCT FROM OLD.es_suplente
         OR NEW.orden_espera IS DISTINCT FROM OLD.orden_espera
         OR NEW.tiempo_limite IS DISTINCT FROM OLD.tiempo_limite THEN
        RAISE EXCEPTION 'permission_denied: usa el flujo de convocatoria'
          USING ERRCODE = '42501';
      END IF;
    END IF;

    IF NEW.estado_confirmacion = 'confirmado'
       AND OLD.estado_confirmacion IS DISTINCT FROM 'confirmado'
       AND NEW.es_suplente = false THEN
      SELECT cupos_max INTO v_cupos
      FROM public.partidos
      WHERE id = NEW.partido_id;

      SELECT count(*)::integer INTO v_confirmados
      FROM public.convocatoria_jugadores
      WHERE partido_id = NEW.partido_id
        AND es_suplente = false
        AND estado_confirmacion = 'confirmado'
        AND id IS DISTINCT FROM NEW.id;

      IF v_confirmados >= coalesce(v_cupos, 0) THEN
        RAISE EXCEPTION 'cupo_lleno'
          USING ERRCODE = 'P0001';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_convocatoria_jugadores_guard ON public.convocatoria_jugadores;
CREATE TRIGGER trg_convocatoria_jugadores_guard
  BEFORE UPDATE ON public.convocatoria_jugadores
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_convocatoria_jugadores_guard();

-- ---------------------------------------------------------------------------
-- E) Promover suplente con lock (organizador / sync lista espera)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.promover_siguiente_suplente(p_partido_id bigint)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_partido public.partidos%ROWTYPE;
  v_ocupados integer;
  v_suplente public.convocatoria_jugadores%ROWTYPE;
  v_limite timestamptz;
BEGIN
  IF auth.uid() IS NULL OR p_partido_id IS NULL THEN
    RETURN NULL;
  END IF;

  IF NOT public.owns_partido(p_partido_id) THEN
    RAISE EXCEPTION 'permission_denied'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_partido
  FROM public.partidos
  WHERE id = p_partido_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT count(*)::integer INTO v_ocupados
  FROM public.convocatoria_jugadores
  WHERE partido_id = p_partido_id
    AND es_suplente = false
    AND estado_confirmacion IN ('invitado', 'confirmado');

  IF v_ocupados >= coalesce(v_partido.cupos_max, 0) THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_suplente
  FROM public.convocatoria_jugadores
  WHERE partido_id = p_partido_id
    AND es_suplente = true
  ORDER BY orden_espera NULLS LAST, id ASC
  FOR UPDATE
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  v_limite := now() + make_interval(hours => greatest(coalesce(v_partido.horas_limite_respuesta, 24), 1));

  UPDATE public.convocatoria_jugadores
  SET es_suplente = false,
      orden_espera = NULL,
      estado_confirmacion = 'invitado',
      tiempo_limite = v_limite,
      notificado_vencimiento = false,
      recordatorio_plazo_enviado = false
  WHERE id = v_suplente.id;

  RETURN v_suplente.jugador_id;
END;
$$;

REVOKE ALL ON FUNCTION public.promover_siguiente_suplente(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.promover_siguiente_suplente(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.promover_siguiente_suplente(bigint) TO authenticated;
