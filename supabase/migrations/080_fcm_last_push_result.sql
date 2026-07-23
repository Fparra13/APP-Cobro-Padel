-- Resultado del último intento de envío FCM (diagnóstico por dispositivo).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS fcm_last_push_at timestamptz,
  ADD COLUMN IF NOT EXISTS fcm_last_push_ok boolean,
  ADD COLUMN IF NOT EXISTS fcm_last_push_detail text;
