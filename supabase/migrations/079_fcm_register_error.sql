-- Diagnóstico remoto cuando getToken FCM falla en el dispositivo.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_register_error text;

COMMENT ON COLUMN public.profiles.fcm_register_error IS
  'Último error al registrar FCM en el cliente; null si OK.';
