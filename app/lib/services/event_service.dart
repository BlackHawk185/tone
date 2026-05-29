import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/services/auth_service.dart';

class EventService {
  static final _db = FirebaseFirestore.instance;
  static const _collection = 'feed';

  /// Real-time stream of a single event.
  static Stream<CalendarEvent?> watchEvent(String eventId) {
    return _db
        .collection(_collection)
        .doc(eventId)
        .snapshots()
        .map((doc) => doc.exists ? CalendarEvent.fromFirestore(doc) : null);
  }

  // Minimum event duration in minutes. Enforced silently — values below this
  // are clamped rather than rejected so the UI never needs to validate it.
  static const int _minDurationMin = 30;

  /// Create a new event in the unified feed. Returns the new document ID.
  static Future<String> createEvent({
    required String title,
    required int color,
    required DateTime time,
    int? durationMin,
    String? location,
    double? lat,
    double? lng,
    String? notes,
    List<String> notifyUnitCodes = const [],
  }) async {
    final user = AuthService.currentUser;
    if (user == null) throw StateError('Not authenticated');
    // Always store a duration so the auto-complete function can determine the
    // end time. Clamp to the minimum — never allow sub-30-minute events.
    final effectiveDuration = (durationMin == null || durationMin < _minDurationMin)
        ? _minDurationMin
        : durationMin;
    final docRef = _db.collection(_collection).doc();
    await docRef.set({
      'type': 'EVENT',
      'title': title,
      'color': color,
      'time': Timestamp.fromDate(time),
      'durationMin': effectiveDuration,
      if (location != null) 'location': location,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (notes != null) 'notes': notes,
      'createdBy': user.uid,
      'status': 'upcoming',
      'attendees': <String, dynamic>{},
      if (notifyUnitCodes.isNotEmpty) 'notifyUnitCodes': notifyUnitCodes,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Record the current user's RSVP. [rsvp] must be 'going', 'maybe', or 'not_going'.
  static Future<void> updateAttendance(String eventId, String rsvp) async {
    final user = AuthService.currentUser;
    if (user == null) return;
    await _db.collection(_collection).doc(eventId).update({
      'attendees.${user.uid}': rsvp,
    });
  }

  /// Cancel an event. Firestore rules enforce creator-only access.
  static Future<void> cancelEvent(String eventId) async {
    await _db
        .collection(_collection)
        .doc(eventId)
        .update({'status': 'cancelled'});
  }
}
