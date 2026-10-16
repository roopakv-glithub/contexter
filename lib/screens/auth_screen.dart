import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creatingAccount = false;
  bool _working = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 8) {
      setState(
        () => _message =
            'Enter an email and a password with at least 8 characters.',
      );
      return;
    }

    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_creatingAccount) {
        final response = await auth.signUp(email: email, password: password);
        if (response.session == null && mounted) {
          setState(
            () => _message =
                'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (error) {
      if (mounted) setState(() => _message = 'Sign-in failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Moscowt',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _creatingAccount
                      ? 'Create an account to analyze and save projects.'
                      : 'Sign in to analyze projects and access your saved reports.',
                  style: const TextStyle(color: Color(0xFF858A95)),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _working ? null : _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Password (8+ characters)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _working ? null : _submit,
                  child: Text(
                    _working
                        ? 'Please wait…'
                        : _creatingAccount
                        ? 'Create account'
                        : 'Sign in',
                  ),
                ),
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() {
                          _creatingAccount = !_creatingAccount;
                          _message = null;
                        }),
                  child: Text(
                    _creatingAccount
                        ? 'Already have an account? Sign in'
                        : 'New to Moscowt? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
