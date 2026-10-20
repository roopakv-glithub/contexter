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
  group('ProjectAnalyzer', () {
    late ProjectAnalyzer analyzer;

    setUp(() {
      analyzer = ProjectAnalyzer(_FakeSupabaseClient());
    });

    test('generates complete structured Markdown prompt from repository reports', () async {
      final folderReport = {
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
      };

      final repositoryReport = {
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
      };

      final prompt = await analyzer.generateContextPrompt(
        projectName: 'StudySync',
        projectDescription: 'Collaborative study tool for students',
        agentName: 'Pixel',
        taskDescription: 'Add rate limiting to the authentication endpoints without modifying models',
        folderReport: folderReport,
        repositoryReport: repositoryReport,
      );

      // Verify all required ContextForge sections are present
      expect(prompt, contains('# ContextForge Coding Agent Instruction'));
      expect(prompt, contains('## A. Project Overview'));
      expect(prompt, contains('StudySync'));
      expect(prompt, contains('## B. User Requested Change'));
      expect(prompt, contains('rate limiting'));
      expect(prompt, contains('## C. Repository Structure & Key Components'));
      expect(prompt, contains('## D. Existing Implementation'));
      expect(prompt, contains('## E. Files to Inspect or Modify'));
      expect(prompt, contains('auth_service.dart'));
      expect(prompt, contains('## F. Local-versus-Remote Differences'));
      expect(prompt, contains('Files present in both: 1'));
      expect(prompt, contains('## G. Functions and Dependencies'));
      expect(prompt, contains('shelf'));
      expect(prompt, contains('## H. Environment & Configuration Requirements'));
      expect(prompt, contains('Never overwrite secrets'));
      expect(prompt, contains('## I. Conflict and Compatibility Risks'));
      expect(prompt, contains('## J. Implementation Plan'));
      expect(prompt, contains('## K. Testing and Validation Instructions'));
      expect(prompt, contains('## L. Preservation Requirements'));
      expect(prompt, contains('## M. Completion Criteria'));
    });

    test('saves and in-memory caches NVIDIA API key correctly', () async {
      await analyzer.saveNvidiaKey('nvapi-test-dummy-key-123456');
      expect(ProjectAnalyzer.activeNvidiaKey, 'nvapi-test-dummy-key-123456');
    });
  });
}
