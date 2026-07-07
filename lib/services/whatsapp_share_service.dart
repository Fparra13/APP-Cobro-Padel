import 'package:url_launcher/url_launcher.dart';

import '../utils/formatters.dart';

/// Abre WhatsApp con un mensaje prearmado (chat directo o selector).
class WhatsAppShareService {
  WhatsAppShareService._();

  static Future<bool> enviar({
    required String mensaje,
    String? telefono,
  }) async {
    final digits =
        telefono != null ? normalizeWhatsAppDigits(telefono) : null;
    final encoded = Uri.encodeComponent(mensaje);
    final uri = digits != null
        ? Uri.parse('https://wa.me/$digits?text=$encoded')
        : Uri.parse('https://wa.me/?text=$encoded');
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
