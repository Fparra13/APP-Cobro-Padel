-- telefono ya no es identificador; email lo reemplaza
-- Ejecutar en Supabase SQL Editor

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_telefono_key;
