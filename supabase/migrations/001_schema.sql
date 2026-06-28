-- Fase 1: Schema base para APP Cobro Pádel
-- Ejecutar en Supabase SQL Editor

create extension if not exists "uuid-ossp";

create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  nombre text not null,
  telefono text unique not null,
  activo boolean not null default true,
  role text not null default 'jugador',
  saldo_acumulado numeric(10,2) not null default 0,
  foto_url text,
  fcm_token text,
  created_at timestamptz not null default now()
);

create table public.partidos (
  id bigserial primary key,
  fecha timestamptz not null,
  costo_cancha numeric(10,2) not null default 0,
  costo_pelotas numeric(10,2) not null default 0,
  recinto text,
  notas text,
  comprobante_cancha_url text,
  comprobante_pelotas_url text,
  estado text not null default 'jugado',
  cupos_max integer not null default 4,
  organizador_id uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.convocatoria_jugadores (
  id bigserial primary key,
  partido_id bigint not null references public.partidos(id) on delete cascade,
  jugador_id uuid not null references public.profiles(id) on delete restrict,
  estado_confirmacion text not null default 'invitado',
  unique(partido_id, jugador_id)
);

create table public.detalles_partido (
  id bigserial primary key,
  partido_id bigint not null references public.partidos(id) on delete cascade,
  jugador_id uuid not null references public.profiles(id) on delete restrict,
  asistio boolean not null default true,
  prorrateo_fijo numeric(10,2) not null default 0,
  total_variables numeric(10,2) not null default 0,
  total numeric(10,2) not null default 0,
  pagado boolean not null default false,
  fecha_pago timestamptz,
  monto_pagado numeric(10,2) not null default 0,
  comprobante_url text,
  comprobante_validado boolean,
  unique(partido_id, jugador_id)
);

create table public.costos_variables (
  id bigserial primary key,
  partido_id bigint not null references public.partidos(id) on delete cascade,
  concepto text not null,
  monto_total numeric(10,2) not null,
  comprobante_url text
);

create table public.asignaciones_costo (
  id bigserial primary key,
  costo_variable_id bigint not null references public.costos_variables(id) on delete cascade,
  jugador_id uuid not null references public.profiles(id) on delete restrict,
  monto numeric(10,2) not null,
  unique(costo_variable_id, jugador_id)
);

create table public.saldos_historicos (
  id bigserial primary key,
  jugador_id uuid not null references public.profiles(id) on delete restrict,
  partido_id bigint references public.partidos(id) on delete set null,
  saldo_anterior numeric(10,2) not null,
  cargo_partido numeric(10,2) not null default 0,
  abono numeric(10,2) not null default 0,
  saldo_nuevo numeric(10,2) not null,
  fecha timestamptz not null default now(),
  concepto text not null
);

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nombre, telefono, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nombre', 'Sin nombre'),
    coalesce(new.phone, ''),
    coalesce(new.raw_user_meta_data->>'role', 'jugador')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create index idx_partidos_estado on public.partidos(estado);
create index idx_detalles_partido_id on public.detalles_partido(partido_id);
create index idx_detalles_jugador_id on public.detalles_partido(jugador_id);
create index idx_saldos_jugador_id on public.saldos_historicos(jugador_id);
create index idx_convocatoria_partido on public.convocatoria_jugadores(partido_id);
