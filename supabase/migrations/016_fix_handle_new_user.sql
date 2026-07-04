-- Fix: magic link falla con "Database error saving new user" cuando el email
-- ya existe como perfil pre-registrado por el organizador.
-- Causa: INSERT del perfil auth antes de DELETE del pre-registro → unique email.

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_telefono_key;

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
  user_role text;
BEGIN
  user_email := lower(trim(coalesce(new.email, '')));
  user_nombre := coalesce(
    nullif(trim(new.raw_user_meta_data->>'nombre'), ''),
    nullif(split_part(user_email, '@', 1), ''),
    'Sin nombre'
  );
  user_role := coalesce(new.raw_user_meta_data->>'role', 'jugador');

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

    -- Borrar pre-registro ANTES de insertar (libera el email único).
    DELETE FROM public.profiles WHERE id = existing_id;

    INSERT INTO public.profiles (
      id, nombre, email, telefono, activo, role,
      saldo_acumulado, foto_url, fcm_token, created_at
    ) VALUES (
      new.id,
      coalesce(nullif(trim(existing_rec.nombre), ''), user_nombre),
      user_email,
      nullif(trim(coalesce(existing_rec.telefono, '')), ''),
      coalesce(existing_rec.activo, true),
      coalesce(nullif(trim(existing_rec.role), ''), user_role),
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
      user_role
    );
  END IF;

  RETURN new;
END;
$$;
