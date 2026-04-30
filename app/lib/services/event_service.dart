import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/services/auth_service.dart';

class EventService {
  static final _db = FirebaseFirestore.instance;

  /// Real-time stream of all events (all time, up to 30 days ahead).
  /// Cancelled events are included so they can be shown greyed out.
  static Stream<List<CalendarEvent>> watchEvents() {
    final until = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 30)),
    );
    return _db
        .collection('events')
        .where('time', isLessThan: until)
        .orderBy('time', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map(CalendarEvent.fromFirestore).toList(),
        );
  }

  /// Real-time stream of a single event.
  static Stream<CalendarEvent?> watchEvent(String eventId) {
    return _db
        .collection('events')
        .doc(eventId)
        .snapshots()
        .map((doc) => doc.exists ? CalendarEvent.fromFirestore(doc) : null);
  }

  /// Create a new event. Returns the new document ID.
  static Future<String> createEvent({
    required String title,
    required int color,
    required DateTime time,
    int? durationMin,
    String? location,
    double? lat,
    double? lng,
    String? notes,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) throw StateError('Not authenticated');
    final docRef = _db.collection('events').doc();
    await docRef.set({
      'title': title,
      'color': color,
      'time': Timestamp.fromDate(time),
      if (durationMin != null) 'durationMin': durationMin,
      if (location != null) 'location': location,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (notes != null) 'notes': notes,
      'createdBy': user.uid,
      'status': 'upcoming',
      'attendees': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Record the current user's RSVP. [rsvp] must be 'going', 'maybe', or 'not_going'.
  static Future<void> updateAttendance(String eventId, String rsvp) async {
    final user = AuthService.currentUser;
    if (user == null) return;
    await _db.collection('events').doc(eventId).update({
      'attendees.${user.uid}': rsvp,
    });
  }

  /// Cancel an event. Firestore rules enforce creator-only access.
  static Future<void> cancelEvent(String eventId) async {
    await _db
        .collection('events')
        .doc(eventId)
        .update({'status': 'cancelled'});
  }
}
