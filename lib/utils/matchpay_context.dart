import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/sport_theme.dart';
import '../core/sport_type.dart';

/// Acceso rápido al tema dinámico MatchPay desde cualquier pantalla.
extension MatchPayThemeContext on BuildContext {
  AppSettingsController watchSettings() =>
      Provider.of<AppSettingsController>(this);

  AppSettingsController readSettings() =>
      Provider.of<AppSettingsController>(this, listen: false);

  /// Cambia modo organizador/jugador y vuelve al shell (Home), sin rutas viejas.
  Future<void> switchAppUiMode(AppUiMode mode) async {
    final nav = Navigator.of(this, rootNavigator: true);
    nav.popUntil((route) => route.isFirst);
    await readSettings().setUiMode(mode);
  }

  SportThemePalette get sportPalette {
    final fromTheme = Theme.of(this).extension<SportThemeExtension>()?.palette;
    if (fromTheme != null) return fromTheme;
    return SportThemeConfig.paletteFor(readSettings().sport);
  }

  Color get sportPrimary => sportPalette.primary;

  Color get sportPrimaryDark => sportPalette.primaryDark;

  /// AppBar estándar con color del deporte activo.
  PreferredSizeWidget sportAppBar({
    required String title,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      backgroundColor: sportPrimary,
      foregroundColor: Colors.white,
      title: Text(title),
      actions: actions,
      bottom: bottom,
    );
  }
}

extension SportTypeL10n on SportType {
  String labelForLocale(String languageCode) => labelForLang(languageCode);
}
