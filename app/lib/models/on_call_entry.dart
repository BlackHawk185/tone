class OnCallEntry {
  final String uid;
  final String displayName;
  final String role;
  final String shiftStart;
  final String shiftEnd;
  final int? wiwUserId;

  const OnCallEntry({
    required this.uid,
    required this.displayName,
    this.role = '',
    required this.shiftStart,
    required this.shiftEnd,
    this.wiwUserId,
  });

  factory OnCallEntry.fromMap(Map<String, dynamic> data) {
    return OnCallEntry(
      uid: data['uid'] as String? ?? '',
      displayName: data['displayName'] as String? ?? 'Unknown',
      role: data['role'] as String? ?? '',
      shiftStart: data['shiftStart'] as String? ?? '',
      shiftEnd: data['shiftEnd'] as String? ?? '',
      wiwUserId: data['wiwUserId'] as int?,
    );
  }

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'displayName': displayName,
    'role': role,
    'shiftStart': shiftStart,
    'shiftEnd': shiftEnd,
    if (wiwUserId != null) 'wiwUserId': wiwUserId,
  };

  /// Returns true if shift is currently active.
  bool get isActive {
    final now = DateTime.now();
    final start = DateTime.tryParse(shiftStart);
    final end = DateTime.tryParse(shiftEnd);
    if (start == null || end == null) return false;
    return now.isAfter(start) && now.isBefore(end);
  }

  /// Human-readable end time, e.g. "0600".
  String get endLabel {
    final end = DateTime.tryParse(shiftEnd);
    if (end == null) return '??';
    final h = end.hour.toString().padLeft(2, '0');
    final m = end.minute.toString().padLeft(2, '0');
    return '$h$m';
  }
}
