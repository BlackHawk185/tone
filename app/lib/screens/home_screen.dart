import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/models/user_status.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/incident_service.dart';
import 'package:tone/services/user_status_service.dart';
import 'package:tone/widgets/event_card.dart';
import 'package:tone/widgets/incident_card.dart';
import 'package:tone/widgets/message_card.dart';
import 'package:tone/widgets/message_dialog.dart';
import 'package:tone/widgets/settings_menu.dart' show SettingsMenu, statusIcon;
import 'package:tone/widgets/shift_countdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Set<String> _subscribedCodes = {};

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
    SettingsMenu.subscriptionsChanged.addListener(_loadSubscriptions);
  }

  @override
  void dispose() {
    SettingsMenu.subscriptionsChanged.removeListener(_loadSubscriptions);
    super.dispose();
  }

  Future<void> _loadSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    final codes = prefs.getStringList('subscribed_unit_codes') ?? [];
    if (mounted) setState(() => _subscribedCodes = codes.toSet());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            onPressed: () => SettingsMenu.showSettingsModal(context),
            backgroundColor: Colors.grey.shade700,
            heroTag: 'settings_fab',
            child: const Icon(Icons.settings, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: () => showMessageDialog(context),
            backgroundColor: const Color(0xFFFF6D00),
            heroTag: 'message_fab',
            child: const Icon(Icons.message, color: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                StreamBuilder<List<UserStatus>>(
                  stream: UserStatusService.watchAllStatuses(),
                  builder: (context, statusSnap) {
                    final statuses = statusSnap.data ?? [];
                    final onCall = statuses
                        .where((s) => s.label.toUpperCase() == 'ON CALL')
                        .toList();
                    final otherStatuses = statuses
                        .where((s) => s.label.toUpperCase() != 'ON CALL')
                        .toList();
                    if (onCall.isEmpty && otherStatuses.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      width: double.infinity,
                      color: Colors.blue.withAlpha(20),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ...onCall.map((s) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withAlpha(25),
                                    border: Border.all(color: Colors.blue.withAlpha(80), width: 1),
                                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(roleIcon(s.role), size: 16, color: Colors.blue.shade400),
                                      const SizedBox(width: 8),
                                      Text(
                                        s.displayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.blue.shade100,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'On Call',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                          color: Colors.blue.shade300,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      ShiftCountdown(shiftEnd: s.expiresAt, color: Colors.blue.shade400),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            ...otherStatuses.map((s) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withAlpha(20),
                                    border: Border.all(color: Colors.amber.withAlpha(60), width: 1),
                                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(statusIcon(s.label), size: 16, color: Colors.amber.shade600),
                                      const SizedBox(width: 8),
                                      Text(
                                        s.displayName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Colors.amber.shade200,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        s.label,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          color: Colors.amber.shade600,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      ShiftCountdown(shiftEnd: s.expiresAt, color: Colors.amber.shade600),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: StreamBuilder<List<AppEvent>>(
                    stream: IncidentService.watchFeed(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snap.hasError) {
                        final user = AuthService.currentUser;
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Feed read failed [20260429b]\n'
                              'signedIn=${user != null} '
                              'uid=${user?.uid ?? 'none'}\n\n'
                              'Error: ${snap.error}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      final all = (snap.data ?? []).where((e) => switch (e) {
                        DispatchEvent d =>
                          d.unitCodes.any(_subscribedCodes.contains),
                        MessageEvent() => true,
                        CalendarEvent() => true,
                      }).toList();
                      if (all.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.handyman,
                                size: 64,
                                color: Colors.amber,
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  "Where'd all the incidents go? Steve's probably broke something.",
                                  style: const TextStyle(fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: all.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: switch (all[index]) {
                            DispatchEvent e => IncidentCard(incident: e),
                            MessageEvent e => MessageCard(event: e),
                            CalendarEvent e => EventCard(event: e),
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
