import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'github_repo_analyzer.dart';
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

  Future<Map<String, dynamic>> analyzeRepository(
    String repositoryUrl, {
    void Function(String message)? onProgress,
  }) async {
    return GithubRepoAnalyzer.analyze(repositoryUrl, onProgress: onProgress);
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

  /// Generates the structured Next-Step Development (NNSD) coding prompt
  /// in three clearly separated sections:
  /// - SECTION A — NNSD IMPLEMENTATION PROMPT (First, actionable prompt with 10 subsections)
  /// - SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT (Second, reference context)
  /// - SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT (Third, reference context)
  Future<String> generateContextPrompt({
    required String projectName,
    required String projectDescription,
    required String agentName,
    required String taskDescription,
    Map<String, dynamic>? folderReport,
    Map<String, dynamic>? repositoryReport,
  }) async {
    final cleanTask = RepositoryScanner.redactSecrets(taskDescription).trim();
    final cleanProject = RepositoryScanner.redactSecrets(projectName).trim();

    // 1. Gather files, technologies, and dependencies from reports
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

    final technologies = <String>{};
    for (final report in [folderReport, repositoryReport]) {
      if (report == null) continue;
      final techs = report['technologies'] as List?;
      if (techs != null) {
        for (final t in techs) {
          if (t is Map && t['name'] != null) {
            technologies.add(
              '${t['name']}${t['category'] != null ? ' (${t['category']})' : ''}',
            );
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
            dependencies.add(
              '${d['name']} ${d['version'] ?? ''} - ${d['purpose'] ?? ''}'
                  .trim(),
            );
          }
        }
      }
    }

    // Match task words to find grounded relevant files
    final taskWords = cleanTask
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 2)
        .toSet();
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
        if (pathLower.contains(word) ||
            purposeLower.contains(word) ||
            moduleLower.contains(word)) {
          matches = true;
          break;
        }
      }

      if (matches) {
        relevantFiles[path] = purpose.isNotEmpty ? purpose : module;
      }
      if (relevantFiles.length >= 10) break;
    }

    // If no direct keyword matches, take key files as candidates
    if (relevantFiles.isEmpty) {
      for (final file in allFiles.take(5)) {
        final path = file['path'] as String? ?? '';
        final purpose = file['purpose'] as String? ?? '';
        final module = file['module'] as String? ?? '';
        if (path.isNotEmpty) {
          relevantFiles[path] = purpose.isNotEmpty ? purpose : module;
        }
      }
    }

    // 2. Build Section B (Local Project Analysis Summary — Reference Context)
    final sectionB = _buildLocalSummarySection(cleanProject, folderReport);

    // 3. Build Section C (GitHub Repository Analysis Summary — Reference Context)
    final sectionC = _buildRemoteSummarySection(repositoryReport);

    // 4. Generate Section A (NNSD Implementation Prompt)
    String sectionA = '';

    // Check if NVIDIA API key is available
    final key = activeNvidiaKey ?? await loadSavedNvidiaKey();
    if (key != null && key.isNotEmpty) {
      try {
        final aiSectionA = await _generateAiSectionA(
          apiKey: key,
          projectName: cleanProject,
          projectDescription: projectDescription,
          taskDescription: cleanTask,
          agentName: agentName,
          folderReport: folderReport,
          repositoryReport: repositoryReport,
          technologies: technologies,
          dependencies: dependencies,
          relevantFiles: relevantFiles,
        );
        if (_isValidSectionA(aiSectionA, cleanTask)) {
          sectionA = aiSectionA;
        }
      } catch (_) {
        // Fall back to deterministic Section A builder
      }
    }

    if (sectionA.isEmpty) {
      sectionA = _buildDeterministicSectionA(
        projectName: cleanProject,
        taskDescription: cleanTask,
        relevantFiles: relevantFiles,
        technologies: technologies,
        dependencies: dependencies,
        folderReport: folderReport,
        repositoryReport: repositoryReport,
      );
    }

    // 5. Assemble and validate 3-section output
    return _assembleFinalResult(
      sectionA: sectionA,
      sectionB: sectionB,
      sectionC: sectionC,
    );
  }

  Future<String> _generateAiSectionA({
    required String apiKey,
    required String projectName,
    required String projectDescription,
    required String taskDescription,
    required String agentName,
    required Map<String, dynamic>? folderReport,
    required Map<String, dynamic>? repositoryReport,
    required Set<String> technologies,
    required Set<String> dependencies,
    required Map<String, String> relevantFiles,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 35);
    try {
      final request = await client.postUrl(
        Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'),
      );
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Content-Type', 'application/json');

      final filesSnippet = relevantFiles.isNotEmpty
          ? relevantFiles.entries
              .map((e) => '- `${e.key}` — ${e.value}')
              .join('\n')
          : 'Files to identify during repository inspection.';

      final promptPayload = {
        'model': 'nvidia/nemotron-3.5-lightning-30b-a3b',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are ContextForge, an expert software architecture and Next-Step Development (NNSD) prompt engineer.\n'
                'Your task is to generate ONLY "SECTION A — NNSD IMPLEMENTATION PROMPT" for another coding AI to implement the user\'s requested task.\n\n'
                'CRITICAL RULES:\n'
                '1. The user\'s original coding request defines WHAT must be implemented. Focus 100% on this task. Do NOT invent unrelated features.\n'
                '2. Ground file paths in the provided repository context. Do not invent non-existent files.\n'
                '3. Output ONLY Section A with the exact structure and all 10 numbered subsections below.\n'
                '4. Never output secrets or placeholder keys.\n'
                '5. Do NOT include Section B or Section C in your response; they are added separately.\n\n'
                'REQUIRED FORMAT:\n'
                '# NNSD — [Short Feature Name]\n\n'
                '## 1. Objective\n'
                '[Exact description of what the user wants implemented.]\n\n'
                '## 2. Existing Functionality\n'
                '[Existing behavior relevant to the requested feature. Explain what already works and must be preserved.]\n\n'
                '## 3. Required Changes\n'
                '[Numbered, implementable requirements detailing exact functionality to add or modify.]\n\n'
                '## 4. Relevant Files to Inspect or Modify\n'
                '[Known relevant files, responsibilities, and expected changes. Use actual paths when available.]\n\n'
                '## 5. Dependencies and Technologies\n'
                '[Existing libraries, frameworks, and APIs. Reuse existing dependencies wherever possible.]\n\n'
                '## 6. Implementation Instructions\n'
                '[Clear, ordered implementation plan integrating with existing architecture, validation, and error handling.]\n\n'
                '## 7. Environment and Configuration Constraints\n'
                '[Specify preserved configurations. Never expose secrets or tokens.]\n\n'
                '## 8. Compatibility and Preservation Requirements\n'
                '[Explicitly list existing features and behavior that must not change. Prevent unrelated refactoring.]\n\n'
                '## 9. Acceptance Criteria\n'
                '[Measurable conditions that must be satisfied for completion.]\n\n'
                '## 10. Verification\n'
                '[Specify relevant tests, checks, and expected results.]\n',
          },
          {
            'role': 'user',
            'content':
                'Project: $projectName\n'
                'User Task:\n$taskDescription\n\n'
                'Repository Context:\n'
                '- Technologies: ${technologies.join(', ')}\n'
                '- Dependencies: ${dependencies.take(10).join(', ')}\n'
                '- Relevant Files:\n$filesSnippet\n'
                '- Local Overview: ${folderReport?['overview'] ?? 'N/A'}\n'
                '- Remote Overview: ${repositoryReport?['overview'] ?? 'N/A'}\n',
          },
        ],
        'temperature': 0.2,
        'max_tokens': 4096,
        'extra_body': {
          'chat_template_kwargs': {'enable_thinking': true},
          'reasoning_budget': 2048,
        },
      };

      request.add(utf8.encode(jsonEncode(promptPayload)));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final parsed = jsonDecode(body);
        final content = parsed?['choices']?[0]?['message']?['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    } finally {
      client.close();
    }
    return '';
  }

  bool _isValidSectionA(String sectionA, String taskDescription) {
    if (sectionA.length < 150) return false;
    const requiredSubsections = [
      '## 1. Objective',
      '## 2. Existing Functionality',
      '## 3. Required Changes',
      '## 4. Relevant Files to Inspect or Modify',
      '## 5. Dependencies and Technologies',
      '## 6. Implementation Instructions',
      '## 7. Environment and Configuration Constraints',
      '## 8. Compatibility and Preservation Requirements',
      '## 9. Acceptance Criteria',
      '## 10. Verification',
    ];
    for (final sub in requiredSubsections) {
      if (!sectionA.contains(sub)) return false;
    }
    return true;
  }

  String _buildDeterministicSectionA({
    required String projectName,
    required String taskDescription,
    required Map<String, String> relevantFiles,
    required Set<String> technologies,
    required Set<String> dependencies,
    Map<String, dynamic>? folderReport,
    Map<String, dynamic>? repositoryReport,
  }) {
    // Generate short feature title from taskDescription
    final firstSentence = taskDescription.split(RegExp(r'[\.\n]')).first.trim();
    final featureTitle = firstSentence.length > 60
        ? '${firstSentence.substring(0, 57)}...'
        : firstSentence;

    final buffer = StringBuffer();
    buffer.writeln('# NNSD — $featureTitle');
    buffer.writeln();

    buffer.writeln('## 1. Objective');
    buffer.writeln('Implement the following requested enhancement for $projectName:');
    buffer.writeln(taskDescription);
    buffer.writeln();

    buffer.writeln('## 2. Existing Functionality');
    final overview = folderReport?['overview'] as String? ??
        repositoryReport?['overview'] as String? ??
        'Existing project codebase with standard architecture.';
    buffer.writeln(overview);
    buffer.writeln('Inspect existing components and data contracts before modifying code.');
    buffer.writeln('Preserve all current working behavior.');
    buffer.writeln();

    buffer.writeln('## 3. Required Changes');
    final taskLines = taskDescription
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (taskLines.length > 1) {
      for (var i = 0; i < taskLines.length; i++) {
        buffer.writeln('### Requirement ${i + 1}');
        buffer.writeln(
          '- ${taskLines[i].replaceFirst(RegExp(r'^[0-9\-\*\.]+\s*'), '')}',
        );
      }
    } else {
      buffer.writeln('### Requirement 1 — Core Implementation');
      buffer.writeln('- ${taskLines.first}');
      buffer.writeln('### Requirement 2 — Integration & Error Handling');
      buffer.writeln(
        '- Connect feature to existing workflows and provide graceful error recovery.',
      );
    }
    buffer.writeln();

    buffer.writeln('## 4. Relevant Files to Inspect or Modify');
    if (relevantFiles.isNotEmpty) {
      relevantFiles.forEach((path, desc) {
        buffer.writeln('- `$path` — $desc');
      });
    } else {
      buffer.writeln('- Files to identify during repository inspection.');
    }
    buffer.writeln();

    buffer.writeln('## 5. Dependencies and Technologies');
    if (technologies.isNotEmpty) {
      buffer.writeln('**Existing Technologies:**');
      for (final t in technologies.take(8)) {
        buffer.writeln('- $t');
      }
    }
    if (dependencies.isNotEmpty) {
      buffer.writeln('\n**Existing Dependencies:**');
      for (final d in dependencies.take(10)) {
        buffer.writeln('- $d');
      }
    }
    buffer.writeln('\n- Reuse existing dependencies and architecture wherever possible.');
    buffer.writeln('- Introduce new dependencies only if strictly required and justified.');
    buffer.writeln();

    buffer.writeln('## 6. Implementation Instructions');
    buffer.writeln('1. Inspect the relevant files and existing architecture before writing code.');
    buffer.writeln('2. Implement the required changes cleanly in accordance with existing code style and patterns.');
    buffer.writeln('3. Incorporate comprehensive validation and robust error handling.');
    buffer.writeln('4. Verify that existing workflows and APIs remain backwards compatible.');
    buffer.writeln('5. Run existing automated tests and static analysis to confirm zero regressions.');
    buffer.writeln();

    buffer.writeln('## 7. Environment and Configuration Constraints');
    buffer.writeln('- Preserve existing configuration files and runtime environment.');
    buffer.writeln('- Never expose secrets, API keys, passwords, or tokens.');
    buffer.writeln('- If new configuration variables are needed, document placeholders in environment templates.');
    buffer.writeln();

    buffer.writeln('## 8. Compatibility and Preservation Requirements');
    buffer.writeln('- All existing features and behavior must remain functional.');
    buffer.writeln('- Avoid unrelated refactoring, redesigns, or dependency upgrades.');
    buffer.writeln('- Maintain backward compatibility with existing interfaces.');
    buffer.writeln();

    buffer.writeln('## 9. Acceptance Criteria');
    buffer.writeln('1. The requested feature is fully implemented and functioning: "$featureTitle".');
    buffer.writeln('2. Validation and error handling are present for all new inputs.');
    buffer.writeln('3. All existing functionality continues to work without regression.');
    buffer.writeln('4. No unrelated code files or dependencies are altered.');
    buffer.writeln();

    buffer.writeln('## 10. Verification');
    buffer.writeln('- Execute relevant unit tests and static analysis checks.');
    buffer.writeln('- Verify happy-path functionality and error recovery.');
    buffer.writeln('- Distinguish completed checks from remaining release-time verification.');

    return buffer.toString().trim();
  }

  String _buildLocalSummarySection(
    String projectName,
    Map<String, dynamic>? folderReport,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT');
    buffer.writeln();

    if (folderReport == null || folderReport.isEmpty) {
      buffer.writeln('Local project analysis was not provided or is unavailable.');
      return buffer.toString().trim();
    }

    final overview = folderReport['overview'] as String? ?? '';
    final architecture = folderReport['architecture'] as String? ?? '';
    final technologies =
        (folderReport['technologies'] as List?)?.whereType<Map>().toList() ?? [];
    final dependencies =
        (folderReport['dependencies'] as List?)?.whereType<Map>().toList() ?? [];
    final files =
        (folderReport['files'] as List?)?.whereType<Map>().toList() ?? [];
    final statistics = folderReport['statistics'] as Map?;

    if (overview.isNotEmpty) {
      buffer.writeln('**Local Project Overview:**');
      buffer.writeln(overview);
      buffer.writeln();
    }

    if (architecture.isNotEmpty) {
      buffer.writeln('**Architecture:**');
      buffer.writeln(architecture);
      buffer.writeln();
    }

    if (technologies.isNotEmpty) {
      buffer.writeln('**Identified Technologies:**');
      for (final t in technologies.take(10)) {
        buffer.writeln(
          '- ${t['name'] ?? ''}${t['category'] != null ? ' (${t['category']})' : ''}',
        );
      }
      buffer.writeln();
    }

    if (dependencies.isNotEmpty) {
      buffer.writeln('**Dependencies & Configuration Requirements:**');
      for (final d in dependencies.take(15)) {
        buffer.writeln(
          '- ${d['name']} ${d['version'] ?? ''} ${d['purpose'] != null ? '— ${d['purpose']}' : ''}'
              .trim(),
        );
      }
      buffer.writeln();
    }

    if (files.isNotEmpty) {
      buffer.writeln(
        '**Local Project Structure & Important Files (${files.length} indexed):**',
      );
      for (final f in files.take(30)) {
        final path = f['path'] ?? '';
        final purpose = f['purpose'] ?? f['module'] ?? '';
        buffer.writeln('- `$path` — $purpose');
      }
      if (files.length > 30) {
        buffer.writeln('... and ${files.length - 30} more source files.');
      }
      buffer.writeln();
    }

    if (statistics != null) {
      buffer.writeln('**Scan Statistics:**');
      buffer.writeln('- Discovered files: ${statistics['discoveredFiles'] ?? 'N/A'}');
      buffer.writeln('- Analyzed files: ${statistics['analyzedFiles'] ?? files.length}');
      buffer.writeln('- Omitted files: ${statistics['omittedFiles'] ?? 0}');
    }

    return buffer.toString().trim();
  }

  String _buildRemoteSummarySection(Map<String, dynamic>? repositoryReport) {
    final buffer = StringBuffer();
    buffer.writeln('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT');
    buffer.writeln();

    if (repositoryReport == null || repositoryReport.isEmpty) {
      buffer.writeln('GitHub repository analysis was not provided or is unavailable.');
      return buffer.toString().trim();
    }

    final overview = repositoryReport['overview'] as String? ?? '';
    final architecture = repositoryReport['architecture'] as String? ?? '';
    final technologies =
        (repositoryReport['technologies'] as List?)?.whereType<Map>().toList() ?? [];
    final dependencies =
        (repositoryReport['dependencies'] as List?)?.whereType<Map>().toList() ?? [];
    final files =
        (repositoryReport['files'] as List?)?.whereType<Map>().toList() ?? [];
    final recommendations =
        (repositoryReport['recommendations'] as List?)?.whereType<String>().toList() ?? [];

    if (overview.isNotEmpty) {
      buffer.writeln('**Remote Repository Overview:**');
      buffer.writeln(overview);
      buffer.writeln();
    }

    if (architecture.isNotEmpty) {
      buffer.writeln('**Architecture & Component Relationships:**');
      buffer.writeln(architecture);
      buffer.writeln();
    }

    if (technologies.isNotEmpty) {
      buffer.writeln('**Technologies & Frameworks:**');
      for (final t in technologies.take(10)) {
        buffer.writeln(
          '- ${t['name'] ?? ''}${t['category'] != null ? ' (${t['category']})' : ''}',
        );
      }
      buffer.writeln();
    }

    if (dependencies.isNotEmpty) {
      buffer.writeln('**Dependencies & Configuration Details:**');
      for (final d in dependencies.take(15)) {
        buffer.writeln(
          '- ${d['name']} ${d['version'] ?? ''} ${d['purpose'] != null ? '— ${d['purpose']}' : ''}'
              .trim(),
        );
      }
      buffer.writeln();
    }

    if (files.isNotEmpty) {
      buffer.writeln(
        '**Remote Repository Structure & Key Source Files (${files.length} indexed):**',
      );
      for (final f in files.take(30)) {
        final path = f['path'] ?? '';
        final purpose = f['purpose'] ?? f['module'] ?? '';
        buffer.writeln('- `$path` — $purpose');
      }
      if (files.length > 30) {
        buffer.writeln('... and ${files.length - 30} more source files.');
      }
      buffer.writeln();
    }

    if (recommendations.isNotEmpty) {
      buffer.writeln('**Implementation Patterns & Integration Points:**');
      for (final r in recommendations.take(6)) {
        buffer.writeln('- $r');
      }
    }

    return buffer.toString().trim();
  }

  String _assembleFinalResult({
    required String sectionA,
    required String sectionB,
    required String sectionC,
  }) {
    // Clean up any stray section labels inside Section A if generated by AI
    var cleanA = sectionA.trim();
    if (cleanA.contains('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY')) {
      cleanA =
          cleanA.split('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY').first.trim();
    }
    if (cleanA.contains('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY')) {
      cleanA =
          cleanA.split('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY').first.trim();
    }

    final sectionAPrefix =
        cleanA.startsWith('### SECTION A — NNSD IMPLEMENTATION PROMPT')
            ? ''
            : '### SECTION A — NNSD IMPLEMENTATION PROMPT\n\n';

    final result = StringBuffer();
    result.writeln('$sectionAPrefix$cleanA');
    result.writeln();
    result.writeln(sectionB);
    result.writeln();
    result.writeln(sectionC);

    return RepositoryScanner.redactSecrets(result.toString().trim());
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

