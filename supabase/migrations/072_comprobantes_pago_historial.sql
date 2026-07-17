-- Historial de comprobantes de pago: cada abono/pago conserva su foto.
-- detalles_partido.comprobante_* sigue siendo el "activo" (cola de validación);
-- esta tabla no se pisa al enviar un segundo abono al mismo ancla.

CREATE TABLE IF NOT EXISTS public.comprobantes_pago (
  id bigserial PRIMARY KEY,
  detalle_id bigint NOT NULL
    REFERENCES public.detalles_partido(id) ON DELETE CASCADE,
  partido_id bigint NOT NULL
    REFERENCES public.partidos(id) ON DELETE CASCADE,
  jugador_id uuid NOT NULL
    REFERENCES public.profiles(id),
  organizador_id uuid NOT NULL
    REFERENCES public.profiles(id),
  storage_path text NOT NULL,
  monto_declarado numeric(12,2),
  es_abono boolean NOT NULL DEFAULT false,
  estado text NOT NULL
    CHECK (estado IN ('en_revision', 'aprobado', 'rechazado')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_comprobantes_pago_detalle_created
  ON public.comprobantes_pago (detalle_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comprobantes_pago_jugador_org
  ON public.comprobantes_pago (jugador_id, organizador_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_comprobantes_pago_path
  ON public.comprobantes_pago (storage_path);

COMMENT ON TABLE public.comprobantes_pago IS
  'Historial de fotos de pago/abono. No se sobrescribe al reenviar.';

ALTER TABLE public.comprobantes_pago ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Ver comprobantes pago propios o org" ON public.comprobantes_pago;
CREATE POLICY "Ver comprobantes pago propios o org"
  ON public.comprobantes_pago
  FOR SELECT
  TO authenticated
  USING (
    jugador_id = auth.uid()
    OR organizador_id = auth.uid()
    OR public.owns_partido(partido_id)
  );

DROP POLICY IF EXISTS "Jugador inserta su comprobante pago" ON public.comprobantes_pago;
CREATE POLICY "Jugador inserta su comprobante pago"
  ON public.comprobantes_pago
  FOR INSERT
  TO authenticated
  WITH CHECK (jugador_id = auth.uid());

DROP POLICY IF EXISTS "Org actualiza estado comprobante pago" ON public.comprobantes_pago;
CREATE POLICY "Org actualiza estado comprobante pago"
  ON public.comprobantes_pago
  FOR UPDATE
  TO authenticated
  USING (organizador_id = auth.uid() OR public.owns_partido(partido_id))
  WITH CHECK (organizador_id = auth.uid() OR public.owns_partido(partido_id));

-- Backfill desde el comprobante activo actual.
INSERT INTO public.comprobantes_pago (
  detalle_id,
  partido_id,
  jugador_id,
  organizador_id,
  storage_path,
  monto_declarado,
  es_abono,
  estado,
  created_at,
  resolved_at
)
SELECT
  dp.id,
  dp.partido_id,
  dp.jugador_id,
  p.organizador_id,
  dp.comprobante_url,
  dp.monto_pago_declarado,
  coalesce(dp.pago_es_abono, false),
  CASE
    WHEN dp.comprobante_estado IN ('en_revision', 'aprobado', 'rechazado')
      THEN dp.comprobante_estado
    WHEN coalesce(dp.comprobante_validado, false) THEN 'aprobado'
    ELSE 'en_revision'
  END,
  coalesce(dp.fecha_pago, p.fecha, now()),
  CASE
    WHEN dp.comprobante_estado IN ('aprobado', 'rechazado')
      OR coalesce(dp.comprobante_validado, false)
    THEN coalesce(dp.fecha_pago, now())
    ELSE NULL
  END
FROM public.detalles_partido dp
INNER JOIN public.partidos p ON p.id = dp.partido_id
WHERE dp.comprobante_url IS NOT NULL
  AND length(trim(dp.comprobante_url)) > 0
  AND NOT EXISTS (
    SELECT 1
    FROM public.comprobantes_pago cp
    WHERE cp.detalle_id = dp.id
      AND cp.storage_path = dp.comprobante_url
  );

CREATE OR REPLACE FUNCTION public.marcar_comprobante_pago_estado(
  p_detalle_id bigint,
  p_storage_path text,
  p_estado text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_detalle_id IS NULL OR p_storage_path IS NULL OR p_estado IS NULL THEN
    RETURN;
  END IF;
  IF p_estado NOT IN ('en_revision', 'aprobado', 'rechazado') THEN
    RETURN;
  END IF;

  UPDATE public.comprobantes_pago
  SET
    estado = p_estado,
    resolved_at = CASE
      WHEN p_estado IN ('aprobado', 'rechazado') THEN coalesce(resolved_at, now())
      ELSE NULL
    END
  WHERE detalle_id = p_detalle_id
    AND storage_path = p_storage_path
    AND estado = 'en_revision';
END;
$$;

GRANT EXECUTE ON FUNCTION public.marcar_comprobante_pago_estado(bigint, text, text)
  TO authenticated;

-- Ampliar Storage SELECT: paths en historial de partidos del org.
DROP POLICY IF EXISTS "Ver comprobantes propios o de mis partidos" ON storage.objects;
CREATE POLICY "Ver comprobantes propios o de mis partidos"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'comprobantes'
    AND (
      auth.uid()::text = (storage.foldername(name))[1]
      OR (
        public.is_organizer()
        AND (storage.foldername(name))[1]
          ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (
          public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
          OR EXISTS (
            SELECT 1
            FROM public.detalles_partido dp
            INNER JOIN public.partidos p ON p.id = dp.partido_id
            WHERE p.organizador_id = auth.uid()
              AND dp.jugador_id = ((storage.foldername(name))[1])::uuid
              AND dp.comprobante_url IS NOT NULL
              AND (
                dp.comprobante_url = name
                OR dp.comprobante_url LIKE
                  ((storage.foldername(name))[1] || '/%')
              )
          )
          OR EXISTS (
            SELECT 1
            FROM public.comprobantes_pago cp
            WHERE cp.organizador_id = auth.uid()
              AND cp.storage_path = name
          )
        )
      )
    )
  );

-- Purge: también limpia historial.
CREATE OR REPLACE FUNCTION public.limpiar_refs_comprobantes(p_paths text[])
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_detalles integer := 0;
  v_hist integer := 0;
  v_cancha integer := 0;
  v_pelotas integer := 0;
  v_costos integer := 0;
BEGIN
  IF p_paths IS NULL OR cardinality(p_paths) = 0 THEN
    RETURN json_build_object(
      'detalles', 0,
      'historial', 0,
      'cancha', 0,
      'pelotas', 0,
      'costos', 0
    );
  END IF;

  UPDATE public.detalles_partido
  SET comprobante_url = null
  WHERE comprobante_url = ANY (p_paths);
  GET DIAGNOSTICS v_detalles = ROW_COUNT;

  DELETE FROM public.comprobantes_pago
  WHERE storage_path = ANY (p_paths);
  GET DIAGNOSTICS v_hist = ROW_COUNT;

  UPDATE public.partidos
  SET comprobante_cancha_url = null
  WHERE comprobante_cancha_url = ANY (p_paths);
  GET DIAGNOSTICS v_cancha = ROW_COUNT;

  UPDATE public.partidos
  SET comprobante_pelotas_url = null
  WHERE comprobante_pelotas_url = ANY (p_paths);
  GET DIAGNOSTICS v_pelotas = ROW_COUNT;

  UPDATE public.costos_variables
  SET comprobante_url = null
  WHERE comprobante_url = ANY (p_paths);
  GET DIAGNOSTICS v_costos = ROW_COUNT;

  RETURN json_build_object(
    'detalles', v_detalles,
    'historial', v_hist,
    'cancha', v_cancha,
    'pelotas', v_pelotas,
    'costos', v_costos
  );
END;
$$;

REVOKE ALL ON FUNCTION public.limpiar_refs_comprobantes(text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.limpiar_refs_comprobantes(text[]) FROM anon;
REVOKE ALL ON FUNCTION public.limpiar_refs_comprobantes(text[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.limpiar_refs_comprobantes(text[]) TO service_role;

-- Al aprobar/rechazar el activo, sincroniza la fila del historial.
CREATE OR REPLACE FUNCTION public.trg_sync_comprobante_pago_estado()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.comprobante_url IS NULL OR length(trim(NEW.comprobante_url)) = 0 THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.comprobante_estado IS DISTINCT FROM OLD.comprobante_estado
     AND NEW.comprobante_estado IN ('aprobado', 'rechazado')
  THEN
    PERFORM public.marcar_comprobante_pago_estado(
      NEW.id,
      NEW.comprobante_url,
      NEW.comprobante_estado
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_detalles_sync_comprobante_pago ON public.detalles_partido;
CREATE TRIGGER trg_detalles_sync_comprobante_pago
  AFTER UPDATE OF comprobante_estado, comprobante_url
  ON public.detalles_partido
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_comprobante_pago_estado();
