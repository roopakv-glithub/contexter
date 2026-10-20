import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository_scanner.dart';

class ProjectAnalyzer {
  ProjectAnalyzer(this._client);

  final SupabaseClient _client;

  Future<FunctionResponse> _invoke(
    String function, {
    required Map<String, dynamic> body,
  }) async {
    try {
      return await _client.functions.invoke(function, body: body);
    } on FunctionException catch (error) {
      if (error.status == 404) {
        throw AiServiceException(
          'The Supabase "$function" function is not deployed (404). '
          'Deploy it from the project folder with: '
          'supabase functions deploy $function',
        );
      }
      if (error.status == 401 || error.status == 403) {
        throw AiServiceException(
          'Supabase rejected the "$function" request (${error.status}). '
          'Check the project URL and public key.',
        );
      }
      if (error.status == 0) {
        throw AiServiceException(
          'Could not reach the Supabase AI service. Check your internet '
          'connection and try again.',
        );
      }
      final details = error.details;
      final message = details is Map && details['error'] is String
          ? details['error'] as String
          : 'Supabase AI request failed (${error.status}).';
      throw AiServiceException(message);
    }
  }

  Future<String> enhancePrompt({
    required String prompt,
    required String projectName,
    required String context,
  }) async {
    final response = await _invoke(
      'enhance-prompt',
      body: {'prompt': prompt, 'projectName': projectName, 'context': context},
    );
    final data = response.data;
    if (data is Map && data['enhancedPrompt'] is String) {
      return (data['enhancedPrompt'] as String).trim();
    }
    throw const FormatException(
      'The prompt enhancement service returned an invalid response.',
    );
  }

  Future<Map<String, dynamic>> analyzeRepository(String repositoryUrl) async {
    final apiKey = await loadSavedNvidiaKey();
    final response = await _invoke(
      'analyze-project',
      body: {
        'repositoryUrl': repositoryUrl,
        if (apiKey != null && apiKey.isNotEmpty) 'nvidiaApiKey': apiKey,
      },
    );
    return _readReport(response.data);
  }

  Future<Map<String, dynamic>> analyzeFolder(
    String folder, {
    void Function(int scanned)? onProgress,
  }) async {
    final scan = await RepositoryScanner.scan(folder, onProgress: onProgress);
    final pathParts = folder
        .split(RegExp(r'[\\/]'))
        .where((part) => part.isNotEmpty)
        .toList();
    final projectName = pathParts.isEmpty ? 'Local project' : pathParts.last;
    final apiKey = await loadSavedNvidiaKey();

    try {
      final response = await _invoke(
        'analyze-project',
        body: {
          'projectName': projectName,
          'files': scan.files.map((file) => file.toJson()).toList(),
          'discoveredFiles': scan.discoveredFiles,
          'omittedFiles': scan.omittedFiles,
          'truncatedFiles': scan.files.where((file) => file.truncated).length,
          if (apiKey != null && apiKey.isNotEmpty) 'nvidiaApiKey': apiKey,
        },
      );
      return _readReport(response.data);
    } catch (_) {
      // Local fallback: synthesize structured report directly from scan evidence
      return _buildLocalReport(
        projectName: projectName,
        scan: scan,
      );
    }
  }

