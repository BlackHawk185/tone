import 'package:flutter/material.dart';

class IncidentTheme {
  final IconData icon;
  final Color color;

  const IncidentTheme({required this.icon, required this.color});

  /// EMS unit codes.
  static const emsUnitCodes = {'PBAMB', 'AMR'};
  /// Fire unit codes.
  static const fireUnitCodes = {'21523', '21503'};

  static const fireColor = Color(0xFFCC2200);
  static const emsColor = Color(0xFF0077CC);
  static const _unknownColor = Color(0xFF7B1FA2);

  /// Is this a fire unit code?
  static bool isFire(String code) => fireUnitCodes.contains(code);
  /// Is this an EMS unit code?
  static bool isEms(String code) => emsUnitCodes.contains(code);

  /// Returns true if the incident involves both fire and EMS units.
  static bool isMultiService(List<String> unitCodes) {
    return unitCodes.any(isEms) && unitCodes.any(isFire);
  }

  /// Returns (emsColor, fireColor) for split banner, or null if single-service.
  static (Color, Color)? splitColors(List<String> unitCodes) {
    if (!isMultiService(unitCodes)) return null;
    return (emsColor, fireColor);
  }

  /// Resolve theme from canonical serviceType.
  /// Maps FIRE, EMS, BOTH, MESSAGE, PRIORITY TRAFFIC to icon and color.
  static IncidentTheme of(String serviceType, {List<String> unitCodes = const []}) {
    final type = serviceType.toUpperCase();
    
    // Non-dispatch types
    if (type == 'PRIORITY TRAFFIC') {
      return const IncidentTheme(icon: Icons.priority_high, color: Color(0xFFFF6D00));
    }
    if (type == 'MESSAGE') {
      return const IncidentTheme(icon: Icons.message, color: Color(0xFF78909C));
    }
    
    // Dispatch types
    if (type == 'BOTH') {
      // Multi-service: fire takes visual priority (split banner handles dual display)
      return const IncidentTheme(icon: Icons.local_fire_department, color: fireColor);
    }
    if (type == 'FIRE') {
      return const IncidentTheme(icon: Icons.local_fire_department, color: fireColor);
    }
    if (type == 'EMS') {
      return const IncidentTheme(icon: Icons.medical_services, color: emsColor);
    }

    return const IncidentTheme(icon: Icons.report, color: _unknownColor);
  }
}

/// Custom painter for a diagonal split banner (EMS blue | Fire red).
class SplitBannerPainter extends CustomPainter {
  final Color leftColor;
  final Color rightColor;

  const SplitBannerPainter({required this.leftColor, required this.rightColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Left side (EMS blue) — polygon: top-left, ~60% top, ~40% bottom, bottom-left
    final leftPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.6, 0)
      ..lineTo(size.width * 0.4, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(leftPath, Paint()..color = leftColor.withAlpha(160));

    // Right side (Fire red) — polygon: ~60% top, top-right, bottom-right, ~40% bottom
    final rightPath = Path()
      ..moveTo(size.width * 0.6, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.4, size.height)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = rightColor.withAlpha(160));
  }

  @override
  bool shouldRepaint(SplitBannerPainter oldDelegate) =>
      leftColor != oldDelegate.leftColor || rightColor != oldDelegate.rightColor;
}
