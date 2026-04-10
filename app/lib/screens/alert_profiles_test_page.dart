import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tone/services/alert_profiles_service.dart';

/// Comprehensive alert profile tester and configurator
class AlertProfilesTestPage extends StatefulWidget {
  const AlertProfilesTestPage({super.key});

  @override
  State<AlertProfilesTestPage> createState() => _AlertProfilesTestPageState();
}

class _AlertProfilesTestPageState extends State<AlertProfilesTestPage> {
  // Current profile being previewed
  late AlertProfile _currentProfile =
      AlertProfilesService.allProfiles.values.first;
  late AlertProfile _previewProfile = _currentProfile;
  bool _isTesting = false;

  final List<String> _channels = [
    'dispatch_fire',
    'dispatch_ems',
    'priority_messages',
    'messages',
  ];

  final Map<String, String> _channelLabels = {
    'dispatch_fire': 'Fire Dispatch',
    'dispatch_ems': 'EMS Dispatch',
    'priority_messages': 'Priority Traffic',
    'messages': 'General Messages',
  };

  late Map<String, String> _selectedProfiles = {};
  bool _hearingImpaired = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final hearing = await AlertProfilesService.isHearingImpaired();
    final prefs = <String, String>{};
    for (final channel in _channels) {
      final profile = await AlertProfilesService.getProfileForChannel(channel);
      prefs[channel] = profile.id;
    }
    if (mounted) {
      setState(() {
        _hearingImpaired = hearing;
        _selectedProfiles = prefs;
      });
    }
  }

  Future<void> _testProfile(AlertProfile profile) async {
    setState(() {
      _isTesting = true;
      _previewProfile = profile;
    });
    await AlertProfilesService.testAlert(profile);
    setState(() => _isTesting = false);
  }

  Future<void> _setChannelProfile(String channelId, String profileId) async {
    await AlertProfilesService.setProfileForChannel(channelId, profileId);
    setState(() => _selectedProfiles[channelId] = profileId);
  }

  void _toggleHearingImpaired(bool? value) {
    if (value == null) return;
    AlertProfilesService.setHearingImpaired(value);
    setState(() => _hearingImpaired = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert Profiles'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── ACCESSIBILITY ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border.all(color: Colors.blue.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '♿ Accessibility',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Prioritize vibration over audio'),
                    subtitle: const Text(
                      'Enhances haptic feedback, reduces reliance on sound',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    value: _hearingImpaired,
                    onChanged: _toggleHearingImpaired,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── PROFILE SELECTOR ──
            const Text(
              'TEST ALERT PROFILES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildProfileGrid(),
            const SizedBox(height: 24),

            // ── CHANNEL CONFIGURATION ──
            const Text(
              'CONFIGURE BY INCIDENT TYPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            ..._channels.map((channel) => _buildChannelTile(channel)),

            const SizedBox(height: 24),

            // ── PREVIEW INFO ──
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Design Philosophy',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These profiles are designed around trauma-informed alert psychology:\n\n'
                    '• Standard: Gradual onset, low-mid frequency, rhythmic (not relentless)\n'
                    '• Minimal: Vibration-only, perfect for Station/home use\n'
                    '• Urgent: For when you need immediate, high-impact attention\n\n'
                    'Test each in the moment. The "right" profile is YOUR stress response.',
                    style: TextStyle(fontSize: 11, height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.9,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: AlertProfilesService.allProfiles.values.map((profile) {
        final isSelected = _previewProfile.id == profile.id;
        return _buildProfileCard(profile, isSelected);
      }).toList(),
    );
  }

  Widget _buildProfileCard(AlertProfile profile, bool isSelected) {
    return GestureDetector(
      onTap: _isTesting ? null : () => setState(() => _previewProfile = profile),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.grey.shade100,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      profile.description,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _isTesting ? null : () => _testProfile(profile),
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Test'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isTesting && _previewProfile.id == profile.id)
              Positioned(
                top: 8,
                right: 8,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.blue.shade600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelTile(String channelId) {
    final label = _channelLabels[channelId] ?? channelId;
    final selected = _selectedProfiles[channelId] ?? 'standard';
    final profile = AlertProfilesService.allProfiles[selected];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AlertProfilesService.allProfiles.entries.map((entry) {
              final isSelected = entry.key == selected;
              return ChoiceChip(
                label: Text(entry.value.label),
                selected: isSelected,
                onSelected: (v) {
                  if (v) _setChannelProfile(channelId, entry.key);
                },
              );
            }).toList(),
          ),
          if (profile != null) ...[
            const SizedBox(height: 8),
            Text(
              'Current: ${profile.description}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
