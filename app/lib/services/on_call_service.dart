import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/on_call_entry.dart';

class OnCallService {
  static final _db = FirebaseFirestore.instance;
  static final _doc = _db.collection('config').doc('onCall');

  /// Real-time stream of currently on-call responders.
  static Stream<List<OnCallEntry>> watchOnCall() {
    return _doc.snapshots().map((snap) {
      if (!snap.exists) return <OnCallEntry>[];
      final data = snap.data()!;
      final list = data['users'] as List<dynamic>? ?? [];
      return list
          .map((e) => OnCallEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((e) => e.isActive)
          .toList();
    });
  }
}
