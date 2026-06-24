import 'package:url_launcher/url_launcher.dart';

class ShareService {
  String _normalizarTelefono(String telefono) {
    var numero = telefono.replaceAll(RegExp(r'\D'), '');
    if (numero.isEmpty) return '';
    if (numero.startsWith('56') && numero.length >= 11) return numero;
    if (numero.length == 9 && numero.startsWith('9')) return '56$numero';
    if (numero.length == 8) return '569$numero';
    return numero;
  }

  Future<void> compartirWhatsApp({
    required String mensaje,
    String? telefono,
  }) async {
    final encoded = Uri.encodeComponent(mensaje);
    final Uri uri;

    final numero = telefono != null ? _normalizarTelefono(telefono) : '';
    if (numero.isNotEmpty) {
      uri = Uri.parse('https://wa.me/$numero?text=$encoded');
    } else {
      uri = Uri.parse('https://wa.me/?text=$encoded');
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir WhatsApp');
    }
  }
}
