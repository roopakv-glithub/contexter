import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth_screen.dart';
import 'services/project_analyzer.dart';
import 'services/repository_scanner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const MoscowtApp());
}

const blue = Color(0xFF0878F9);
const ink = Color(0xFF20232A);
const muted = Color(0xFF858A95);
const canvas = Color(0xFFF4F5F8);

class MoscowtApp extends StatelessWidget {
  const MoscowtApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Moscowt',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        brightness: Brightness.light,
      ),
      fontFamily: 'Segoe UI',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: ink,
          fontSize: 27,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: ink,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: ink, fontSize: 13),
        bodySmall: TextStyle(color: muted, fontSize: 11),
      ),
    ),
    home: const _AuthGate(),
  );
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _client = Supabase.instance.client;
  late Session? _session = _client.auth.currentSession;
  late final StreamSubscription<AuthState> _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _client.auth.onAuthStateChange.listen((state) {
      if (mounted) setState(() => _session = state.session);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _session == null ? const AuthScreen() : const MoscowtShell();
}

enum Page { home, setup, agents, history, models, settings, enhance }

class MoscowtShell extends StatefulWidget {
  const MoscowtShell({super.key});

  @override
  State<MoscowtShell> createState() => _MoscowtShellState();
}

class _MoscowtShellState extends State<MoscowtShell> {
  Page page = Page.home;
  int setupStep = 0;
  int selectedMascot = 0;
  int selectedAgent = 0;
  bool busy = false;
  String project = 'moscowt-api';
  String prompt =
      'Add rate limiting to the login endpoint so people can’t brute force it, use whatever we already have';
  String enhanced = '';
  Map<String, dynamic>? analysisReport;
  List<Map<String, dynamic>> savedReports = [];
  List<Map<String, dynamic>> savedPrompts = [];
  bool analysisBusy = false;
  bool reportsBusy = false;
  String? analysisError;
  int scannedFiles = 0;
  String projectSource = '';
  final projectController = TextEditingController(text: 'moscowt-api');
  final folderController = TextEditingController(
    text: r'C:\Users\you\Projects\moscowt-api',
  );
  final repoController = TextEditingController(
    text: 'https://github.com/your-org/moscowt-api',
  );
  final descriptionController = TextEditingController();
  final agentController = TextEditingController(text: 'API Helper');
  final purposeController = TextEditingController(
    text: 'Improve prompts for backend tasks',
  );
  final promptController = TextEditingController(
    text: 'Add rate limiting to the login endpoint so people can’t brute force it, use whatever we already have',
  );
  final searchController = TextEditingController();
  final repositoryAnalysisController = TextEditingController();

  @override
  void dispose() {
    projectController.dispose();
    folderController.dispose();
    repoController.dispose();
    descriptionController.dispose();
    agentController.dispose();
    purposeController.dispose();
    promptController.dispose();
    searchController.dispose();
    repositoryAnalysisController.dispose();
    super.dispose();
  }

  void go(Page next) {
    setState(() => page = next);
    if (next == Page.history) _loadSavedHistory();
  }

  ProjectAnalyzer get _analyzer => ProjectAnalyzer(Supabase.instance.client);

  Future<void> analyzeRepository() async {
    final url = repositoryAnalysisController.text.trim();
    if (url.isEmpty) {
      notice('Enter a public GitHub repository URL.');
      return;
    }
    await _runAnalysis(() => _analyzer.analyzeRepository(url), source: url);
  }

  Future<void> analyzeLocalFolder() async {
    try {
      final folder = await RepositoryScanner.pickFolder();
      if (folder == null) return;
      projectSource = folder;
      await _runAnalysis(
        () => _analyzer.analyzeFolder(
          folder,
          onProgress: (count) {
            if (mounted) setState(() => scannedFiles = count);
          },
        ),
        source: 'Local folder',
      );
    } catch (error) {
      if (mounted) notice('Could not scan the selected folder: $error');
    }
  }

  Future<void> _runAnalysis(
    Future<Map<String, dynamic>> Function() analyze, {
    required String source,
  }) async {
    setState(() {
      analysisBusy = true;
      analysisError = null;
      analysisReport = null;
      scannedFiles = 0;
      projectSource = source;
    });
    try {
      final report = await analyze();
      if (!mounted) return;
      setState(() {
        analysisReport = report;
        project = report['projectName'] as String? ?? project;
        projectController.text = project;
      });
      try {
        await _analyzer.saveReport(
          projectName: project,
          source: source.startsWith('https://') ? source : 'Local folder',
          report: report,
        );
        if (mounted) {
          setState(() => savedReports = []);
          notice('Analysis complete and saved to your account.');
        }
      } catch (error) {
        if (mounted) {
          notice('Analysis is ready, but saving the report failed: $error');
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => analysisError = '$error');
      notice('Project analysis failed: $error');
    } finally {
      if (mounted) setState(() => analysisBusy = false);
    }
  }

  Future<void> _loadSavedHistory() async {
    setState(() => reportsBusy = true);
    try {
      final results = await Future.wait([
        _analyzer.recentReports(),
        _analyzer.recentPrompts(),
      ]);
      if (mounted) {
        setState(() {
          savedReports = results[0];
          savedPrompts = results[1];
        });
      }
    } catch (error) {
      if (mounted) notice('Could not load saved analyses: $error');
    } finally {
      if (mounted) setState(() => reportsBusy = false);
    }
  }

  void _openSavedReport(Map<String, dynamic> saved) {
    final report = saved['report'];
    if (report is! Map) {
      notice('This saved report has an invalid format.');
      return;
    }
    setState(() {
      analysisReport = Map<String, dynamic>.from(report);
      project = saved['project_name'] as String? ?? 'Project';
      projectSource = saved['source'] as String? ?? '';
    });
    go(Page.models);
  }

  Future<void> enhancePrompt() async {
    final input = promptController.text.trim();
    if (input.isEmpty) {
      notice('Enter a prompt to enhance.');
      return;
    }
    setState(() => busy = true);
    try {
      final context = analysisReport == null
          ? ''
          : jsonEncode({
              'overview': analysisReport!['overview'],
              'architecture': analysisReport!['architecture'],
              'technologies': analysisReport!['technologies'],
              'dependencies': analysisReport!['dependencies'],
              'files': (analysisReport!['files'] as List? ?? const [])
                  .take(40)
                  .map(
                    (item) => {
                      'path': item['path'],
                      'purpose': item['purpose'],
                      'functions': item['functions'],
                    },
                  )
                  .toList(),
            });
      final result = await _analyzer.enhancePrompt(
        prompt: input,
        projectName: project,
        context: context,
      );
      if (result.isEmpty) {
        throw const FormatException(
          'The AI returned an empty enhanced prompt.',
        );
      }
      setState(() {
        prompt = input;
        enhanced = result;
      });
      try {
        await _analyzer.savePrompt(
          original: input,
          enhanced: result,
          projectName: project,
        );
      } catch (error) {
        if (mounted) {
          notice('Prompt enhanced, but saving it to history failed: $error');
        }
      }
    } catch (error) {
      notice('Prompt enhancement failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Row(
      children: [
        _Sidebar(
          page: page,
          onSelect: go,
          agent: agentController.text,
          project: project,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 26, 34, 24),
            child: _pageBody(),
          ),
        ),
      ],
    ),
  );

  Widget _pageBody() {
    switch (page) {
      case Page.home:
        return _home();
      case Page.setup:
        return _setup();
      case Page.agents:
        return _agents();
      case Page.history:
        return _history();
      case Page.models:
        return _repository();
      case Page.settings:
        return _settings();
      case Page.enhance:
        return _enhancer();
    }
  }

  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Heading(
        'Home',
        'Welcome back — here’s what your companion can do.',
      ),
      const SizedBox(height: 20),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ActionButton(
            'Enhance a prompt',
            Icons.auto_awesome,
            onPressed: () => go(Page.enhance),
            primary: true,
          ),
          _ActionButton(
            'Switch project',
            Icons.swap_horiz,
            onPressed: () => go(Page.setup),
          ),
          _ActionButton(
            'Create agent',
            Icons.add,
            onPressed: () {
              setState(() => setupStep = 1);
              go(Page.setup);
            },
          ),
          _ActionButton(
            'Open companion',
            Icons.sentiment_satisfied_alt,
            onPressed: () => go(Page.enhance),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _Label('Active project'),
                  Row(
                    children: [
                      Text(
                        project,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const _Pill(
                        'Indexed',
                        Color(0xFFE3F7EB),
                        Color(0xFF1EAF61),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    folderController.text,
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'GitHub · ${repoController.text.replaceFirst('https://github.com/', '')} · main',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _Card(
              child: Row(
                children: [
                  _Mascot(size: 68, index: selectedMascot),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Label('Active agent'),
                        Text(
                          agentController.text,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${_mascots[selectedMascot].name} · Claude Sonnet 5.5',
                          style: const TextStyle(color: muted),
                        ),
                        TextButton(
                          onPressed: () => go(Page.enhance),
                          child: const Text('Open companion'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Repository indexing',
              value: '1,248 files indexed',
              foot: 'Last updated today, 10:42 AM',
              progress: true,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: _StatCard(
              label: 'Prompts enhanced today',
              value: '24',
              foot: '+6 vs. yesterday',
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: _StatCard(
              label: 'Estimated tokens saved',
              value: '18.4k',
              foot: '▂ ▃ ▄ ▅ ▆ ▇ █',
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(
        child: _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent prompt activity',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final item in const [
                ('Add rate limiting to the login endpoint', '10:42 AM', '−38%'),
                (
                  'Refactor token service to use refresh tokens',
                  '10:15 AM',
                  '−24%',
                ),
                ('Write tests for the billing webhook', '9:03 AM', '−41%'),
                ('Explain the Prisma schema relations', 'Yesterday', '−19%'),
              ])
                _ActivityRow(title: item.$1, time: item.$2, saving: item.$3),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _setup() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Heading(
        setupStep == 0
            ? 'Set up your project'
            : setupStep == 1
            ? 'Create your agent'
            : 'Review and finish',
        setupStep == 0
            ? 'Connect a local folder, a GitHub repository, or both.'
            : setupStep == 1
            ? 'Pick a Moscowt companion and tell it what to focus on.'
            : 'Everything look right? You can change any of this later in My Agents.',
      ),
      const SizedBox(height: 18),
      _Stepper(active: setupStep),
      const SizedBox(height: 18),
      Expanded(
        child: SingleChildScrollView(
          child: setupStep == 0
              ? _projectForm()
              : setupStep == 1
              ? _agentForm()
              : _review(),
        ),
      ),
      Row(
        children: [
          TextButton(
            onPressed: () {
              if (setupStep == 0) {
                go(Page.home);
              } else {
                setState(() => setupStep--);
              }
            },
            child: Text(setupStep == 0 ? 'Cancel' : 'Back'),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {
              if (setupStep < 2) {
                setState(() {
                  setupStep++;
                  if (setupStep == 1) {
                    project = projectController.text.trim().isEmpty
                        ? 'New project'
                        : projectController.text.trim();
                  }
                });
              } else {
                setState(() {
                  project = projectController.text.trim().isEmpty
                      ? 'New project'
                      : projectController.text.trim();
                });
                go(Page.home);
                notice('Your project and agent are ready.');
              }
            },
            child: Text(setupStep == 2 ? 'Create Agent' : 'Continue'),
          ),
        ],
      ),
    ],
  );

  Widget _projectForm() => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Field(
                label: 'Project Name',
                controller: projectController,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _Field(
                label: 'Project Description (optional)',
                controller: descriptionController,
                hint: 'What does this project do?',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'Project Folder',
          controller: folderController,
          trailing: TextButton(
            onPressed: () =>
                notice('Choose a project folder from the Windows app.'),
            child: const Text('Browse Folder'),
          ),
        ),
        const SizedBox(height: 16),
        _Field(
          label: 'GitHub Repository (optional)',
          controller: repoController,
          hint: 'https://github.com/owner/repository',
        ),
        const SizedBox(height: 8),
        const Text(
          'Connect a repository to give your agent relevant project context.',
          style: TextStyle(color: muted, fontSize: 11),
        ),
      ],
    ),
  );

  Widget _agentForm() => Column(
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final cards = List.generate(
            _mascots.length,
            (index) => _MascotCard(
              index: index,
              selected: selectedMascot == index,
              onTap: () => setState(() => selectedMascot = index),
            ),
          );
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: cards
                .map(
                  (card) => SizedBox(
                    width: (constraints.maxWidth - 28) / 3,
                    child: card,
                  ),
                )
                .toList(),
          );
        },
      ),
      const SizedBox(height: 18),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _Field(label: 'Agent Name', controller: agentController),
                const SizedBox(height: 14),
                _DropdownField(
                  label: 'AI Model',
                  value: 'Claude Sonnet 5.5',
                  values: const [
                    'Claude Sonnet 5.5',
                    'GPT-4.1',
                    'Gemini 2.5 Pro',
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(height: 14),
                _DropdownField(
                  label: 'Agent Personality (optional)',
                  value: 'Friendly & concise',
                  values: const [
                    'Friendly & concise',
                    'Detailed & thorough',
                    'Direct & technical',
                  ],
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                _DropdownField(
                  label: 'Select Project',
                  value: projectController.text.isEmpty
                      ? 'New project'
                      : projectController.text,
                  values: [
                    projectController.text.isEmpty
                        ? 'New project'
                        : projectController.text,
                  ],
                  onChanged: (_) {},
                ),
                const SizedBox(height: 14),
                _Field(
                  label: 'Agent Purpose (optional)',
                  controller: purposeController,
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );

  Widget _review() => _Card(
    child: Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _ReviewRow('Project name', projectController.text),
              _ReviewRow('Local folder', folderController.text),
              _ReviewRow(
                'GitHub',
                repoController.text.replaceFirst('https://github.com/', ''),
              ),
              _ReviewRow('Agent name', agentController.text),
              _ReviewRow(
                'Moscowt',
                '${_mascots[selectedMascot].name} — ${_mascots[selectedMascot].tagline.toLowerCase()}',
              ),
              const _ReviewRow('AI model', 'Claude Sonnet 5.5'),
            ],
          ),
        ),
        const SizedBox(width: 28),
        SizedBox(
          width: 220,
          child: Column(
            children: [
              _Mascot(size: 118, index: selectedMascot),
              const SizedBox(height: 12),
              Text(
                _mascots[selectedMascot].name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Text(
                'Ready to meet your project',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _agents() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Heading(
        'My Agents',
        'Meet your AI companions and the context they use.',
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(
            child: _StatCard(
              label: 'Local folder',
              value: r'...\Projects\moscowt-api',
              foot: 'Project workspace',
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: _StatCard(
              label: 'GitHub',
              value: 'your-org/moscowt-api',
              foot: 'Connected repository',
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: _StatCard(
              label: 'Indexed files',
              value: '1,248',
              foot: 'Updated today',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _StatCard(
              label: 'Last indexed',
              value: 'Today, 10:42 AM',
              foot: 'All files up to date',
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: _Card(
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repository context',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: .82,
                          minHeight: 7,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '1,019 of 1,248 files · indexing in the background',
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  FilledButton(
                    onPressed: () => notice('Repository indexing queued.'),
                    child: const Text('Reindex Project'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: _Card(
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GitHub token not connected',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Connect securely in Settings to sync private repos.',
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(
        child: _Card(
          child: Column(
            children: [
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search indexed files',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              for (final file in const [
                (
                  'src/routes/auth.ts',
                  'src/routes',
                  '4.2 KB',
                  'High relevance',
                ),
                (
                  'src/services/token.ts',
                  'src/services',
                  '2.8 KB',
                  'High relevance',
                ),
                ('prisma/schema.prisma', 'prisma', '6.1 KB', 'Medium'),
                (
                  'src/middleware/rateLimit.ts',
                  'src/middleware',
                  '1.4 KB',
                  'Medium',
                ),
                ('.env', 'project root', '—', 'Content hidden'),
              ])
                _FileRow(
                  name: file.$1,
                  directory: file.$2,
                  size: file.$3,
                  relevance: file.$4,
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Heading(
        'Prompt History',
        'Reopen, copy or compare anything your companion has improved.',
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search prompts',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const _ActionButton(
            'All',
            Icons.filter_list,
            onPressed: null,
            primary: true,
          ),
          const SizedBox(width: 8),
          const _ActionButton(
            'This week',
            Icons.calendar_today,
            onPressed: null,
          ),
          const SizedBox(width: 8),
          _ActionButton(project, Icons.folder_outlined, onPressed: null),
        ],
      ),
      const SizedBox(height: 18),
      Expanded(
        child: ListView(
          children: [
            if (reportsBusy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (savedPrompts.isEmpty && savedReports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Your saved prompt enhancements and project analyses will appear here.',
                  style: TextStyle(color: muted),
                ),
              ),
            if (savedPrompts.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Prompt enhancements',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final item in savedPrompts.where((item) {
                final query = searchController.text.toLowerCase().trim();
                return query.isEmpty ||
                    (item['original_prompt'] as String? ?? '')
                        .toLowerCase()
                        .contains(query) ||
                    (item['project_name'] as String? ?? '')
                        .toLowerCase()
                        .contains(query);
              }))
                _SavedPromptCard(
                  item: item,
                  onReopen: () {
                    promptController.text =
                        item['original_prompt'] as String? ?? '';
                    prompt = promptController.text;
                    enhanced = item['enhanced_prompt'] as String? ?? '';
                    go(Page.enhance);
                  },
                ),
            ],
            if (savedReports.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Project analyses',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final item in savedReports.where((item) {
                final query = searchController.text.toLowerCase().trim();
                return query.isEmpty ||
                    (item['project_name'] as String? ?? '')
                        .toLowerCase()
                        .contains(query) ||
                    (item['source'] as String? ?? '').toLowerCase().contains(
                      query,
                    );
              }))
                _SavedReportCard(
                  item: item,
                  onOpen: () => _openSavedReport(item),
                ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _repository() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Heading(
        'Project Analyzer',
        'Analyze a GitHub repository or a local project folder with NVIDIA AI.',
      ),
      const SizedBox(height: 18),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Analyze a public GitHub repository',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: repositoryAnalysisController,
                    keyboardType: TextInputType.url,
                    onSubmitted: (_) =>
                        analysisBusy ? null : analyzeRepository(),
                    decoration: const InputDecoration(
                      hintText: 'https://github.com/owner/repository',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: analysisBusy ? null : analyzeRepository,
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Analyze URL'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: analysisBusy ? null : analyzeLocalFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose local folder'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Private repositories require a secure GitHub connection. Secrets and generated files are excluded.',
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      if (analysisBusy)
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                projectSource.startsWith('https://')
                    ? 'Fetching repository and analyzing its files…'
                    : 'Scanning project files…',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              if (scannedFiles > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '$scannedFiles project files scanned',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 6),
              const Text(
                'The AI reviews source modules and dependencies in batches.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      if (analysisError != null && !analysisBusy)
        _Card(
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(width: 10),
              Expanded(child: SelectableText(analysisError!)),
            ],
          ),
        ),
      if (analysisReport != null)
        Expanded(child: _AnalysisReportView(report: analysisReport!))
      else if (!analysisBusy)
        const Expanded(
          child: Center(
            child: Text(
              'Choose a GitHub URL or a local folder to generate a complete project report.',
              style: TextStyle(color: muted),
            ),
          ),
        ),
    ],
  );

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Heading(
        'Settings',
        'Customize how Moscowt looks, behaves and protects your data.',
      ),
      const SizedBox(height: 18),
      Expanded(
        child: ListView(
          children: [
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Appearance',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Theme',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Choose how Moscowt looks on this device.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Dark', label: Text('Dark')),
                      ButtonSegment(value: 'Light', label: Text('Light')),
                      ButtonSegment(value: 'System', label: Text('System')),
                    ],
                    selected: const {'Light'},
                    onSelectionChanged: (_) {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Floating mascot',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  const _SettingSwitch(
                    title: 'Idle animation',
                    subtitle: 'Gentle floating and blinking',
                  ),
                  const _SettingSwitch(
                    title: 'Always on top',
                    subtitle: 'Keep the mascot above other windows',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'AI models',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Moscowt uses NVIDIA z-ai/glm-5.3 through authenticated Supabase Edge Functions. The NVIDIA API key stays server-side and is never stored in this Windows app.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Supabase account',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Supabase.instance.client.auth.currentUser?.email ?? '',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await Supabase.instance.client.auth.signOut();
                      } catch (error) {
                        if (mounted) notice('Could not sign out: $error');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _enhancer() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _Mascot(size: 38, index: selectedMascot),
          const SizedBox(width: 12),
          const Expanded(
            child: _Heading(
              'Enhance prompt',
              'Turn a rough request into a clear, context-aware task.',
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Enhanced', label: Text('Enhanced')),
              ButtonSegment(value: 'Compare', label: Text('Compare')),
            ],
            selected: const {'Enhanced'},
            onSelectionChanged: (_) {},
          ),
        ],
      ),
      const SizedBox(height: 18),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Original prompt',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: TextField(
                              controller: promptController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              onChanged: (value) =>
                                  setState(() => prompt = value),
                              decoration: const InputDecoration(
                                hintText: 'Describe what you want to do…',
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${promptController.text.length} chars · ~${(promptController.text.length / 4).ceil()} tokens',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    notice('Paste a prompt into the editor.'),
                                icon: const Icon(Icons.content_paste),
                                label: const Text('Paste'),
                              ),
                              TextButton.icon(
                                onPressed: () => notice(
                                  'Text capture is available in the Windows companion.',
                                ),
                                icon: const Icon(Icons.text_fields),
                                label: const Text('Capture selected text'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Repository context',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              TextButton(
                                onPressed: () => go(Page.models),
                                child: const Text('Refresh context'),
                              ),
                            ],
                          ),
                          Text(
                            '$project · 4 files found',
                            style: TextStyle(color: muted),
                          ),
                          for (final item in const [
                            (
                              'src/routes/auth.ts',
                              'Login handler — defines POST /auth/login',
                            ),
                            (
                              'src/middleware/rateLimit.ts',
                              'Existing limiter you can reuse',
                            ),
                            ('prisma/schema.prisma', 'User and Session models'),
                            (
                              'src/services/token.ts',
                              'Token helpers — lower relevance',
                            ),
                          ])
                            _ContextToggle(path: item.$1, detail: item.$2),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Enhanced prompt',
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const _Pill(
                          'Ready to copy',
                          Color(0xFFE3F7EB),
                          Color(0xFF1EAF61),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _Metric(
                          label: 'Original',
                          value:
                              '~${(promptController.text.length / 4).ceil()}',
                        ),
                        const SizedBox(width: 8),
                        _Metric(
                          label: 'Enhanced',
                          value:
                              '~${(enhanced.isEmpty ? (promptController.text.length * 1.6).ceil() / 4 : enhanced.length / 4).ceil()}',
                        ),
                        const SizedBox(width: 8),
                        const _Metric(label: 'Context files', value: '4'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          enhanced.isEmpty
                              ? 'Your improved prompt will appear here. Click “Enhance prompt” to create a clear, structured task with relevant constraints and acceptance criteria.'
                              : enhanced,
                          style: const TextStyle(height: 1.55),
                        ),
                      ),
                    ),
                    const Divider(),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: enhanced.isEmpty
                              ? enhancePrompt
                              : () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: enhanced),
                                  );
                                  notice('Enhanced prompt copied.');
                                },
                          icon: Icon(
                            enhanced.isEmpty ? Icons.auto_awesome : Icons.copy,
                          ),
                          label: Text(
                            busy
                                ? 'Enhancing…'
                                : enhanced.isEmpty
                                ? 'Enhance prompt'
                                : 'Copy Enhanced Prompt',
                          ),
                        ),
                        TextButton(
                          onPressed: enhancePrompt,
                          child: const Text('Regenerate'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => enhanced = ''),
                          child: const Text('Restore original'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Moscowt’s local C++ engine structures your prompt. Connect an AI provider in Settings for model-powered results.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

const _mascots = [
  (
    name: 'Momo',
    tagline: 'Creative · prompt improvement',
    description: 'Friendly purple robot that polishes your prompts.',
    emoji: '🤖',
    color: Color(0xFFAA79E9),
  ),
  (
    name: 'Byte',
    tagline: 'Code-aware · repository context',
    description:
        'A small blue companion with glowing eyes that reads your repo.',
    emoji: '👾',
    color: Color(0xFF55A8EC),
  ),
  (
    name: 'Pixel',
    tagline: 'Concise · token efficiency',
    description: 'A playful mint creature that keeps prompts short and clear.',
    emoji: '🐸',
    color: Color(0xFF60CCAE),
  ),
];

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.page,
    required this.onSelect,
    required this.agent,
    required this.project,
  });
  final Page page;
  final ValueChanged<Page> onSelect;
  final String agent;
  final String project;

  @override
  Widget build(BuildContext context) {
    const entries = [
      (Page.home, 'Home', Icons.home_outlined),
      (Page.setup, 'Setup Project', Icons.add_circle_outline),
      (Page.agents, 'My Agents', Icons.smart_toy_outlined),
      (Page.history, 'Prompt History', Icons.history),
      (Page.models, 'Repository Context', Icons.memory),
      (Page.settings, 'Settings', Icons.tune),
    ];
    return Container(
      width: 226,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      color: const Color(0xFFFAFAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Mascot(size: 36, index: 0),
              const SizedBox(width: 9),
              const Text(
                'Moscowt',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  dense: true,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  selected: page == entry.$1,
                  selectedTileColor: const Color(0xFFE8F2FF),
                  selectedColor: blue,
                  leading: Icon(entry.$3, size: 18),
                  title: Text(
                    entry.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onTap: () => onSelect(entry.$1),
                ),
              ),
            ),
          const Spacer(),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelect(Page.enhance),
              child: Padding(
                padding: const EdgeInsets.all(11),
                child: Row(
                  children: [
                    const _Mascot(size: 35, index: 0),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            agent.isEmpty ? 'Your Agent' : agent,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            project,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.circle, size: 9, color: Color(0xFF38C977)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 27,
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: const TextStyle(color: muted, fontSize: 13)),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
    ),
    child: child,
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(text, style: const TextStyle(fontSize: 11, color: muted)),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.trailing,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Label(label),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    ],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
    this.label,
    this.icon, {
    required this.onPressed,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) => primary
      ? FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          label: Text(label),
        );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.background, this.foreground);
  final String text;
  final Color background;
  final Color foreground;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text('•  $text', style: TextStyle(color: foreground, fontSize: 11)),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.foot,
    this.progress = false,
  });
  final String label;
  final String value;
  final String foot;
  final bool progress;
  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 7),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (progress) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            value: .82,
            minHeight: 6,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ],
        const SizedBox(height: 7),
        Text(foot, style: const TextStyle(color: muted, fontSize: 10)),
      ],
    ),
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.title,
    required this.time,
    required this.saving,
  });
  final String title;
  final String time;
  final String saving;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE5E6EA))),
    ),
    child: Row(
      children: [
        const Icon(Icons.circle, size: 8, color: blue),
        const SizedBox(width: 11),
        Expanded(child: Text(title)),
        Text(time, style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(width: 12),
        _Pill(saving, const Color(0xFFE3F7EB), const Color(0xFF1EAF61)),
      ],
    ),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.active});
  final int active;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (int index = 0; index < 3; index++) ...[
        if (index > 0)
          Expanded(
            child: Container(
              height: 2,
              color: index <= active ? blue : const Color(0xFFD7D9DF),
            ),
          ),
        CircleAvatar(
          radius: 14,
          backgroundColor: index <= active ? blue : const Color(0xFFE5E7EB),
          child: Text(
            index < active ? '✓' : '${index + 1}',
            style: TextStyle(
              color: index <= active ? Colors.white : muted,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          const ['Project details', 'Create agent', 'Review & finish'][index],
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        if (index < 2) const SizedBox(width: 16),
      ],
    ],
  );
}

class _MascotCard extends StatelessWidget {
  const _MascotCard({
    required this.index,
    required this.selected,
    required this.onTap,
  });
  final int index;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final mascot = _mascots[index];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? blue : Colors.white,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            if (selected)
              Align(
                alignment: Alignment.topRight,
                heightFactor: .7,
                child: Icon(Icons.check_circle, color: blue, size: 20),
              ),
            _Mascot(size: 70, index: index),
            const SizedBox(height: 5),
            Text(
              mascot.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              mascot.tagline,
              textAlign: TextAlign.center,
              style: const TextStyle(color: blue, fontSize: 11),
            ),
            const SizedBox(height: 5),
            Text(
              mascot.description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Mascot extends StatelessWidget {
  const _Mascot({required this.size, required this.index});
  final double size;
  final int index;
  @override
  Widget build(BuildContext context) {
    final mascot = _mascots[index];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mascot.color.withValues(alpha: .16),
        shape: BoxShape.circle,
      ),
      child: Text(mascot.emoji, style: TextStyle(fontSize: size * .62)),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.title, this.value);
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      children: [
        SizedBox(
          width: 125,
          child: Text(title, style: const TextStyle(color: muted)),
        ),
        Expanded(child: Text(value, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Label(label),
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE0E2E7)),
          ),
        ),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    ],
  );
}

