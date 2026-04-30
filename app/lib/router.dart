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
    _sub = FirebaseAuth.instance.idTokenChanges().listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthChangeNotifier();

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _AuthedRoute extends StatelessWidget {
  final Widget child;

  const _AuthedRoute({required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        final user = authSnap.data;
        if (user == null) {
          return const _AuthLoadingScreen();
        }

        return FutureBuilder<String?>(
          future: user.getIdToken(),
          builder: (context, tokenSnap) {
            if (tokenSnap.connectionState != ConnectionState.done) {
              return const _AuthLoadingScreen();
            }
            if (tokenSnap.hasError || tokenSnap.data == null) {
              return const _AuthLoadingScreen();
            }
            return child;
          },
        );
      },
    );
  }
}

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
      builder: (context, state) => const _AuthedRoute(child: HomeScreen()),
    ),
    GoRoute(
      path: '/incident/:id',
      builder: (context, state) => _AuthedRoute(
        child: IncidentScreen(
          incidentId: state.pathParameters['id']!,
        ),
      ),
    ),
    GoRoute(
      path: '/event/:id',
      builder: (context, state) => _AuthedRoute(
        child: _EventPlaceholderScreen(
          eventId: state.pathParameters['id']!,
        ),
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
