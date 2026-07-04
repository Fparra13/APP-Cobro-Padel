import 'package:share_plus/share_plus.dart';

class ShareService {
  /// Abre el selector del sistema para compartir texto (convocatorias, etc.).
  Future<void> compartirTexto(String mensaje) async {
    await SharePlus.instance.share(ShareParams(text: mensaje));
  }
}
