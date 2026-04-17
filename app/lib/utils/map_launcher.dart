import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:url_launcher/url_launcher.dart';
import 'package:tone/utils/map_launcher_stub.dart'
    if (dart.library.html) 'package:tone/utils/map_launcher_web.dart'
    as web;

/// Opens the device's default map app with directions to [lat],[lng].
/// Uses current location as origin, driving mode, and launches straight into navigation.
Future<void> openMap(double lat, double lng) async {
  if (kIsWeb) {
    // Bypass url_launcher on web — direct anchor click avoids popup-blocker issues
    web.openMapUrl('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving&dir_action=navigate');
    return;
  }

  Uri uri;

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // Apple Maps: current location assumed when saddr omitted, dirflg=d for driving
    // No URL parameter exists to skip the route preview screen
    uri = Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d');
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    // google.navigation scheme launches straight into turn-by-turn, current location assumed
    uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
  } else {
    uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving&dir_action=navigate');
  }

  await launchUrl(uri, mode: LaunchMode.platformDefault);
}
