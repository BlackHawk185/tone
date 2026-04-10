import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tone/models/user_status.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/user_status_service.dart';

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSettingsModal(context),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey.shade700,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.settings, color: Colors.white, size: 28),
      ),
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
  /// Flip to true to show the "Test Dispatch" button in settings.
  static const _debugMode = true;

  static const _topics = {
    'dispatch_fire': 'Fire Calls',
    'dispatch_ems': 'EMS Calls',
    'priority_messages': 'Priority Traffic',
    'messages': 'Messages',
  };

  // Android notification channel IDs → display info
  static const _channelSounds = {
    'dispatch_fire':      _ChannelInfo('Fire Dispatch', Icons.local_fire_department),
    'dispatch_ems':       _ChannelInfo('EMS Dispatch', Icons.medical_services),
    'priority_messages':  _ChannelInfo('Priority Traffic', Icons.warning_amber),
    'messages':           _ChannelInfo('General Messages', Icons.message),
  };

  final Map<String, bool> _subscriptions = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> _loadPrefs() async {
    if (_isAndroid) {
      // Android: force-subscribe to all topics, no user toggle
      for (final topic in _topics.keys) {
        _subscriptions[topic] = true;
        await FirebaseMessaging.instance.subscribeToTopic(topic);
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      for (final topic in _topics.keys) {
        _subscriptions[topic] = prefs.getBool('topic_$topic') ?? true;
      }
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

  static const _settingsChannel = MethodChannel('com.valence.tone/settings');

  Future<void> _openChannelSettings(String channelId) async {
    try {
      await _settingsChannel.invokeMethod('openChannelSettings', {
        'channelId': channelId,
      });
    } catch (e) {
      debugPrint('[Settings] Could not open channel settings: $e');
    }
  }

  Future<void> _sendTestDispatch() async {
    // 10 second delay so you can lock the screen
    debugPrint('[Settings] Test dispatch will fire in 10 seconds...');
    await Future.delayed(const Duration(seconds: 10));
    try {
      await _settingsChannel.invokeMethod('sendTestDispatch');
    } catch (e) {
      debugPrint('[Settings] Error sending test dispatch: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    return SafeArea(
      child: SingleChildScrollView(
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
            // ── Custom Status ──
            const Text(
              'STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            StreamBuilder<UserStatus?>(
              stream: UserStatusService.watchMyStatus(),
              builder: (context, snap) {
                final status = snap.data;
                if (status != null) {
                  return _ActiveStatusTile(status: status);
                }
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Set Status'),
                  subtitle: const Text(
                    'Let the team know your availability',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  onTap: () => _showSetStatusDialog(context),
                );
              },
            ),
            const Divider(),
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
            // Android: manage notifications at the OS channel level only
            if (_isAndroid) ...[
              const Padding(
                padding: EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  'Tap to manage sound, vibration & visibility',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              ..._channelSounds.entries.map((e) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(e.value.icon, size: 20),
                    title: Text(e.value.label, style: const TextStyle(fontSize: 14)),
                    trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                    onTap: () => _openChannelSettings(e.key),
                  )),
            ]
            // iOS / web: in-app topic toggles
            else ...[
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
            ],
            const Divider(),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active),
              title: const Text('Alert Profiles'),
              subtitle: const Text(
                'Customize sound & vibration patterns',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
              onTap: () {
                Navigator.pop(context);
                context.go('/alert-profiles');
              },
            ),
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
            const Divider(),
            if (_debugMode) ...[                          
              const Text(
                'DEBUG',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bug_report, color: Colors.orange),
                title: const Text('Send Test Dispatch'),
                subtitle: const Text(
                  'Triggers a fake dispatch alert via debug channel',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _sendTestDispatch();
                },
              ),
              if (_isAndroid)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_none, size: 20),
                  title: const Text('Debug Channel Settings', style: TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                  onTap: () => _openChannelSettings('debug'),
                ),
              const Divider(),
            ],
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

  void _showSetStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => const _SetStatusDialog(),
    );
  }
}

// ── Channel info for notification sound settings ──

class _ChannelInfo {
  final String label;
  final IconData icon;
  const _ChannelInfo(this.label, this.icon);
}

// ── Active status tile shown in settings when a status is set ──

class _ActiveStatusTile extends StatelessWidget {
  final UserStatus status;
  const _ActiveStatusTile({required this.status});

  @override
  Widget build(BuildContext context) {
    final remaining = status.remaining;
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    final timeLeft = h > 0 ? '${h}h ${m}m remaining' : '${m}m remaining';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(25),
        border: Border.all(color: Colors.amber.withAlpha(80)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.amber.shade600),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Colors.amber.shade300,
                  ),
                ),
                Text(
                  timeLeft,
                  style: TextStyle(fontSize: 11, color: Colors.amber.shade600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: Colors.amber.shade600),
            tooltip: 'Clear status',
            onPressed: () => UserStatusService.clearStatus(),
          ),
        ],
      ),
    );
  }
}

// ── Dialog for setting a new custom status ──

class _SetStatusDialog extends StatefulWidget {
  const _SetStatusDialog();

  @override
  State<_SetStatusDialog> createState() => _SetStatusDialogState();
}

IconData statusIcon(String label) {
  switch (label.toUpperCase()) {
    case 'OOA':
      return Icons.wrong_location_outlined;
    case 'TRAINING':
      return Icons.school;
    case 'ON CALL':
      return Icons.phone_in_talk;
    default:
      return Icons.info_outline;
  }
}

class _SetStatusDialogState extends State<_SetStatusDialog> {
  static const _presets = ['OOA', 'Training', 'On Call'];

  final _customController = TextEditingController();
  final _hoursController = TextEditingController();
  String? _selectedPreset;
  bool _usingCustom = false;

  @override
  void dispose() {
    _customController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  String get _label {
    if (_usingCustom) return _customController.text.trim();
    return _selectedPreset ?? '';
  }

  int? get _hours {
    final v = int.tryParse(_hoursController.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Set Status')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ..._presets.map((p) => ChoiceChip(
                      avatar: Icon(statusIcon(p), size: 16),
                      label: Text(p),
                      selected: !_usingCustom && _selectedPreset == p,
                      onSelected: (_) => setState(() {
                        _usingCustom = false;
                        _selectedPreset = p;
                      }),
                    )),
                ChoiceChip(
                  label: const Text('Custom'),
                  selected: _usingCustom,
                  onSelected: (_) => setState(() {
                    _usingCustom = true;
                    _selectedPreset = null;
                  }),
                ),
              ],
            ),
            if (_usingCustom) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customController,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'e.g. VACATION',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'DURATION (HOURS)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _hoursController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 16',
                border: OutlineInputBorder(),
                isDense: true,
                suffixText: 'hours',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: (_label.isEmpty || _hours == null)
              ? null
              : () {
                  UserStatusService.setStatus(
                    label: _label,
                    duration: Duration(hours: _hours!),
                  );
                  Navigator.pop(context);
                },
          child: const Text('Set'),
        ),
      ],
    );
  }
}
