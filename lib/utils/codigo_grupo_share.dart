import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_repositories.dart';
import '../core/legal_urls.dart';
import '../l10n/matchpay_strings.dart';

/// Comparte el código de grupo del organizador (mismo mensaje que la card).
Future<void> compartirCodigoGrupoOrganizador(BuildContext context) async {
  final l10n = context.l10n;
  try {
    final code = await context.repos.obtenerMiCodigoGrupo();
    if (!context.mounted) return;
    if (code.trim().isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text: l10n.tr(
          'groupCodeShareMessage',
          params: {'code': code, 'url': LegalUrls.website},
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.userError(e))),
    );
  }
}
