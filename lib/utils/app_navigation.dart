import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/feature_gate.dart';
import '../core/subscription_service.dart';
import '../screens/nuevo_partido_screen.dart';
import '../screens/organizar_partido_screen.dart';

Future<bool?> abrirOrganizarPartido(
  BuildContext context, {
  int? partidoId,
}) async {
  if (partidoId == null) {
    final allowed = await FeatureGate.requirePro(
      context,
      feature: ProFeature.createMatch,
      message: 'Crear convocatorias requiere MatchPay Pro.',
    );
    if (!allowed || !context.mounted) return null;
  }

  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (ctx) => AppRepositoriesScope(
        repos: AppRepositories.I,
        child: OrganizarPartidoScreen(partidoId: partidoId),
      ),
    ),
  );
}

Future<bool?> abrirNuevoPartidoJugado(BuildContext context) async {
  final allowed = await FeatureGate.requirePro(
    context,
    feature: ProFeature.createMatch,
    message: 'Registrar partidos jugados requiere MatchPay Pro.',
  );
  if (!allowed || !context.mounted) return null;
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (ctx) => AppRepositoriesScope(
        repos: AppRepositories.I,
        child: const NuevoPartidoScreen(),
      ),
    ),
  );
}
