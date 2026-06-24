import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
              title: const Text('Galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cámara'),
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
      await delete(replacePath);
    }

    final dir = await _storageDir();
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = File(p.join(dir.path, name));
    await File(xFile.path).copy(dest.path);
    return p.join(subdir, name);
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

Future<void> showComprobanteViewer(
  BuildContext context, {
  required String relativePath,
}) async {
  final file = await ComprobanteService.instance.resolveFile(relativePath);
  if (!context.mounted || file == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró la imagen del comprobante')),
      );
    }
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: const Text('Comprobante del gasto'),
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
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ],
      ),
    ),
  );
}
