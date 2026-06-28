-- Fase 1: Row Level Security
-- Ejecutar después de 001_schema.sql

alter table public.profiles enable row level security;
alter table public.partidos enable row level security;
alter table public.convocatoria_jugadores enable row level security;
alter table public.detalles_partido enable row level security;
alter table public.costos_variables enable row level security;
alter table public.asignaciones_costo enable row level security;
alter table public.saldos_historicos enable row level security;

create or replace function public.is_organizer()
returns boolean as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'organizer'
  );
$$ language sql security definer;

-- PROFILES
create policy "Todos ven perfiles activos"
  on public.profiles for select using (activo = true);

create policy "Cada uno edita su propio perfil"
  on public.profiles for update using (auth.uid() = id);

create policy "Organizador puede crear jugadores"
  on public.profiles for insert with check (public.is_organizer());

-- PARTIDOS
create policy "Jugadores ven sus partidos"
  on public.partidos for select using (
    public.is_organizer() or
    exists (
      select 1 from public.convocatoria_jugadores
      where partido_id = id and jugador_id = auth.uid()
    )
  );

create policy "Solo organizador crea/edita/elimina partidos"
  on public.partidos for all using (public.is_organizer());

-- CONVOCATORIA
create policy "Ver convocatoria propia o ser organizador"
  on public.convocatoria_jugadores for select using (
    public.is_organizer() or jugador_id = auth.uid()
  );

create policy "Organizador gestiona convocatoria"
  on public.convocatoria_jugadores for insert with check (public.is_organizer());

create policy "Jugador actualiza su propia confirmación"
  on public.convocatoria_jugadores for update using (
    public.is_organizer() or jugador_id = auth.uid()
  );

-- DETALLES PARTIDO
create policy "Ver propio detalle o ser organizador"
  on public.detalles_partido for select using (
    public.is_organizer() or jugador_id = auth.uid()
  );

create policy "Organizador gestiona detalles"
  on public.detalles_partido for all using (public.is_organizer());

create policy "Jugador sube su comprobante"
  on public.detalles_partido for update using (
    jugador_id = auth.uid()
  ) with check (
    jugador_id = auth.uid()
  );

-- HISTORIAL SALDOS
create policy "Ver propio historial o ser organizador"
  on public.saldos_historicos for select using (
    public.is_organizer() or jugador_id = auth.uid()
  );

create policy "Solo organizador escribe historial"
  on public.saldos_historicos for all using (public.is_organizer());

-- COSTOS VARIABLES
create policy "Ver costos de partidos propios"
  on public.costos_variables for select using (
    public.is_organizer() or
    exists (
      select 1 from public.convocatoria_jugadores
      where partido_id = costos_variables.partido_id and jugador_id = auth.uid()
    )
  );

create policy "Organizador gestiona costos variables"
  on public.costos_variables for all using (public.is_organizer());

-- ASIGNACIONES COSTO
create policy "Ver asignaciones de partidos propios"
  on public.asignaciones_costo for select using (
    public.is_organizer() or jugador_id = auth.uid()
  );

create policy "Organizador gestiona asignaciones"
  on public.asignaciones_costo for all using (public.is_organizer());
