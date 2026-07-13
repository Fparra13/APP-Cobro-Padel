import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../database/database_helper.dart';

class BackupRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<String> exportDatabase() async {
    await _db.database;
    final sourcePath = await DatabaseHelper.resolveDbPath();

    final exportDir = await _getExportDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final destPath = p.join(exportDir.path, 'matchpay_$timestamp.db');

    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<String> exportJson() async {
    final db = await _db.database;
    final data = <String, dynamic>{};

    for (final table in [
      'jugadores',
      'partidos',
      'detalles_partido',
      'costos_variables',
      'asignaciones_costo',
      'saldos_historicos',
    ]) {
      data[table] = await db.query(table);
    }

    final exportDir = await _getExportDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final destPath = p.join(exportDir.path, 'matchpay_$timestamp.json');

    await File(destPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    return destPath;
  }

  Future<void> shareFile(String filePath) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath)],
        text: 'Respaldo Kloovi',
      ),
    );
  }

  Future<bool> importDatabase() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
    );
    if (result == null || result.files.single.path == null) return false;

    await _db.close();
    final destPath = await DatabaseHelper.resolveDbPath();
    await File(result.files.single.path!).copy(destPath);
    await _db.database;
    return true;
  }

  Future<bool> importJson() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return false;

    final content = await File(result.files.single.path!).readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;

    await _db.resetDatabase();
    final db = await _db.database;

    await db.transaction((txn) async {
      for (final table in [
        'jugadores',
        'partidos',
        'detalles_partido',
        'costos_variables',
        'asignaciones_costo',
        'saldos_historicos',
      ]) {
        final rows = (data[table] as List?) ?? [];
        for (final row in rows) {
          await txn.insert(table, Map<String, dynamic>.from(row as Map));
        }
      }
    });
    return true;
  }

  Future<Directory> _getExportDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(docs.path, 'backups'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }
}
