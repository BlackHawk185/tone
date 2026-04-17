import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/incident.dart';
import 'package:tone/services/auth_service.dart';

class IncidentService {
  static final _db = FirebaseFirestore.instance;

  /// Real-time stream of all incidents ordered by dispatch time descending
  static Stream<List<Incident>> watchIncidents() {
    return _db
        .collection('incidents')
        .orderBy('dispatchTime', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(Incident.fromFirestore).toList());
  }

  /// Real-time stream of a single incident
  static Stream<Incident?> watchIncident(String incidentId) {
    return _db
        .collection('incidents')
        .doc(incidentId)
        .snapshots()
        .map((doc) => doc.exists ? Incident.fromFirestore(doc) : null);
  }

  /// Fetch a single incident by ID
  static Future<Incident?> getIncident(String incidentId) async {
    final doc = await _db.collection('incidents').doc(incidentId).get();
    if (!doc.exists) return null;
    return Incident.fromFirestore(doc);
  }

  /// Toggle active/inactive status for an incident
  static Future<void> setActiveStatus(String incidentId, {required bool active}) {
    return _db
        .collection('incidents')
        .doc(incidentId)
        .update({'status': active ? 'active' : 'inactive'});
  }

  /// Send a broadcast message as a lightweight MESSAGE-type incident
  static Future<void> sendMessage(String text, {bool priority = false, List<String> unitCodes = const []}) async {
    final user = AuthService.currentUser;
    final now = DateTime.now().toUtc().toIso8601String();
    final docRef = _db.collection('incidents').doc();
    await docRef.set({
      'incidentType': priority ? 'PRIORITY TRAFFIC' : 'MESSAGE',
      'incidentCategory': priority ? 'PRIORITY TRAFFIC' : 'MESSAGE',
      'serviceType': priority ? 'PRIORITY TRAFFIC' : 'MESSAGE',
      'displayLabel': text,
      'address': user?.displayName ?? 'Unknown',
      'natureOfCall': text,
      'units': <String>[],
      'unitCodes': unitCodes,
      'dispatchTime': now,
      'status': 'active',
      'narrative': <Map<String, dynamic>>[],
      'responders': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'senderUid': user?.uid,
    });
  }
}
