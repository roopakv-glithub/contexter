import 'package:supabase_flutter/supabase_flutter.dart';

import 'repository_scanner.dart';

class ProjectAnalyzer {
  ProjectAnalyzer(this._client);

  final SupabaseClient _client;

  Future<String> enhancePrompt({
    required String prompt,
    required String projectName,
    required String context,
  }) async {
    final response = await _client.functions.invoke(
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

  Future<void> savePrompt({
    required String original,
    required String enhanced,
    required String projectName,
  }) async {
    await _client.from('prompt_history').insert({
      'project_name': projectName,
      'original_prompt': original,
      'enhanced_prompt': enhanced,
    });
  }

  Future<List<Map<String, dynamic>>> recentPrompts() async {
    final rows = await _client
        .from('prompt_history')
        .select(
          'id, project_name, original_prompt, enhanced_prompt, created_at',
        )
        .order('created_at', ascending: false)
        .limit(100);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> analyzeRepository(String repositoryUrl) async {
    final response = await _client.functions.invoke(
      'analyze-project',
      body: {'repositoryUrl': repositoryUrl},
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
    final response = await _client.functions.invoke(
      'analyze-project',
      body: {
        'projectName': pathParts.isEmpty ? 'Local project' : pathParts.last,
        'files': scan.files.map((file) => file.toJson()).toList(),
        'discoveredFiles': scan.discoveredFiles,
        'omittedFiles': scan.omittedFiles,
        'truncatedFiles': scan.files.where((file) => file.truncated).length,
      },
    );
    return _readReport(response.data);
  }

  Future<String> saveReport({
    required String projectName,
    required String source,
    required Map<String, dynamic> report,
  }) async {
    final saved = await _client
        .from('analysis_reports')
        .insert({
          'project_name': projectName,
          'source': source,
          'report': report,
        })
        .select('id')
        .single();
    return saved['id'] as String;
  }

  Future<List<Map<String, dynamic>>> recentReports() async {
    final rows = await _client
        .from('analysis_reports')
        .select('id, project_name, source, created_at, report')
        .order('created_at', ascending: false)
        .limit(20);
    return List<Map<String, dynamic>>.from(rows);
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
