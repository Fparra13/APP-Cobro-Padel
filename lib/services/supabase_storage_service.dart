import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_helpers.dart';

/// Subida de archivos a Supabase Storage (comprobantes de pago).
class SupabaseStorageService {
  SupabaseStorageService._();
  static final SupabaseStorageService instance = SupabaseStorageService._();

  static const bucket = 'comprobantes';
  static const avatarsBucket = 'avatars';

  Future<String> uploadComprobante({
    required String userId,
    required File file,
    String? nombreArchivo,
  }) async {
    final client = SupabaseHelpers.client;
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final name = nombreArchivo ??
        '${DateTime.now().millisecondsSinceEpoch}$ext';
    final path = '$userId/$name';

    await client.storage.from(bucket).upload(path, file);

    return path;
  }

  Future<String> signedUrl(String storagePath) async {
    final client = SupabaseHelpers.client;
    return client.storage.from(bucket).createSignedUrl(
          storagePath,
          3600,
        );
  }

  Future<void> deleteIfExists(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return;
    try {
      await SupabaseHelpers.client.storage.from(bucket).remove([storagePath]);
    } catch (_) {}
  }

  /// Sube foto de perfil y devuelve URL pública.
  Future<String> uploadAvatar({
    required String jugadorId,
    required File file,
  }) async {
    final client = SupabaseHelpers.client;
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final storagePath = '$jugadorId/${DateTime.now().millisecondsSinceEpoch}$ext';

    await client.storage.from(avatarsBucket).upload(
          storagePath,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    return client.storage.from(avatarsBucket).getPublicUrl(storagePath);
  }

  Future<void> deleteAvatarPublicUrl(String? publicUrl) async {
    if (publicUrl == null || publicUrl.isEmpty) return;
    final path = _storagePathFromPublicUrl(publicUrl);
    if (path == null) return;
    try {
      await SupabaseHelpers.client.storage.from(avatarsBucket).remove([path]);
    } catch (_) {}
  }

  String? _storagePathFromPublicUrl(String publicUrl) {
    final uri = Uri.tryParse(publicUrl);
    if (uri == null) return null;
    final segments = uri.pathSegments;
    final idx = segments.indexOf(avatarsBucket);
    if (idx < 0 || idx + 1 >= segments.length) return null;
    return segments.sublist(idx + 1).join('/');
  }
}
