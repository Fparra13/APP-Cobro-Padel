/// Resultado del envío de convocatoria tras la persistencia crítica.
///
/// Punto de éxito "enviada": [activateDeadlines] completó (asigna
/// `tiempo_limite` → `convocatoriaEnviada`). Las notificaciones son
/// best-effort y no revierten ese estado.
enum ConvocatoriaSendStatus {
  /// Guardado o activación de plazos falló / no aplicó.
  notSent,

  /// Persistencia crítica OK y notificaciones OK.
  sent,

  /// Persistencia crítica OK; falló el envío de avisos (sigue siendo enviada).
  sentWithNotificationGaps,
}

/// Orquesta save → plazos → notificaciones con semántica de éxito parcial.
class ConvocatoriaSendSemantics {
  ConvocatoriaSendSemantics._();

  /// Tras [activateDeadlines] exitoso la convocatoria se considera enviada.
  static Future<ConvocatoriaSendStatus> run({
    required Future<bool> Function() save,
    required Future<void> Function() activateDeadlines,
    required Future<void> Function() notify,
  }) async {
    final saved = await save();
    if (!saved) return ConvocatoriaSendStatus.notSent;

    await activateDeadlines();

    try {
      await notify();
      return ConvocatoriaSendStatus.sent;
    } catch (_) {
      return ConvocatoriaSendStatus.sentWithNotificationGaps;
    }
  }

  static bool isConsideredSent(ConvocatoriaSendStatus status) =>
      status == ConvocatoriaSendStatus.sent ||
      status == ConvocatoriaSendStatus.sentWithNotificationGaps;

  static bool shouldCloseUi(ConvocatoriaSendStatus status) =>
      isConsideredSent(status);

  static String snackMessageKey(ConvocatoriaSendStatus status) {
    switch (status) {
      case ConvocatoriaSendStatus.sentWithNotificationGaps:
        return 'organizeInviteSentPartialNoticesSnack';
      case ConvocatoriaSendStatus.sent:
        return 'organizeInviteSentSnack';
      case ConvocatoriaSendStatus.notSent:
        return 'organizeInviteSentSnack';
    }
  }
}
