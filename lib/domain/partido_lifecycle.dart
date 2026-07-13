import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/mi_convocatoria.dart';
import '../models/partido.dart';

/// Fase derivada de la convocatoria (no persistida en `partidos.estado`).
enum ConvocatoriaFase {
  /// Antes de la hora del partido: respuestas abiertas según plazo.
  abierta,

  /// Pasó la hora del partido; la convocatoria ya no admite respuestas.
  expirada,
}

/// Situación operativa para el organizador.
enum ConvocatoriaOrganizadorSituacion {
  preparando,
  sinResolver,
  listoParaGastos,
}

/// SSOT del ciclo convocatoria ↔ partido. La fecha/hora sola nunca implica
/// que el partido se jugó.
class PartidoLifecycle {
  PartidoLifecycle._();

  static DateTime now() => DateTime.now();

  static bool convocatoriaActiva(Partido partido) =>
      partido.estado == EstadoPartido.organizando ||
      partido.estado == EstadoPartido.confirmado;

  /// Convocatoria expirada: hora del partido ya pasó.
  static bool convocatoriaExpirada(Partido partido, [DateTime? reference]) {
    if (!convocatoriaActiva(partido)) return false;
    final t = reference ?? now();
    return !partido.fecha.isAfter(t);
  }

  static ConvocatoriaFase faseConvocatoria(Partido partido, [DateTime? reference]) {
    return convocatoriaExpirada(partido, reference)
        ? ConvocatoriaFase.expirada
        : ConvocatoriaFase.abierta;
  }

  static bool plazoRespuestaVencido(
    ConvocatoriaJugadorEntry entry, [
    DateTime? reference,
  ]) {
    if (entry.estado != EstadoConfirmacion.invitado) return false;
    final limite = entry.tiempoLimite;
    if (limite == null) return false;
    return (reference ?? now()).isAfter(limite);
  }

  /// El jugador aún puede confirmar o rechazar (primera respuesta).
  static bool puedeResponderJugador(
    MiConvocatoria convocatoria, [
    DateTime? reference,
  ]) {
    final t = reference ?? now();
    if (convocatoria.entry.esSuplente) return false;
    if (convocatoria.entry.estado != EstadoConfirmacion.invitado) return false;
    if (plazoRespuestaVencido(convocatoria.entry, t)) return false;
    if (convocatoriaExpirada(convocatoria.partido, t)) return false;
    return true;
  }

  /// Titular que ya confirmó puede avisar que ya no puede ir.
  static bool puedeDeclinarTrasConfirmar(
    MiConvocatoria convocatoria, [
    DateTime? reference,
  ]) {
    if (convocatoria.entry.esSuplente) return false;
    if (convocatoria.entry.estado != EstadoConfirmacion.confirmado) {
      return false;
    }
    if (convocatoriaExpirada(convocatoria.partido, reference)) return false;
    return convocatoriaActiva(convocatoria.partido);
  }

  /// Destinatario de push/WhatsApp al cancelar el encuentro.
  ///
  /// Solo nómina titular “en juego”: confirmados e invitados con plazo vigente.
  /// Nunca reservas, rechazados ni quienes ya liberaron cupo (`no_respondio`).
  static bool debeRecibirAvisoCancelacion(
    ConvocatoriaJugadorEntry entry, [
    DateTime? reference,
  ]) {
    if (entry.esSuplente) return false;
    switch (entry.estado) {
      case EstadoConfirmacion.confirmado:
        return true;
      case EstadoConfirmacion.invitado:
        return !plazoRespuestaVencido(entry, reference);
      case EstadoConfirmacion.rechazado:
      case EstadoConfirmacion.noRespondio:
        return false;
    }
  }

  /// Evidencia para asumir que el partido sí ocurrió (sin acción explícita del
  /// organizador de marcarlo jugado).
  ///
  /// Regla: partido en `confirmado` (cupos cerrados o confirmación manual) y
  /// hora ya pasada. `organizando` con fecha pasada nunca califica.
  static bool evidenciaPartidoJugado(
    ConvocatoriaCompleta convocatoria, [
    DateTime? reference,
  ]) {
    if (!convocatoriaExpirada(convocatoria.partido, reference)) return false;
    return convocatoria.partido.estado == EstadoPartido.confirmado;
  }

  static ConvocatoriaOrganizadorSituacion situacionOrganizador(
    ConvocatoriaCompleta convocatoria, [
    DateTime? reference,
  ]) {
    if (!convocatoriaExpirada(convocatoria.partido, reference)) {
      return ConvocatoriaOrganizadorSituacion.preparando;
    }
    if (evidenciaPartidoJugado(convocatoria, reference)) {
      return ConvocatoriaOrganizadorSituacion.listoParaGastos;
    }
    return ConvocatoriaOrganizadorSituacion.sinResolver;
  }

  static bool puedeRegistrarGastos(
    ConvocatoriaCompleta convocatoria, [
    DateTime? reference,
  ]) =>
      evidenciaPartidoJugado(convocatoria, reference);

  static bool puedeRegistrarGastosDesdeOrganizar({
    required Partido partido,
    required bool convocatoriaEnviada,
    DateTime? reference,
  }) {
    if (!convocatoriaEnviada) return false;
    if (partido.estado != EstadoPartido.confirmado) return false;
    return convocatoriaExpirada(partido, reference);
  }
}
