-- Email como identificador de jugadores + perfiles pre-registro por organizador
-- Ejecutar en Supabase SQL Editor

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email text;

-- Permitir perfiles creados por el organizador antes del magic link
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;
ALTER TABLE public.profiles ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.profiles ALTER COLUMN telefono DROP NOT NULL;

-- Migrar emails guardados en telefono (compatibilidad)
UPDATE public.profiles
SET email = lower(trim(telefono))
WHERE (email IS NULL OR trim(email) = '')
  AND telefono IS NOT NULL
  AND telefono LIKE '%@%';

CREATE UNIQUE INDEX IF NOT EXISTS profiles_email_lower_unique
  ON public.profiles (lower(trim(email)))
  WHERE email IS NOT NULL AND trim(email) <> '';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
  user_email text;
  existing_id uuid;
  existing_rec public.profiles%ROWTYPE;
BEGIN
  user_email := lower(trim(coalesce(new.email, '')));

  IF user_email <> '' THEN
    SELECT id INTO existing_id
    FROM public.profiles
    WHERE lower(trim(email)) = user_email
      AND id <> new.id
    LIMIT 1;
  END IF;

  IF existing_id IS NOT NULL THEN
    SELECT * INTO existing_rec FROM public.profiles WHERE id = existing_id;

    UPDATE public.convocatoria_jugadores SET jugador_id = new.id WHERE jugador_id = existing_id;
    UPDATE public.detalles_partido SET jugador_id = new.id WHERE jugador_id = existing_id;
    UPDATE public.asignaciones_costo SET jugador_id = new.id WHERE jugador_id = existing_id;
    UPDATE public.saldos_historicos SET jugador_id = new.id WHERE jugador_id = existing_id;
    UPDATE public.partidos SET organizador_id = new.id WHERE organizador_id = existing_id;

    INSERT INTO public.profiles (
      id, nombre, email, telefono, activo, role, saldo_acumulado, foto_url, fcm_token, created_at
    ) VALUES (
      new.id,
      coalesce(nullif(trim(existing_rec.nombre), ''), split_part(user_email, '@', 1), 'Sin nombre'),
      user_email,
      coalesce(existing_rec.telefono, ''),
      existing_rec.activo,
      coalesce(existing_rec.role, coalesce(new.raw_user_meta_data->>'role', 'jugador')),
      existing_rec.saldo_acumulado,
      existing_rec.foto_url,
      existing_rec.fcm_token,
      existing_rec.created_at
    );

    DELETE FROM public.profiles WHERE id = existing_id;
  ELSE
    INSERT INTO public.profiles (id, nombre, email, telefono, role)
    VALUES (
      new.id,
      coalesce(
        new.raw_user_meta_data->>'nombre',
        nullif(split_part(user_email, '@', 1), ''),
        'Sin nombre'
      ),
      nullif(user_email, ''),
      coalesce(new.phone, ''),
      coalesce(new.raw_user_meta_data->>'role', 'jugador')
    );
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
