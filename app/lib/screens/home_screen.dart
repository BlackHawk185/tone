import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/models/on_call_entry.dart';
import 'package:tone/models/user_status.dart';
import 'package:tone/services/incident_service.dart';
import 'package:tone/services/on_call_service.dart';
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => showMessageDialog(context),
        backgroundColor: const Color(0xFFFF6D00),
        child: const Icon(Icons.message, color: Colors.white),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                StreamBuilder<List<OnCallEntry>>(
                  stream: OnCallService.watchOnCall(),
                  builder: (context, onCallSnap) {
                    return StreamBuilder<List<UserStatus>>(
                      stream: UserStatusService.watchAllStatuses(),
                      builder: (context, statusSnap) {
                        final onCall = onCallSnap.data ?? [];
                        final statuses = statusSnap.data ?? [];
                        if (onCall.isEmpty && statuses.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          width: double.infinity,
                          color: Colors.green.withAlpha(25),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // On-call entries
                                ...onCall.map((e) {
                                  final shiftEnd = DateTime.tryParse(e.shiftEnd);
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.withAlpha(20),
                                        border: Border.all(color: Colors.teal.withAlpha(60), width: 1),
                                        borderRadius: const BorderRadius.all(Radius.circular(12)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(roleIcon(e.role), size: 14, color: Colors.teal),
                                              const SizedBox(width: 6),
                                              Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: e.displayName,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 13,
                                                        color: Colors.green.shade200,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: ' - on call',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w500,
                                                        fontSize: 11,
                                                        color: Colors.green.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (e.role.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: Colors.teal.withAlpha(40),
                                                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                                                  ),
                                                  child: Text(
                                                    e.role.toUpperCase(),
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 8,
                                                      color: Colors.teal,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ),
                                              if (e.role.isNotEmpty && shiftEnd != null)
                                                const SizedBox(width: 5),
                                              if (shiftEnd != null)
                                                ShiftCountdown(shiftEnd: shiftEnd),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                                // Custom status entries
                                ...statuses.map((s) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.withAlpha(20),
                                        border: Border.all(color: Colors.amber.withAlpha(60), width: 1),
                                        borderRadius: const BorderRadius.all(Radius.circular(12)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(statusIcon(s.label), size: 14, color: Colors.amber.shade600),
                                              const SizedBox(width: 6),
                                              Text.rich(
                                                TextSpan(
                                                  children: [
                                                    TextSpan(
                                                      text: s.displayName,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 13,
                                                        color: Colors.amber.shade200,
                                                      ),
                                                    ),
                                                    TextSpan(
                                                      text: ' - ${s.label}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 11,
                                                        color: Colors.amber.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 3),
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
                        return Center(
                          child: Text('Error: ${snap.error}'),
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
            // Settings button
            Positioned(
              top: 4,
              right: 4,
              child: const SettingsMenu(),
            ),
          ],
        ),
      ),
    );
  }
}
