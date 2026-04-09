import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:tone/models/user_status.dart';
import 'package:tone/services/auth_service.dart';

class UserStatusService {
  static final _db = FirebaseFirestore.instance;

  /// Set a custom status for the current user with a duration.
  static Future<void> setStatus({
    required String label,
    required Duration duration,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) return;
    final expiresAt = DateTime.now().add(duration);
    await _db.collection('users').doc(user.uid).set({
      'displayName': user.displayName ?? user.email ?? 'Unknown',
      'customStatus': label,
      'statusExpiresAt': expiresAt.toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// Clear the current user's custom status.
  static Future<void> clearStatus() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    await _db.collection('users').doc(user.uid).update({
      'customStatus': FieldValue.delete(),
      'statusExpiresAt': FieldValue.delete(),
    });
  }

  /// Stream the current user's status (for settings UI).
  static Stream<UserStatus?> watchMyStatus() {
    final user = AuthService.currentUser;
    if (user == null) return Stream.value(null);
    return _db.collection('users').doc(user.uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      if (data['customStatus'] == null || data['statusExpiresAt'] == null) {
        return null;
      }
      final status = UserStatus.fromFirestore(doc);
      return status.isActive ? status : null;
    });
  }

  /// Stream all active custom statuses across the department.
  static Stream<List<UserStatus>> watchAllStatuses() {
    return _db.collection('users').snapshots().map((snap) {
      return snap.docs
          .where((doc) {
            final data = doc.data();
            return data.containsKey('customStatus') &&
                data.containsKey('statusExpiresAt') &&
                (data['customStatus'] as String?)?.isNotEmpty == true;
          })
          .map((doc) => UserStatus.fromFirestore(doc))
          .where((s) => s.isActive)
          .toList();
    });
  }
}
