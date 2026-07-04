-- MatchPay: deporte, moneda, locale e iconos de gasto
-- Ejecutar en Supabase SQL Editor

ALTER TABLE public.partidos
  ADD COLUMN IF NOT EXISTS sport_type text NOT NULL DEFAULT 'padel';

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS preferred_sport text DEFAULT 'padel',
  ADD COLUMN IF NOT EXISTS preferred_currency text DEFAULT 'CLP',
  ADD COLUMN IF NOT EXISTS preferred_locale text DEFAULT 'es';

ALTER TABLE public.costos_variables
  ADD COLUMN IF NOT EXISTS icon_key text;

CREATE INDEX IF NOT EXISTS idx_partidos_sport_type ON public.partidos(sport_type);

COMMENT ON COLUMN public.partidos.sport_type IS 'padel|football|tennis|general';
COMMENT ON COLUMN public.costos_variables.icon_key IS 'meat|drink|ball|general|court';
