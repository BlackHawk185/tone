import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tone/models/incident.dart';
import 'package:tone/models/response_role.dart';
import 'package:tone/models/on_call_entry.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/incident_service.dart';
import 'package:tone/services/location_service.dart';
import 'package:tone/services/on_call_service.dart';
import 'package:tone/utils/incident_theme.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/widgets/bounce_on_change.dart';
import 'package:tone/widgets/info_tile.dart';
import 'package:tone/widgets/live_elapsed.dart';
import 'package:tone/widgets/pulsing_dot.dart';
import 'package:tone/widgets/settings_menu.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showMessageDialog(context),
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
                    final onCall = onCallSnap.data ?? [];
                    if (onCall.isEmpty) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      color: Colors.green.withAlpha(25),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: onCall.map((e) {
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
                                            Icon(_roleIcon(e.role), size: 14, color: Colors.teal),
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
                                              _ShiftCountdown(shiftEnd: shiftEnd),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: StreamBuilder<List<Incident>>(
                    stream: IncidentService.watchIncidents(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final incidents = snapshot.data ?? [];
                      if (incidents.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                              SizedBox(height: 12),
                              Text('No active incidents', style: TextStyle(fontSize: 18)),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: incidents.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: IncidentCard(incident: incidents[index]),
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

void _showMessageDialog(BuildContext context, {String initialText = ''}) {
  final controller = TextEditingController(text: initialText);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Broadcast Message'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          hintText: 'Message to all responders...',
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
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(ctx);
            _confirmSend(context, text, priority: false);
          },
          child: const Text('Send'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)),
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(ctx);
            _confirmSend(context, text, priority: true);
          },
          child: const Text('Priority'),
        ),
      ],
    ),
  );
}

void _confirmSend(BuildContext context, String text, {required bool priority}) {
  final color = priority ? const Color(0xFFFF6D00) : Theme.of(context).colorScheme.primary;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          if (priority) const Icon(Icons.priority_high, color: Color(0xFFFF6D00)),
          if (priority) const SizedBox(width: 8),
          Text(priority ? 'Confirm Priority Traffic' : 'Confirm Message'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            priority ? 'This will alert all responders:' : 'Send this message?',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              border: Border.all(color: color.withAlpha(80)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            _showMessageDialog(context, initialText: text);
          },
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: priority ? FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6D00)) : null,
          onPressed: () {
            IncidentService.sendMessage(text, priority: priority);
            Navigator.pop(ctx);
          },
          child: Text(priority ? 'Send Priority' : 'Send'),
        ),
      ],
    ),
  );
}

class IncidentCard extends StatefulWidget {
  final Incident incident;
  const IncidentCard({super.key, required this.incident});

  @override
  State<IncidentCard> createState() => _IncidentCardState();
}

