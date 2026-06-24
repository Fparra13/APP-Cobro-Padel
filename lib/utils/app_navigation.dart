import 'package:flutter/material.dart';

import '../screens/organizar_partido_screen.dart';

Future<bool?> abrirOrganizarPartido(
  BuildContext context, {
  int? partidoId,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(
      builder: (_) => OrganizarPartidoScreen(partidoId: partidoId),
    ),
  );
}
