import 'dart:async' show StreamController;
import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FcmService {
  static final _fcm = FirebaseMessaging.instance;
  static const _settingsChannel = MethodChannel('com.valence.tone/settings');

  /// Stream for notification tap events - listen to this to handle navigation
  static final _notificationTapStream = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get notificationTapStream => _notificationTapStream.stream;

  /// Stream for dispatch alerts - triggers the full-screen alert overlay
  static final _dispatchAlertStream = StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get dispatchAlertStream => _dispatchAlertStream.stream;

  static Future<void> initialize() async {
    // On web, skip token fetch and topic subscription — the browser will
    // prompt for notification permission if we call getToken() here.
    // Permission is requested explicitly by the user tapping the badge
    // on the login screen, after which subscribeToAllTopics() is called.
    if (!kIsWeb) {
      try {
        final token = await _fcm.getToken();
        debugPrint('[FCM] Device FCM token: $token');
      } catch (e) {
        debugPrint('[FCM] Error getting token: $e');
      }
      await subscribeToAllTopics();
    }

    // Set up token refresh listener (in case token changes)
    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] Token refreshed: $newToken');
    });

    // Foreground message handler — check OS channel toggle before showing
    // the full-screen dispatch alert overlay.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('[FCM] Foreground message: ${message.data}');

      final serviceType = message.data['serviceType'] ?? 'UNKNOWN';
      if (serviceType != 'MESSAGE' && message.data.containsKey('incidentId')) {
        final channel = message.data['channel'] ?? 'dispatch_PBAMB';
        if (!kIsWeb && Platform.isAndroid) {
          final enabled = await isChannelEnabled(channel);
          if (!enabled) {
            debugPrint('[FCM] Channel "$channel" disabled, suppressing alert');
            return;
          }
        }
        debugPrint('[FCM] Emitting dispatch alert for full-screen overlay');
        _dispatchAlertStream.add(message.data.cast<String, dynamic>());
      }
    });

    // Handle when notification is tapped while app is in background/quit
    // (iOS still shows APNS notifications; this handles taps on those)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] App opened from notification: ${message.data}');
      _routeMessage(message.data);
    });

    // Handle app launched from notification (cold start)
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] App launched from notification: ${initialMessage.data}');
      // Short delay so the widget tree is ready for the overlay push
      Future.delayed(const Duration(milliseconds: 600), () {
        _routeMessage(initialMessage.data);
      });
    }
  }

  /// Route an incoming message to either the full-screen dispatch alert
  /// or a plain navigation depending on type.
  static void _routeMessage(Map<String, dynamic> data) {
    final serviceType = data['serviceType'] ?? 'UNKNOWN';
    if (serviceType != 'MESSAGE' && data.containsKey('incidentId')) {
      debugPrint('[FCM] Routing to dispatch alert overlay');
      _dispatchAlertStream.add(Map<String, dynamic>.from(data));
    } else {
      _handleNotificationData(data);
    }
  }

  /// Navigate to incident based on notification data
  static void _handleNotificationData(Map<String, dynamic> data) {
    final incidentId = data['incidentId'];
    if (incidentId != null) {
      debugPrint('[FCM] Notification action: navigate to incident $incidentId');
      _notificationTapStream.add(data);
    }
  }

  /// Subscribe to FCM topics based on the user's dynamic channel subscriptions.
  /// Each subscribed unit code gets topics like dispatch_21523, priority_21523, etc.
  /// On web, also fetches the FCM token (safe to call only after notification permission granted).
  static Future<void> subscribeToAllTopics() async {
    if (kIsWeb) {
      try {
        final token = await _fcm.getToken();
        debugPrint('[FCM] Web FCM token: $token');
      } catch (e) {
        debugPrint('[FCM] Error getting web token: $e');
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final codes = prefs.getStringList('subscribed_unit_codes') ?? [];
    const types = ['dispatch', 'priority', 'messages'];

    for (final code in codes) {
      for (final type in types) {
        final topic = '${type}_$code';
        final enabled = prefs.getBool('topic_$topic') ?? true;
        if (enabled) {
          await _fcm.subscribeToTopic(topic);
        } else {
          await _fcm.unsubscribeFromTopic(topic);
        }
      }
    }
    debugPrint('[FCM] Topics synced for ${codes.length} unit codes');
  }

  static Future<String?> getToken() => _fcm.getToken();

  /// Check if an Android notification channel is enabled at the OS level.
  static Future<bool> isChannelEnabled(String channelId) async {
    try {
      final result = await _settingsChannel.invokeMethod(
        'isChannelEnabled',
        {'channelId': channelId},
      );
      return result == true;
    } catch (e) {
      debugPrint('[FCM] Error checking channel enabled: $e');
      return true; // Assume enabled on error
    }
  }
}
