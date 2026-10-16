import 'dart:io';

import 'package:file_picker/file_picker.dart';

class ScannedFile {
  const ScannedFile({
    required this.path,
    required this.content,
    this.truncated = false,
  });

  final String path;
  final String content;
  final bool truncated;

  Map<String, dynamic> toJson() => {
    'path': path,
    'content': content,
    'truncated': truncated,
  };
}

class ScanResult {
  const ScanResult({
    required this.files,
    required this.discoveredFiles,
    required this.omittedFiles,
  });

  final List<ScannedFile> files;
  final int discoveredFiles;
  final int omittedFiles;
}

class RepositoryScanner {
  static const maxFiles = 180;
  static const maxFileCharacters = 12000;
  static const maxTotalCharacters = 900000;

  static const _sourceExtensions = {
    '.c',
    '.cc',
    '.cpp',
    '.cs',
    '.cjs',
    '.dart',
    '.ex',
    '.exs',
    '.go',
    '.gradle',
    '.h',
    '.hh',
    '.hpp',
    '.html',
    '.java',
    '.js',
    '.jsx',
    '.kt',
    '.kts',
    '.md',
    '.mjs',
    '.php',
    '.py',
    '.rb',
    '.rs',
    '.sh',
    '.sql',
    '.swift',
    '.ts',
    '.tsx',
    '.vue',
    '.xml',
    '.yaml',
    '.yml',
    '.json',
    '.toml',
    '.ini',
    '.cfg',
    '.properties',
    '.cmake',
    '.mk',
    '.prisma',
    '.graphql',
    '.gql',
    '.proto',
    '.tf',
    '.hcl',
    '.csproj',
    '.sln',
  };
  static const _manifestFiles = {
    'cargo.toml',
    'dockerfile',
    'gemfile',
    'go.mod',
    'package.json',
    'pom.xml',
    'pubspec.yaml',
    'pyproject.toml',
    'requirements.txt',
    'setup.py',
    'pubspec.lock',
    'package-lock.json',
    'pnpm-lock.yaml',
    'yarn.lock',
    'cargo.lock',
    'poetry.lock',
    'pipfile.lock',
    'composer.json',
  };
  static const _ignoredDirectories = {
    '.dart_tool',
    '.git',
    '.idea',
    '.next',
    '.pytest_cache',
    '.venv',
    'build',
    'coverage',
    'dist',
    'node_modules',
    'pods',
    'target',
    'vendor',
    'venv',
  };

  static String _redactSecrets(String content) => content
      .replaceAll(
        RegExp(
          r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
        ),
        '[REDACTED PRIVATE KEY]',
      )
      .replaceAll(
        RegExp(
          r'\b(?:nvapi-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,})\b',
        ),
        '[REDACTED TOKEN]',
      )
      .replaceAll(
        RegExp(
          r'\beyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b',
        ),
        '[REDACTED JWT]',
      )
      .replaceAll(
        RegExp(
          r'((?:api[_-]?key|(?:access|auth)[_-]?token|token|secret|password|credential|client[_-]?secret|service[_-]?role|private[_-]?key)\s*[:=]\s*["\x27]?)[^"\x27`\s,;]+',
          caseSensitive: false,
        ),
        r'$1[REDACTED]',
      );

  static bool _isAllowed(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (parts.any((part) => _ignoredDirectories.contains(part.toLowerCase()))) {
      return false;
    }

    final name = parts.last.toLowerCase();
    if (name == '.env' ||
        name.startsWith('.env.') ||
        name.endsWith('.pem') ||
        name.endsWith('.key') ||
        name.endsWith('.p12') ||
        name.contains('secret') ||
        name.contains('credential')) {
      return false;
    }

    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot);
    return _sourceExtensions.contains(extension) ||
        _manifestFiles.contains(name);
  }

  static bool _isIgnoredDirectory(String path) => _ignoredDirectories.contains(
    path.split(Platform.pathSeparator).last.toLowerCase(),
  );

  static Future<String?> pickFolder() => FilePicker.getDirectoryPath(
    dialogTitle: 'Choose a project folder to analyze',
  );

  static Future<ScanResult> scan(
    String folder, {
    void Function(int scanned)? onProgress,
  }) async {
    final root = Directory(folder);
    if (!await root.exists()) {
      throw FileSystemException(
        'The selected project folder does not exist.',
        folder,
      );
    }

    final files = <ScannedFile>[];
    final candidates = <File>[];
    final directories = <Directory>[root];
    while (directories.isNotEmpty) {
      final directory = directories.removeLast();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Directory) {
          if (!_isIgnoredDirectory(entity.path)) directories.add(entity);
          continue;
        }
        if (entity is! File) continue;
        final relativePath = entity.path
            .substring(root.path.length)
            .replaceFirst(RegExp(r'^[\\/]'), '')
            .replaceAll('\\', '/');
        if (_isAllowed(relativePath)) candidates.add(entity);
      }
    }

    candidates.sort((a, b) {
      final aName = a.path.split(Platform.pathSeparator).last.toLowerCase();
      final bName = b.path.split(Platform.pathSeparator).last.toLowerCase();
      final aPriority = _manifestFiles.contains(aName)
          ? 0
          : aName.endsWith('.md')
          ? 2
          : 1;
      final bPriority = _manifestFiles.contains(bName)
          ? 0
          : bName.endsWith('.md')
          ? 2
          : 1;
      return aPriority.compareTo(bPriority);
    });

    var totalCharacters = 0;
    var scanned = 0;
    for (final entity in candidates.take(maxFiles)) {
      final relativePath = entity.path
          .substring(root.path.length)
          .replaceFirst(RegExp(r'^[\\/]'), '')
          .replaceAll('\\', '/');
      if (!_isAllowed(relativePath)) continue;
      if (files.length >= maxFiles) break;

      try {
        final size = await entity.length();
        if (size == 0 || size > maxFileCharacters * 8) continue;
        final content = _redactSecrets(await entity.readAsString());
        if (content.contains('\u0000')) continue;
        final remainingCharacters = maxTotalCharacters - totalCharacters;
        if (remainingCharacters <= 0) break;
        final bounded = content.length > maxFileCharacters
            ? content.substring(0, maxFileCharacters)
            : content;
        final limited = bounded.length > remainingCharacters
            ? bounded.substring(0, remainingCharacters)
            : bounded;
        files.add(
          ScannedFile(
            path: relativePath,
            content: limited,
            truncated: content.length > limited.length,
          ),
        );
        totalCharacters += limited.length;
        scanned++;
        onProgress?.call(scanned);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }

    if (files.isEmpty) {
      throw const FileSystemException(
        'No supported source files or dependency manifests were found.',
      );
    }
    return ScanResult(
      files: files,
      discoveredFiles: candidates.length,
      omittedFiles: candidates.length - files.length,
    );
  }
}
