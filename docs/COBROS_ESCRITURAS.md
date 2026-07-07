# Auditoría de escrituras — cobros MatchPay

**Alcance:** dónde se **modifica** (INSERT/UPDATE) cada campo crítico.  
**Conclusión:** hoy **no existe un único flujo de escritura**. Hay 3–6 rutas por campo según el caso.

---

## Veredicto

| Campo | ¿Un solo lugar autorizado? | Riesgo |
|-------|---------------------------|--------|
| `profiles.saldo_acumulado` | ❌ No (8+ rutas) | Alto |
| `saldos_historicos.saldo_anterior` | ⚠️ Solo INSERT al crear cargo/abono; valor nunca se UPDATE | Medio (origen al insertar) |
| `detalles_partido.monto_pagado` | ❌ No (6+ rutas) | Alto |
| `detalles_partido.pagado` | ❌ No (7+ rutas) | Alto |

**Ruta paralela peligrosa:** `reconciliarDetallesJugador` modifica detalle + a veces saldo **sin** pasar por el mismo camino que registrar partido / validar pago.

---

## 1. `profiles.saldo_acumulado`

### Escrituras en app (Dart)

| # | Proceso | Archivo · función | ¿Autorizado? | Notas |
|---|---------|-------------------|--------------|-------|
| 1 | **Registrar partido** (cargo) | `partido_repository_remote.dart` · `_insertarCostosYDetalles` → `updateSaldo` | ✅ Sí | Escribe `saldoNuevo` tras cargo |
| 2 | **Registrar partido** (post-hook) | `_insertarCostosYDetalles` → `_recalcularSaldoJugador` | ⚠️ Duplicado | **Sobrescribe** saldo desde último `saldos_historicos.saldo_nuevo` |
| 3 | **Abono manual** | `registrarAbono` → `updateSaldo` | ✅ Sí | `saldoNuevo = saldoAnterior - monto` |
| 4 | **Abono manual** (post) | `registrarAbono` → `reconciliarDetallesJugador` → `_recalcularSaldoJugador` | ⚠️ Duplicado | Puede reescribir saldo otra vez |
| 5 | **Validar comprobante** | `validarComprobantePago` → `updateSaldo` | ✅ Sí | Tras abono aprobado |
| 6 | **Validar comprobante** (post) | `validarComprobantePago` → `reconciliarDetallesJugador` | ⚠️ Duplicado | Tercera pasada sobre saldo |
| 7 | **Reconciliar** (crédito) | `reconciliarDetallesJugador` (rama `saldo <= 0`) | ❌ No | Recalcula y puede `updateSaldo` si cambió |
| 8 | **Recalcular desde historial** | `_recalcularSaldoJugador` | ⚠️ Mantenimiento | Último `saldo_nuevo` del historial |
| 9 | **Eliminar partido** | `eliminarPartido` → `_recalcularSaldoJugador` + `reconciliarDetallesJugador` | ⚠️ Sí (borrado) | Dos pasadas |

**Local SQLite** (`partido_repository.dart`):

| Proceso | Función | Notas |
|---------|---------|-------|
| Guardar partido | `guardarPartido` → `txn.update jugadores` | Directo |
| Abono | `registrarAbono` | Directo |
| Recalcular | `recalcularSaldosDesdeHistorial` | Reset a 0 + replay historial |
| Eliminar partido | `eliminarPartido` → recalcular | |
| Reconciliar | `_reconciliarDetallesJugador` | Puede update saldo |

**Capa baja (única que toca Supabase `profiles`):**

- `jugador_repository_remote.dart` · `updateSaldo` — **debería ser el único UPDATE directo**

### Escrituras en Supabase (SQL/RPC)

| Proceso | Migración / función | ¿Autorizado? |
|---------|---------------------|--------------|
| Recalcular saldo | `recalcular_saldo_jugador` (015) | ⚠️ Post-eliminación / relink |
| Reconciliar crédito | `reconciliar_detalles_jugador` (028, 029) | ❌ Parche |
| Reparación | `reparar_jugador_cobros`, `reparar_cobros_organizador` | ❌ Solo mantenimiento |
| Relink email | `relink_convocatorias_por_email` → recalcular | ⚠️ Auth |
| Reset manual | `scripts/reset_partidos.sql` | ❌ Dev only |

### Inconsistencias detectadas

1. **Doble escritura:** `updateSaldo` + `_recalcularSaldoJugador` en la misma operación (guardar partido).
2. **Reconciliar tras cada pago** puede modificar detalles y saldo con lógica distinta a la del pago.
3. **`reconciliarDetallesJugador` invocado desde `historial_screen`** al abrir ficha — escritura en **lectura**.

---

## 2. `saldos_historicos.saldo_anterior`

**Regla deseada:** INSERT **una sola vez** al registrar el cargo del partido. Nunca UPDATE del valor.

### Escrituras del valor `saldo_anterior`

| # | Proceso | Archivo · función | Origen del valor | ¿Autorizado? |
|---|---------|-------------------|------------------|--------------|
| 1 | **Insertar cargo partido** | `_insertarCostosYDetalles` | `saldosAnterioresSnapshot` **o** `_saldoAnteriorVivoParaPartido` | ⚠️ Parcial |
| 2 | **Abono manual** | `registrarAbono` | `jugador.saldoAcumulado` vivo | ✅ (abono no es snapshot de partido) |
| 3 | **Validar comprobante** | `validarComprobantePago` | `jugador.saldoAcumulado` vivo | ✅ (fila de abono) |

**Local:** `guardarPartido` / `registrarAbono` — mismo patrón.

### UPDATE de `saldo_anterior`

