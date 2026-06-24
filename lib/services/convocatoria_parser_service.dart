import '../models/estado_partido.dart';
import '../models/jugador.dart';

class ResultadoImportacionConvocatoria {
  final Map<int, EstadoConfirmacion> cambios;
  final List<String> noReconocidos;

  const ResultadoImportacionConvocatoria({
    required this.cambios,
    required this.noReconocidos,
  });

  int get totalAplicados => cambios.length;
}

class ConvocatoriaParserService {
  static final _confirmado = RegExp(
    r'(✅|\+ ?1\b|confirmo|confirmado|voy\b|va\b|dale|cuenta conmigo|presente|asisto|sí\b|si\b)',
    caseSensitive: false,
  );
  static final _rechazado = RegExp(
    r'(❌|no voy|no puedo|no podré|no asisto|rechazo|paso\b|imposible)',
    caseSensitive: false,
  );

  ResultadoImportacionConvocatoria parsear({
    required String texto,
    required List<Jugador> jugadoresInvitados,
  }) {
    final cambios = <int, EstadoConfirmacion>{};
    final noReconocidos = <String>[];
    final lineas = texto.split(RegExp(r'[\r\n]+'));

    for (final linea in lineas) {
      final limpia = linea.trim();
      if (limpia.isEmpty) continue;

      final estado = _estadoDeLinea(limpia);
      if (estado == null) continue;

      final jugador = _buscarJugador(limpia, jugadoresInvitados);
      if (jugador?.id != null) {
        cambios[jugador!.id!] = estado;
      } else {
        final nombre = _extraerNombre(limpia);
        if (nombre != null && nombre.length >= 2) {
          noReconocidos.add(nombre);
        }
      }
    }

    return ResultadoImportacionConvocatoria(
      cambios: cambios,
      noReconocidos: noReconocidos.toSet().toList(),
    );
  }

  EstadoConfirmacion? _estadoDeLinea(String linea) {
    if (_rechazado.hasMatch(linea)) return EstadoConfirmacion.rechazado;
    if (_confirmado.hasMatch(linea)) return EstadoConfirmacion.confirmado;
    return null;
  }

  Jugador? _buscarJugador(String linea, List<Jugador> jugadores) {
    final normalizada = _normalizar(linea);

    Jugador? mejor;
    var mejorPuntaje = 0;

    for (final j in jugadores) {
      final nombreNorm = _normalizar(j.nombre);
      if (nombreNorm.isEmpty) continue;

      if (normalizada.contains(nombreNorm)) {
        if (nombreNorm.length > mejorPuntaje) {
          mejorPuntaje = nombreNorm.length;
          mejor = j;
        }
        continue;
      }

      for (final parte in nombreNorm.split(' ')) {
        if (parte.length < 3) continue;
        if (normalizada.contains(parte) && parte.length > mejorPuntaje) {
          mejorPuntaje = parte.length;
          mejor = j;
        }
      }
    }

    return mejor;
  }

  String? _extraerNombre(String linea) {
    var texto = linea
        .replaceAll(_confirmado, '')
        .replaceAll(_rechazado, '')
        .replaceAll(RegExp(r'[✅❌\-–—:.,]'), ' ')
        .trim();

    texto = texto.replaceFirst(
      RegExp(r'^voy\s+', caseSensitive: false),
      '',
    );
    texto = texto.replaceFirst(
      RegExp(r'^no voy\s+', caseSensitive: false),
      '',
    );

    return texto.trim().isEmpty ? null : texto.trim();
  }

  String _normalizar(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
