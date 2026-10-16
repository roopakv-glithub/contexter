import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalHistory {
  LocalHistory({this.directory});

  final Directory? directory;
  Future<void> _writeQueue = Future<void>.value();
  Future<File>? _historyFile;

  Future<File> get _file => _historyFile ??= _resolveFile();

  Future<File> _resolveFile() async {
    final historyDirectory =
        directory ?? await getApplicationSupportDirectory();
    await historyDirectory.create(recursive: true);
    return File(
      '${historyDirectory.path}${Platform.pathSeparator}history.json',
    );
  }

  Future<Map<String, dynamic>> _read() async {
    final file = await _file;
    if (!await file.exists()) {
      return {'reports': <dynamic>[], 'prompts': <dynamic>[]};
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Local history file has an invalid format.');
    }
    return decoded;
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) {
    final rows = data[key];
    if (rows is! List) return [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<List<Map<String, dynamic>>> recentReports() async =>
      _rows(await _read(), 'reports');

  Future<List<Map<String, dynamic>>> recentPrompts() async =>
      _rows(await _read(), 'prompts');

  Future<Map<String, dynamic>> saveReport({
    required String projectName,
    required String source,
    required Map<String, dynamic> report,
  }) async {
    final saved = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'project_name': projectName,
      'source': source,
      'report': report,
      'created_at': DateTime.now().toIso8601String(),
    };
    await _update((data) {
      data['reports'] = [saved, ..._rows(data, 'reports').take(19)];
    });
    return saved;
  }

  Future<Map<String, dynamic>> savePrompt({
    required String original,
    required String enhanced,
    required String projectName,
  }) async {
    final saved = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'project_name': projectName,
      'original_prompt': original,
      'enhanced_prompt': enhanced,
      'created_at': DateTime.now().toIso8601String(),
    };
    await _update((data) {
      data['prompts'] = [saved, ..._rows(data, 'prompts').take(99)];
    });
    return saved;
  }

  Future<void> _update(void Function(Map<String, dynamic>) update) async {
    final previous = _writeQueue;
    final completer = Completer<void>();
    _writeQueue = completer.future;
    try {
      await previous;
      final data = await _read();
      update(data);
      final file = await _file;
      await file.writeAsString(jsonEncode(data), flush: true);
    } finally {
      completer.complete();
    }
  }
}
