import '../core/auth_service.dart';

/// Nudges suaves para conversión jugador → organizador (no invasivos).
class OrganizerNudgeService {
  OrganizerNudgeService._();

  static Future<bool> shouldShowHomeCard({
    required int partidosJugados,
    required int invitesRecibidas,
  }) async {
    if (AuthService.instance.isOrganizer) return false;
    if (partidosJugados >= 3 || invitesRecibidas >= 2) return true;
    return false;
  }
}
