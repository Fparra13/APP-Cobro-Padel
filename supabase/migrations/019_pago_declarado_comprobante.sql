-- Pago declarado por jugador antes de subir comprobante (pendiente validación).

ALTER TABLE public.detalles_partido
  ADD COLUMN IF NOT EXISTS monto_pago_declarado numeric(10,2),
  ADD COLUMN IF NOT EXISTS pago_es_abono boolean;
