import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/supabase_config.dart';
import '../l10n/matchpay_strings.dart';
import 'supabase_storage_service.dart';

class JugadorFotoService {
  JugadorFotoService._();
  static final JugadorFotoService instance = JugadorFotoService._();

  static const subdir = 'fotos_jugadores';
  final ImagePicker _picker = ImagePicker();

  Future<Directory> _storageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, subdir));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File?> resolveFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    if (await file.exists()) return file;
    return null;
  }

  Future<ImageSource?> askSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(ctx.l10n.tr('pickSourceGallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(ctx.l10n.tr('pickSourceCamera')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> pickAndSave({
    required BuildContext context,
    String? replacePath,
  }) async {
    final source = await askSource(context);
    if (source == null || !context.mounted) return null;

    final xFile = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (xFile == null) return null;

    if (replacePath != null) {
      await delete(replacePath);
    }

    final dir = await _storageDir();
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = File(p.join(dir.path, name));
    await File(xFile.path).copy(dest.path);
    return p.join(subdir, name);
  }

  /// Guarda localmente y, si hay Supabase, sube a Storage.
  Future<({String localPath, String? publicUrl})?> pickSaveAndSync({
    required BuildContext context,
    required String jugadorId,
    String? replaceLocalPath,
    String? replacePublicUrl,
    bool uploadToCloud = false,
  }) async {
    final localPath = await pickAndSave(
      context: context,
      replacePath: replaceLocalPath,
    );
    if (localPath == null) return null;

    if (!uploadToCloud || !SupabaseConfig.isConfigured) {
      return (localPath: localPath, publicUrl: null);
    }

    final file = await resolveFile(localPath);
    if (file == null) {
      return (localPath: localPath, publicUrl: null);
    }

    if (replacePublicUrl != null && replacePublicUrl.isNotEmpty) {
      await SupabaseStorageService.instance.deleteAvatarPublicUrl(
        replacePublicUrl,
      );
    }

    final publicUrl = await SupabaseStorageService.instance.uploadAvatar(
      jugadorId: jugadorId,
      file: file,
    );
    return (localPath: localPath, publicUrl: publicUrl);
  }

  Future<void> delete(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