  Map<String, dynamic> _buildLocalReport({
    required String projectName,
    required ScanResult scan,
  }) {
    final technologies = <Map<String, String>>[];
    final dependencies = <Map<String, dynamic>>[];
    final filesList = <Map<String, dynamic>>[];

    final extCount = <String, int>{};
    for (final file in scan.files) {
      final dot = file.path.lastIndexOf('.');
      if (dot >= 0) {
        final ext = file.path.substring(dot).toLowerCase();
        extCount[ext] = (extCount[ext] ?? 0) + 1;
      }

      final lowerPath = file.path.toLowerCase();
      if (lowerPath.endsWith('pubspec.yaml')) {
        technologies.add({'name': 'Flutter / Dart', 'category': 'Framework', 'evidence': file.path});
      } else if (lowerPath.endsWith('package.json')) {
        technologies.add({'name': 'Node.js / TypeScript', 'category': 'Runtime', 'evidence': file.path});
      } else if (lowerPath.endsWith('requirements.txt') || lowerPath.endsWith('pyproject.toml')) {
        technologies.add({'name': 'Python', 'category': 'Language', 'evidence': file.path});
      } else if (lowerPath.endsWith('cargo.toml')) {
        technologies.add({'name': 'Rust', 'category': 'Language', 'evidence': file.path});
      } else if (lowerPath.endsWith('pom.xml') || lowerPath.endsWith('build.gradle')) {
        technologies.add({'name': 'Java / Kotlin', 'category': 'Language', 'evidence': file.path});
      } else if (lowerPath.endsWith('go.mod')) {
        technologies.add({'name': 'Go', 'category': 'Language', 'evidence': file.path});
      }

      final slash = file.path.replaceAll('\\', '/');
      final firstPart = slash.contains('/') ? slash.split('/').first : 'root';

      filesList.add({
        'path': slash,
        'module': firstPart,
        'purpose': 'Source file in $projectName',
        'functions': <Map<String, String>>[],
        'dependencies': <String>[],
      });
    }

    final topLangs = extCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final langSummary = topLangs.take(4).map((e) => '${e.key} (${e.value} files)').join(', ');

    return {
      'projectName': projectName,
      'overview': 'Local project scan of $projectName containing ${scan.files.length} indexed files. Primary file types: ${langSummary.isEmpty ? "general source" : langSummary}.',
      'architecture': 'Standard modular application structure with ${scan.files.length} source files across ${filesList.map((f) => f['module']).toSet().length} modules.',
      'technologies': technologies,
      'dependencies': dependencies,
      'recommendations': [
        'Local repository scan completed successfully.',
        'Use the NVIDIA model in Settings for deeper AI prompt synthesis.',
      ],
      'files': filesList,
      'statistics': {
        'discoveredFiles': scan.discoveredFiles,
        'analyzedFiles': scan.files.length,
        'omittedFiles': scan.omittedFiles,
        'truncatedFiles': scan.files.where((f) => f.truncated).length,
        'model': 'local-scanner',
      },
    };
  }

  static String? activeNvidiaKey;

