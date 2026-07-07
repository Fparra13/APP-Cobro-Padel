-- Corrige cobros_resumen: incluye perfiles sin role explícito y siempre devuelve 1 fila.

create or replace view public.cobros_resumen
with (security_invoker = true)
as
select
  case
    when public.is_organizer() then coalesce(
      sum(
        case
          when p.saldo_acumulado > 0.005 then p.saldo_acumulado
          else 0
        end
      ),
      0
    )
    else 0
  end::numeric(12, 2) as monto_total_pendiente,
  case
    when public.is_organizer() then coalesce(
      count(*) filter (where p.saldo_acumulado > 0.005),
      0
    )
    else 0
  end::integer as jugadores_con_deuda
from public.profiles p
where p.activo = true
  and coalesce(p.role, 'jugador') not in ('organizer', 'organizador');

grant select on public.cobros_resumen to authenticated;
