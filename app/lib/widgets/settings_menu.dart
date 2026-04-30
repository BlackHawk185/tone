import 'dart:async';import 'dart:io' show Platform;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/models/user_status.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/event_service.dart';
import 'package:tone/services/user_status_service.dart';
import 'package:tone/utils/text_styles.dart';
import 'package:tone/widgets/dialog_title_bar.dart';

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({super.key});

  /// Notifies listeners when channel subscriptions change.
  static final subscriptionsChanged = ValueNotifier<int>(0);

  /// Well-known unit codes and friendly names. Used as suggestions
  /// and display labels. Users can subscribe to any code, not just these.
  static const knownUnitLabels = {
    '21523': 'District 5 (FD5)',
    'PBAMB': 'Pine Bluffs EMS',
    '21503': 'District 3 (FD3)',
    'AMR': 'AMR Ambulance',
    'DEBUG': 'Test Alerts',
  };

  /// Returns the user's subscribed unit codes from SharedPreferences.
  static Future<List<String>> getSubscribedUnitCodes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('subscribed_unit_codes') ?? [];
  }

  /// Returns unit codes the user has subscribed to for messages specifically.
  static Future<List<String>> getMessageSubscribedUnitCodes() async {
    final prefs = await SharedPreferences.getInstance();
    final codes = prefs.getStringList('subscribed_unit_codes') ?? [];
    return codes
        .where((code) => prefs.getBool('topic_messages_$code') ?? true)
        .toList();
  }

  /// Display label for a unit code.
  static String labelFor(String code) => knownUnitLabels[code] ?? code;

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
    final outerContext = context;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _SettingsSheet(outerContext: outerContext),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  final BuildContext outerContext;
  const _SettingsSheet({required this.outerContext});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  /// Local notifications plugin for sound + vibration alerts.
  static final _notifications = FlutterLocalNotificationsPlugin();
  static bool _notifInit = false;

  /// Flip to true to show the "Test Dispatch" button in settings.


  /// Channel types a user can subscribe to per unit code.
  static const _channelTypes = {
    'dispatch': _ChannelInfo('Dispatch', Icons.notifications_active),
    'priority': _ChannelInfo('Priority Traffic', Icons.warning_amber),
    'messages': _ChannelInfo('Messages', Icons.message),
  };

  /// Dynamically loaded from SharedPreferences — the unit codes this user follows.
  List<String> _subscribedCodes = [];
  final Map<String, bool> _subscriptions = {};
  bool _loaded = false;

  /// Which test tone is currently looping (null = none playing).
  String? _activeTestLabel;
  Timer? _testLoopTimer;
  int _testLoopCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _ensureNotificationsReady();
  }

  static Future<void> _ensureNotificationsReady() async {
    if (_notifInit) return;
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _notifInit = true;
    } catch (e) {
      debugPrint('[Tone] Notification init: $e');
    }
  }

  /// Toggle a test alert: first tap starts, second tap stops.
  /// Dispatch uses the full native alert sequence (TTS + beep pattern).
  /// Priority/Message use simple tone playback.
  void _toggleTestAlert({
    required String label,
    required String soundAsset,
    required List<Duration> vibrationPattern,
  }) {
    // If this tone is already playing, stop it
    if (_activeTestLabel == label) {
      _stopTestAlert();
      return;
    }
    // If a different tone is playing, stop it first
    if (_activeTestLabel != null) _stopTestAlert();

    setState(() => _activeTestLabel = label);

    if (label == 'Dispatch') {
      // Full native alert sequence: "Dispatch received" → thrum pattern → loop
      _settingsChannel.invokeMethod('startAlertSequence');
    } else if (label == 'Priority') {
      // Same native engine, different speech primer
      _settingsChannel.invokeMethod('startAlertSequence', {'speechText': 'Priority traffic received'});
    } else {
      final resName = soundAsset.replaceAll(RegExp(r'\.[^.]+$'), '');
      _testLoopCount = 0;
      _fireTestTone(resName, 0.8, vibrationPattern);
      _testLoopTimer = Timer.periodic(const Duration(milliseconds: 5500), (_) {
        if (_activeTestLabel != label) return;
        _testLoopCount++;
        final vol = (_testLoopCount * 0.05 + 0.35).clamp(0.35, 0.8);
        _fireTestTone(resName, vol, vibrationPattern);
      });
    }
  }

  void _fireTestTone(String resName, double volume, List<Duration> vibrationPattern) {
    try {
      _settingsChannel.invokeMethod('playSound', {'sound': resName, 'volume': volume});
      if (!kIsWeb) {
        final pattern = <int>[0];
        for (final d in vibrationPattern) {
          pattern.add(d.inMilliseconds);
        }
        _settingsChannel.invokeMethod('vibrate', {'pattern': pattern});
      }
    } catch (e) {
      debugPrint('[Tone] Test alert error: $e');
    }
  }

  void _speakAndVibrate(String text, List<Duration> vibrationPattern) {
    try {
      _settingsChannel.invokeMethod('speak', {'text': text});
      if (!kIsWeb && vibrationPattern.isNotEmpty) {
        final pattern = <int>[0];
        for (final d in vibrationPattern) {
          pattern.add(d.inMilliseconds);
        }
        _settingsChannel.invokeMethod('vibrate', {'pattern': pattern});
      }
    } catch (e) {
      debugPrint('[Tone] TTS error: $e');
    }
  }

  void _stopTestAlert() {
    _testLoopTimer?.cancel();
    _testLoopTimer = null;
    try {
      _settingsChannel.invokeMethod('stopAlertSequence');
      _settingsChannel.invokeMethod('stopSpeaking');
      _settingsChannel.invokeMethod('stopSound');
      _settingsChannel.invokeMethod('cancelVibration');
    } catch (_) {}
    setState(() => _activeTestLabel = null);
  }

  @override
  void dispose() {
    _stopTestAlert();
    super.dispose();
  }

  Widget _buildTestTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required String soundAsset,
    required List<Duration> vibrationPattern,
  }) {
    final isPlaying = _activeTestLabel == label;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: isPlaying ? Colors.green : null),
      title: Text(
        '$label Tone',
        style: TextStyle(color: isPlaying ? Colors.green : null),
      ),
      subtitle: Text(
        isPlaying ? 'Playing — tap to stop' : subtitle,
        style: TextStyle(
          fontSize: 11,
          color: isPlaying ? Colors.green.shade300 : null,
        ),
      ),
      trailing: Icon(
        isPlaying ? Icons.stop : Icons.play_arrow,
        size: 20,
        color: isPlaying ? Colors.green : null,
      ),
      onTap: () => _toggleTestAlert(
        label: label,
        soundAsset: soundAsset,
        vibrationPattern: vibrationPattern,
      ),
    );
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _subscribedCodes = prefs.getStringList('subscribed_unit_codes') ?? [];

    for (final code in _subscribedCodes) {
      for (final type in _channelTypes.keys) {
        final key = '${type}_$code';
        _subscriptions[key] = prefs.getBool('topic_$key') ?? true;
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

  Future<void> _addChannel(String code) async {
    if (code.isEmpty || _subscribedCodes.contains(code)) return;
    final prefs = await SharedPreferences.getInstance();
    _subscribedCodes.add(code);
    await prefs.setStringList('subscribed_unit_codes', _subscribedCodes);
    // Default: all types on — responders should receive everything until they opt out
    for (final type in _channelTypes.keys) {
      final key = '${type}_$code';
      _subscriptions[key] = true;
      await prefs.setBool('topic_$key', true);
      if (!kIsWeb) {
        await FirebaseMessaging.instance.subscribeToTopic(key);
      }
    }
    if (mounted) setState(() {});
    SettingsMenu.subscriptionsChanged.value++;
  }

  Future<void> _removeChannel(String code) async {
    final prefs = await SharedPreferences.getInstance();
    _subscribedCodes.remove(code);
    await prefs.setStringList('subscribed_unit_codes', _subscribedCodes);
    for (final type in _channelTypes.keys) {
      final key = '${type}_$code';
      _subscriptions.remove(key);
      await prefs.remove('topic_$key');
      if (!kIsWeb) {
        await FirebaseMessaging.instance.unsubscribeFromTopic(key);
      }
    }
    if (mounted) setState(() {});
    SettingsMenu.subscriptionsChanged.value++;
  }

  void _showAddChannelDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscribe to Channel'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Channel code',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final code = controller.text.trim().toUpperCase();
              Navigator.pop(ctx);
              _addChannel(code);
            },
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );
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
              style: ToneTextStyles.settingsLabel,
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
              style: ToneTextStyles.settingsLabel,
            ),
            const SizedBox(height: 4),
            // Channel subscriptions (all platforms)
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              if (_subscribedCodes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No channels subscribed. Add one below.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ..._subscribedCodes.map((code) {
                final label = SettingsMenu.labelFor(code);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _removeChannel(code),
                            child: const Icon(Icons.close, size: 16, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ..._channelTypes.entries.map((ch) {
                      final topicKey = '${ch.key}_$code';
                      if (_isAndroid) {
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(ch.value.icon, size: 18),
                          title: Text(ch.value.label, style: const TextStyle(fontSize: 13)),
                          trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                          onTap: () => _openChannelSettings(topicKey),
                        );
                      }
                      return SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        secondary: Icon(ch.value.icon, size: 18),
                        title: Text(ch.value.label, style: const TextStyle(fontSize: 13)),
                        value: _subscriptions[topicKey] ?? false,
                        onChanged: (v) => _toggle(topicKey, v),
                      );
                    }),
                  ],
                );
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showAddChannelDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Subscribe to Channel'),
              ),

            ],
            const Divider(),
            if (_subscribedCodes.contains('DEBUG')) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'TEST ALERTS'.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Colors.grey,
                  ),
                ),
              ),
              _buildTestTile(
                label: 'Dispatch',
                subtitle: '"Dispatch received" + thrum pattern',
                icon: Icons.volume_up,
                soundAsset: 'dispatch_thrum.wav',
                vibrationPattern: const [],
              ),
              _buildTestTile(
                label: 'Priority',
                subtitle: '"Priority traffic received" + thrum pattern',
                icon: Icons.record_voice_over,
                soundAsset: '',
                vibrationPattern: const [],
              ),
              _buildTestTile(
                label: 'Message',
                subtitle: 'Soft bell — informational, no urgency',
                icon: Icons.notifications_none,
                soundAsset: 'message_tone.wav',
                vibrationPattern: const [
                  Duration(milliseconds: 200),
                ],
              ),
              const Divider(),
            ],
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Create Event'),
              subtitle: const Text(
                'Schedule a training, drill, standby, or meeting',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              onTap: () => _showCreateEventDialog(context),
            ),
            const Divider(),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.share),
              title: const Text('Share App'),
              onTap: () {
                Navigator.pop(context);
                _showShareDialog(context);
              },
            ),
            const Divider(),
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

  void _showCreateEventDialog(BuildContext context) {
    showDialog(
      context: widget.outerContext,
      useRootNavigator: false,
      builder: (ctx) => const _CreateEventDialog(),
    );
  }

  void _showShareDialog(BuildContext context) {
    const downloadUrl = 'https://tone.web.app/download';
    showDialog(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Share App'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: downloadUrl,
              size: 200,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: SelectableText(
                    downloadUrl,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(const ClipboardData(text: downloadUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
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
      title: const DialogTitleBar(title: 'Set Status'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STATUS',
              style: ToneTextStyles.settingsLabel,
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
              style: ToneTextStyles.settingsLabel,
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

// ── Create Event dialog ──

class _CreateEventDialog extends StatefulWidget {
  const _CreateEventDialog();

  @override
  State<_CreateEventDialog> createState() => _CreateEventDialogState();
}

class _CreateEventDialogState extends State<_CreateEventDialog> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();

  Color _selectedColor = const Color(0xFF3949AB);
  DateTime? _scheduledTime;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  bool get _valid =>
      _titleController.text.trim().isNotEmpty && _scheduledTime != null;

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      useRootNavigator: false,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      useRootNavigator: false,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() { _saving = true; _error = null; });
    try {
      await EventService.createEvent(
        title: _titleController.text.trim(),
        color: _selectedColor.value,
        time: _scheduledTime!,
        durationMin: int.tryParse(_durationController.text.trim()),
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        notes: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel = _scheduledTime == null
        ? 'Pick date & time'
        : '${_scheduledTime!.month}/${_scheduledTime!.day}/${_scheduledTime!.year}  '
            '${TimeOfDay.fromDateTime(_scheduledTime!).format(context)}';

    return AlertDialog(
      title: DialogTitleBar(
        title: 'Create Event',
        onClose: () => Navigator.pop(context),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: '🔥 Tuesday Drill',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => showDialog(
                context: context,
                useRootNavigator: false,
                builder: (_) => AlertDialog(
                  title: const Text('Pick a color'),
                  content: SingleChildScrollView(
                    child: ColorPicker(
                      pickerColor: _selectedColor,
                      onColorChanged: (c) => setState(() => _selectedColor = c),
                      pickerAreaHeightPercent: 0.7,
                      enableAlpha: false,
                      labelTypes: const [],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _selectedColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _selectedColor.withAlpha(120),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Event color',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 14, color: Colors.grey),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDateTime,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(timeLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes, optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Location (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: (_valid && !_saving) ? _submit : null,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
