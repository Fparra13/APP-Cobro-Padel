import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/matchpay_strings.dart';
import '../utils/comprobante_path.dart';
import 'supabase_storage_service.dart';

class ComprobanteService {
  ComprobanteService._();
  static final ComprobanteService instance = ComprobanteService._();

  static const subdir = 'comprobantes';
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
    if (isCloudComprobantePath(relativePath)) return null;
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    if (await file.exists()) return file;
    return null;
  }

  /// Local [File] o URL firmada de Storage para mostrar / ampliar.
  Future<({File? file, String? networkUrl})> resolveForDisplay(
    String? path,
  ) async {
    if (path == null || path.isEmpty) {
      return (file: null, networkUrl: null);
    }
    if (isCloudComprobantePath(path)) {
      try {
        final url = await SupabaseStorageService.instance.signedUrl(path);
        return (file: null, networkUrl: url);
      } catch (_) {
        return (file: null, networkUrl: null);
      }
    }
    final file = await resolveFile(path);
    return (file: file, networkUrl: null);
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
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (xFile == null) return null;

    if (replacePath != null) {
      await deleteAny(replacePath);
    }

    final dir = await _storageDir();
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = File(p.join(dir.path, name));
    await File(xFile.path).copy(dest.path);
    return p.join(subdir, name);
  }

  Future<void> delete(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return;
    if (isCloudComprobantePath(relativePath)) return;
    final docs = await getApplicationDocumentsDirectory();
    final file = File(p.join(docs.path, relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Borra local o en Storage según el tipo de path.
  Future<void> deleteAny(String? path) async {
    if (path == null || path.isEmpty) return;
    if (isCloudComprobantePath(path)) {
      await SupabaseStorageService.instance.deleteIfExists(path);
      return;
    }
    await delete(path);
  }

  /// Si [path] es local, sube a Storage y borra el archivo local.
  /// Paths cloud se dejan igual. Devuelve el path a persistir en DB.
  Future<String?> ensureCloudPath({
    required String? path,
    required String userId,
    int? partidoId,
  }) async {
    if (path == null || path.isEmpty) return null;
    if (isCloudComprobantePath(path)) return path;

    final file = await resolveFile(path);
    if (file == null) {
      // Referencia local rota: no subir basura; conservar path (legacy).
      return path;
    }

    final subfolder =
        partidoId != null ? 'gastos/$partidoId' : 'gastos';
    final cloud = await SupabaseStorageService.instance.uploadComprobante(
      userId: userId,
      file: file,
      subfolder: subfolder,
    );
    await delete(path);
    return cloud;
  }
}

Future<void> showComprobanteViewer(
  BuildContext context, {
  required String relativePath,
}) async {
  final resolved =
      await ComprobanteService.instance.resolveForDisplay(relativePath);
  if (!context.mounted) return;

  if (resolved.file == null && resolved.networkUrl == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('receiptImageNotFound'))),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text(ctx.l10n.tr('expenseReceiptLabel')),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          Flexible(
            child: InteractiveViewer(
              child: resolved.file != null
                  ? Image.file(resolved.file!, fit: BoxFit.contain)
                  : Image.network(
                      resolved.networkUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(ctx.l10n.tr('receiptImageNotFound')),
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
