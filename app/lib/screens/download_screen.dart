import 'package:flutter/material.dart';
import 'dart:html' as html;

class DownloadScreen extends StatelessWidget {
  final String platform;

  const DownloadScreen({required this.platform});

  @override
  Widget build(BuildContext context) {
    // Auto-redirect based on platform
    Future.microtask(() {
      final url = _getDownloadUrl(platform);
      if (url != null) {
        html.window.location.href = url;
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Tone Download')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Redirecting to $platform download...'),
          ],
        ),
      ),
    );
  }

  String? _getDownloadUrl(String platform) {
    switch (platform.toLowerCase()) {
      case 'ios':
        return 'https://github.com/BlackHawk185/tone/releases/download/ios/Tone.ipa';
      case 'android':
        return 'https://github.com/BlackHawk185/tone/releases/download/android/Tone.apk';
      case 'altstore':
      case 'altstore.json':
        return 'https://raw.githubusercontent.com/BlackHawk185/tone/main/altstore.json';
      default:
        return null;
    }
  }
}
