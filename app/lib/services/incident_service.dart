import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/models/incident.dart';
import 'package:tone/services/auth_service.dart';

class IncidentService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'feed';

  /// Real-time stream of the entire feed ordered by time descending.
  static Stream<List<AppEvent>> watchFeed() {
    return _db
        .collection(_collection)
        .orderBy('time', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(appEventFromFeedDoc).toList());
  }

  /// Real-time stream of a single dispatch by ID.
  static Stream<Incident?> watchIncident(String incidentId) {
    return _db
        .collection(_collection)
        .doc(incidentId)
        .snapshots()
        .map((doc) => doc.exists ? Incident.fromFirestore(doc) : null);
  }

  /// Fetch a single dispatch by ID.
  static Future<Incident?> getIncident(String incidentId) async {
    final doc = await _db.collection(_collection).doc(incidentId).get();
    if (!doc.exists) return null;
    return Incident.fromFirestore(doc);
  }

  /// Toggle active/inactive status for a dispatch.
  static Future<void> setActiveStatus(String incidentId, {required bool active}) {
    return _db
        .collection(_collection)
        .doc(incidentId)
        .update({'status': active ? 'active' : 'inactive'});
  }

  /// Send a broadcast message into the unified feed.
  static Future<void> sendMessage(String text, {bool priority = false, List<String> unitCodes = const []}) async {
    final user = AuthService.currentUser;
    final now = DateTime.now().toUtc();
    final docRef = _db.collection(_collection).doc();
    await docRef.set({
      'type': 'MESSAGE',
      'isPriority': priority,
      'displayLabel': text,
      'text': text,
      'senderName': user?.displayName ?? 'Unknown',
      'senderUid': user?.uid,
      'unitCodes': unitCodes,
      'time': Timestamp.fromDate(now),
      'dispatchTime': now.toIso8601String(),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
