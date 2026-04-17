import 'package:flutter/material.dart';

/// A role slot that an incident needs filled (e.g. Driver, Direct to Scene).
class ResponseRole {
  final String id;
  final String label;
  final IconData icon;
  final int priority; // lower = more critical to fill first

  const ResponseRole({
    required this.id,
    required this.label,
    required this.icon,
    required this.priority,
  });

  /// Default role — what everyone does if they don't pick something else.
  static const responding = ResponseRole(
    id: 'responding',
    label: 'Responding',
    icon: Icons.fire_truck,
    priority: 0,
  );

  static const directToScene = ResponseRole(
    id: 'direct_to_scene',
    label: 'Scene',
    icon: Icons.directions_run,
    priority: 1,
  );

  static const rigOperator = ResponseRole(
    id: 'rig_operator',
    label: 'Rig Operator',
    icon: Icons.engineering,
    priority: 2,
  );

  static const entryTeam = ResponseRole(
    id: 'entry_team',
    label: 'Entry Team',
    icon: Icons.shield,
    priority: 3,
  );

  static const safety = ResponseRole(
    id: 'safety',
    label: 'Safety',
    icon: Icons.health_and_safety,
    priority: 4,
  );

  static const pcp = ResponseRole(
    id: 'pcp',
    label: 'PCP',
    icon: Icons.medical_information,
    priority: 2,
  );

  static const delayed = ResponseRole(
    id: 'delayed',
    label: 'Delayed',
    icon: Icons.schedule,
    priority: 10,
  );

  static const onScene = ResponseRole(
    id: 'on_scene',
    label: 'On Scene',
    icon: Icons.person_pin_circle,
    priority: 11,
  );

  static const support = ResponseRole(
    id: 'support',
    label: 'Support',
    icon: Icons.group,
    priority: 6,
  );

  /// All known roles by id.
  static const _all = {
    'responding': responding,
    'direct_to_scene': directToScene,
    'rig_operator': rigOperator,
    'entry_team': entryTeam,
    'pcp': pcp,
    'delayed': delayed,
    'on_scene': onScene,
    'safety': safety,
    'support': support,
  };

  static ResponseRole? fromId(String? id) => _all[id];

  /// Roles that appear on every incident type.
  static const _global = [responding, directToScene, delayed];

  /// Additional roles specific to certain incident categories.
  static const _typeSpecific = {
    'fire': [entryTeam, rigOperator, safety],
    'medical': [pcp],
    'mva': [pcp, safety],
    'rescue': [rigOperator, safety],
    'hazmat': [safety],
  };

  static List<ResponseRole> _mergeUnique(List<ResponseRole> roles) {
    final seen = <String>{};
    return roles.where((role) => seen.add(role.id)).toList();
  }

  /// Returns only the type-specific roles (no globals) for this service type.
  static List<ResponseRole> typeSpecificRoles(String serviceType) {
    final type = serviceType.toUpperCase();
    if (type == 'BOTH') {
      return _mergeUnique([
        ...?_typeSpecific['fire'],
        ...?_typeSpecific['medical'],
      ]);
    }

    String category = 'default';
    if (_matches(type, ['FIRE', 'STRUCTURE', 'BRUSH', 'VEHICLE FIRE', 'WILDLAND'])) {
      category = 'fire';
    } else if (_matches(type, ['MEDICAL', 'EMS', 'CARDIAC', 'BREATHING', 'STROKE', 'TRAUMA', 'UNCONSCIOUS'])) {
      category = 'medical';
    } else if (_matches(type, ['MVA', 'ACCIDENT', 'VEHICLE', 'CRASH', 'COLLISION'])) {
      category = 'mva';
    } else if (_matches(type, ['RESCUE', 'WATER', 'SWIFT', 'ENTRAPMENT', 'CONFINED'])) {
      category = 'rescue';
    } else if (_matches(type, ['HAZMAT', 'GAS', 'SPILL', 'CHEMICAL'])) {
      category = 'hazmat';
    }
    return _typeSpecific[category] ?? const [];
  }

  /// Returns global roles + type-specific roles for this incident.
  /// Order = display/fill priority. First in list is the default.
  static List<ResponseRole> rolesForType(String serviceType) {
    final type = serviceType.toUpperCase();
    if (type == 'BOTH') {
      return [
        ..._global.where((r) => r.id != 'delayed'),
        ..._mergeUnique([
          ...?_typeSpecific['fire'],
          ...?_typeSpecific['medical'],
        ]),
        delayed,
      ];
    }

    String category = 'default';
    if (_matches(type, ['FIRE', 'STRUCTURE', 'BRUSH', 'VEHICLE FIRE', 'WILDLAND'])) {
      category = 'fire';
    } else if (_matches(type, ['MEDICAL', 'EMS', 'CARDIAC', 'BREATHING', 'STROKE', 'TRAUMA', 'UNCONSCIOUS'])) {
      category = 'medical';
    } else if (_matches(type, ['MVA', 'ACCIDENT', 'VEHICLE', 'CRASH', 'COLLISION'])) {
      category = 'mva';
    } else if (_matches(type, ['RESCUE', 'WATER', 'SWIFT', 'ENTRAPMENT', 'CONFINED'])) {
      category = 'rescue';
    } else if (_matches(type, ['HAZMAT', 'GAS', 'SPILL', 'CHEMICAL'])) {
      category = 'hazmat';
    }

    final extras = _typeSpecific[category] ?? const [];
    // Insert type-specific roles before Delayed (which stays last among globals)
    return [
      ..._global.where((r) => r.id != 'delayed'),
      ...extras,
      delayed,
    ];
  }

  static bool _matches(String type, List<String> keywords) =>
      keywords.any((kw) => type.contains(kw));
}
