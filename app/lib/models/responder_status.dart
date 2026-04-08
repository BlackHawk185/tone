import 'package:tone/models/response_role.dart';

class ResponderStatus {
  final String uid;
  final String displayName;
  final String role; // e.g. 'driver', 'direct_to_scene', 'on_scene', 'delayed'
  final String updatedAt;
  final double? distanceMiles;
  final int? etaMinutes;

  const ResponderStatus({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.updatedAt,
    this.distanceMiles,
    this.etaMinutes,
  });

  factory ResponderStatus.fromMap(String uid, Map<String, dynamic> data) {
    return ResponderStatus(
      uid: uid,
      displayName: data['displayName'] as String? ?? 'Unknown',
      role: data['role'] as String? ?? 'driver',
      updatedAt: data['updatedAt'] as String? ?? '',
      distanceMiles: (data['distanceMiles'] as num?)?.toDouble(),
      etaMinutes: (data['etaMinutes'] as num?)?.toInt(),
    );
  }

  String get roleLabel => ResponseRole.fromId(role)?.label ?? role;

  bool get isOnScene => role == 'on_scene';

  String? get distStr {
    if (distanceMiles == null) return null;
    return distanceMiles! < 10
        ? distanceMiles!.toStringAsFixed(1)
        : distanceMiles!.round().toString();
  }
}
