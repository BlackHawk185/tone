/// Web-only permission helpers.
/// On non-web platforms, web_permissions_stub.dart is used instead.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as html;

String getNotificationPermission() {
  return html.Notification.permission;
}

Future<String> requestNotificationPermission() async {
  final result = await html.Notification.requestPermission().toDart;
  return result.toDart;
}

/// Returns true if the app is running as an installed PWA
/// (i.e. display-mode is standalone, not a normal browser tab).
bool isPwa() {
  return html.window
      .matchMedia('(display-mode: standalone)')
      .matches;
}

/// Trigger the browser's native PWA install dialog.
/// Only works if the browser fired beforeinstallprompt (captured in index.html).
Future<void> triggerInstallPrompt() async {
  final prompt = html.window.getProperty<JSObject?>('_deferredInstallPrompt'.toJS);
  if (prompt == null) return;
  await prompt.callMethod<JSPromise<JSAny?>>('prompt'.toJS).toDart;
  // Clear so it can't be triggered twice.
  html.window.setProperty('_deferredInstallPrompt'.toJS, JSObject());
}

/// Check geolocation permission state without triggering a browser prompt.
/// Uses raw JS interop since PermissionDescriptor isn't a typed Dart class.
/// Returns 'granted', 'denied', or 'prompt'.
Future<String> checkLocationPermission() async {
  try {
    final permissions = html.window.navigator.permissions;

    final descriptor = JSObject();
    descriptor.setProperty('name'.toJS, 'geolocation'.toJS);
    // Call query() via JS interop — returns a Promise<PermissionStatus>.
    final statusObj = await (permissions as JSObject)
        .callMethod<JSPromise<JSObject>>('query'.toJS, descriptor)
        .toDart;
    final state = statusObj.getProperty<JSString>('state'.toJS).toDart;
    return state;
  } catch (_) {
    return 'prompt';
  }
}
