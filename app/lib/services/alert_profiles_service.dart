import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vibration pattern: list of durations alternating [on, off, on, off, ...]
/// All durations in milliseconds.
class VibrationPattern {
  final String name;
  final String description;
  final List<Duration> pattern;

  const VibrationPattern({
    required this.name,
    required this.description,
    required this.pattern,
  });

  /// Convert to list of milliseconds for HapticFeedback.vibrate()
  List<int> toMilliseconds() => pattern.map((d) => d.inMilliseconds).toList();
}

/// Alert profile: combines sound choice, vibration pattern, and volume settings
class AlertProfile {
  final String id; // 'standard', 'minimal', 'urgent', 'custom'
  final String label;
  final String description;
  final VibrationPattern vibration;
  final double audioVolume; // 0.0 - 1.0
  final bool enableAudio;
  final String? audioAsset; // e.g., 'assets/sounds/fire_dispatch.m4a'

  const AlertProfile({
    required this.id,
    required this.label,
    required this.description,
    required this.vibration,
    required this.audioVolume,
    required this.enableAudio,
    this.audioAsset,
  });

  String toJson() => '$id|$audioVolume|$enableAudio';

  static AlertProfile fromJson(String json, Map<String, AlertProfile> profiles) {
    final parts = json.split('|');
    final id = parts[0];
    final profile = profiles[id];
    if (profile == null) return profiles['standard']!;
    if (parts.length < 3) return profile;
    final audioVolume = double.tryParse(parts[1]) ?? profile.audioVolume;
    final enableAudio = parts[2] == 'true';
    return AlertProfile(
      id: profile.id,
      label: profile.label,
      description: profile.description,
      vibration: profile.vibration,
      audioVolume: audioVolume,
      enableAudio: enableAudio,
      audioAsset: profile.audioAsset,
    );
  }
}

/// Manages alert sound/vibration profiles per incident type
class AlertProfilesService {
  // ────────────────────────────────────────────────────────────────────────
  // VIBRATION PATTERNS
  // ────────────────────────────────────────────────────────────────────────
  // "Soothing": long pulse + micro-silence + medium pulse
  // "Minimal": gentle long pulse only (low stress)
  // "Urgent": rapid short pulses (high attention)

  static const _standardVibration = VibrationPattern(
    name: 'Standard (Soothing)',
    description: 'Long pulse + micro-silence + medium pulse. Calm but alert.',
    pattern: [
      Duration(milliseconds: 250), // on
      Duration(milliseconds: 100), // off
      Duration(milliseconds: 150), // on
      Duration(milliseconds: 200), // off
    ],
  );

  static const _minimalVibration = VibrationPattern(
    name: 'Minimal',
    description: 'Single long pulse. Gentlest option.',
    pattern: [
      Duration(milliseconds: 300), // on
      Duration(milliseconds: 100), // off
    ],
  );

  static const _urgentVibration = VibrationPattern(
    name: 'Urgent',
    description: 'Rapid short pulses. High intensity.',
    pattern: [
      Duration(milliseconds: 80), // on
      Duration(milliseconds: 60), // off
      Duration(milliseconds: 80), // on
      Duration(milliseconds: 60), // off
      Duration(milliseconds: 80), // on
      Duration(milliseconds: 200), // off
    ],
  );

  // ────────────────────────────────────────────────────────────────────────
  // ALERT PROFILES (per incident type)
  // ────────────────────────────────────────────────────────────────────────

  static final Map<String, AlertProfile> _profiles = {
    'standard': AlertProfile(
      id: 'standard',
      label: 'Standard (Soothing)',
      description: 'Calm, steady rhythm + low-frequency tone.',
      vibration: _standardVibration,
      audioVolume: 0.7,
      enableAudio: true,
      audioAsset: 'assets/sounds/dispatch_alert.m4a',
    ),
    'minimal': AlertProfile(
      id: 'minimal',
      label: 'Minimal',
      description: 'Vibration only, no sound (or very soft). Least stressful.',
      vibration: _minimalVibration,
      audioVolume: 0.0,
      enableAudio: false,
      audioAsset: null,
    ),
    'urgent': AlertProfile(
      id: 'urgent',
      label: 'Urgent',
      description: 'Rapid pulses + louder tone. High intensity.',
      vibration: _urgentVibration,
      audioVolume: 1.0,
      enableAudio: true,
      audioAsset: 'assets/sounds/dispatch_alert.m4a',
    ),
  };

  // Per-channel prefs: e.g., 'dispatch_fire' -> 'standard'
  static final Map<String, String> _channelProfiles = {
    'dispatch_fire': 'standard',
    'dispatch_ems': 'standard',
    'priority_messages': 'minimal',
    'messages': 'minimal',
  };

  static const _prefixChannel = 'alert_profile_';
  static const _prefixHearingImpaired = 'alert_hearing_impaired';

  // ────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────────────────

  /// Get all available alert profiles
  static Map<String, AlertProfile> get allProfiles => _profiles;

  /// Get the current profile for a notification channel
  static Future<AlertProfile> getProfileForChannel(String channelId) async {
    final prefs = await SharedPreferences.getInstance();
    final profileId =
        prefs.getString('$_prefixChannel$channelId') ?? _channelProfiles[channelId] ?? 'standard';
    return _profiles[profileId] ?? _profiles['standard']!;
  }

  /// Set profile for a channel
  static Future<void> setProfileForChannel(String channelId, String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefixChannel$channelId', profileId);
  }

  /// Check if user has indicated they're hearing impaired (prioritize vibration)
  static Future<bool> isHearingImpaired() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefixHearingImpaired) ?? false;
  }

  /// Set whether to prioritize vibration over audio
  static Future<void> setHearingImpaired(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefixHearingImpaired, value);
  }

  /// Test alert: vibrate + optional audio
  static Future<void> testAlert(AlertProfile profile) async {
    // Vibrate with pattern
    if (Platform.isAndroid || Platform.isIOS) {
      await HapticFeedback.vibrate();
      await _vibrationPattern(profile.vibration);
    }

    // Play sound (placeholder for now)
    if (profile.enableAudio && profile.audioAsset != null) {
      debugPrint('[Alert] Would play audio: ${profile.audioAsset} @ ${profile.audioVolume}');
      // TODO: integrate audio player when ready
    }
  }

  /// Trigger full alert (called by notification handler)
  static Future<void> fireAlert(AlertProfile profile) async {
    // In production, this is called when notification arrives
    await testAlert(profile);
  }

  // ────────────────────────────────────────────────────────────────────────
  // PRIVATE
  // ────────────────────────────────────────────────────────────────────────

  /// Execute vibration pattern with proper timing
  static Future<void> _vibrationPattern(VibrationPattern pattern) async {
    // For now, just do a simple feedback. Real implementation would need
    // a custom native channel to handle complex patterns on Android.
    // iOS has limited control, so we do best-effort haptic feedback.

    try {
      for (int i = 0; i < pattern.pattern.length; i++) {
        final duration = pattern.pattern[i];
        // Odd indices are "off" (silence), even are "on" (vibrate)
        if (i.isEven && duration.inMilliseconds > 0) {
          // This is a vibration pulse
          await HapticFeedback.mediumImpact();
        }
        // Sleep for the duration (both on and off)
        await Future.delayed(duration);
      }
    } catch (e) {
      debugPrint('[Alert] Vibration pattern error: $e');
    }
  }
}
