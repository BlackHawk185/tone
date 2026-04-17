import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/fcm_service.dart';
import 'package:tone/utils/web_permissions_stub.dart'
    if (dart.library.html) 'package:tone/utils/web_permissions.dart'
    as web_perms;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with WidgetsBindingObserver {
  static const _settingsChannel = MethodChannel('com.valence.tone/settings');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  // Permission state
  bool _notificationsGranted = false;
  bool _locationGranted = false;
  bool _dndGranted = false;
  bool _overlayGranted = false;
  bool _checkingPermissions = true;
  // On web, require the app to be installed as a PWA before login is accessible.
  bool _isPwa = true;

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _allGranted =>
      _isPwa &&
      _notificationsGranted &&
      _locationGranted &&
      (_isAndroid ? _dndGranted : true) &&
      (_isAndroid ? _overlayGranted : true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _checkingPermissions = true);

    try {
      // ── PWA gate (web only) ──
      if (kIsWeb) {
        final pwa = web_perms.isPwa();
        if (!pwa) {
          // Not installed — no point checking other permissions yet.
          if (mounted) setState(() {
            _isPwa = false;
            _checkingPermissions = false;
          });
          return;
        }
        setState(() => _isPwa = true);
      }

      // ── Notifications ──
      bool notifGranted = false;
      if (kIsWeb) {
        try {
          notifGranted = web_perms.getNotificationPermission() == 'granted';
        } catch (_) {
          notifGranted = false;
        }
      } else {
        final settings =
            await FirebaseMessaging.instance.getNotificationSettings();
        notifGranted =
            settings.authorizationStatus == AuthorizationStatus.authorized;
      }

      // ── Location ──
      bool locGranted = false;
      if (kIsWeb) {
        // Use the Permissions API — never triggers a browser prompt.
        final state = await web_perms.checkLocationPermission();
        locGranted = state == 'granted';
      } else {
        try {
          final locPerm = await Geolocator.checkPermission();
          locGranted = locPerm == LocationPermission.always ||
              locPerm == LocationPermission.whileInUse;
        } catch (_) {
          // Platform doesn't support location services (desktop) — treat as granted.
          locGranted = true;
        }
      }

      // ── DND (Android only) ──
      bool dndGranted = true;
      if (_isAndroid) {
        try {
          dndGranted =
              await _settingsChannel.invokeMethod<bool>('isDndAccessGranted') ??
                  false;
        } catch (_) {
          dndGranted = false;
        }
      }

      // ── Overlay / Draw over other apps (Android only) ──
      bool overlayGranted = true;
      if (_isAndroid) {
        try {
          overlayGranted =
              await _settingsChannel.invokeMethod<bool>('canDrawOverlays') ??
                  false;
        } catch (_) {
          overlayGranted = false;
        }
      }

      if (!mounted) return;
      setState(() {
        _notificationsGranted = notifGranted;
        _locationGranted = locGranted;
        _dndGranted = dndGranted;
        _overlayGranted = overlayGranted;
        _checkingPermissions = false;
      });



      if (_allGranted) {
        await FcmService.subscribeToAllTopics();
      }
    } catch (e) {
      debugPrint('[Permissions] Error checking permissions: $e');
      if (!mounted) return;
      setState(() => _checkingPermissions = false);
    }
  }

  Future<void> _requestNotifications() async {
    if (kIsWeb) {
      try {
        final result = await web_perms.requestNotificationPermission();
        if (result == 'granted') {
          setState(() => _notificationsGranted = true);
          if (_allGranted) await FcmService.subscribeToAllTopics();
        }
      } catch (e) {
        debugPrint('[Permissions] Web notification request failed: $e');
      }
    } else {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        setState(() => _notificationsGranted = true);
        if (_allGranted) await FcmService.subscribeToAllTopics();
      }
    }
  }

  Future<void> _requestLocation() async {
    try {
      if (kIsWeb) {
        // On web, requestPermission triggers the browser prompt directly
        final perm = await Geolocator.requestPermission();
        final granted = perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse;
        if (granted) {
          setState(() => _locationGranted = true);
          if (_allGranted) await FcmService.subscribeToAllTopics();
        }
      } else {
        if (!await Geolocator.isLocationServiceEnabled()) {
          await Geolocator.openLocationSettings();
          return;
        }
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
          return;
        }
        final granted = perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse;
        if (granted) {
          setState(() => _locationGranted = true);
          if (_allGranted) await FcmService.subscribeToAllTopics();
        }
      }
    } catch (_) {
      // Platform does not support Geolocator → treat as granted
      setState(() => _locationGranted = true);
    }
  }

  Future<void> _requestDnd() async {
    try {
      await _settingsChannel.invokeMethod('openDndSettings');
    } catch (e) {
      debugPrint('[Permissions] Could not open DND settings: $e');
    }
  }

  Future<void> _requestOverlay() async {
    try {
      await _settingsChannel.invokeMethod('openOverlaySettings');
    } catch (e) {
      debugPrint('[Permissions] Could not open overlay settings: $e');
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      final name = _nameController.text.trim();
      if (name.isNotEmpty) {
        await AuthService.currentUser?.updateDisplayName(name);
      }
      // Tell the autofill framework the form was submitted successfully so
      // password managers (1Password, etc.) get the save/update prompt.
      TextInput.finishAutofillContext();
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authErrorMessage(e.code));
    } on FirebaseException catch (e) {
      setState(() => _error = _authErrorMessage(e.code));
    } catch (_) {
      setState(() => _error = 'Sign in failed.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _authErrorMessage(String code) => switch (code) {
        'user-not-found' || 'invalid-email' => 'Email not recognized.',
        'wrong-password' || 'invalid-credential' => 'Incorrect password.',
        'user-disabled' => 'Account disabled.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        _ => 'Sign in failed.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _GradientOutlinedLogo(),
                const SizedBox(height: 48),
                if (_checkingPermissions)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: CircularProgressIndicator(),
                  )
                else if (!_allGranted)
                  _buildPermissionsForm()
                else
                  _buildLoginForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsForm() {
    return Column(
      children: [
        Text(
          'Grant Permissions',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Tone needs these permissions to alert you when a call drops '
          'and provide directions and ETAs to the scene.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 24,
          runSpacing: 20,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: [
            if (kIsWeb)
              _PermissionIcon(
                icon: Icons.install_desktop,
                label: 'Install App',
                granted: _isPwa,
                onTap: _isPwa ? () {} : () => web_perms.triggerInstallPrompt(),
              ),
            _PermissionIcon(
              icon: Icons.notifications,
              label: 'Notifications',
              granted: _notificationsGranted,
              onTap: _requestNotifications,
            ),
            _PermissionIcon(
              icon: Icons.location_on,
              label: 'Location',
              granted: _locationGranted,
              onTap: _requestLocation,
            ),
            if (_isAndroid) ...[
              _PermissionIcon(
                icon: Icons.do_not_disturb_off,
                label: 'Silent Mode',
                granted: _dndGranted,
                onTap: _requestDnd,
              ),
              _PermissionIcon(
                icon: Icons.open_in_new,
                label: 'Overlay',
                granted: _overlayGranted,
                onTap: _requestOverlay,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _formKey,
      child: AutofillGroup(
        onDisposeAction: AutofillContextAction.commit,
        child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
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
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _signIn(),
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter your password' : null,
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
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign In'),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _PermissionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool granted;
  final VoidCallback onTap;

  const _PermissionIcon({
    required this.icon,
    required this.label,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green : Colors.red;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withAlpha(granted ? 30 : 40),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withAlpha(120), width: 1.5),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientOutlinedLogo extends StatelessWidget {
  const _GradientOutlinedLogo();

  static const _text = 'TONE';
  static const _letterSpacing = 16.0;
  static const _fontSize = 64.0;
  static const _strokeWidth = 5.0;

  TextStyle get _baseStyle => const TextStyle(
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        fontSize: _fontSize,
        letterSpacing: _letterSpacing,
      );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient stroke layer
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => ui.Gradient.linear(
            Offset.zero,
            Offset(bounds.width, 0),
            const [Color(0xFF1565C0), Color(0xFFCC2200)],
          ),
          child: Text(
            _text,
            style: _baseStyle.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = _strokeWidth
                ..color = Colors.white,
            ),
          ),
        ),
        // White fill layer on top
        Text(
          _text,
          style: _baseStyle.copyWith(color: Colors.white),
        ),
      ],
    );
  }
}
