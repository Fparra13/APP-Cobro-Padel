import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/formatters.dart';

/// Abre WhatsApp con un mensaje prearmado (chat directo o selector).
class WhatsAppShareService {
  WhatsAppShareService._();

  /// WhatsApp personal (no Business).
  static const _packagePersonal = 'com.whatsapp';

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

    if (Platform.isAndroid) {
      final ok = await _abrirEnAndroid(uri, package: _packagePersonal);
      if (ok) return true;
    }

    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Fuerza la app indicada (evita que Android abra WhatsApp Business por defecto).
  static Future<bool> _abrirEnAndroid(
    Uri uri, {
    required String package,
  }) async {
    try {
      final intent = AndroidIntent(
        action: 'action_view',
        data: uri.toString(),
        package: package,
      );
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }
}
