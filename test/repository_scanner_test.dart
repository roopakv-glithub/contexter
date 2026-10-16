import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moscowt/services/repository_scanner.dart';

void main() {
  test(
    'scans source and manifests, excluding generated and secret files',
    () async {
      final root = await Directory.systemTemp.createTemp('moscowt-scan-');
      addTearDown(() => root.delete(recursive: true));
      final lib = Directory('${root.path}${Platform.pathSeparator}lib');
      await lib.create(recursive: true);
      await File('${lib.path}${Platform.pathSeparator}main.dart')
          .writeAsString('void main() {}');
      await File('${root.path}${Platform.pathSeparator}pubspec.yaml')
          .writeAsString('dependencies:\n  flutter:\n    sdk: flutter');
      await File('${root.path}${Platform.pathSeparator}.env')
          .writeAsString('API_KEY=should-not-be-read');
      final nodeModules = Directory(
        '${root.path}${Platform.pathSeparator}node_modules',
      );
      await nodeModules.create(recursive: true);
      await File('${nodeModules.path}${Platform.pathSeparator}ignored.js')
          .writeAsString('ignored');

      final result = await RepositoryScanner.scan(root.path);

      expect(
        result.files.map((file) => file.path),
        containsAll(['lib/main.dart', 'pubspec.yaml']),
      );
      expect(result.files.map((file) => file.path), isNot(contains('.env')));
      expect(
        result.files.map((file) => file.path),
        isNot(contains('node_modules/ignored.js')),
      );
      expect(result.discoveredFiles, 2);
      expect(result.omittedFiles, 0);
    },
  );

  test(
    'redacts provider tokens before the folder contents leave the device',
    () async {
      final root = await Directory.systemTemp.createTemp('moscowt-redact-');
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}${Platform.pathSeparator}settings.ts');
      await source.writeAsString(
        "const NVIDIA_API_KEY = 'nvapi-abcdefghijklmnopqrstuvwxyz123456';",
      );

      final result = await RepositoryScanner.scan(root.path);

      expect(result.files.single.content, isNot(contains('nvapi-')));
      expect(result.files.single.content, contains('[REDACTED'));
    },
  );

  test('marks source files truncated at the analysis limit', () async {
    final root = await Directory.systemTemp.createTemp('moscowt-truncate-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}${Platform.pathSeparator}large.dart')
        .writeAsString('a' * (RepositoryScanner.maxFileCharacters + 100));

    final result = await RepositoryScanner.scan(root.path);

    expect(
      result.files.single.content.length,
      RepositoryScanner.maxFileCharacters,
    );
    expect(result.files.single.truncated, isTrue);
    expect(result.omittedFiles, 0);
  });
}
