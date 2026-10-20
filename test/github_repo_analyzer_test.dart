import 'package:flutter_test/flutter_test.dart';
import 'package:moscowt/services/github_repo_analyzer.dart';
import 'package:moscowt/services/project_analyzer.dart';

void main() {
  group('GithubRepoAnalyzer', () {
    test('validates and parses full GitHub URLs', () {
      final info = GithubRepoAnalyzer.parseUrl('https://github.com/heyputer/kv.js');
      expect(info.owner, 'heyputer');
      expect(info.repo, 'kv.js');
      expect(info.branch, isNull);
      expect(info.subdirectory, isEmpty);
      expect(info.repositoryPath, 'heyputer/kv.js');
    });

    test('validates and parses GitHub URLs with branch and subdirectory', () {
      final info = GithubRepoAnalyzer.parseUrl(
        'https://github.com/flutter/flutter/tree/master/packages/flutter',
      );
      expect(info.owner, 'flutter');
      expect(info.repo, 'flutter');
      expect(info.branch, 'master');
      expect(info.subdirectory, 'packages/flutter');
      expect(info.repositoryPath, 'flutter/flutter/packages/flutter');
    });

    test('validates and parses short owner/repo format', () {
      final info = GithubRepoAnalyzer.parseUrl('torvalds/linux');
      expect(info.owner, 'torvalds');
      expect(info.repo, 'linux');
    });

    test('rejects malformed or empty URLs', () {
      expect(
        () => GithubRepoAnalyzer.parseUrl(''),
        throwsA(isA<AiServiceException>()),
      );
      expect(
        () => GithubRepoAnalyzer.parseUrl('not-a-repo'),
        throwsA(isA<AiServiceException>()),
      );
      expect(
        () => GithubRepoAnalyzer.parseUrl('https://gitlab.com/owner/repo'),
        throwsA(isA<AiServiceException>()),
      );
    });

    test('parses Repo-to-Markdown file blocks correctly', () {
      const sampleMarkdown = '''
# Repository Overview
- Repository: heyputer/kv.js
- Total Files: 2

# Repository Structure
```
heyputer/kv.js/
├── kv.js
└── package.json
```

================================================================================
// File: package.json
================================================================================
{
  "name": "kv.js",
  "version": "1.0.0"
}

================================================================================
// File: src/kv.js
================================================================================
class KVStore {
  constructor() {}
}
''';

      final files = GithubRepoAnalyzer.parseMarkdownFiles(sampleMarkdown);
      expect(files.length, 2);
      expect(files[0]['path'], 'package.json');
      expect(files[0]['module'], 'root');
      expect(files[0]['content'], contains('"name": "kv.js"'));

      expect(files[1]['path'], 'src/kv.js');
      expect(files[1]['module'], 'src');
      expect(files[1]['content'], contains('class KVStore'));
    });

    test('verifies that Markdown without source files is rejected', () {
      const readmeOnlyMarkdown = '''
# Repository Overview
## About This Document
Only README available.
''';

      expect(
        () => GithubRepoAnalyzer.parseMarkdownFiles(readmeOnlyMarkdown),
        returnsNormally,
      );
      expect(
        GithubRepoAnalyzer.parseMarkdownFiles(readmeOnlyMarkdown),
        isEmpty,
      );
    });
  });
}
