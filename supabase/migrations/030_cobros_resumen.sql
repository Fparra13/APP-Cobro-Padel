-- Resumen de cobranza del grupo (SSOT: profiles.saldo_acumulado).
-- Solo lectura para organizador; agrega deuda neta por jugador activo.

create or replace view public.cobros_resumen
with (security_invoker = true)
as
select
  coalesce(
    sum(
      case
        when p.saldo_acumulado > 0.005 then p.saldo_acumulado
        else 0
      end
    ),
    0
  )::numeric(12, 2) as monto_total_pendiente,
  count(*) filter (where p.saldo_acumulado > 0.005)::integer
    as jugadores_con_deuda
from public.profiles p
where p.activo = true
  and p.role = 'jugador'
  and public.is_organizer();

grant select on public.cobros_resumen to authenticated;