class _IncidentCardState extends State<IncidentCard>
    with SingleTickerProviderStateMixin {
  Future<_DistEta?>? _distEtaFuture;
  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    final i = widget.incident;
    if (i.lat != null && i.lng != null) {
      _distEtaFuture = _fetchDistEta(i.lat!, i.lng!);
    }
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeIn);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final isActive = incident.isActive;
    final iTheme = IncidentTheme.of(incident.incidentType);
    final uid = AuthService.currentUser?.uid;
    final myStatus = uid != null ? incident.responders[uid] : null;

    // When inactive, all accent colours are replaced with grey
    Color tileColor(Color active) => isActive ? active : Colors.grey;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Card(
      color: Theme.of(context).colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push('/incident/${incident.incidentId}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coloured type header
            Container(
              color: isActive ? iTheme.color : Colors.grey.withAlpha(60),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(iTheme.icon, color: isActive ? Colors.white : Colors.grey.shade400, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: incident.incidentType,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.grey.shade400,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.6,
                            ),
                          ),
                          if (incident.isMessage)
                            TextSpan(
                              text: ' — ${incident.address}',
                              style: TextStyle(
                                color: isActive ? Colors.white70 : Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                                letterSpacing: 0.3,
                              ),
                            )
                          else if (incident.natureOfCall != null)
                            TextSpan(
                              text: ' — ${incident.natureOfCall}',
                              style: TextStyle(
                                color: isActive ? Colors.white70 : Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                                fontSize: 11,
                                letterSpacing: 0.3,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isActive && !incident.isMessage)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha(60),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'CLOSED',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Body
            Padding(
              padding: const EdgeInsets.all(10),
              child: incident.isMessage
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          incident.natureOfCall ?? '',
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                        const SizedBox(height: 8),
                        LiveElapsed(dispatchTime: incident.dispatchTime),
                      ],
                    )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                    // Info tiles (single row)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Role badges
                          ...() {
                            final allRoles = ResponseRole.rolesForType(incident.incidentType);
                            final roleCount = <String, int>{};
                            for (final r in incident.responders.values) {
                              if (r.role != null) {
                                roleCount[r.role!] = (roleCount[r.role!] ?? 0) + 1;
                              }
                            }
                            return allRoles
                                .where((role) => roleCount.containsKey(role.id))
                                .map((role) {
                                  final isMyRole = myStatus?.role == role.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: BounceOnChange(
                                      bounceKey: isMyRole ? (myStatus!.role ?? 'rig') : 'inactive',
                                      child: InfoTile(
                                        icon: role.icon,
                                        label: role.label.toUpperCase(),
                                        value: '${roleCount[role.id]}',
                                        color: isActive
                                            ? (role.id == 'delayed' ? Colors.amber : Colors.green)
                                            : Colors.grey,
                                        suffix: (isActive && isMyRole) ? const PulsingDot(color: Colors.green) : null,
                                      ),
                                    ),
                                  );
                                });
                          }(),
                          InfoTile(icon: Icons.location_on, label: 'ADDRESS', value: incident.address, color: tileColor(Colors.orange),
                            onTap: incident.lat != null && incident.lng != null
                                ? () => openMap(incident.lat!, incident.lng!)
                                : null),
                          const SizedBox(width: 8),
                          LiveElapsed(dispatchTime: incident.dispatchTime),
                          if (isActive && _distEtaFuture != null)
                            FutureBuilder<_DistEta?>(
                              future: _distEtaFuture,
                              builder: (context, snap) {
                                if (snap.data == null) return const SizedBox.shrink();
                                return _FadeIn(
                                  child: Row(children: [
                                  const SizedBox(width: 8),
                                  InfoTile(icon: Icons.timer_outlined, label: 'ETA', value: '~${snap.data!.etaMin} min', color: Colors.purple,
                                    onTap: incident.lat != null && incident.lng != null
                                        ? () => openMap(incident.lat!, incident.lng!)
                                        : null),
                                  const SizedBox(width: 8),
                                  InfoTile(icon: Icons.near_me, label: 'DISTANCE', value: '${snap.data!.distStr} mi', color: Colors.blue,
                                    onTap: incident.lat != null && incident.lng != null
                                        ? () => openMap(incident.lat!, incident.lng!)
                                        : null),
                                ]),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    ),
    );
  }

  Future<_DistEta?> _fetchDistEta(double lat, double lng) async {
    final miles = await LocationService.distanceMiles(lat, lng);
    if (miles == null) return null;
    final eta = await LocationService.etaMinutes(lat, lng);
    if (eta == null) return null;
    final distStr = miles < 10 ? miles.toStringAsFixed(1) : miles.round().toString();
    return _DistEta(distStr: distStr, etaMin: eta);
  }
}

class _DistEta {
  final String distStr;
  final int etaMin;
  const _DistEta({required this.distStr, required this.etaMin});
}

class _FadeIn extends StatefulWidget {
  final Widget child;
  const _FadeIn({required this.child});

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _ctrl, child: widget.child);
  }
}

IconData _roleIcon(String role) {
  switch (role.toLowerCase()) {
    case 'pcp':
      return Icons.medical_information;
    case 'driver':
      return Icons.directions_car;
    default:
      return Icons.person;
  }
}

class _ShiftCountdown extends StatefulWidget {
  final DateTime shiftEnd;
  const _ShiftCountdown({required this.shiftEnd});

  @override
  State<_ShiftCountdown> createState() => _ShiftCountdownState();
}

class _ShiftCountdownState extends State<_ShiftCountdown> {
  Timer? _timer;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    final diff = widget.shiftEnd.difference(DateTime.now());
    if (diff.isNegative) {
      if (mounted) setState(() => _label = 'ENDED');
      return;
    }
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    final v = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    if (v != _label && mounted) setState(() => _label = v);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label,
      style: TextStyle(
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        color: Colors.green.shade500,
        letterSpacing: 0.5,
      ),
    );
  }
}

