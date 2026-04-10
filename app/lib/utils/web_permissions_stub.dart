/// Stub for non-web platforms — these functions should never be called.
library;

String getNotificationPermission() => 'denied';

Future<String> requestNotificationPermission() async => 'denied';
