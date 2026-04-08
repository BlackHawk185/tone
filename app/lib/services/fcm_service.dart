import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'dispatch_alerts',
    'Dispatch Alerts',
    description: 'Incoming dispatch notifications for Tone',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> initialize() async {
    // Create the Android high-priority notification channel (no-op on web/iOS)
    if (!kIsWeb) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }

    // Request permission (iOS requires explicit ask; Android 13+ as well)
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      if (!kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        const topics = ['dispatch_fire', 'dispatch_ems', 'messages', 'priority_messages'];
        for (final topic in topics) {
          final enabled = prefs.getBool('topic_$topic') ?? true;
          if (enabled) {
            await _fcm.subscribeToTopic(topic);
          } else {
            await _fcm.unsubscribeFromTopic(topic);
          }
        }
        debugPrint('[FCM] Topics synced from preferences');
      }
    }

    // Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM] Foreground message: ${message.notification?.title}');
    });
  }

  static Future<String?> getToken() => _fcm.getToken();
}