**Ninguno** en operación normal. Solo migraciones de relink cambian `jugador_id`, no el monto:

- `008`, `010`, `013`, `015`, `003` — relink UUID

### Problema crítico en INSERT de cargo

```dart
// partido_repository_remote.dart · _insertarCostosYDetalles
final saldoAnterior = snapSaldo ??
    await _saldoAnteriorVivoParaPartido(...);  // ← RECALCULA si no hay snapshot
```

Si falta snapshot, **inventa** `saldo_anterior` sumando partidos anteriores o leyendo saldo vivo.  
**Violación de tu regla:** debería lanzar error, no recalcular.

---

## 3. `detalles_partido.monto_pagado`

| # | Proceso | Archivo · función | ¿Autorizado? |
|---|---------|-------------------|--------------|
| 1 | **Crear partido** | `_insertarCostosYDetalles` · INSERT | ✅ Inicial |
| 2 | **Validar comprobante** | `validarComprobantePago` · UPDATE | ✅ Pago aprobado |
| 3 | **Abono virtual** | `_aplicarAbonoVirtualDetalles` | ❌ Reparte abono sin tocar saldo primero |
| 4 | **Reconciliar (crédito)** | `reconciliarDetallesJugador` | ❌ Puede setear `monto_pagado` |
| 5 | **Reabrir por déficit** | `_reabrirDetallesPorDeficit` | ❌ Reduce `monto_pagado` |
| 6 | **Sincronizar (local)** | `_sincronizarDetallesTrasPago` | ❌ Duplica lógica de abono virtual |

**Supabase RPC:**

| Función | Migración |
|---------|-----------|
| `aplicar_abono_virtual_detalles` | 029 |
| `reconciliar_detalles_jugador` | 028, 029 |
| `alinear_detalles_con_historico` | 028 |

### Inconsistencias

- `validarComprobantePago` usa pendiente **bruto** (`total - monto_pagado`) para decidir cuánto aplicar al detalle.
- `_aplicarAbonoVirtualDetalles` reparte excedente en detalles **sin** fila de historial por cada aplicación parcial.
- Local `_sincronizarDetallesTrasPago` marca `monto_pagado = total` cuando saldo ≤ 0 (ignora neto con crédito).

---

## 4. `detalles_partido.pagado`

Mismas rutas que `monto_pagado`, más:

| # | Proceso | Notas |
|---|---------|-------|
| 7 | **Subir comprobante** | No toca `pagado` (solo comprobante_*) ✅ |
| 8 | **Rechazar comprobante** | No toca `pagado` ✅ |
| 9 | **Reconciliar** | Marca `pagado=true` con crédito sin pago en efectivo |
| 10 | **Local sync** | `pagado=1` masivo si `saldoNuevo <= 0` |

**Flag `pagado` no es SSOT:** puede ser `true` con deuda neta si el crédito no se reflejó bien en detalle.

---

## Flujo deseado (único)

```
                    ┌─────────────────────┐
                    │   CobroWriteService │  (futuro: 1 módulo)
                    └──────────┬──────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
  registrarCargo()      registrarPago()      eliminarPartido()
         │                     │                     │
         ├─ INSERT detalle     ├─ UPDATE detalle    ├─ DELETE historial partido
         ├─ INSERT historial   ├─ INSERT historial  └─ recalcular_saldo_jugador()
         │   (snapshot SA)     │   (abono)
         └─ UPDATE saldo       └─ UPDATE saldo
              (1 sola vez)          (1 sola vez)
```

**Prohibido en flujo normal:**

- `reconciliarDetallesJugador` automático post-pago
- `_aplicarAbonoVirtualDetalles` como segunda verdad
- `_saldoAnteriorVivoParaPartido` al escribir
- `_recalcularSaldoJugador` inmediatamente después de `updateSaldo` en la misma TX

---

## Respuestas a tus preguntas concretas

### ¿`saldo_anterior` siempre del snapshot?

**No hoy.** Al crear partido, si no hay `saldosAnterioresSnapshot`, se llama `_saldoAnteriorVivoParaPartido`.  
**Debe ser:** snapshot obligatorio o error `DatosInconsistentesException`.

### ¿Quién puede modificar `saldo_acumulado`?

**Ideal:** solo `registrarCargo` y `registrarPago` (+ `eliminarPartido` / recalcular).

**Realidad:** también reconciliar, reparar RPC, relink, recalcular post-hook, ficha jugador al abrir.

### ¿Fallbacks silenciosos?

| Fallback | Dónde |
|----------|-------|
| Recalcular SA si falta snapshot | `_insertarCostosYDetalles` |
| Reconciliar tras validar/abono | `validarComprobantePago`, `registrarAbono` |
| Reconciliar al abrir ficha | `historial_screen._load` |
| Abono virtual en detalles | `_aplicarAbonoVirtualDetalles`, RPC 029 |
| Recalcular saldo tras update directo | `_recalcularSaldoJugador` en guardar partido |

---

## Orden de consolidación de escrituras (antes de migrar lecturas)

1. Crear **`CobroWriteService`** (o métodos en repo) con 3 operaciones: `registrarCargo`, `registrarPago`, `eliminarPartido`.
2. Eliminar post-hooks: `reconciliarDetallesJugador` tras pago/guardado.
3. Snapshot obligatorio en cargo; error si falta.
4. Un solo UPDATE de saldo por operación (eliminar `_recalcularSaldoJugador` redundante).
5. Deprecar `_aplicarAbonoVirtualDetalles` y RPC equivalente — el pago ya actualiza saldo; detalle sigue al saldo, no al revés.
6. Quitar `reconciliar` de `historial_screen._load`.
