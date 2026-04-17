/// Stub for non-web platforms — these functions should never be called.
library;

String getNotificationPermission() => 'denied';

Future<String> requestNotificationPermission() async => 'denied';

/// On native platforms the app is always "installed", so no gate needed.
bool isPwa() => true;

/// On native platforms there is no PWA install prompt.
Future<void> triggerInstallPrompt() async {}

/// On native platforms location is checked directly via Geolocator.
Future<String> checkLocationPermission() async => 'granted';
