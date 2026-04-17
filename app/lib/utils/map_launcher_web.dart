library;

import 'package:web/web.dart' as html;

void openMapUrl(String url) {
  final anchor = html.document.createElement('a') as html.HTMLAnchorElement
    ..href = url
    ..target = '_blank'
    ..rel = 'noopener';
  anchor.click();
}
