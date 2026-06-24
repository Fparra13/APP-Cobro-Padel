import 'package:share_plus/share_plus.dart';
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
    final texto = mensaje.replaceAll('\r\n', '\n').trim();
    final numero = telefono != null ? _normalizarTelefono(telefono) : '';

    final uri = numero.isNotEmpty
        ? Uri.https('wa.me', numero, {'text': texto})
        : Uri.https('wa.me', '', {'text': texto});

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('No se pudo abrir WhatsApp');
    }
  }

  /// Abre el selector del sistema (WhatsApp grupo, etc.) con el texto listo.
  Future<void> compartirTexto(String mensaje) async {
    await SharePlus.instance.share(ShareParams(text: mensaje));
  }
}
