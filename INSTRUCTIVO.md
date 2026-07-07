# MatchPay — Guía de uso

App para organizar partidos, repartir gastos y llevar el cobro del grupo.

---

## 1. Primeros pasos

1. **Config** (menú inferior) → ingresa tus **datos bancarios** (titular, banco, cuenta). Se usan en los mensajes de WhatsApp y PDF.
2. **Jugadores** → agrega a tu grupo con nombre y **WhatsApp** (opcional pero recomendado).
3. Marca **Jugador habitual** ⭐ a quienes juegan seguido; aparecen automáticamente al crear partidos.

---

## 2. Menú principal

| Pestaña | Para qué sirve |
|---------|----------------|
| **Inicio** | Resumen de deudas, pagos rápidos y accesos directos |
| **Jugadores** | Crear, editar y ver fichas |
| **Historial** | Partidos jugados y ranking del grupo |
| **Respaldo** | Exportar/importar datos y PDF de saldos |
| **Config** | Datos bancarios y recordatorios automáticos |

---

## 3. Crear un partido

Toca el botón verde **Partido** (abajo a la derecha en Inicio):

### A) Organizar convocatoria
*Antes de jugar — sin cobros aún.*

- Define fecha, recinto, cupos e invita jugadores.
- Marca quién **confirmó**, **rechazó** o está **invitado**.
- **Compartir convocatoria** por WhatsApp (grupo o directo).
- **Importar respuestas** pegando mensajes del chat.
- Al confirmar el partido → **Ir a cobrar** para registrar gastos y pagos.

### B) Registrar partido jugado
*Cuando ya jugaron — con cobros.*

Completa en este orden:

1. **Datos** — fecha, recinto y notas.
2. **Gastos** — Cancha, Pelotas, Asado, Barra Schop, Otros.  
   - Cancha y pelotas se reparten entre asistentes.  
   - Asado, schop y otros: marca quién participó.
3. **Jugadores y pagos** — selecciona quién jugó y su estado:
   - **Pago total** — quedó al día.
   - **Abono** — ingresa monto y pulsa **Confirmar abono**.
   - **Sin pago** — queda con deuda.
4. **Resumen** — revisa totales y guarda.

> Las deudas anteriores se suman automáticamente. Un abono mayor al total genera **saldo a favor**.

---

## 4. Inicio — operaciones diarias

### Resumen del grupo
Muestra total por cobrar, jugadores con deuda y al día.

### Herramientas
- **PDF saldos** — informe del grupo.
- **Último partido** — ver, editar o generar PDF.
- **Recordar deudores** — WhatsApp masivo a quienes deben.
- **Jugadores** — ir a la lista.

### Convocatorias activas
Partidos en espera o confirmados. Toca uno para editarlo o pasar a cobrar.

### Registrar pagos (planilla)
Desde Inicio, sin entrar al partido:
- Marca uno o más deudores.
- **Varios seleccionados** → pago total de cada uno.
- **Un solo jugador** → pago total o abono parcial.

---

## 5. Ficha del jugador

Accede desde **Ver ficha de un jugador** (Inicio) o tocando un jugador en la lista.

- **Saldo actual**, partidos jugados y pagados.
- **Historial** de cargos y abonos (filtros por tipo).
- **Foto** del jugador (opcional).
- **Registrar pago** manual (total o abono).
- **Recordar / WhatsApp** — mensaje con detalle del partido, deuda anterior y datos de transferencia.

---

## 6. Jugadores

- **+ Nuevo jugador** — nombre, WhatsApp y si es habitual.
- Toca una tarjeta → **ficha** o **editar**.
- Icono **Estadísticas** (arriba) → rankings del grupo:
  - Participación, buen pagador, pago rápido, activo reciente, convocatorias, total aportado, mayor deuda.

---

## 7. Historial y ranking

### Partidos
Lista de partidos jugados y convocatorias. Toca uno para ver detalle, editar, PDF o eliminar.

### Ranking
Clasificación del grupo por partidos jugados y otros criterios.

---

## 8. WhatsApp

La app abre WhatsApp con el mensaje listo. Incluye:
- Detalle del partido (cancha, pelotas, etc.).
- Deuda anterior si aplica.
- Total pendiente.
- Datos bancarios para transferir.

**Requisito:** el jugador debe tener número de WhatsApp guardado.

---

## 9. Respaldo

> Haz respaldo antes de cambiar de celular. Los datos viven solo en el teléfono.

- **Exportar .db** — copia exacta de la base de datos.
- **Exportar JSON** — formato legible.
- **Importar** — restaura un respaldo (reemplaza todo).
- **Reporte PDF de saldos** — desde esta pantalla o desde Inicio.

Comparte el archivo por WhatsApp, Gmail o Drive.

---

## 10. Configuración

### Datos bancarios
Titular, banco, cuenta y RUT. Aparecen en mensajes y reportes.

### Recordatorios automáticos
Notificación si hay deudas sin cobrar después de X días. Configura:
- Activar/desactivar.
- Días de espera (1–30).
- Hora del aviso.

---

## Flujo típico

```
Agregar jugadores → Organizar convocatoria → Confirmar asistentes
       → Ir a cobrar → Registrar gastos y pagos → Recordar deudores por WhatsApp
```

O directamente: **Registrar partido jugado** si no necesitas convocatoria previa.

---

## Consejos

- Desliza hacia abajo en cualquier lista para **actualizar**.
- Usa **Respaldo** con frecuencia.
- Los **habituales ⭐** ahorran tiempo al armar partidos.
- Si alguien transfiere después, usa **Registrar pagos** en Inicio o en su ficha.
