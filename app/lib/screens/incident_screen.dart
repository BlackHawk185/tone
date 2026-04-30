import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;
import 'package:tone/models/incident.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/incident_service.dart';
import 'package:tone/services/location_service.dart';
import 'package:tone/services/response_service.dart';
import 'package:tone/utils/incident_theme.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/utils/text_styles.dart';
import 'package:tone/widgets/call_details_card.dart';
import 'package:tone/widgets/dialog_title_bar.dart';
import 'package:tone/widgets/info_grid.dart';
import 'package:tone/widgets/info_tile.dart';
import 'package:tone/widgets/live_elapsed.dart';
import 'package:tone/widgets/role_groups.dart';
import 'package:tone/widgets/settings_menu.dart';
import 'package:tone/widgets/swipe_to_respond.dart';

class IncidentScreen extends StatelessWidget {
  final String incidentId;
  const IncidentScreen({super.key, required this.incidentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident'),
        actions: const [
          SettingsMenu(),
        ],
      ),
      body: StreamBuilder<Incident?>(
        stream: IncidentService.watchIncident(incidentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final incident = snapshot.data;
          if (incident == null) {
            return const Center(child: Text('Incident not found.'));
          }
          return _IncidentDetail(incident: incident);
        },
      ),
    );
  }
}

class _IncidentDetail extends StatefulWidget {
  final Incident incident;
  const _IncidentDetail({required this.incident});

  @override
  State<_IncidentDetail> createState() => _IncidentDetailState();
}

class _IncidentDetailState extends State<_IncidentDetail> {
  bool _updating = false;
  bool _callDetailsExpanded = false;
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startLocationUpdates() {
    // Update location immediately, then every 60 seconds while responding
    _pushLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pushLocation());
  }

  Future<void> _pushLocation() async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    final incident = widget.incident;
    if (incident.responders[uid] == null) return;
    if (incident.lat == null || incident.lng == null) return;
    final miles = await LocationService.distanceMiles(incident.lat!, incident.lng!);
    if (miles == null) return;
    final eta = await LocationService.etaMinutes(incident.lat!, incident.lng!);
    if (eta == null) return;
    await ResponseService.updateLocation(
      incidentId: incident.incidentId,
      uid: uid,
      distanceMiles: miles,
      etaMinutes: eta,
    );
  }

  String? get _currentRole {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return null;
    return widget.incident.responders[uid]?.role;
  }

  bool get _isResponding => _currentRole != null;

  Future<void> _toggleActiveStatus(BuildContext context) async {
    final incident = widget.incident;
    final nowActive = incident.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => AlertDialog(
        title: DialogTitleBar(
          title: nowActive ? 'Close Incident?' : 'Reopen Incident?',
          onClose: () => Navigator.pop(context, false),
        ),
        content: Text(
          nowActive
              ? 'Mark this incident as closed. Responders can still view it.'
              : 'Mark this incident as active again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(nowActive ? 'Close' : 'Reopen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await IncidentService.setActiveStatus(
        incident.incidentId,
        active: !nowActive,
      );
    }
  }

  Future<void> _toggleResponse() async {
    final user = AuthService.currentUser;
    if (user == null) return;
    setState(() => _updating = true);
    try {
      if (_isResponding) {
        await ResponseService.clearStatus(
          incidentId: widget.incident.incidentId,
          uid: user.uid,
        );
      } else {
        final name = user.displayName ?? user.email?.split('@').first ?? 'Unknown';
        // Compute distance/ETA before writing
        double? miles;
        int? eta;
        if (widget.incident.lat != null && widget.incident.lng != null) {
          miles = await LocationService.distanceMiles(widget.incident.lat!, widget.incident.lng!);
          if (miles != null) eta = await LocationService.etaMinutes(widget.incident.lat!, widget.incident.lng!);
        }
        await ResponseService.updateStatus(
          incidentId: widget.incident.incidentId,
          uid: user.uid,
          displayName: name,
          role: 'responding',
          distanceMiles: miles,
          etaMinutes: eta,
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incident = widget.incident;
    final theme = IncidentTheme.of(incident.serviceType, unitCodes: incident.unitCodes);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Info tiles (2-column grid, type card first) ───────────
                InfoGrid(cardExpanded: _callDetailsExpanded, children: [
                      CallDetailsCard(
                        incident: incident,
                        theme: theme,
                        expanded: _callDetailsExpanded,
                        onToggle: () => setState(() => _callDetailsExpanded = !_callDetailsExpanded),
                        onLongPress: () => _toggleActiveStatus(context),
                      ),
                      InfoTile(
                        icon: Icons.location_on,
                        color: Colors.orange,
                        label: 'ADDRESS',
                        value: incident.crossStreets != null
                            ? '${incident.address}\n${incident.crossStreets}'
                            : incident.address,
                        onTap: incident.lat != null && incident.lng != null
                            ? () => openMap(incident.lat!, incident.lng!)
                            : null,
                      ),
                      LiveElapsed(time: DateTime.tryParse(incident.dispatchTime) ?? DateTime.now()),
                      if (incident.priority != null)
                        InfoTile(
                          icon: Icons.flag,
                          color: Colors.red,
                          label: 'PRIORITY',
                          value: 'P${incident.priority}',
                        ),
                ]),

                // ── Apparatus (single row) ──────────────────────────────────
                if (incident.units.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('APPARATUS',
                      style: ToneTextStyles.sectionHeader),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: incident.units.map((unit) {
                        final idx = incident.units.indexOf(unit);
                        return Padding(
                          padding: EdgeInsets.only(left: idx > 0 ? 10 : 0),
                          child: InfoTile(
                            icon: Icons.local_fire_department,
                            color: Colors.blueGrey,
                            label: 'UNIT',
                            value: unit,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // ── Role groups with nested responders ──────────────────────────
                RoleGroups(incident: incident),
              ],
            ),
          ),
        ),
        // ── Response (pinned to bottom) ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SwipeToRespond(
            active: _isResponding,
            updating: _updating,
            onRespond: () => _toggleResponse(),
          ),
        ),
      ],
    );
  }

}

