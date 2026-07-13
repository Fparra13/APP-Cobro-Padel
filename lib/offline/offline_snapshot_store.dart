import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OfflineSnapshot {
  final DateTime fetchedAt;
  final Map<String, dynamic> payload;

  const OfflineSnapshot({
    required this.fetchedAt,
    required this.payload,
  });
}

/// Store genérico clave→JSON. No conoce modelos de Kloovi.
class OfflineSnapshotStore {
  OfflineSnapshotStore({
    required this.userId,
    Directory? baseDirectory,
  }) : _baseDirectory = baseDirectory;

  static const schemaVersion = 1;

  final String userId;
  final Directory? _baseDirectory;

  Future<File> _fileForKey(String key) async {
    final dir = await _directoryForUser();
    return File(p.join(dir.path, '$key.json'));
  }

  Future<Directory> _directoryForUser() async {
    if (_baseDirectory != null) {
      final dir = Directory(p.join(_baseDirectory!.path, userId));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'matchpay_offline', userId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> save(String key, Map<String, dynamic> payload) async {
    final envelope = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    final jsonString = await compute(_encodeJson, envelope);
    final file = await _fileForKey(key);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonString, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<OfflineSnapshot?> read(String key) async {
    final file = await _fileForKey(key);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = await compute(_decodeJson, raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final version = map['schemaVersion'];
      if (version != schemaVersion) return null;
      final fetchedRaw = map['fetchedAt'];
      if (fetchedRaw is! String) return null;
      final fetchedAt = DateTime.tryParse(fetchedRaw);
      if (fetchedAt == null) return null;
      final payloadRaw = map['payload'];
      if (payloadRaw is! Map) return null;
      return OfflineSnapshot(
        fetchedAt: fetchedAt.toLocal(),
        payload: Map<String, dynamic>.from(payloadRaw),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearForUser(String userId, {Directory? baseDirectory}) async {
    if (baseDirectory != null) {
      final dir = Directory(p.join(baseDirectory.path, userId));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'matchpay_offline', userId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

String _encodeJson(Map<String, dynamic> envelope) =>
    jsonEncode(envelope);

dynamic _decodeJson(String raw) => jsonDecode(raw);
