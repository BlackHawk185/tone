import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tone/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      final name = _nameController.text.trim();
      if (name.isNotEmpty) {
        await AuthService.currentUser?.updateDisplayName(name);
      }
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      final code = e.code;
      final msg = switch (code) {
        'user-not-found' || 'invalid-email'       => 'Email not recognized.',
        'wrong-password' || 'invalid-credential'   => 'Incorrect password.',
        'user-disabled'                            => 'Account disabled.',
        'too-many-requests'                        => 'Too many attempts. Try again later.',
        _                                          => 'Sign in failed.',
      };
      setState(() { _error = msg; });
    } on FirebaseException catch (e) {
      final code = e.code;
      final msg = switch (code) {
        'user-not-found' || 'invalid-email'       => 'Email not recognized.',
        'wrong-password' || 'invalid-credential'   => 'Incorrect password.',
        'user-disabled'                            => 'Account disabled.',
        'too-many-requests'                        => 'Too many attempts. Try again later.',
        _                                          => 'Sign in failed.',
      };
      setState(() { _error = msg; });
    } catch (_) {
      setState(() { _error = 'Sign in failed.'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_fire_department, size: 72, color: Color(0xFFCC2200)),
                  const SizedBox(height: 12),
                  Text('TONE', style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: const Color(0xFFCC2200),
                  )),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Display Name',
                      border: OutlineInputBorder(),
                      hintText: 'How your name appears to others',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _signIn(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign In'),
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
}
