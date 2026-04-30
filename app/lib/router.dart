import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:tone/screens/login_screen.dart';
import 'package:tone/screens/home_screen.dart';
import 'package:tone/screens/incident_screen.dart';
import 'package:tone/services/auth_service.dart';

/// Bridges a Stream into a ChangeNotifier so GoRouter refreshes on auth changes.
class _AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<User?> _sub;
  _AuthChangeNotifier() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthChangeNotifier();

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: _authNotifier,
  redirect: (context, state) {
    final isLoggedIn = AuthService.isLoggedIn;
    final loc = state.matchedLocation;

    // Login is accessible only when NOT logged in
    if (loc == '/login') {
      return isLoggedIn ? '/home' : null;
    }

    // Everything else requires auth
    if (!isLoggedIn) return '/login';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/incident/:id',
      builder: (context, state) => IncidentScreen(
        incidentId: state.pathParameters['id']!,
      ),
    ),
    GoRoute(
      path: '/event/:id',
      builder: (context, state) => _EventPlaceholderScreen(
        eventId: state.pathParameters['id']!,
      ),
    ),
  ],
);

class _EventPlaceholderScreen extends StatelessWidget {
  final String eventId;
  const _EventPlaceholderScreen({required this.eventId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Event')),
      body: const Center(child: Text('Event details coming soon')),
    );
  }
}
