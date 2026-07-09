import 'package:flutter/material.dart';

import '../core/auth_service.dart';
import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/jugador.dart';
import '../services/jugador_foto_service.dart';
import '../services/supabase_storage_service.dart';
import '../utils/matchpay_context.dart';

/// El jugador (o admin sobre sí mismo) elige / quita su foto de perfil.
Future<void> editarFotoPerfil(
  BuildContext context, {
  required Jugador jugador,
  VoidCallback? onDone,
}) async {
  final l10n = context.l10n;
  final fotoService = JugadorFotoService.instance;
  final tieneFoto =
      (jugador.fotoPath != null && jugador.fotoPath!.isNotEmpty) ||
      (jugador.fotoUrl != null && jugador.fotoUrl!.isNotEmpty);

  final opcion = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_a_photo_outlined),
            title: Text(l10n.tr('pickPhoto')),
            onTap: () => Navigator.pop(ctx, 'elegir'),
          ),
          if (tieneFoto)
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: Text(
                l10n.tr('removePhoto'),
                style: TextStyle(color: Colors.red.shade700),
              ),
              onTap: () => Navigator.pop(ctx, 'quitar'),
            ),
        ],
      ),
    ),
  );

  if (!context.mounted || opcion == null) return;

  final repos = AppRepositories.isReady ? AppRepositories.I : context.repos;
  final messenger = ScaffoldMessenger.of(context);

  try {
    if (opcion == 'quitar') {
      await fotoService.delete(jugador.fotoPath);
      if (repos.isCloud && jugador.fotoUrl != null) {
        await SupabaseStorageService.instance.deleteAvatarPublicUrl(
          jugador.fotoUrl,
        );
      }
      await repos.updateJugador(jugador.copyWith(clearFoto: true));
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.tr('photoRemoved'))));
      AppRepositories.notifyDataChanged();
      onDone?.call();
      return;
    }

    final uid = AuthService.instance.currentUser?.id;
    final storageJugadorId =
        uid != null && jugador.supabaseId == uid ? uid : jugador.keyId;
    if (storageJugadorId.isEmpty) {
      throw Exception('Perfil sin identificador');
    }

    final result = await fotoService.pickSaveAndSync(
      context: context,
      jugadorId: storageJugadorId,
      replaceLocalPath: jugador.fotoPath,
      replacePublicUrl: jugador.fotoUrl,
      uploadToCloud: repos.isCloud,
    );
    if (result == null || !context.mounted) return;

    await repos.updateJugador(
      jugador.copyWith(
        fotoPath: result.localPath,
        fotoUrl: result.publicUrl,
      ),
    );
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.tr('photoUpdated'))));
    AppRepositories.notifyDataChanged();
    onDone?.call();
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(context.userError(e)), backgroundColor: Colors.red.shade700),
    );
  }
}
