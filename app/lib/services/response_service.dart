import 'package:cloud_firestore/cloud_firestore.dart';

class ResponseService {
  static final _db = FirebaseFirestore.instance;

  /// Update the current user's response on an incident.
  static Future<void> updateStatus({
    required String incidentId,
    required String uid,
    required String displayName,
    required String role,
    double? distanceMiles,
    int? etaMinutes,
  }) async {
    final data = <String, dynamic>{
      'displayName': displayName,
      'role': role,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (distanceMiles != null) data['distanceMiles'] = distanceMiles;
    if (etaMinutes != null) data['etaMinutes'] = etaMinutes;
    await _db.collection('incidents').doc(incidentId).update({
      'responders.$uid': data,
    });
  }

  /// Update only the role for an existing responder.
  static Future<void> updateRole({
    required String incidentId,
    required String uid,
    required String role,
  }) async {
    await _db.collection('incidents').doc(incidentId).update({
      'responders.$uid.role': role,
      'responders.$uid.updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Update only the location fields for an existing responder.
  static Future<void> updateLocation({
    required String incidentId,
    required String uid,
    required double distanceMiles,
    required int etaMinutes,
  }) async {
    await _db.collection('incidents').doc(incidentId).update({
      'responders.$uid.distanceMiles': distanceMiles,
      'responders.$uid.etaMinutes': etaMinutes,
      'responders.$uid.updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Remove the current user's response status (clear / not responding)
  static Future<void> clearStatus({
    required String incidentId,
    required String uid,
  }) async {
    await _db.collection('incidents').doc(incidentId).update({
      'responders.$uid': FieldValue.delete(),
    });
  }
}
