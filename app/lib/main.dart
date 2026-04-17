import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tone/router.dart';
import 'package:tone/screens/dispatch_alert_screen.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/fcm_service.dart';
import 'package:tone/services/response_service.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint(
    '[FCM] Background/Quit message received: ${message.notification?.title}',
  );
  debugPrint('[FCM] Background message data: ${message.data}');
  // Background messages are already shown by Firebase if they have notification,
  // but we log it here for debugging. In production, you might save to local DB.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await FcmService.initialize();
  runApp(const ToneApp());
}

class ToneApp extends StatefulWidget {
  const ToneApp({super.key});

  @override
  State<ToneApp> createState() => _ToneAppState();
}

class _ToneAppState extends State<ToneApp> {
  static const _settingsChannel = MethodChannel('com.valence.tone/settings');
  late final _notificationSubscription;
  late final _dispatchAlertSubscription;

  /// Global navigator key for showing overlays from outside widget tree
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // Listen for native dispatch alerts (app brought to foreground by DispatchMessagingService)
    if (!kIsWeb) {
      _settingsChannel.setMethodCallHandler((call) async {
        if (call.method == 'onDispatchAlert') {
          final data = Map<String, dynamic>.from(call.arguments as Map);
          debugPrint('[App] Native dispatch alert: ${data['incidentId']}');
          _showDispatchAlert(data);
        }
      });

      // Check if we were launched by a dispatch intent
      _checkPendingDispatch();
    }

    // Listen for notification taps and navigate to incident
    _notificationSubscription =
        FcmService.notificationTapStream.listen((notificationData) {
      final incidentId = notificationData['incidentId'];
      if (incidentId != null && mounted) {
        debugPrint('[App] Navigating to incident: $incidentId');

        // Quick-respond: mark responding immediately, then navigate
        if (notificationData['quickRespond'] == 'true') {
          _quickRespond(incidentId);
        }

        appRouter.go('/home');
        appRouter.push('/incident/$incidentId');
      }
    });

    // Listen for dispatch alerts to show full-screen overlay
    _dispatchAlertSubscription =
        FcmService.dispatchAlertStream.listen((data) {
      debugPrint('[App] Dispatch alert received: ${data['incidentId']}');
      _showDispatchAlert(data);
    });
  }

  Future<void> _checkPendingDispatch() async {
    // Small delay so the navigator is mounted
    await Future.delayed(const Duration(milliseconds: 800));
    try {
      final result = await _settingsChannel.invokeMethod('getPendingDispatch');
      if (result != null) {
        final data = Map<String, dynamic>.from(result as Map);
        debugPrint('[App] Pending dispatch from native: ${data['incidentId']}');
        _showDispatchAlert(data);
      }
    } catch (e) {
      debugPrint('[App] Error checking pending dispatch: $e');
    }
  }

  Future<void> _quickRespond(String incidentId) async {
    final user = AuthService.currentUser;
    if (user == null) return;
    final name = user.displayName ?? user.email?.split('@').first ?? 'Unknown';
    try {
      await ResponseService.updateStatus(
        incidentId: incidentId,
        uid: user.uid,
        displayName: name,
        role: 'responding',
      );
      debugPrint('[App] Quick-respond success for $incidentId');
    } catch (e) {
      debugPrint('[App] Quick-respond error: $e');
    }
  }

  void _showDispatchAlert(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    final units = data['units'];
    List<String> unitList = [];
    if (units is String && units.isNotEmpty) {
      try {
        unitList = List<String>.from(jsonDecode(units));
      } catch (_) {
        unitList = [units];
      }
    }

    final uCodes = data['unitCodes'];
    List<String> unitCodeList = [];
    if (uCodes is String && uCodes.isNotEmpty) {
      try {
        unitCodeList = List<String>.from(jsonDecode(uCodes));
      } catch (_) {}
    }

    nav.push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => DispatchAlertScreen(
          incidentId: data['incidentId'] ?? '',
          serviceType: data['serviceType'] ?? data['incidentType'] ?? 'UNKNOWN',
          displayLabel: data['displayLabel'] ?? data['natureOfCall'] ?? '',
          address: data['address'] ?? 'Unknown',
          natureOfCall: data['natureOfCall'],
          units: unitList,
          unitCodes: unitCodeList,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    ).then((result) {
      if (result == 'view' || result == 'responded') {
        final incidentId = data['incidentId'];
        if (incidentId != null) {
          // go('/home') sets the base, push adds incident on top
          // so the back button returns to home
          appRouter.go('/home');
          appRouter.push('/incident/$incidentId');
        }
      }
    });
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    _dispatchAlertSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Navigator(
        key: navigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => MaterialApp.router(
          title: 'Tone',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.black,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.white,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          routerConfig: appRouter,
        ),
      ),
    ),
    );
  }
}
