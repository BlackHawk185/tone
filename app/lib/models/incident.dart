import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/responder_status.dart';

class NarrativeEntry {
  final String time;
  final String author;
  final String text;

  const NarrativeEntry({
    required this.time,
    required this.author,
    required this.text,
  });

  factory NarrativeEntry.fromMap(Map<String, dynamic> data) {
    return NarrativeEntry(
      time:   data['time']   as String? ?? '',
      author: data['author'] as String? ?? '',
      text:   data['text']   as String? ?? '',
    );
  }
}

class Incident {
  final String incidentId;
  final String incidentType;
  final String address;
  final String? crossStreets;
  final String? fireQuadrant;
  final String? emsDistrict;
  final List<String> units;
  final String? priority;
  final String dispatchTime;
  final String status;
  final String? natureOfCall;
  final List<NarrativeEntry> narrative;
  final Map<String, ResponderStatus> responders;
  final double? lat;
  final double? lng;

  const Incident({
    required this.incidentId,
    required this.incidentType,
    required this.address,
    this.crossStreets,
    this.fireQuadrant,
    this.emsDistrict,
    required this.units,
    this.priority,
    required this.dispatchTime,
    required this.status,
    this.natureOfCall,
    this.narrative = const [],
    this.responders = const {},
    this.lat,
    this.lng,
  });

  factory Incident.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final respondersRaw = data['responders'] as Map<String, dynamic>? ?? {};
    final responders = respondersRaw.map((uid, val) =>
        MapEntry(uid, ResponderStatus.fromMap(uid, val as Map<String, dynamic>)));

    final narrativeRaw = data['narrative'] as List<dynamic>? ?? [];
    final narrative = narrativeRaw
        .map((e) => NarrativeEntry.fromMap(e as Map<String, dynamic>))
        .toList();

    return Incident(
      incidentId:   doc.id,
      incidentType: data['incidentType']  as String? ?? 'Unknown',
      address:      data['address']       as String? ?? 'Unknown',
      crossStreets: data['crossStreets']  as String?,
      fireQuadrant: data['fireQuadrant']  as String?,
      emsDistrict:  data['emsDistrict']   as String?,
      units:        List<String>.from(data['units'] as List? ?? []),
      priority:     data['priority']      as String?,
      dispatchTime: data['dispatchTime']  as String? ?? '',
      status:       data['status']        as String? ?? 'active',
      natureOfCall: data['natureOfCall']  as String?,
      narrative:    narrative,
      responders:   responders,
      lat:          (data['lat']  as num?)?.toDouble(),
      lng:          (data['lng']  as num?)?.toDouble(),
    );
  }

  bool get isActive => status == 'active';
  bool get isMessage => incidentType == 'MESSAGE' || incidentType == 'PRIORITY TRAFFIC';
  bool get isPriorityMessage => incidentType == 'PRIORITY TRAFFIC';
}
