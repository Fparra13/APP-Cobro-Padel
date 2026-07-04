-- Realtime + Storage para flujo colaborativo online
-- Ejecutar en Supabase SQL Editor después de 005

-- Habilitar Realtime en tablas clave
alter publication supabase_realtime add table public.convocatoria_jugadores;
alter publication supabase_realtime add table public.partidos;
alter publication supabase_realtime add table public.detalles_partido;
alter publication supabase_realtime add table public.profiles;

-- Bucket de comprobantes (público lectura autenticada vía signed URLs)
insert into storage.buckets (id, name, public)
values ('comprobantes', 'comprobantes', false)
on conflict (id) do nothing;

create policy "Jugador sube su comprobante"
  on storage.objects for insert
  with check (
    bucket_id = 'comprobantes'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "Ver comprobantes propios o ser organizador"
  on storage.objects for select
  using (
    bucket_id = 'comprobantes'
    and (
      public.is_organizer()
      or auth.uid()::text = (storage.foldername(name))[1]
    )
  );

-- Organizador puede validar: actualizar detalle incluye comprobante_validado
-- (RLS existente en detalles_partido ya cubre update por jugador;
--  organizador tiene policy for all)
