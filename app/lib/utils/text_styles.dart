import 'package:flutter/material.dart';

/// Centralised text styles used across the app.
abstract final class ToneTextStyles {
  /// ALL-CAPS section header: ROLES, APPARATUS, etc.
  static TextStyle sectionHeader = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    color: Colors.grey[500],
  );

  /// Smaller all-caps label used in settings/config screens.
  static const TextStyle settingsLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: Colors.grey,
  );
}
