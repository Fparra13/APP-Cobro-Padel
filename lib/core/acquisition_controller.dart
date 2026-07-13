import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Intención del usuario al entrar a Kloovi (no confundir con [profiles.role]).
enum MatchPayAcquisitionIntent {
  /// Cold start: aún no eligió camino (mostrar pantalla de adquisición).
  unknown,

  /// Invitación: deep link, email pre-cargado o "¿Ya te invitaron?".
  invited,

  /// Acción explícita: "Crear mi primer grupo" (organizer tras login).
  createFirstGroup,
}

/// Contexto de llegada: deep links, elección en cold start y navegación post-login.
class AcquisitionController extends ChangeNotifier {
  AcquisitionController._();

  static final AcquisitionController instance = AcquisitionController._();

  static const _keyResolved = 'matchpay_acquisition_resolved';
  static const _keyIntent = 'matchpay_acquisition_intent';
  static const _keyInvitePartidoId = 'matchpay_invite_partido_id';

  final AppLinks _appLinks = AppLinks();

  bool _loaded = false;
  bool _resolved = false;
  MatchPayAcquisitionIntent _intent = MatchPayAcquisitionIntent.unknown;
  int? _invitePartidoId;
  bool _pendingOpenOrganizer = false;
  bool _pendingOpenInvite = false;

  bool get isLoaded => _loaded;
  bool get isResolved => _resolved;
  MatchPayAcquisitionIntent get intent => _intent;
  int? get invitePartidoId => _invitePartidoId;

  /// Saltar pantalla de adquisición (invitación, elección previa o usuario recurrente).
  bool get shouldSkipAcquisitionScreen =>
      _resolved || _intent != MatchPayAcquisitionIntent.unknown;

  /// Deep link con partido: saltar intro de valor (ir directo a login).
  bool get skipIntroOnboarding => _invitePartidoId != null;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _resolved = prefs.getBool(_keyResolved) ?? false;
    _intent = _parseIntent(prefs.getString(_keyIntent));
    final storedInvite = prefs.getInt(_keyInvitePartidoId);
    if (storedInvite != null && storedInvite > 0) {
      _invitePartidoId = storedInvite;
    }

    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _applyInviteUri(initial);
      }
      _appLinks.uriLinkStream.listen(_applyInviteUri);
    } catch (e) {
      debugPrint('AcquisitionController: app links $e');
    }

    _loaded = true;
    notifyListeners();
  }

  void _applyInviteUri(Uri uri) {
    final partidoId = _parseInvitePartidoId(uri);
    if (partidoId == null) return;

    _invitePartidoId = partidoId;
    _intent = MatchPayAcquisitionIntent.invited;
    _resolved = true;
    unawaited(_persist());
    notifyListeners();
  }

  static int? _parseInvitePartidoId(Uri uri) {
    if (uri.scheme != 'matchpay') return null;
    if (uri.host != 'invite') return null;

    if (uri.pathSegments.isNotEmpty) {
      final id = int.tryParse(uri.pathSegments.first);
      if (id != null && id > 0) return id;
    }
    final q = uri.queryParameters['partido'] ??
        uri.queryParameters['partidoId'] ??
        uri.queryParameters['id'];
    if (q != null) {
      final id = int.tryParse(q);
      if (id != null && id > 0) return id;
    }
    return null;
  }

  /// Usuario elige organizar (Play Store) — no cambia role hasta post-login.
  Future<void> chooseCreateFirstGroup() async {
    _intent = MatchPayAcquisitionIntent.createFirstGroup;
    _resolved = true;
    await _persist();
    notifyListeners();
  }

  /// Usuario elige flujo jugador ("Soy jugador" o enlace de invitación manual).
  Future<void> choosePlayer() async {
    _intent = MatchPayAcquisitionIntent.invited;
    _resolved = true;
    await _persist();
    notifyListeners();
  }

  /// Alias para compatibilidad con flujos de invitación manual.
  Future<void> chooseInvited() => choosePlayer();

  /// Vuelve a la pantalla de elección de rol (back desde intro).
  Future<void> resetColdStartChoice() async {
    if (_invitePartidoId != null) return;
    _resolved = false;
    _intent = MatchPayAcquisitionIntent.unknown;
    await _persist();
    notifyListeners();
  }

  /// Tras login exitoso según intención createFirstGroup.
  void markPendingOpenOrganizer() {
    _pendingOpenOrganizer = true;
  }

  /// Tras login con invitación (deep link o flujo jugador).
  void markPendingOpenInvite() {
    if (_invitePartidoId != null) {
      _pendingOpenInvite = true;
    }
  }

  bool consumePendingOpenOrganizer() {
    if (!_pendingOpenOrganizer) return false;
    _pendingOpenOrganizer = false;
    // Solo la primera vez tras "Crear mi primer grupo".
    // Si no, cada hot restart / reload de RoleAwareShell reabre Organizar.
    if (_intent == MatchPayAcquisitionIntent.createFirstGroup) {
      _intent = MatchPayAcquisitionIntent.unknown;
      unawaited(_persist());
    }
    return true;
  }

  bool consumePendingOpenInvite() {
    if (!_pendingOpenInvite || _invitePartidoId == null) return false;
    _pendingOpenInvite = false;
    return true;
  }

  int? consumeInvitePartidoId() {
    final id = _invitePartidoId;
    _invitePartidoId = null;
    unawaited(_persist());
    return id;
  }

  Future<void> markResolvedAfterLogin() async {
    _resolved = true;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyResolved, _resolved);
    await prefs.setString(_keyIntent, _intent.name);
    if (_invitePartidoId != null) {
      await prefs.setInt(_keyInvitePartidoId, _invitePartidoId!);
    } else {
      await prefs.remove(_keyInvitePartidoId);
    }
  }

  static MatchPayAcquisitionIntent _parseIntent(String? raw) {
    if (raw == null || raw.isEmpty) {
      return MatchPayAcquisitionIntent.unknown;
    }
    for (final v in MatchPayAcquisitionIntent.values) {
      if (v.name == raw) return v;
    }
    return MatchPayAcquisitionIntent.unknown;
  }
}
