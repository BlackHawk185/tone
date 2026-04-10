/// Web-only permission helpers.
/// On non-web platforms, web_permissions_stub.dart is used instead.
library;

import 'dart:js_interop';
import 'package:web/web.dart' as html;

String getNotificationPermission() {
  return html.Notification.permission;
}

Future<String> requestNotificationPermission() async {
  final result = await html.Notification.requestPermission().toDart;
  return result.toDart;
}
