import 'package:intl/intl.dart';

String? deltaTime(String isoTime) {
  if (isoTime.isEmpty) return null;
  try {
    final dt = DateTime.parse(isoTime);
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative) return null;
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inDays < 1) return '${diff.inMinutes}m ago';
    return '${diff.inDays}d ago';
  } catch (_) {
    return null;
  }
}

String formatTime(String isoTime) {
  if (isoTime.isEmpty) return '';
  try {
    final dt = DateTime.parse(isoTime).toLocal();
    return DateFormat('MMM d, h:mm a').format(dt);
  } catch (_) {
    return isoTime;
  }
}
