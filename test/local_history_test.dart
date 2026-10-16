import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moscowt/services/local_history.dart';

void main() {
  late Directory directory;
  late LocalHistory history;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('moscowt-history-test-');
    history = LocalHistory(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('saves reports and prompts locally across instances', () async {
    await history.saveReport(
      projectName: 'sample',
      source: 'Local folder',
      report: {'overview': 'A sample project'},
    );
    await history.savePrompt(
      original: 'Make a change',
      enhanced: 'Inspect the project, then make the change.',
      projectName: 'sample',
    );

    final reopened = LocalHistory(directory: directory);
    final reports = await reopened.recentReports();
    final prompts = await reopened.recentPrompts();

    expect(reports.single['project_name'], 'sample');
    expect((reports.single['report'] as Map)['overview'], 'A sample project');
    expect(prompts.single['original_prompt'], 'Make a change');
    expect(prompts.single['enhanced_prompt'], contains('Inspect the project'));
  });
}
