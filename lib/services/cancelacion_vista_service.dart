import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../utils/app_log.dart';

/// Partidos cancelados cuyo popup in-app el jugador ya cerró.
///
/// SSOT en Supabase (`cancelacion_vista_en`); SharedPreferences es caché local.
class CancelacionVistaService {
  CancelacionVistaService._();

  static String _key(String userId) => 'cancelaciones_vistas_$userId';

  static Future<Set<int>> _vistasLocal(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key(userId)) ?? const [];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> _marcarLocal({
    required String userId,
    required int partidoId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final vistas = await _vistasLocal(userId);
    if (vistas.contains(partidoId)) return;
    vistas.add(partidoId);
    await prefs.setStringList(
      _key(userId),
      vistas.map((id) => '$id').toList(),
    );
  }

  static Future<List<int>> filtrarNoVistas({
    required String userId,
    required Iterable<int> partidoIds,
  }) async {
    final vistas = await _vistasLocal(userId);
    return partidoIds.where((id) => !vistas.contains(id)).toList();
  }

  static Future<void> marcarVista({
    required String userId,
    required int partidoId,
  }) async {
    await _marcarLocal(userId: userId, partidoId: partidoId);
    if (!SupabaseConfig.isConfigured) return;
    try {
      await Supabase.instance.client.rpc(
        'marcar_cancelacion_vista',
        params: {'p_partido_id': partidoId},
      );
    } catch (e) {
      appLog('CancelacionVistaService.marcarVista remote: $e');
    }
  }
}