  static Future<String?> loadSavedNvidiaKey() async {
    if (activeNvidiaKey != null && activeNvidiaKey!.isNotEmpty) {
      return activeNvidiaKey;
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/nvidia_key.txt');
      if (await file.exists()) {
        final key = (await file.readAsString()).trim();
        if (key.isNotEmpty) {
          activeNvidiaKey = key;
          return key;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveNvidiaKey(String key) async {
    activeNvidiaKey = key.trim();
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/nvidia_key.txt');
      await file.writeAsString(key.trim());
    } catch (_) {}
  }

  Future<void> testNvidiaKey(String key) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(
        Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
      );
      request.headers.set('Authorization', 'Bearer ${key.trim()}');
      request.headers.set('Content-Type', 'application/json');
      request.add(
        utf8.encode(
          jsonEncode({
            'model': 'nvidia/nemotron-3.5-lightning-30b-a3b',
            'messages': [
              {'role': 'user', 'content': 'ping'}
            ],
            'max_tokens': 8,
          }),
        ),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AiServiceException(
          'NVIDIA rejected this API key (unauthorized).',
        );
      }
      if (response.statusCode == 429) {
        throw const AiServiceException(
          'NVIDIA rate limit reached. Key is valid but currently rate limited.',
        );
      }
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['error'] != null) {
          throw AiServiceException('NVIDIA error: ${decoded['error']}');
        }
      } catch (_) {}
      throw AiServiceException(
        'NVIDIA connection test returned status ${response.statusCode}.',
      );
    } finally {
      client.close();
    }
  }

  /// Generates the final, comprehensive ContextForge coding prompt by combining
  /// the user's task description with repository evidence from local and/or GitHub analysis.
  Future<String> generateContextPrompt({
    required String projectName,
    required String projectDescription,
    required String agentName,
    required String taskDescription,
    Map<String, dynamic>? folderReport,
    Map<String, dynamic>? repositoryReport,
  }) async {
    // 1. Synthesize local vs remote differences and structure
    final localFiles = (folderReport?['files'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
    final remoteFiles = (repositoryReport?['files'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    final localPaths = localFiles.map((f) => f['path'] as String? ?? '').where((p) => p.isNotEmpty).toSet();
    final remotePaths = remoteFiles.map((f) => f['path'] as String? ?? '').where((p) => p.isNotEmpty).toSet();

    final commonPaths = localPaths.intersection(remotePaths);
    final localOnlyPaths = localPaths.difference(remotePaths);
    final remoteOnlyPaths = remotePaths.difference(localPaths);

    final localOverview = folderReport?['overview'] as String? ?? '';
    final remoteOverview = repositoryReport?['overview'] as String? ?? '';
    final localArchitecture = folderReport?['architecture'] as String? ?? '';
    final remoteArchitecture = repositoryReport?['architecture'] as String? ?? '';

    // Collect technologies & dependencies
    final technologies = <String>{};
    for (final report in [folderReport, repositoryReport]) {
      if (report == null) continue;
      final techs = report['technologies'] as List?;
      if (techs != null) {
        for (final t in techs) {
          if (t is Map && t['name'] != null) {
            technologies.add('${t['name']}${t['category'] != null ? ' (${t['category']})' : ''}');
          }
        }
      }
    }

    final dependencies = <String>{};
    for (final report in [folderReport, repositoryReport]) {
      if (report == null) continue;
      final deps = report['dependencies'] as List?;
      if (deps != null) {
        for (final d in deps) {
          if (d is Map && d['name'] != null) {
            dependencies.add('${d['name']} ${d['version'] ?? ''} - ${d['purpose'] ?? ''}'.trim());
          }
        }
      }
    }

    // Identify files relevant to the user's task
    final taskWords = taskDescription.toLowerCase().split(RegExp(r'\W+')).where((w) => w.length > 2).toSet();
    final allFiles = [...localFiles, ...remoteFiles];
    final relevantFiles = <String, String>{};

    for (final file in allFiles) {
      final path = file['path'] as String? ?? '';
      final purpose = file['purpose'] as String? ?? '';
      final module = file['module'] as String? ?? '';
      if (path.isEmpty) continue;

      bool matches = false;
      final pathLower = path.toLowerCase();
      final purposeLower = purpose.toLowerCase();
      final moduleLower = module.toLowerCase();

      for (final word in taskWords) {
        if (pathLower.contains(word) || purposeLower.contains(word) || moduleLower.contains(word)) {
          matches = true;
          break;
        }
      }

      if (matches || relevantFiles.length < 5) {
        relevantFiles[path] = purpose.isNotEmpty ? purpose : module;
      }
      if (relevantFiles.length >= 15) break;
    }

    // Build the structured Markdown context document
    final buffer = StringBuffer();
    buffer.writeln('# ContextForge Coding Agent Instruction');
    buffer.writeln();
    buffer.writeln('## A. Project Overview');
    buffer.writeln('**Project:** $projectName');
    if (projectDescription.isNotEmpty) {
      buffer.writeln('**Description:** $projectDescription');
    }
    if (agentName.isNotEmpty) {
      buffer.writeln('**Assigned Agent Role:** $agentName');
    }
    if (localOverview.isNotEmpty) {
      buffer.writeln('\n**Local Repository Summary:**\n$localOverview');
    }
    if (remoteOverview.isNotEmpty) {
      buffer.writeln('\n**Remote Repository Summary:**\n$remoteOverview');
    }
    if (localArchitecture.isNotEmpty || remoteArchitecture.isNotEmpty) {
      buffer.writeln('\n**Architecture:**');
      buffer.writeln(localArchitecture.isNotEmpty ? localArchitecture : remoteArchitecture);
    }

    buffer.writeln();
    buffer.writeln('## B. User Requested Change');
    buffer.writeln(taskDescription);

    buffer.writeln();
    buffer.writeln('## C. Repository Structure & Key Components');
    if (localFiles.isNotEmpty) {
      buffer.writeln('Local inventory contains ${localFiles.length} analyzed files.');
    }
    if (remoteFiles.isNotEmpty) {
      buffer.writeln('GitHub repository contains ${remoteFiles.length} analyzed files.');
    }
    if (technologies.isNotEmpty) {
      buffer.writeln('\n**Identified Technologies:**');
      for (final tech in technologies.take(12)) {
        buffer.writeln('- $tech');
      }
    }

    buffer.writeln();
    buffer.writeln('## D. Existing Implementation');
    buffer.writeln('Inspect the repository to understand current conventions and data contracts before modifying code.');
    buffer.writeln('Do not assume files or models that have not been verified.');

    buffer.writeln();
    buffer.writeln('## E. Files to Inspect or Modify');
    if (relevantFiles.isNotEmpty) {
      relevantFiles.forEach((p, purp) {
        buffer.writeln('- `$p` — $purp');
      });
    } else {
      for (final p in localPaths.take(8)) {
        buffer.writeln('- `$p`');
      }
    }

    buffer.writeln();
    buffer.writeln('## F. Local-versus-Remote Differences');
    if (folderReport != null && repositoryReport != null) {
      buffer.writeln('- Files present in both: ${commonPaths.length}');
      buffer.writeln('- Files present only locally: ${localOnlyPaths.length} ${localOnlyPaths.isNotEmpty ? '(${localOnlyPaths.take(5).join(', ')})' : ''}');
      buffer.writeln('- Files present only remotely: ${remoteOnlyPaths.length} ${remoteOnlyPaths.isNotEmpty ? '(${remoteOnlyPaths.take(5).join(', ')})' : ''}');
    } else if (folderReport != null) {
      buffer.writeln('Local repository analysis complete. No remote repository was specified for comparison.');
    } else if (repositoryReport != null) {
      buffer.writeln('Remote GitHub analysis complete. No local folder was specified for comparison.');
    }

    buffer.writeln();
    buffer.writeln('## G. Functions and Dependencies');
    if (dependencies.isNotEmpty) {
      for (final dep in dependencies.take(15)) {
        buffer.writeln('- $dep');
      }
    } else {
      buffer.writeln('Preserve existing dependencies and version constraints.');
    }

    buffer.writeln();
    buffer.writeln('## H. Environment & Configuration Requirements');
    buffer.writeln('- Preserve all environment configurations (`.env`, `.env.example`, build configs).');
    buffer.writeln('- Never overwrite secrets or hardcode sensitive credentials.');
    buffer.writeln('- If new environment variables are needed, update `.env.example` with placeholders.');

    buffer.writeln();
    buffer.writeln('## I. Conflict and Compatibility Risks');
    if (localOnlyPaths.isNotEmpty && remoteOnlyPaths.isNotEmpty) {
      buffer.writeln('Notice: Local tree and remote repository have diverging files. Verify non-overlapping changes before merging.');
    } else {
      buffer.writeln('No immediate file naming collisions detected.');
    }

    buffer.writeln();
    buffer.writeln('## J. Implementation Plan');
    buffer.writeln('1. Inspect the relevant files identified above.');
    buffer.writeln('2. Determine the minimal set of code changes needed to achieve the goal.');
    buffer.writeln('3. Implement the feature respecting existing naming patterns, state management, and conventions.');
    buffer.writeln('4. Verify with tests or build commands.');

    buffer.writeln();
    buffer.writeln('## K. Testing and Validation Instructions');
    buffer.writeln('Run the project\'s existing test suite or static analysis checks after implementing the change.');

    buffer.writeln();
    buffer.writeln('## L. Preservation Requirements');
    buffer.writeln('- Do NOT modify or delete unrelated features.');
    buffer.writeln('- Do NOT overwrite uncommitted local work.');
    buffer.writeln('- Preserve existing UI aesthetics, typography, and layout.');

    buffer.writeln();
    buffer.writeln('## M. Completion Criteria');
    buffer.writeln('- The requested functionality: "$taskDescription" is fully working.');
    buffer.writeln('- Existing features continue to operate without regression.');
    buffer.writeln('- The project compiles and runs cleanly.');

    final synthesizedContext = buffer.toString();

    // 2. If NVIDIA key is available or Supabase function is accessible, enhance with AI reasoning
    final key = activeNvidiaKey ?? await loadSavedNvidiaKey();
    if (key != null && key.isNotEmpty) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 25);
        final request = await client.postUrl(
          Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
        );
        request.headers.set('Authorization', 'Bearer $key');
        request.headers.set('Content-Type', 'application/json');
        request.add(
          utf8.encode(
            jsonEncode({
              'model': 'nvidia/nemotron-3.5-lightning-30b-a3b',
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'You are ContextForge, an expert software architecture and prompt engineering assistant. '
                      'Reason over the provided repository context and the user\'s requested task. '
                      'Synthesize a comprehensive, production-ready, context-aware coding prompt in Markdown. '
                      'Follow all sections (A through M) clearly. Do not invent missing files or dependencies. '
                      'Keep technical guidance exact, actionable, and strictly preserving existing architecture.',
                },
                {
                  'role': 'user',
                  'content':
                      'Project: $projectName\n'
                      'Task: $taskDescription\n\n'
                      'Context Document:\n$synthesizedContext',
                },
              ],
              'temperature': 0.25,
              'max_tokens': 8192,
              'extra_body': {
                'chat_template_kwargs': {'enable_thinking': true},
                'reasoning_budget': 4096,
              },
            }),
          ),
        );
        final response = await request.close();
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final parsed = jsonDecode(body);
          final content = parsed?['choices']?[0]?['message']?['content'];
          if (content is String && content.trim().isNotEmpty) {
            return content.trim();
          }
        }
      } catch (_) {
        // Fall back to synthesized Markdown context
      }
    }

    // Try Supabase edge function if available
    try {
      final response = await _invoke(
        'enhance-prompt',
        body: {
          'prompt': taskDescription,
          'projectName': projectName,
          'context': synthesizedContext,
        },
      );
      final data = response.data;
      if (data is Map && data['enhancedPrompt'] is String) {
        return (data['enhancedPrompt'] as String).trim();
      }
    } catch (_) {
      // Fall back to synthesized Markdown context
    }

    return synthesizedContext;
  }

  Map<String, dynamic> _readReport(dynamic data) {
    if (data is Map) {
      final report = data['report'];
      if (report is Map) return Map<String, dynamic>.from(report);
      return Map<String, dynamic>.from(data);
    }
    throw const FormatException(
      'The analysis service returned an invalid report.',
    );
  }
}

class AiServiceException implements Exception {
  const AiServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

