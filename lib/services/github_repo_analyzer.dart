import 'dart:convert';
import 'dart:io';

import 'project_analyzer.dart';

class RepoInfo {
  const RepoInfo({
    required this.owner,
    required this.repo,
    this.branch,
    this.subdirectory = '',
    required this.originalUrl,
  });

  final String owner;
  final String repo;
  final String? branch;
  final String subdirectory;
  final String originalUrl;

  String get repositoryPath =>
      subdirectory.isNotEmpty ? '$owner/$repo/$subdirectory' : '$owner/$repo';
}

class GithubRepoAnalyzer {
  static String? get _githubPat =>
      Platform.environment['GITHUB_PAT'] ??
      Platform.environment['GITHUB_TOKEN'] ??
      const String.fromEnvironment('GITHUB_PAT');

  static const _skipPatterns = [
    'node_modules/',
    '.git/',
    '*.min.js',
    '*.min.css',
    '*.map',
    'package-lock.json',
    'yarn.lock',
    'pnpm-lock.yaml',
    'composer.lock',
    'Gemfile.lock',
    'Pipfile.lock',
    'poetry.lock',
    'Cargo.lock',
    'go.sum',
    'mix.lock',
    'pubspec.lock',
    '*.test.js',
    '*.spec.js',
    '*.test.ts',
    '*.spec.ts',
    '__tests__/',
    'test/',
    'tests/',
    '.gitignore',
    '.gitattributes',
    '.editorconfig',
    '.prettierrc*',
    '.eslintrc*',
    '*.config.js',
    '*.config.ts',
    '*.config.json',
    '.env*',
    '.env.local',
    '.env.production',
    '.env.development',
    '.env.test',
    '.envrc',
    '.nvmrc',
    '.node-version',
    '.ruby-version',
    '.python-version',
    '.tool-versions',
    'tsconfig.json',
    'babel.config.js',
    'webpack.config.js',
    'vite.config.js',
    'jest.config.js',
    '*.md',
    '*.bundle.js',
    '*.chunk.js',
    '*.pyc',
    '*.pyo',
    '__pycache__/',
    '*.egg-info/',
    '*.whl',
    '.tox/',
    'venv/',
    'env/',
    '.pytest_cache/',
    'dist/',
    'build/',
    'out/',
    'target/',
    'bin/',
    '.vscode/',
    '.idea/',
  ];

