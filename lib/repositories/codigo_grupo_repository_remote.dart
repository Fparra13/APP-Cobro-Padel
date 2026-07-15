import '../core/supabase_helpers.dart';
import '../models/codigo_grupo.dart';

/// Código de grupo del organizador + unirse como jugador.
class CodigoGrupoRepositoryRemote {
  final _client = SupabaseHelpers.client;

  Future<String> obtenerMiCodigo() {
    return SupabaseHelpers.guard('Obtener código de grupo', () async {
      final raw = await _client.rpc('obtener_mi_codigo_grupo');
      final code = raw?.toString().trim() ?? '';
      if (code.isEmpty) {
        throw Exception('No se pudo obtener el código de grupo');
      }
      return code;
    });
  }

  Future<String> regenerarMiCodigo() {
    return SupabaseHelpers.guard('Regenerar código de grupo', () async {
      final raw = await _client.rpc('regenerar_mi_codigo_grupo');
      final code = raw?.toString().trim() ?? '';
      if (code.isEmpty) {
        throw Exception('No se pudo regenerar el código');
      }
      return code;
    });
  }

  Future<UnirseGrupoResult> unirseConCodigo(String codigo) {
    return SupabaseHelpers.guard('Unirse con código', () async {
      final raw = await _client.rpc(
        'unirse_con_codigo_grupo',
        params: {'p_codigo': codigo.trim()},
      );
      if (raw is Map) {
        return UnirseGrupoResult.fromJson(Map<String, dynamic>.from(raw));
      }
      throw Exception('Respuesta inválida al unirse al grupo');
    });
  }

  Future<List<MiOrganizadorGrupo>> listarMisOrganizadores() {
    return SupabaseHelpers.guard('Listar mis grupos', () async {
      final raw = await _client.rpc('listar_mis_organizadores');
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => MiOrganizadorGrupo.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    });
  }
}