class _ContextToggle extends StatefulWidget {
  const _ContextToggle({required this.path, required this.detail});
  final String path;
  final String detail;
  @override
  State<_ContextToggle> createState() => _ContextToggleState();
}

class _ContextToggleState extends State<_ContextToggle> {
  bool included = true;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 5),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFFE5E6EA))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.path,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              Text(
                widget.detail,
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ),
        Switch(
          value: included,
          onChanged: (value) => setState(() => included = value),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: canvas,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 10)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: blue,
            ),
          ),
        ],
      ),
    ),
  );
}

class _AnalysisReportView extends StatefulWidget {
  const _AnalysisReportView({required this.report});

  final Map<String, dynamic> report;

  @override
  State<_AnalysisReportView> createState() => _AnalysisReportViewState();
}

class _AnalysisReportViewState extends State<_AnalysisReportView> {
  String query = '';

  List<Map<String, dynamic>> _items(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final technologies = _items(report['technologies']);
    final dependencies = _items(report['dependencies']);
    final files = _items(report['files']);
    final normalizedQuery = query.toLowerCase().trim();
    final visibleFiles = files.where((file) {
      if (normalizedQuery.isEmpty) return true;
      return '${file['path']} ${file['module']} ${file['purpose']}'
          .toLowerCase()
          .contains(normalizedQuery);
    }).toList();
    final statistics = report['statistics'];

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report['projectName'] as String? ?? 'Project',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (statistics is Map)
                          Text(
                            '${statistics['analyzedFiles'] ?? files.length} files analyzed',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                      ],
                    ),
                    if (report['repositoryUrl'] is String) ...[
                      const SizedBox(height: 3),
                      SelectableText(
                        report['repositoryUrl'] as String,
                        style: const TextStyle(color: blue, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text(
                      'Project overview',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      report['overview'] as String? ?? 'No overview provided.',
                      style: const TextStyle(height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Architecture',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      report['architecture'] as String? ??
                          'No architecture details provided.',
                      style: const TextStyle(height: 1.5),
                    ),
                    if (statistics is Map &&
                        (statistics['omittedFiles'] as num? ?? 0) > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        '${statistics['omittedFiles']} files were not analyzed because of scan limits or unreadable content.',
                        style: const TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (statistics is Map &&
                        (statistics['truncatedFiles'] as num? ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${statistics['truncatedFiles']} large files were shortened to fit the analysis limits.',
                        style: const TextStyle(
                          color: Colors.deepOrange,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tech stack (${technologies.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 9),
                    if (technologies.isEmpty)
                      const Text(
                        'No technologies identified.',
                        style: TextStyle(color: muted),
                      )
                    else
                      for (final item in technologies)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 130,
                                child: Text(
                                  item['category'] as String? ?? 'Technology',
                                  style: const TextStyle(color: muted),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] as String? ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (item['evidence'] is String)
                                      Text(
                                        item['evidence'] as String,
                                        style: const TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dependencies (${dependencies.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (dependencies.isEmpty)
                      const Text(
                        'No dependencies identified from the project manifests.',
                        style: TextStyle(color: muted),
                      )
                    else
                      for (final item in dependencies)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${item['name'] ?? 'Unknown'}${item['dev'] == true ? ' · dev' : ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item['version'] as String? ?? '',
                                  style: const TextStyle(color: muted),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item['purpose'] as String? ??
                                      'Purpose not specified',
                                  style: const TextStyle(color: muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Files and modules (${files.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: TextField(
                            onChanged: (value) => setState(() => query = value),
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search, size: 18),
                              hintText: 'Filter files',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (visibleFiles.isEmpty)
                      const Text(
                        'No files match this search.',
                        style: TextStyle(color: muted),
                      )
                    else
                      for (final file in visibleFiles)
                        _AnalyzedFile(file: file),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recommendations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final item
                        in report['recommendations'] is List
                            ? report['recommendations'] as List
                            : const [])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.lightbulb_outline,
                              size: 17,
                              color: blue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text('$item')),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalyzedFile extends StatelessWidget {
  const _AnalyzedFile({required this.file});
  final Map<String, dynamic> file;

  @override
  Widget build(BuildContext context) {
    final functions = file['functions'] is List
        ? (file['functions'] as List).whereType<Map>().toList()
        : const <Map>[];
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 14, right: 8, bottom: 12),
      title: Text(
        file['path'] as String? ?? 'Unknown file',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${file['module'] ?? 'Module'} · ${file['purpose'] ?? 'Purpose not specified'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: muted),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Module: ${file['module'] ?? 'Unknown'}\nPurpose: ${file['purpose'] ?? 'Not specified'}',
            style: const TextStyle(height: 1.5),
          ),
        ),
        if (functions.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final item in functions)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${item['name'] ?? 'Function'} — ${item['purpose'] ?? 'Purpose not specified'}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SavedPromptCard extends StatelessWidget {
  const _SavedPromptCard({required this.item, required this.onReopen});
  final Map<String, dynamic> item;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item['project_name'] as String? ?? 'Project',
          style: const TextStyle(color: muted, fontSize: 11),
        ),
        const SizedBox(height: 5),
        Text(item['original_prompt'] as String? ?? ''),
        const Divider(height: 22),
        Text(
          item['enhanced_prompt'] as String? ?? '',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () async {
                  final text = item['enhanced_prompt'] as String? ?? '';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enhanced prompt copied.')),
                    );
                  }
                },
                child: const Text('Copy'),
              ),
              TextButton(onPressed: onReopen, child: const Text('Reopen')),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SavedReportCard extends StatelessWidget {
  const _SavedReportCard({required this.item, required this.onOpen});
  final Map<String, dynamic> item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        const Icon(Icons.folder_copy_outlined, color: blue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['project_name'] as String? ?? 'Project',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                item['source'] as String? ?? '',
                style: const TextStyle(color: muted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        TextButton(onPressed: onOpen, child: const Text('Open report')),
      ],
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.directory,
    required this.size,
    required this.relevance,
  });
  final String name, directory, size, relevance;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: const Icon(
      Icons.insert_drive_file_outlined,
      size: 18,
      color: muted,
    ),
    title: Text(
      name,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      directory,
      style: const TextStyle(fontSize: 10, color: muted),
    ),
    trailing: SizedBox(
      width: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(size, style: const TextStyle(color: muted, fontSize: 10)),
          const SizedBox(width: 9),
          Flexible(
            child: _Pill(
              relevance,
              relevance == 'Content hidden'
                  ? const Color(0xFFFFE7E5)
                  : relevance == 'Medium'
                  ? const Color(0xFFE8F2FF)
                  : const Color(0xFFE3F7EB),
              relevance == 'Content hidden'
                  ? Colors.redAccent
                  : relevance == 'Medium'
                  ? blue
                  : const Color(0xFF1EAF61),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SettingSwitch extends StatefulWidget {
  const _SettingSwitch({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  State<_SettingSwitch> createState() => _SettingSwitchState();
}

class _SettingSwitchState extends State<_SettingSwitch> {
  bool value = true;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              widget.subtitle,
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
      Switch(value: value, onChanged: (next) => setState(() => value = next)),
    ],
  );
}
