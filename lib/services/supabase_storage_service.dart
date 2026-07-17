import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_helpers.dart';

/// Subida de archivos a Supabase Storage (comprobantes de pago / avatares).
class SupabaseStorageService {
  SupabaseStorageService._();
  static final SupabaseStorageService instance = SupabaseStorageService._();

  static const bucket = 'comprobantes';
  static const avatarsBucket = 'avatars';

  static const _imageMimeByExt = <String, String>{
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.heif': 'image/heif',
  };

  String _contentTypeForPath(String path) {
    final ext = p.extension(path).toLowerCase();
    return _imageMimeByExt[ext] ?? 'image/jpeg';
  }

  /// Sube al bucket [comprobantes].
  ///
  /// [subfolder] opcional, p. ej. `gastos` o `gastos/42` →
  /// `{userId}/gastos/42/{ts}.jpg`.
  Future<String> uploadComprobante({
    required String userId,
    required File file,
    String? nombreArchivo,
    String? subfolder,
  }) async {
    final client = SupabaseHelpers.client;
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final name = nombreArchivo ??
        '${DateTime.now().millisecondsSinceEpoch}$ext';
    final folder = (subfolder == null || subfolder.isEmpty)
        ? userId
        : '$userId/${subfolder.replaceAll(RegExp(r'^/+|/+$'), '')}';
    final path = '$folder/$name';
    final contentType = _contentTypeForPath(name);

    await client.storage.from(bucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType),
        );

    return path;
  }

  /// Path relativo en el bucket (`{uuid}/…jpg`). Si llega una URL completa, extrae el path.
  static String normalizeComprobantePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!trimmed.contains('://')) {
      return trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    final segments = uri.pathSegments;
    final idx = segments.indexOf(bucket);
    if (idx < 0 || idx + 1 >= segments.length) return trimmed;
    return segments.sublist(idx + 1).join('/');
  }

  Future<String> signedUrl(String storagePath) async {
    final client = SupabaseHelpers.client;
    final path = normalizeComprobantePath(storagePath);
    return client.storage.from(bucket).createSignedUrl(path, 3600);
  }

  Future<void> deleteIfExists(String? storagePath) async {
    if (storagePath == null || storagePath.isEmpty) return;
    try {
      await SupabaseHelpers.client.storage.from(bucket).remove([storagePath]);
    } catch (e) {
      debugPrint('Storage delete comprobante falló ($storagePath): $e');
    }
  }

  /// Sube foto de perfil y devuelve URL pública.
  Future<String> uploadAvatar({
    required String jugadorId,
    required File file,
  }) async {
    final client = SupabaseHelpers.client;
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final storagePath = '$jugadorId/${DateTime.now().millisecondsSinceEpoch}$ext';
    final contentType = _contentTypeForPath(storagePath);

    await client.storage.from(avatarsBucket).upload(
          storagePath,
          file,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );

    return client.storage.from(avatarsBucket).getPublicUrl(storagePath);
  }

  Future<void> deleteAvatarPublicUrl(String? publicUrl) async {
    if (publicUrl == null || publicUrl.isEmpty) return;
    final path = _storagePathFromPublicUrl(publicUrl);
    if (path == null) return;
    try {
      await SupabaseHelpers.client.storage.from(avatarsBucket).remove([path]);
    } catch (e) {
      debugPrint('Storage delete avatar falló ($path): $e');
    }
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
