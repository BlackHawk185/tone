import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/incident.dart' show NarrativeEntry;
import 'package:tone/models/responder_status.dart';

/// Root type for everything that appears in the home feed.
sealed class AppEvent {
  String get id;
  DateTime get time;
}

/// A fire/EMS dispatch from the IAR email parser.
final class DispatchEvent extends AppEvent {
  @override
  final String id;
  @override
  final DateTime time;
  final String displayLabel;
  final String serviceType; // FIRE | EMS | BOTH
  final String address;
  final String? crossStreets;
  final String? fireQuadrant;
  final String? emsDistrict;
  final List<String> units;
  final List<String> unitCodes;
  final String? priority;
  final String status;
  final String? natureOfCall;
  final List<NarrativeEntry> narrative;
  final Map<String, ResponderStatus> responders;
  final double? lat;
  final double? lng;

  DispatchEvent({
    required this.id,
    required this.time,
    required this.displayLabel,
    required this.serviceType,
    required this.address,
    this.crossStreets,
    this.fireQuadrant,
    this.emsDistrict,
    required this.units,
    required this.unitCodes,
    this.priority,
    required this.status,
    this.natureOfCall,
    this.narrative = const [],
    this.responders = const {},
    this.lat,
    this.lng,
  });

  bool get isActive => status == 'active';

  String get primaryDisplay {
    if (displayLabel.isNotEmpty) return displayLabel;
    if (serviceType == 'BOTH') return 'Multi-Agency';
    return serviceType;
  }

  factory DispatchEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawServiceType =
        (data['serviceType'] as String? ?? 'UNKNOWN').toUpperCase();
    final respondersRaw = data['responders'] as Map<String, dynamic>? ?? {};
    final responders = respondersRaw.map(
      (uid, val) =>
          MapEntry(uid, ResponderStatus.fromMap(uid, val as Map<String, dynamic>)),
    );
    final narrativeRaw = data['narrative'] as List<dynamic>? ?? [];
    final narrative = narrativeRaw
        .map((e) => NarrativeEntry.fromMap(e as Map<String, dynamic>))
        .toList();
    return DispatchEvent(
      id: doc.id,
      time: DateTime.tryParse(data['dispatchTime'] as String? ?? '') ??
          DateTime.now(),
      displayLabel: (data['displayLabel'] as String? ?? '').trim(),
      serviceType: rawServiceType,
      address: data['address'] as String? ?? 'Unknown',
      crossStreets: data['crossStreets'] as String?,
      fireQuadrant: data['fireQuadrant'] as String?,
      emsDistrict: data['emsDistrict'] as String?,
      units: List<String>.from(data['units'] as List? ?? []),
      unitCodes: List<String>.from(data['unitCodes'] as List? ?? []),
      priority: data['priority'] as String?,
      status: data['status'] as String? ?? 'active',
      natureOfCall: data['natureOfCall'] as String?,
      narrative: narrative,
      responders: responders,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
    );
  }
}

/// A broadcast message or priority traffic notice.
final class MessageEvent extends AppEvent {
  @override
  final String id;
  @override
  final DateTime time;
  final String text;
  final String senderName;
  final bool isPriority;
  final String status;

  MessageEvent({
    required this.id,
    required this.time,
    required this.text,
    required this.senderName,
    required this.isPriority,
    required this.status,
  });

  bool get isActive => status == 'active';

  factory MessageEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageEvent(
      id: doc.id,
      time: DateTime.tryParse(data['dispatchTime'] as String? ?? '') ??
          DateTime.now(),
      text: (data['displayLabel'] as String?)?.trim() ??
          (data['natureOfCall'] as String?)?.trim() ??
          '',
      senderName: data['address'] as String? ?? 'Unknown',
      isPriority:
          (data['serviceType'] as String? ?? '') == 'PRIORITY TRAFFIC',
      status: data['status'] as String? ?? 'active',
    );
  }
}

/// A scheduled department event (training, drill, meeting, etc.).
final class CalendarEvent extends AppEvent {
  @override
  final String id;
  @override
  final DateTime time; // scheduled start time
  final String title;
  final int color; // ARGB int, e.g. Colors.indigo.value
  final int? durationMin;
  final String? location;
  final double? lat;
  final double? lng;
  final String? notes;
  final String createdBy;
  final String status; // upcoming | active | completed | cancelled
  final Map<String, String> attendees; // uid → going | maybe | not_going

  CalendarEvent({
    required this.id,
    required this.time,
    required this.title,
    required this.color,
    this.durationMin,
    this.location,
    this.lat,
    this.lng,
    this.notes,
    required this.createdBy,
    required this.status,
    this.attendees = const {},
  });

  bool get isUpcoming => time.isAfter(DateTime.now());

  factory CalendarEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final attendeesRaw = data['attendees'] as Map<String, dynamic>? ?? {};
    return CalendarEvent(
      id: doc.id,
      time: (data['time'] as Timestamp).toDate(),
      title: data['title'] as String? ?? '',
      color: data['color'] as int? ?? 0xFF3949AB, // default indigo
      durationMin: data['durationMin'] as int?,
      location: data['location'] as String?,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      notes: data['notes'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      status: data['status'] as String? ?? 'upcoming',
      attendees: attendeesRaw.map((k, v) => MapEntry(k, v as String)),
    );
  }
}

/// Routes a document from the `incidents/` collection to the correct subtype.
AppEvent appEventFromIncidentDoc(DocumentSnapshot doc) {
  final data = doc.data() as Map<String, dynamic>;
  final serviceType = (data['serviceType'] as String? ?? '').toUpperCase();
  if (serviceType == 'MESSAGE' || serviceType == 'PRIORITY TRAFFIC') {
    return MessageEvent.fromFirestore(doc);
  }
  return DispatchEvent.fromFirestore(doc);
}
