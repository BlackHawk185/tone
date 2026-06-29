import 'package:cloud_firestore/cloud_firestore.dart';

class UserStatus {
  final String uid;
  final String displayName;
  final String label;
  final DateTime expiresAt;
  final String managedBy;
  final String role;

  const UserStatus({
    required this.uid,
    required this.displayName,
    required this.label,
    required this.expiresAt,
    this.managedBy = '',
    this.role = '',
  });

  factory UserStatus.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserStatus(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? 'Unknown',
      label: data['customStatus'] as String? ?? '',
      expiresAt: DateTime.parse(data['statusExpiresAt'] as String),
      managedBy: data['statusManagedBy'] as String? ?? '',
      role: data['statusRole'] as String? ?? '',
    );
  }

  bool get isActive => DateTime.now().isBefore(expiresAt);
  bool get isCalendarManaged => managedBy == 'google_calendar';

  Duration get remaining => expiresAt.difference(DateTime.now());
}
