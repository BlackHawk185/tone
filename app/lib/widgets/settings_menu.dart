import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tone/services/auth_service.dart';

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Settings',
      onPressed: () => _showSettingsModal(context),
    );
  }

  static void _showSettingsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => const _SettingsSheet(),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  static const _topics = {
    'dispatch_fire': 'Fire Calls',
    'dispatch_ems': 'EMS Calls',
    'priority_messages': 'Priority Traffic',
    'messages': 'Messages',
  };

  final Map<String, bool> _subscriptions = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final topic in _topics.keys) {
      _subscriptions[topic] = prefs.getBool('topic_$topic') ?? true;
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _toggle(String topic, bool value) async {
    setState(() => _subscriptions[topic] = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('topic_$topic', value);
    if (kIsWeb) return;
    if (value) {
      await FirebaseMessaging.instance.subscribeToTopic(topic);
    } else {
      await FirebaseMessaging.instance.unsubscribeFromTopic(topic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade600,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (user != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  user.displayName ?? user.email ?? 'User',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            const Text(
              'NOTIFICATIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              ..._topics.entries.map((e) => SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.value),
                    value: _subscriptions[e.key] ?? true,
                    onChanged: (v) => _toggle(e.key, v),
                  )),
            const Divider(),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.share),
              title: const Text('Share App'),
              onTap: () {
                Navigator.pop(context);
                // TODO: implement share
              },
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                await AuthService.signOut();
                if (context.mounted) context.go('/login');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
