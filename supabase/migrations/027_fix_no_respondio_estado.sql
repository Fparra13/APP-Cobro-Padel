-- Corrige filas guardadas con el valor legacy camelCase del cliente.
UPDATE public.convocatoria_jugadores
SET estado_confirmacion = 'no_respondio'
WHERE estado_confirmacion = 'noRespondio';
