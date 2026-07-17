-- El organizador debe poder firmar (SELECT) comprobantes de pago de jugadores
-- de SUS partidos, no solo del roster. Si el vínculo en organizador_jugadores
-- falta o es inconsistente, createSignedUrl fallaba y solo el jugador veía la
-- imagen (su propia carpeta sí pasa el primer OR).

DROP POLICY IF EXISTS "Ver comprobantes propios o de mis jugadores" ON storage.objects;
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
        )
      )
    )
  );
