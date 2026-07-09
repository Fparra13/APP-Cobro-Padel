import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/matchpay_design_tokens.dart';
import '../core/offline_status_controller.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import 'matchpay_ui.dart';

/// Banner global cuando se muestran datos cacheados sin conexión.
class OfflineReadonlyBanner extends StatelessWidget {
  const OfflineReadonlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineStatusController>(
      builder: (context, status, _) {
        if (status.mode != OfflineDisplayMode.offlineCached) {
          return const SizedBox.shrink();
        }
        final fetchedAt = status.activeSnapshotAt;
        final age = fetchedAt == null ? '' : formatTiempoRelativo(fetchedAt);
        return Material(
          color: MatchPayTokens.surfaceBase,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: MatchPayStatusBanner(
                icon: Icons.cloud_off_outlined,
                message: context.l10n.tr(
                  'offlineReadonlyBanner',
                  params: {'age': age},
                ),
                urgent: false,
              ),
            ),
          ),
        );
      },
    );
  }
}
