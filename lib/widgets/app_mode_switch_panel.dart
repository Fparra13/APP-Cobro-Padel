import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';

/// Interruptor Organizador ↔ Jugador (solo perfiles organizador).
class AppModeSwitchPanel extends StatelessWidget {
  const AppModeSwitchPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isOrganizer) {
      return const SizedBox.shrink();
    }

    final settings = context.watch<AppSettingsController>();
    final l10n = context.l10n;
    final mode = settings.uiMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.tr('appModeTitle'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.tr('appModeSubtitle'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        SegmentedButton<AppUiMode>(
          segments: [
            ButtonSegment(
              value: AppUiMode.organizer,
              icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
              label: Text(l10n.tr('appModeOrganizer')),
            ),
            ButtonSegment(
              value: AppUiMode.player,
              icon: const Icon(Icons.person_outline, size: 18),
              label: Text(l10n.tr('appModePlayer')),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (set) {
            context.switchAppUiMode(set.first);
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mode == AppUiMode.organizer
                ? Colors.blue.shade50
                : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: mode == AppUiMode.organizer
                  ? Colors.blue.shade100
                  : Colors.green.shade100,
            ),
          ),
          child: Text(
            mode == AppUiMode.organizer
                ? l10n.tr('appModeOrganizerHint')
                : l10n.tr('appModePlayerHint'),
            style: TextStyle(
              fontSize: 13,
              color: mode == AppUiMode.organizer
                  ? Colors.blue.shade900
                  : Colors.green.shade900,
            ),
          ),
        ),
      ],
    );
  }
}
