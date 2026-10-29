import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalStorageService {
  // ignore: prefer_initializing_formals
  LocalStorageService({Directory? directory}) : _directory = directory;

  Directory? _directory;
  File? _file;
  Map<String, dynamic> _data = <String, dynamic>{};

  Future<void> init() async {
    _directory ??= await getApplicationDocumentsDirectory();
    _file = File('${_directory!.path}/mishkat_store.json');

    // Crash recovery: if primary file does not exist, check for orphaned .tmp files
    if (!await _file!.exists()) {
      try {
        final dir = _file!.parent;
        if (await dir.exists()) {
          final prefix = '${_file!.path}.';
          final tmpFiles = dir
              .listSync()
              .whereType<File>()
              .where(
                (f) => f.path.startsWith(prefix) && f.path.endsWith('.tmp'),
              )
              .toList();
          if (tmpFiles.isNotEmpty) {
            tmpFiles.sort(
              (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
            );
            final newest = tmpFiles.first;
            await newest.rename(_file!.path);
          }
        }
      } catch (_) {
        // Recovery best-effort; proceed to normal check
      }
    }

    if (!await _file!.exists()) return;
    try {
      final decoded = jsonDecode(await _file!.readAsString());
      if (decoded is Map<String, dynamic>) _data = decoded;
    } on Object {
      _data = <String, dynamic>{};
    }
  }

  Map<String, dynamic> readMap(String key) {
    final value = _data[key];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  List<dynamic> readList(String key) {
    final value = _data[key];
    return value is List ? List<dynamic>.from(value) : <dynamic>[];
  }

  int readInt(String key, [int fallback = 0]) {
    final value = _data[key];
    return value is num ? value.toInt() : fallback;
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    final previous = _data[key];
    final hadKey = _data.containsKey(key);
    _data[key] = value;
    try {
      await _persist();
    } catch (_) {
      if (hadKey) {
        _data[key] = previous;
      } else {
        _data.remove(key);
      }
      rethrow;
    }
  }

  Future<void> writeList(String key, List<dynamic> value) async {
    final previous = _data[key];
    final hadKey = _data.containsKey(key);
    _data[key] = value;
    try {
      await _persist();
    } catch (_) {
      if (hadKey) {
        _data[key] = previous;
      } else {
        _data.remove(key);
      }
      rethrow;
    }
  }

  Future<void> writeInt(String key, int value) async {
    final previous = _data[key];
    final hadKey = _data.containsKey(key);
    _data[key] = value;
    try {
      await _persist();
    } catch (_) {
      if (hadKey) {
        _data[key] = previous;
      } else {
        _data.remove(key);
      }
      rethrow;
    }
  }

  Future<void> remove(String key) async {
    final previous = _data[key];
    final hadKey = _data.containsKey(key);
    if (!hadKey) return;
    _data.remove(key);
    try {
      await _persist();
    } catch (_) {
      _data[key] = previous;
      rethrow;
    }
  }

  Future<void> clear() async {
    final previous = Map<String, dynamic>.from(_data);
    _data.clear();
    try {
      await _persist();
    } catch (_) {
      _data = previous;
      rethrow;
    }
  }

  Future<void>? _pendingPersist;
  bool _needsPersist = false;

  Future<void> _persist() async {
    final file = _file;
    if (file == null) {
      throw StateError('LocalStorageService.init must be called first');
    }
    _needsPersist = true;
    if (_pendingPersist != null) return _pendingPersist!;

    _pendingPersist =
        Future<void>(() async {
          while (_needsPersist) {
            _needsPersist = false;
            try {
              await file.parent.create(recursive: true);
              final raw = jsonEncode(_data);
              final temporary = File(
                '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
              );
              await temporary.writeAsString(raw, flush: true);
              try {
                await temporary.rename(file.path);
              } on FileSystemException {
                if (await file.exists()) {
                  await file.delete();
                }
                await temporary.rename(file.path);
              }
            } catch (_) {
              try {
                await file.writeAsString(jsonEncode(_data), flush: true);
              } catch (_) {
                rethrow;
              }
            }
          }
        }).whenComplete(() {
          _pendingPersist = null;
        });

    return _pendingPersist!;
  }
}
