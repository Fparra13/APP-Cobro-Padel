-- 049: Storage — DELETE comprobantes + avatares acotados a path/roster + MIME.

-- ---------------------------------------------------------------------------
-- A) Comprobantes: borrar (dueño de carpeta o organizador del jugador)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Borrar comprobantes propios o de mis jugadores"
  ON storage.objects;

CREATE POLICY "Borrar comprobantes propios o de mis jugadores"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'comprobantes'
    AND (
      auth.uid()::text = (storage.foldername(name))[1]
      OR (
        public.is_organizer()
        AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
        AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
      )
    )
  );

-- INSERT: exigir carpeta = auth.uid + imagen
DROP POLICY IF EXISTS "Jugador sube su comprobante" ON storage.objects;
CREATE POLICY "Jugador sube su comprobante"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'comprobantes'
    AND auth.uid()::text = (storage.foldername(name))[1]
    AND coalesce(metadata->>'mimetype', '') IN (
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    )
  );

-- ---------------------------------------------------------------------------
-- B) Avatares: organizador solo en carpeta de su roster; MIME imagen
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Organizador sube avatares" ON storage.objects;
DROP POLICY IF EXISTS "Organizador actualiza avatares" ON storage.objects;
DROP POLICY IF EXISTS "Organizador elimina avatares" ON storage.objects;

CREATE POLICY "Organizador sube avatares de su roster"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND public.is_organizer()
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
    AND coalesce(metadata->>'mimetype', '') IN (
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    )
  );

CREATE POLICY "Organizador actualiza avatares de su roster"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'avatars'
    AND public.is_organizer()
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND public.is_organizer()
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
  );

CREATE POLICY "Organizador elimina avatares de su roster"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'avatars'
    AND public.is_organizer()
    AND (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
    AND public.es_mi_jugador(((storage.foldername(name))[1])::uuid)
  );

-- Jugador self: MIME en INSERT
DROP POLICY IF EXISTS "Jugador sube su avatar" ON storage.objects;
CREATE POLICY "Jugador sube su avatar"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND coalesce(metadata->>'mimetype', '') IN (
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif'
    )
  );
