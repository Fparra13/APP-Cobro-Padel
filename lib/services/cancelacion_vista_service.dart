import 'package:shared_preferences/shared_preferences.dart';

/// Partidos cancelados cuyo popup in-app el jugador ya cerró (persistente).
class CancelacionVistaService {
  CancelacionVistaService._();

  static String _key(String userId) => 'cancelaciones_vistas_$userId';

  static Future<Set<int>> _vistas(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(userId)) ?? const [];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<List<int>> filtrarNoVistas({
    required String userId,
    required Iterable<int> partidoIds,
  }) async {
    final vistas = await _vistas(userId);
    return partidoIds.where((id) => !vistas.contains(id)).toList();
  }

  static Future<void> marcarVista({
    required String userId,
    required int partidoId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final vistas = await _vistas(userId);
    if (vistas.contains(partidoId)) return;
    vistas.add(partidoId);
    await prefs.setStringList(
      _key(userId),
      vistas.map((id) => '$id').toList(),
    );
  }
}
