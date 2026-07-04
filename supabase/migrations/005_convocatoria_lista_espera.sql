-- Lista de espera y tiempo límite en convocatorias
-- Ejecutar en Supabase SQL Editor

ALTER TABLE public.partidos
  ADD COLUMN IF NOT EXISTS horas_limite_respuesta integer NOT NULL DEFAULT 24;

ALTER TABLE public.convocatoria_jugadores
  ADD COLUMN IF NOT EXISTS es_suplente boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS orden_espera integer,
  ADD COLUMN IF NOT EXISTS tiempo_limite timestamptz,
  ADD COLUMN IF NOT EXISTS notificado_vencimiento boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_convocatoria_suplente
  ON public.convocatoria_jugadores (partido_id, es_suplente, orden_espera);
