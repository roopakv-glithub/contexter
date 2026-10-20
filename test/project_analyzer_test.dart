import 'package:flutter_test/flutter_test.dart';
import 'package:moscowt/services/project_analyzer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeFunctionsClient extends Fake implements FunctionsClient {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      throw const FunctionException(status: 404);
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  FunctionsClient get functions => _FakeFunctionsClient();
}

void main() {
  group('ProjectAnalyzer NNSD Prompt Generation', () {
    late ProjectAnalyzer analyzer;

    setUp(() {
      ProjectAnalyzer.activeNvidiaKey = null;
      analyzer = ProjectAnalyzer(_FakeSupabaseClient());
    });

    final sampleFolderReport = {
      'overview': 'Backend microservice for student note synchronization.',
      'architecture': 'Clean architecture with controller, service, repository layers.',
      'technologies': [
        {'name': 'Dart', 'category': 'Language'},
        {'name': 'PostgreSQL', 'category': 'Database'},
      ],
      'dependencies': [
        {'name': 'shelf', 'version': '^1.4.0', 'purpose': 'HTTP routing'},
      ],
      'files': [
        {'path': 'lib/auth_service.dart', 'module': 'Auth', 'purpose': 'Handles token authentication'},
        {'path': 'lib/note_controller.dart', 'module': 'API', 'purpose': 'Note endpoints'},
      ],
      'statistics': {
        'discoveredFiles': 10,
        'analyzedFiles': 2,
        'omittedFiles': 8,
      },
    };

    final sampleRepositoryReport = {
      'overview': 'Remote GitHub main branch with base models.',
      'architecture': 'Standard client-server structure.',
      'technologies': [
        {'name': 'Dart', 'category': 'Language'},
      ],
      'dependencies': [
        {'name': 'shelf', 'version': '^1.4.0', 'purpose': 'HTTP routing'},
      ],
      'files': [
        {'path': 'lib/auth_service.dart', 'module': 'Auth', 'purpose': 'Handles token authentication'},
        {'path': 'lib/remote_sync.dart', 'module': 'Sync', 'purpose': 'Syncs notes with cloud'},
      ],
      'recommendations': [
        'Ensure shelf pipeline is configured before route dispatch',
      ],
    };

    test('generates output with required 3-section ordering (Section A first, then B, then C)', () async {
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'StudySync',
        projectDescription: 'Collaborative study tool for students',
        agentName: 'Pixel',
        taskDescription: 'Add rate limiting to authentication endpoints without modifying models',
        folderReport: sampleFolderReport,
        repositoryReport: sampleRepositoryReport,
      );

      final indexA = prompt.indexOf('### SECTION A — NNSD IMPLEMENTATION PROMPT');
      final indexB = prompt.indexOf('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT');
      final indexC = prompt.indexOf('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT');

      expect(indexA, isNonNegative, reason: 'Section A must exist');
      expect(indexB, isNonNegative, reason: 'Section B must exist');
      expect(indexC, isNonNegative, reason: 'Section C must exist');

      expect(indexA < indexB, isTrue, reason: 'Section A must appear before Section B');
      expect(indexB < indexC, isTrue, reason: 'Section B must appear before Section C');
    });

    test('Section A contains all 10 required numbered subsections', () async {
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'PaperToPortal',
        projectDescription: 'Document scanning portal',
        agentName: 'Byte',
        taskDescription: 'Add PAN card scanning and bank application document scanning',
        folderReport: sampleFolderReport,
        repositoryReport: sampleRepositoryReport,
      );

      expect(prompt, contains('## 1. Objective'));
      expect(prompt, contains('## 2. Existing Functionality'));
      expect(prompt, contains('## 3. Required Changes'));
      expect(prompt, contains('## 4. Relevant Files to Inspect or Modify'));
      expect(prompt, contains('## 5. Dependencies and Technologies'));
      expect(prompt, contains('## 6. Implementation Instructions'));
      expect(prompt, contains('## 7. Environment and Configuration Constraints'));
      expect(prompt, contains('## 8. Compatibility and Preservation Requirements'));
      expect(prompt, contains('## 9. Acceptance Criteria'));
      expect(prompt, contains('## 10. Verification'));
    });

    test('preserves user task objective and explicit constraints', () async {
      const explicitTask = 'Add rate limiting to auth endpoints. Do not modify the database schema or auth tokens.';
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'StudySync',
        projectDescription: 'Collaborative study tool',
        agentName: 'Pixel',
        taskDescription: explicitTask,
        folderReport: sampleFolderReport,
        repositoryReport: sampleRepositoryReport,
      );

      expect(prompt, contains('Add rate limiting to auth endpoints'));
      expect(prompt, contains('Do not modify the database schema or auth tokens'));
    });

    test('grounds relevant files from analysis evidence without inventing files', () async {
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'StudySync',
        projectDescription: 'Study tool',
        agentName: 'Byte',
        taskDescription: 'Update auth_service with token caching',
        folderReport: sampleFolderReport,
        repositoryReport: sampleRepositoryReport,
      );

      expect(prompt, contains('lib/auth_service.dart'));
      expect(prompt, contains('Handles token authentication'));
    });

    test('handles missing local folder report gracefully with explicit message', () async {
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'StudySync',
        projectDescription: 'Study tool',
        agentName: 'Momo',
        taskDescription: 'Implement remote metrics exporter',
        folderReport: null,
        repositoryReport: sampleRepositoryReport,
      );

      expect(prompt, contains('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT'));
      expect(prompt, contains('Local project analysis was not provided or is unavailable.'));
      expect(prompt, contains('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT'));
      expect(prompt, contains('Remote GitHub main branch with base models.'));
    });

    test('handles missing GitHub repository report gracefully with explicit message', () async {
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'StudySync',
        projectDescription: 'Study tool',
        agentName: 'Momo',
        taskDescription: 'Implement local caching',
        folderReport: sampleFolderReport,
        repositoryReport: null,
      );

      expect(prompt, contains('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT'));
      expect(prompt, contains('Backend microservice for student note synchronization.'));
      expect(prompt, contains('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT'));
      expect(prompt, contains('GitHub repository analysis was not provided or is unavailable.'));
    });

    test('redacts secrets from user task, inputs, and final output', () async {
      const taskWithSecret = 'Connect to database using password=superSecretPassword123 and nvapi-abcdef1234567890xyz token';
      final prompt = await analyzer.generateContextPrompt(
        projectName: 'SecretProject',
        projectDescription: 'Test project',
        agentName: 'Pixel',
        taskDescription: taskWithSecret,
        folderReport: sampleFolderReport,
        repositoryReport: sampleRepositoryReport,
      );

      expect(prompt, isNot(contains('superSecretPassword123')));
      expect(prompt, isNot(contains('nvapi-abcdef1234567890xyz')));
      expect(prompt, contains('[REDACTED'));
    });

    test('handles large context inputs without truncating Section A or B or C', () async {
      final largeFiles = List.generate(
        150,
        (i) => {
          'path': 'lib/module_$i/file_$i.dart',
          'module': 'module_$i',
          'purpose': 'Generated module service $i for large repository testing',
        },
      );

      final largeFolderReport = {
        'overview': 'Large scale enterprise backend with extensive modules.',
        'architecture': 'Micro-modular service topology.',
        'technologies': [{'name': 'Dart', 'category': 'Language'}],
        'dependencies': [{'name': 'shelf', 'version': '^1.4.0'}],
        'files': largeFiles,
        'statistics': {'discoveredFiles': 150, 'analyzedFiles': 150, 'omittedFiles': 0},
      };

      final prompt = await analyzer.generateContextPrompt(
        projectName: 'EnterpriseSync',
        projectDescription: 'Enterprise study tool',
        agentName: 'Byte',
        taskDescription: 'Add distributed tracing headers across HTTP handlers',
        folderReport: largeFolderReport,
        repositoryReport: sampleRepositoryReport,
      );

      expect(prompt, contains('### SECTION A — NNSD IMPLEMENTATION PROMPT'));
      expect(prompt, contains('### SECTION B — LOCAL PROJECT ANALYSIS SUMMARY — REFERENCE CONTEXT'));
      expect(prompt, contains('### SECTION C — GITHUB REPOSITORY ANALYSIS SUMMARY — REFERENCE CONTEXT'));
      expect(prompt, contains('## 1. Objective'));
      expect(prompt, contains('## 10. Verification'));
    });

    test('saves and in-memory caches NVIDIA API key correctly', () async {
      await analyzer.saveNvidiaKey('nvapi-test-dummy-key-123456');
      expect(ProjectAnalyzer.activeNvidiaKey, 'nvapi-test-dummy-key-123456');
    });
  });
}
