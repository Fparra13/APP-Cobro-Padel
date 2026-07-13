# Reglas oficiales de cobros — Kloovi

Documento de contrato de negocio. Si el código contradice esto, el código está mal.

## Modelo mental

Un jugador **siempre tiene un saldo** (`profiles.saldo_acumulado`):

| Valor | Significado |
|-------|-------------|
| `> 0` | Debe dinero al organizador |
| `= 0` | Al día |
| `< 0` | Tiene crédito a favor |

Los **partidos generan cargos**. Los **pagos modifican el saldo**. No hay más magia.

## Fórmula única

```
saldo_nuevo = saldo_anterior + cargo_partido − monto_pagado
```

Implementación: `CobroLogic.saldoTrasMovimiento()`.

## Reglas de negocio

1. **Un partido genera un cargo** prorrateado entre asistentes.
2. **Un pago siempre reduce el saldo acumulado** (abono, transferencia, efectivo validado).
3. **Un pago puede ser menor, igual o mayor** al monto debido en ese momento.
4. **Si el pago excede la deuda**, el excedente queda como **saldo a favor** (saldo negativo).
5. **El saldo a favor se aplica automáticamente** al registrar el siguiente cargo (sin pago en efectivo).
6. **`saldo_acumulado` es la única fuente de verdad** sobre cuánto debe un jugador **ahora**.
7. **`saldos_historicos` es auditoría**: explica cómo se llegó al saldo. No se usa para calcular deuda en pantallas.
8. **Ninguna pantalla calcula dinero.** Solo muestra valores de `CobroLogic`.

## Single Source of Truth (lectura)

| Pregunta | Función | Fuente de datos |
|----------|---------|-----------------|
| ¿Cuánto debe el jugador? | `obtenerPendienteJugador(saldoAcumulado)` | `profiles.saldo_acumulado` |
| ¿Cuánto crédito tiene? | `obtenerCreditoJugador(saldoAcumulado)` | `profiles.saldo_acumulado` |
| ¿Cuánto falta por un partido? | `obtenerPendientePartido(saldoAnterior, cargo, pagado)` | Snapshot + detalle |
| ¿Cuánto debe el grupo? | `obtenerPendienteGrupo(saldos)` | Suma de saldos de jugadores |
| ¿Partido cerrado? | `partidoEstaCerrado(...)` | Misma fórmula neto |

## `saldo_anterior` al partido (snapshot)

Al **crear o editar** un partido se guarda en `saldos_historicos.saldo_anterior` el saldo del jugador **en ese instante**.

**Regla:** para partidos **ya registrados**, `saldo_anterior` **siempre** se lee del snapshot. **Nunca recalcularlo** en pantallas.

Usar: `CobroLogic.saldoAnteriorAlPartido(snapshotHistorico)`.

Solo en **preview antes de guardar** (formulario nuevo partido) se usa el saldo vivo del jugador.

## Quién puede modificar `saldo_acumulado`

Solo estos procesos (escritura):

| Proceso | Cuándo |
|---------|--------|
| Registrar partido | Al insertar cargos en `detalles_partido` + historial |
| Registrar abono manual | Organizador registra pago en efectivo |
| Validar comprobante | Organizador aprueba pago del jugador |
| Eliminar partido | Recalcula desde historial (`recalcular_saldo_jugador`) |
| Reconciliar (mantenimiento) | Solo RPC/scripts de reparación, no en lectura normal |

**Prohibido:** que una pantalla haga `updateSaldo` por su cuenta.

## Prohibiciones explícitas

- ❌ `total - monto_pagado` fuera de `CobroLogic` (bruto sin crédito).
- ❌ Calcular deuda sumando partidos impagos en UI.
- ❌ Usar `pagado = true` en detalle como única señal de “todo cobrado”.
- ❌ Recalcular `saldo_anterior` de un partido ya guardado.
- ❌ `reconciliarDetallesJugador` al abrir una pantalla (solo al escribir si hace falta).

## Tests canónicos

Todo escenario que produjo un bug debe quedar en `test/cobro_ssot_test.dart`.

Matriz mínima:

```
saldo 0      + cargo 10.000 → debe 10.000
saldo 5.000  + cargo 10.000 → debe 15.000
saldo -5.000 + cargo 10.000 → debe 5.000
saldo -15.000+ cargo 10.000 → crédito 5.000
pago exacto / parcial / mayor
varios partidos encadenados
```

## Migración pendiente

Código legacy a retirar progresivamente:

- `DetallePartido.montoPendiente` — deprecated; usar `CobroLogic`.
- `saldo_anterior_vivo_partido` — no usar en lectura; preferir snapshot `cargo_partido > 0`.

**Completado (032):** RPC `get_mi_desglose_partido` y `get_mis_deudas_pendientes` usan snapshot al registrar.
**Completado:** vista `cobros_resumen`, pantalla `OrganizerCobrosScreen`, pendientes por partido con snapshot en Dart.