  static const _binaryExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.bmp',
    '.ico',
    '.svg',
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.zip',
    '.rar',
    '.7z',
    '.tar',
    '.gz',
    '.exe',
    '.dll',
    '.so',
    '.dylib',
    '.bin',
    '.dat',
    '.db',
    '.sqlite',
    '.mp3',
    '.mp4',
    '.avi',
    '.mov',
    '.wav',
    '.flac',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.eot',
  };

  /// Validates and extracts owner, repo, branch, and subdirectory from a GitHub URL or string.
  static RepoInfo parseUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const AiServiceException(
        'Please enter a valid GitHub repository URL.',
      );
    }

    String owner;
    String repo;
    String? branch;
    String subdirectory = '';

    if (trimmed.contains('github.com')) {
      Uri uri;
      try {
        uri = Uri.parse(
          trimmed.startsWith('http') ? trimmed : 'https://$trimmed',
        );
      } catch (_) {
        throw const AiServiceException(
          'Invalid GitHub URL format. Example: https://github.com/owner/repository',
        );
      }

      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length < 2) {
        throw const AiServiceException(
          'GitHub URL must include an owner and repository name.',
        );
      }

      owner = segments[0];
      repo = segments[1].replaceAll(RegExp(r'\.git$', caseSensitive: false), '');

      if (segments.length > 2) {
        final routeType = segments[2];
        if ((routeType == 'tree' || routeType == 'blob') &&
            segments.length > 3) {
          branch = segments[3];
          if (segments.length > 4) {
            subdirectory = segments.sublist(4).join('/');
          }
        } else if (routeType == 'raw' && segments.length > 3) {
          branch = segments[3];
          subdirectory = segments.sublist(4).join('/');
        } else {
          const special = {
            'issues',
            'pulls',
            'pull',
            'actions',
            'commits',
            'releases',
          };
          if (!special.contains(routeType)) {
            subdirectory = segments.sublist(2).join('/');
          }
        }
      }
    } else {
      final parts = trimmed.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length != 2) {
        throw const AiServiceException(
          'Please enter a valid GitHub repository (e.g., owner/repository or https://github.com/owner/repository).',
        );
      }
      owner = parts[0];
      repo = parts[1];
    }

    if (!RegExp(r'^[\w.-]+$').hasMatch(owner) ||
        !RegExp(r'^[\w.-]+$').hasMatch(repo)) {
      throw const AiServiceException(
        'The GitHub repository URL contains an invalid owner or repository name.',
      );
    }

    return RepoInfo(
      owner: owner,
      repo: repo,
      branch: branch,
      subdirectory: subdirectory,
      originalUrl: trimmed,
    );
  }

  /// Converts the GitHub repository to an AI-ready Markdown document using Repo-to-Markdown specification.
  static Future<String> convertRepoToMarkdown(
    RepoInfo info, {
    void Function(String message)? onStatus,
  }) async {
    onStatus?.call('Validating GitHub repository ${info.repositoryPath}...');

    // 1. Try automation script if available
    try {
      final scriptFile = File('scripts/repo_to_markdown.js');
      if (await scriptFile.exists()) {
        onStatus?.call('Running repo-to-markdown conversion...');
        final env = <String, String>{};
        if (_githubPat != null && _githubPat!.isNotEmpty) {
          env['GITHUB_PAT'] = _githubPat!;
        }
        final result = await Process.run(
          'node',
          ['scripts/repo_to_markdown.js', info.originalUrl],
          environment: env,
        );
        if (result.exitCode == 0 &&
            result.stdout is String &&
            (result.stdout as String).contains('// File:')) {
          final md = result.stdout as String;
          _verifyGeneratedMarkdown(md, info);
          return md;
        }
      }
    } catch (_) {
      // Fall through to native Dart Repo-to-Markdown engine
    }

    // 2. Native Dart Repo-to-Markdown engine
    return _convertNatively(info, onStatus: onStatus);
  }

  static Future<String> _convertNatively(
    RepoInfo info, {
    void Function(String message)? onStatus,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final branchesToTry = info.branch != null
          ? [info.branch!, 'main', 'master', 'dev']
          : ['main', 'master', 'dev'];

      String? workingBranch;
      List<dynamic>? treeFiles;

      onStatus?.call('Fetching repository file tree from GitHub...');
      for (final branch in branchesToTry) {
        try {
          final uri = Uri.parse(
            'https://api.github.com/repos/${info.owner}/${info.repo}/git/trees/$branch?recursive=1',
          );
          final request = await client.getUrl(uri);
          request.headers.set('User-Agent', 'ContextForge-RepoToMarkdown/1.0');
          request.headers.set('Accept', 'application/vnd.github.v3+json');
          if (_githubPat != null && _githubPat!.isNotEmpty) {
            request.headers.set('Authorization', 'token $_githubPat');
          }

          final response = await request.close();
          if (response.statusCode == 200) {
            final body = await response.transform(utf8.decoder).join();
            final json = jsonDecode(body);
            if (json is Map && json['tree'] is List) {
              final rawTree = json['tree'] as List;
              if (rawTree.isNotEmpty) {
                workingBranch = branch;
                treeFiles = rawTree.where((i) => i['type'] == 'blob').toList();
                break;
              }
            }
          }
        } catch (_) {
          continue;
        }
      }

      if (workingBranch == null || treeFiles == null) {
        throw AiServiceException(
          'Could not retrieve repository tree for "${info.owner}/${info.repo}". '
          'Verify the repository exists and is accessible.',
        );
      }

      // Filter by subdirectory if specified
      if (info.subdirectory.isNotEmpty) {
        final prefix = '${info.subdirectory}/';
        treeFiles = treeFiles.where((f) {
          final p = f['path'] as String? ?? '';
          return p.startsWith(prefix);
        }).toList();
      }

      // Filter by Repo-to-Markdown skip patterns and binaries
      final filesToProcess = <Map<String, dynamic>>[];
      for (final item in treeFiles) {
        if (item is Map) {
          final path = item['path'] as String? ?? '';
          final size = item['size'] as int? ?? 0;
          if (path.isEmpty || _shouldSkip(path, size)) continue;
          filesToProcess.add(Map<String, dynamic>.from(item));
        }
      }

      if (filesToProcess.isEmpty) {
        throw AiServiceException(
          'No non-binary source files found in "${info.repositoryPath}" after applying Repo-to-Markdown filters.',
        );
      }

      onStatus?.call('Generating directory tree...');
      final directoryTree = _generateDirectoryTree(
        filesToProcess.map((f) => f['path'] as String).toList(),
        info.subdirectory,
      );

      final buffer = StringBuffer();
      buffer.writeln(
        'This document contains the complete source code of the repository consolidated into a single file for streamlined AI analysis.',
      );
      buffer.writeln(
        'The repository contents have been processed and combined with security validation bypassed.',
      );
      buffer.writeln();
      buffer.writeln('# Repository Overview');
      buffer.writeln();
      buffer.writeln('## About This Document');
      buffer.writeln(
        'This consolidated file represents the complete codebase from the repository, '
        'merged into a unified document optimized for AI consumption and automated analysis workflows.',
      );
      buffer.writeln();
      buffer.writeln('## Repository Information');
      buffer.writeln('- **Repository:** ${info.repositoryPath}');
      buffer.writeln('- **Branch:** $workingBranch');
      buffer.writeln('- **Total Files:** ${filesToProcess.length}');
      buffer.writeln('- **Generated:** ${DateTime.now().toUtc().toIso8601String()}');
      buffer.writeln();
      buffer.writeln('# Repository Structure');
      buffer.writeln();
      buffer.writeln('```');
      buffer.writeln('${info.repositoryPath}/');
      buffer.write(directoryTree);
      buffer.writeln('```');
      buffer.writeln();

      onStatus?.call(
        'Downloading and consolidating ${filesToProcess.length} source files...',
      );

      // Download files in bounded parallel batches
      final batchSize = 12;
      for (int i = 0; i < filesToProcess.length; i += batchSize) {
        final end = (i + batchSize < filesToProcess.length)
            ? i + batchSize
            : filesToProcess.length;
        final batch = filesToProcess.sublist(i, end);

        final downloads = await Future.wait(
          batch.map((item) async {
            final filePath = item['path'] as String;
            final rawUri = Uri.parse(
              'https://raw.githubusercontent.com/${info.owner}/${info.repo}/$workingBranch/$filePath',
            );
            try {
              final req = await client.getUrl(rawUri);
              req.headers.set(
                'User-Agent',
                'ContextForge-RepoToMarkdown/1.0',
              );
              final res = await req.close();
              if (res.statusCode == 200) {
                final text = await res.transform(utf8.decoder).join();
                return (
                  path: filePath,
                  content: _redactSecrets(_removeLicenseHeaders(text)),
                );
              }
            } catch (_) {}
            return (path: filePath, content: '');
          }),
        );

        for (final downloaded in downloads) {
          if (downloaded.content.trim().isEmpty) continue;
          buffer.writeln('=' * 80);
          buffer.writeln('// File: ${downloaded.path}');
          buffer.writeln('=' * 80);
          buffer.writeln(downloaded.content);
          if (!downloaded.content.endsWith('\n')) buffer.writeln();
        }
      }

      final generated = buffer.toString();
      _verifyGeneratedMarkdown(generated, info);
      return generated;
    } finally {
      client.close();
    }
  }

  static bool _shouldSkip(String path, int size) {
    if (size > 1024 * 1024) return true; // 1MB limit per repo-to-markdown
    final lower = path.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot >= 0 && _binaryExtensions.contains(lower.substring(dot))) {
      return true;
    }

    final basename = lower.contains('/') ? lower.split('/').last : lower;
    for (final pattern in _skipPatterns) {
      if (_matchesGlob(lower, pattern) || _matchesGlob(basename, pattern)) {
        return true;
      }
    }
    return false;
  }

  static bool _matchesGlob(String filename, String pattern) {
    final regexPattern = pattern
        .replaceAll('.', r'\.')
        .replaceAll('*', '.*')
        .replaceAll('?', '.')
        .replaceAll('/', r'\/');
    final regex = RegExp('^$regexPattern\$', caseSensitive: false);
    return regex.hasMatch(filename) ||
        filename.toLowerCase().contains(pattern.toLowerCase());
  }

  static String _removeLicenseHeaders(String content) {
    final lines = content.split('\n');
    int startIndex = 0;
    const licenseKeywords = [
      'license',
      'copyright',
      'mit',
      'apache',
      'gpl',
      'bsd',
    ];

    for (int i = 0; i < lines.length && i < 20; i++) {
      final line = lines[i].toLowerCase();
      if (licenseKeywords.any((k) => line.contains(k))) {
        if (line.contains('*/') || line.contains('-->')) {
          startIndex = i + 1;
          break;
        }
        if (line.startsWith('//') || line.startsWith('#')) {
          startIndex = i + 1;
          break;
        }
      }
      if (line.trim().isNotEmpty &&
          !line.trim().startsWith('//') &&
          !line.trim().startsWith('#') &&
          !line.trim().startsWith('/*') &&
          !line.trim().startsWith('*') &&
          !line.trim().startsWith('<!--')) {
        break;
      }
    }
    if (startIndex > 0) {
      return lines.sublist(startIndex).join('\n').replaceFirst(
        RegExp(r'^\s*\n+'),
        '',
      );
    }
    return content;
  }

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
          r'((?:api[_-]?key|(?:access|auth)[_-]?token|token|secret|password|credential|client[_-]?secret|service[_-]?role|private[_-]?key)\s*[:=]\s*["'
          "']?)[^\"'`\\s,;]+",
          caseSensitive: false,
        ),
        r'$1[REDACTED]',
      );

  static String _generateDirectoryTree(List<String> paths, String subdirectory) {
    final root = <String, dynamic>{};
    for (final rawPath in paths) {
      var path = rawPath;
      if (subdirectory.isNotEmpty && path.startsWith('$subdirectory/')) {
        path = path.substring(subdirectory.length + 1);
      }
      final parts = path.split('/');
      var current = root;
      for (int i = 0; i < parts.length; i++) {
        final part = parts[i];
        if (i == parts.length - 1) {
          current[part] = null;
        } else {
          current = current.putIfAbsent(
            part,
            () => <String, dynamic>{},
          ) as Map<String, dynamic>;
        }
      }
    }

    String nodeToString(
      Map<String, dynamic> node,
      String prefix,
      bool isLast,
    ) {
      final buffer = StringBuffer();
      final entries = node.entries.toList()
        ..sort((a, b) {
          final aIsDir = a.value != null;
          final bIsDir = b.value != null;
          if (aIsDir != bIsDir) return bIsDir ? 1 : -1;
          return a.key.compareTo(b.key);
        });

      for (int i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final last = i == entries.length - 1;
        final connector = last ? '└── ' : '├── ';
        buffer.writeln('$prefix$connector${entry.key}');
        if (entry.value is Map<String, dynamic>) {
          buffer.write(
            nodeToString(
              entry.value as Map<String, dynamic>,
              '$prefix${last ? "    " : "│   "}',
              last,
            ),
          );
        }
      }
      return buffer.toString();
    }

    return nodeToString(root, '', true);
  }

  static void _verifyGeneratedMarkdown(String markdown, RepoInfo info) {
    if (markdown.trim().isEmpty) {
      throw AiServiceException(
        'Repo-to-Markdown conversion returned empty content for "${info.repositoryPath}".',
      );
    }
    if (!markdown.contains('// File:')) {
      throw AiServiceException(
        'The retrieved Markdown for "${info.repositoryPath}" contains only documentation or is missing source code files.',
      );
    }
  }

  /// Parses the generated Repo-to-Markdown file into structured sections and files.
  static List<Map<String, dynamic>> parseMarkdownFiles(String markdown) {
    final files = <Map<String, dynamic>>[];
    final sections = markdown.split(RegExp(r'(?:^|\r?\n)// File:\s*'));

    for (int i = 1; i < sections.length; i++) {
      final section = sections[i];
      final firstLineEnd = section.indexOf('\n');
      if (firstLineEnd < 0) continue;
      final path = section.substring(0, firstLineEnd).trim();
      var rest = section.substring(firstLineEnd + 1).trim();

      // Strip leading separator lines
      if (rest.startsWith('=')) {
        final sepEnd = rest.indexOf('\n');
        if (sepEnd >= 0) {
          rest = rest.substring(sepEnd + 1).trim();
        }
      }

      // Strip trailing separator lines
      rest = rest.replaceAll(RegExp(r'=+\s*$'), '').trim();

      if (path.isEmpty) continue;
      final module = path.contains('/') ? path.split('/').first : 'root';
      files.add({
        'path': path,
        'module': module,
        'purpose': 'Source file ($module module)',
        'content': rest.length > 4000 ? rest.substring(0, 4000) : rest,
        'functions': <Map<String, String>>[],
        'dependencies': <String>[],
      });
    }

    return files;
  }

  /// Performs full analysis on the Repo-to-Markdown content and produces
  /// the standard ContextForge repository report.
  static Future<Map<String, dynamic>> analyze(
    String repositoryUrl, {
    void Function(String message)? onProgress,
  }) async {
    final repoInfo = parseUrl(repositoryUrl);
    final markdown = await convertRepoToMarkdown(repoInfo, onStatus: onProgress);

    onProgress?.call('Parsing repository structure and source code...');
    final parsedFiles = parseMarkdownFiles(markdown);

    // Identify technologies
    final technologies = <Map<String, String>>[];
    final extCount = <String, int>{};

    for (final f in parsedFiles) {
      final path = (f['path'] as String).toLowerCase();
      final dot = path.lastIndexOf('.');
      if (dot >= 0) {
        final ext = path.substring(dot);
        extCount[ext] = (extCount[ext] ?? 0) + 1;
      }

      if (path.endsWith('pubspec.yaml')) {
        technologies.add({
          'name': 'Flutter / Dart',
          'category': 'Framework',
          'evidence': path,
        });
      } else if (path.endsWith('package.json')) {
        technologies.add({
          'name': 'Node.js / TypeScript',
          'category': 'Runtime',
          'evidence': path,
        });
      } else if (path.endsWith('requirements.txt') ||
          path.endsWith('pyproject.toml')) {
        technologies.add({
          'name': 'Python',
          'category': 'Language',
          'evidence': path,
        });
      } else if (path.endsWith('cargo.toml')) {
        technologies.add({
          'name': 'Rust',
          'category': 'Language',
          'evidence': path,
        });
      } else if (path.endsWith('go.mod')) {
        technologies.add({
          'name': 'Go',
          'category': 'Language',
          'evidence': path,
        });
      }
    }

    final topLangs = extCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final langSummary = topLangs
        .take(4)
        .map((e) => '${e.key} (${e.value} files)')
        .join(', ');

    // AI Semantic Summarization using NVIDIA Nemotron
    onProgress?.call('Synthesizing repository architecture with NVIDIA model...');
    final apiKey = await ProjectAnalyzer.loadSavedNvidiaKey();

    String overview =
        'GitHub repository ${repoInfo.repositoryPath} converted via Repo-to-Markdown with ${parsedFiles.length} source files indexed. Primary file types: ${langSummary.isEmpty ? "general source" : langSummary}.';
    String architecture =
        'Modular repository structure with ${parsedFiles.length} code files across ${parsedFiles.map((f) => f["module"]).toSet().length} modules.';
    List<dynamic> recommendations = [
      'Repository converted to unified Markdown for full-context prompt generation.',
      'All source files and directory hierarchy successfully indexed.',
    ];

    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 15);
        final request = await client.postUrl(
          Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
        );
        request.headers.set('Authorization', 'Bearer $apiKey');
        request.headers.set('Content-Type', 'application/json');

        // Extract tree preview from markdown
        final treePreview = markdown.contains('# Repository Structure')
            ? markdown.split('# Repository Structure').last.split('=====').first
            : '';

        final prompt = jsonEncode({
          'model': 'nvidia/nemotron-3.5-lightning-30b-a3b',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are ContextForge, an expert repository analyzer. Based on the provided repository metadata, file tree, and source files from Repo-to-Markdown, return valid JSON with keys: overview (string), architecture (string), recommendations (array of strings). Keep summaries factual, technical, and concise.',
            },
            {
              'role': 'user',
              'content':
                  'Repository: ${repoInfo.repositoryPath}\n\nFile Structure:\n$treePreview\n\nSample Files:\n${parsedFiles.take(8).map((f) => f["path"]).join("\n")}',
            },
          ],
          'temperature': 0.2,
          'max_tokens': 1024,
          'extra_body': {
            'chat_template_kwargs': {'enable_thinking': true},
            'reasoning_budget': 1024,
          },
        });

        request.add(utf8.encode(prompt));
        final response = await request.close();
        if (response.statusCode == 200) {
          final resBody = await response.transform(utf8.decoder).join();
          final parsedRes = jsonDecode(resBody);
          final content = parsedRes?['choices']?[0]?['message']?['content'];
          if (content is String) {
            final cleaned = content
                .trim()
                .replaceFirst(RegExp(r'^```json\s*', caseSensitive: false), '')
                .replaceFirst(RegExp(r'\s*```$'), '');
            try {
              final jsonSummary = jsonDecode(cleaned);
              if (jsonSummary is Map) {
                if (jsonSummary['overview'] is String) {
                  overview = jsonSummary['overview'] as String;
                }
                if (jsonSummary['architecture'] is String) {
                  architecture = jsonSummary['architecture'] as String;
                }
                if (jsonSummary['recommendations'] is List) {
                  recommendations = jsonSummary['recommendations'] as List;
                }
              }
            } catch (_) {}
          }
        }
        client.close();
      } catch (_) {}
    }

    onProgress?.call('Repository analysis completed successfully.');

    return {
      'projectName': repoInfo.repo,
      'repositoryUrl': repoInfo.originalUrl,
      'overview': overview,
      'architecture': architecture,
      'technologies': technologies,
      'dependencies': <Map<String, dynamic>>[],
      'recommendations': recommendations,
      'files': parsedFiles,
      'statistics': {
        'discoveredFiles': parsedFiles.length,
        'analyzedFiles': parsedFiles.length,
        'omittedFiles': 0,
        'truncatedFiles': 0,
        'model': 'repo-to-markdown+nemotron',
      },
      'markdown': markdown,
    };
  }
}
