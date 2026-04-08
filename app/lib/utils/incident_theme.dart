import 'package:flutter/material.dart';

class IncidentTheme {
  final IconData icon;
  final Color color;

  const IncidentTheme({required this.icon, required this.color});

  static IncidentTheme of(String incidentType) {
    final type = incidentType.toUpperCase();

    if (_matches(type, ['FIRE', 'STRUCTURE', 'BRUSH', 'VEHICLE FIRE', 'WILDLAND'])) {
      return const IncidentTheme(icon: Icons.local_fire_department, color: Color(0xFFCC2200));
    }
    if (_matches(type, ['MEDICAL', 'EMS', 'CARDIAC', 'BREATHING', 'STROKE', 'TRAUMA', 'UNCONSCIOUS'])) {
      return const IncidentTheme(icon: Icons.medical_services, color: Color(0xFF0077CC));
    }
    if (_matches(type, ['MVA', 'ACCIDENT', 'VEHICLE', 'CRASH', 'COLLISION'])) {
      return const IncidentTheme(icon: Icons.directions_car, color: Color(0xFFE65100));
    }
    if (_matches(type, ['RESCUE', 'WATER', 'SWIFT', 'ENTRAPMENT', 'CONFINED'])) {
      return const IncidentTheme(icon: Icons.hardware, color: Color(0xFF2E7D32));
    }
    if (_matches(type, ['HAZMAT', 'GAS', 'SPILL', 'CHEMICAL'])) {
      return const IncidentTheme(icon: Icons.warning, color: Color(0xFFF9A825));
    }
    if (type == 'PRIORITY TRAFFIC') {
      return const IncidentTheme(icon: Icons.priority_high, color: Color(0xFFFF6D00));
    }
    if (type == 'MESSAGE') {
      return const IncidentTheme(icon: Icons.message, color: Color(0xFF78909C));
    }

    return const IncidentTheme(icon: Icons.report, color: Color(0xFF7B1FA2));
  }

  static bool _matches(String type, List<String> keywords) =>
      keywords.any((kw) => type.contains(kw));
}
