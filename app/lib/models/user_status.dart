import 'package:cloud_firestore/cloud_firestore.dart';

class UserStatus {
  final String uid;
  final String displayName;
  final String label;
  final DateTime expiresAt;

  const UserStatus({
    required this.uid,
    required this.displayName,
    required this.label,
    required this.expiresAt,
  });

  factory UserStatus.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserStatus(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? 'Unknown',
      label: data['customStatus'] as String? ?? '',
      expiresAt: DateTime.parse(data['statusExpiresAt'] as String),
    );
  }

  bool get isActive => DateTime.now().isBefore(expiresAt);

  Duration get remaining => expiresAt.difference(DateTime.now());
}
