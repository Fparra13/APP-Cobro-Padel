-- Avatares de jugadores (lectura pública, subida por organizador).
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Organizador sube avatares"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'avatars'
    AND public.is_organizer()
  );

CREATE POLICY "Organizador actualiza avatares"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'avatars' AND public.is_organizer())
  WITH CHECK (bucket_id = 'avatars' AND public.is_organizer());

CREATE POLICY "Organizador elimina avatares"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'avatars' AND public.is_organizer());

CREATE POLICY "Lectura pública avatares"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');
