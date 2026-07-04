-- Flag para no repetir el recordatorio "te queda 1 hora".
ALTER TABLE public.convocatoria_jugadores
  ADD COLUMN IF NOT EXISTS recordatorio_plazo_enviado boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.convocatoria_jugadores.recordatorio_plazo_enviado IS
  'Push de recordatorio enviado cuando queda ~1 h de plazo';
COMMENT ON COLUMN public.convocatoria_jugadores.notificado_vencimiento IS
  'Push enviado al marcar no_respondio por plazo vencido';
