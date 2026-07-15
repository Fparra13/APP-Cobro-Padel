-- Alinea handle_new_user con saldo por organizador (sin profiles.saldo_acumulado)
-- y preserva filas de organizador_jugadores al fusionar perfiles.

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
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(split_part(user_email, '@', 1), ''),
    'Sin nombre'
  );

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

    UPDATE public.saldos_historicos
    SET organizador_id = new.id
    WHERE organizador_id = existing_id;

    UPDATE public.partidos
    SET organizador_id = new.id
    WHERE organizador_id = existing_id;

    -- Antes del DELETE CASCADE: mover cuentas de saldo.
    UPDATE public.organizador_jugadores
    SET jugador_id = new.id
    WHERE jugador_id = existing_id;

    UPDATE public.organizador_jugadores
    SET organizador_id = new.id
    WHERE organizador_id = existing_id;

    DELETE FROM public.profiles WHERE id = existing_id;

    IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id = existing_id) THEN
      merged_role := coalesce(nullif(trim(existing_rec.role), ''), 'jugador');
    ELSE
      merged_role := 'jugador';
    END IF;

    INSERT INTO public.profiles (
      id, nombre, email, telefono, activo, role,
      foto_url, fcm_token, created_at
    ) VALUES (
      new.id,
      coalesce(nullif(trim(existing_rec.nombre), ''), user_nombre),
      user_email,
      nullif(trim(coalesce(existing_rec.telefono, '')), ''),
      coalesce(existing_rec.activo, true),
      merged_role,
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
