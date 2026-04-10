import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemChrome, SystemUiMode;
import 'package:tone/models/incident.dart';
import 'package:tone/models/responder_status.dart';
import 'package:tone/models/response_role.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/incident_service.dart';
import 'package:tone/services/location_service.dart';
import 'package:tone/services/response_service.dart';
import 'package:tone/utils/incident_theme.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/widgets/info_tile.dart';
import 'package:tone/widgets/live_elapsed.dart';
import 'package:tone/widgets/settings_menu.dart';

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
        title: Row(
          children: [
            Expanded(child: Text(nowActive ? 'Close Incident?' : 'Reopen Incident?')),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, false),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
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
          role: 'rig',
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
    final theme = IncidentTheme.of(incident.incidentType);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Info tiles (2-column grid, type card first) ───────────
                _InfoGrid(cardExpanded: _callDetailsExpanded, children: [
                      _CallDetailsCard(
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
                      LiveElapsed(dispatchTime: incident.dispatchTime),
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
                      style: TextStyle(fontSize: 12, color: Colors.grey[500], letterSpacing: 1.5)),
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
                _RoleGroups(incident: incident),
              ],
            ),
          ),
        ),
        // ── Response (pinned to bottom) ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _SwipeToRespond(
            active: _isResponding,
            updating: _updating,
            onRespond: () => _toggleResponse(),
          ),
        ),
      ],
    );
  }

}

// ── Role groups: shows roles as sections with nested responders ────────────
class _RoleGroups extends StatelessWidget {
  final Incident incident;
  const _RoleGroups({required this.incident});

  @override
  Widget build(BuildContext context) {
    final allRoles = ResponseRole.rolesForType(incident.incidentType);
    final uid = AuthService.currentUser?.uid;
    final myStatus = uid != null ? incident.responders[uid] : null;
    final isResponding = myStatus != null;

    // Group responders by role
    final respondersByRole = <String, List<ResponderStatus>>{};
    for (final r in incident.responders.values) {
      respondersByRole.putIfAbsent(r.role, () => []).add(r);
    }

    // Sort responders within each role by response time
    for (final responders in respondersByRole.values) {
      responders.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ROLES',
            style: TextStyle(fontSize: 12, color: Colors.grey[500], letterSpacing: 1.5)),
        const SizedBox(height: 10),
        ...allRoles.where((role) {
          final hasFilled = respondersByRole.containsKey(role.id);
          // Show filled roles always, vacant roles only if responding
          return hasFilled || isResponding;
        }).map((role) {
          final responders = respondersByRole[role.id] ?? [];
          final vacant = responders.isEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: isResponding ? () => _claimRole(context, role.id) : null,
                child: Container(
                  decoration: BoxDecoration(
                    color: vacant
                        ? Colors.grey.withAlpha(10)
                        : (role.id == 'delayed' ? Colors.amber.withAlpha(15) : Colors.teal.withAlpha(15)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: vacant
                          ? Colors.grey.withAlpha(60)
                          : (role.id == 'delayed' ? Colors.amber.withAlpha(80) : Colors.teal.withAlpha(80)),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Role header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              role.icon,
                              size: 18,
                              color: vacant
                                  ? Colors.grey.withAlpha(150)
                                  : (role.id == 'delayed' ? Colors.amber : Colors.teal),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                role.label.toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: vacant
                                      ? Colors.grey.withAlpha(150)
                                      : (role.id == 'delayed' ? Colors.amber : Colors.teal),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            if (!vacant)
                              Text(
                                '${responders.length}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                  color: Colors.grey.withAlpha(150),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Responders list
                      if (!vacant)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: responders.map((r) {
                              final color = r.isOnScene ? Colors.blueGrey : Colors.green;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(25),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: color.withAlpha(80), width: 0.5),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            r.isOnScene ? Icons.person_pin_circle : Icons.person,
                                            size: 14,
                                            color: color,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              r.displayName + (r.uid == uid ? ' (you)' : ''),
                                              style: TextStyle(
                                                color: color,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!r.isOnScene && (r.etaMinutes != null || r.distStr != null))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              if (r.etaMinutes != null)
                                                InfoTile(
                                                  icon: Icons.timer_outlined,
                                                  color: Colors.purple,
                                                  label: 'ETA',
                                                  value: '~${r.etaMinutes} min',
                                                  onTap: incident.lat != null && incident.lng != null
                                                      ? () => openMap(incident.lat!, incident.lng!)
                                                      : null,
                                                ),
                                              if (r.distStr != null)
                                                InfoTile(
                                                  icon: Icons.near_me,
                                                  color: Colors.blue,
                                                  label: 'DIST',
                                                  value: '${r.distStr} mi',
                                                  onTap: incident.lat != null && incident.lng != null
                                                      ? () => openMap(incident.lat!, incident.lng!)
                                                      : null,
                                                ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        )
                      // Vacant slot
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                          child: Row(
                            children: [
                              Icon(
                                isResponding ? Icons.add_circle_outline : Icons.circle_outlined,
                                size: 16,
                                color: Colors.grey.withAlpha(isResponding ? 150 : 80),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isResponding ? 'Tap to claim' : 'Vacant',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.withAlpha(isResponding ? 150 : 100),
                                  fontStyle: FontStyle.italic,
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
        }),
      ],
    );
  }

  Future<void> _claimRole(BuildContext context, String roleId) async {
    final uid = AuthService.currentUser?.uid;
    if (uid == null) return;
    await ResponseService.updateRole(
      incidentId: incident.incidentId,
      uid: uid,
      role: roleId,
    );
  }
}


// ── Type card: always shows type + nature of call, expands to narrative ───────
class _CallDetailsCard extends StatelessWidget {
  final Incident incident;
  final dynamic theme; // IncidentTheme
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const _CallDetailsCard({
    required this.incident,
    required this.theme,
    required this.expanded,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasNarrative = incident.narrative.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: theme.color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.color.withAlpha(80), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasNarrative ? onToggle : null,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Always visible: type + nature of call ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(theme.icon, color: theme.color, size: 14),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: incident.incidentType,
                          style: TextStyle(
                            color: theme.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (incident.natureOfCall != null)
                          TextSpan(
                            text: '\n${incident.natureOfCall}',
                            style: TextStyle(
                              color: Colors.white.withAlpha(200),
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (hasNarrative)
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOut,
                    child: Icon(Icons.expand_more, color: theme.color.withAlpha(180), size: 18),
                  ),
              ],
            ),

            // ── Expandable: narrative only ──
            if (hasNarrative)
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: SizedBox(
                  height: expanded ? null : 0,
                  child: AnimatedOpacity(
                    opacity: expanded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 160),
                    child: Container(
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NARRATIVE',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.grey[500],
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 6),
                            ...incident.narrative.map((entry) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _formatNarrativeTime(entry.time),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey[400],
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                          if (entry.author.isNotEmpty)
                                            Text(
                                              entry.author,
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          entry.text,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatNarrativeTime(String isoOrRaw) {
    try {
      final dt = DateTime.parse(isoOrRaw).toLocal();
      final h  = dt.hour.toString().padLeft(2, '0');
      final m  = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return isoOrRaw.length >= 5 ? isoOrRaw.substring(0, 5) : isoOrRaw;
    }
  }
}

// ── Info grid (2-column layout) ──────────────────────────────────────────────
class _InfoGrid extends StatelessWidget {
  final List<Widget> children;
  final bool cardExpanded;
  const _InfoGrid({required this.children, this.cardExpanded = false});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cols = width < 400 ? 1 : 2;

    // When card is expanded: type card fills left, all others stack on right
    if (cardExpanded && cols == 2 && children.length > 1) {
      final others = children.skip(1).toList();
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < others.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    others[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Normal 2-per-row grid
    final List<Widget> rows = [];
    for (int i = 0; i < children.length; i += cols) {
      if (cols == 1) {
        rows.add(children[i]);
      } else {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
          ],
        ));
      }
      if (i + cols < children.length) rows.add(const SizedBox(height: 10));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

// ── Swipe-to-respond track ──────────────────────────────────────────────────
class _SwipeToRespond extends StatefulWidget {
  final bool active;
  final bool updating;
  final VoidCallback onRespond;

  const _SwipeToRespond({
    required this.active,
    required this.updating,
    required this.onRespond,
  });

  @override
  State<_SwipeToRespond> createState() => _SwipeToRespondState();
}

class _SwipeToRespondState extends State<_SwipeToRespond>
    with TickerProviderStateMixin {
  static const double _thumbSize = 56;
  static const double _triggerFraction = 0.82;

  double _offset = 0;
  late final AnimationController _snapBack;
  late Animation<double> _snapAnim;
  double _snapFrom = 0;
  late final AnimationController _flashCtrl;
  late final Animation<double> _flashAnim;

  @override
  void initState() {
    super.initState();
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _snapBack.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) => _snapBack.stop();

  void _onDragUpdate(DragUpdateDetails d, double trackW) {
    if (widget.updating) return;
    final maxDrag = trackW - _thumbSize;
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(0.0, maxDrag);
    });
    if (maxDrag > 0 && _offset / maxDrag >= _triggerFraction) {
      HapticFeedback.mediumImpact();
      setState(() => _offset = 0);
      _flashCtrl.forward(from: 0);
      widget.onRespond();
    }
  }

  void _onDragEnd(DragEndDetails _) {
    if (_offset == 0) return;
    _snapFrom = _offset;
    _snapAnim = Tween<double>(begin: _snapFrom, end: 0).animate(
      CurvedAnimation(parent: _snapBack, curve: Curves.easeOut),
    )..addListener(() => setState(() => _offset = _snapAnim.value));
    _snapBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final trackW = constraints.maxWidth;
      final maxDrag = (trackW - _thumbSize).clamp(1.0, double.infinity);
      final progress = (_offset / maxDrag).clamp(0.0, 1.0);

      return GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, trackW),
        onHorizontalDragEnd: _onDragEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 60,
          decoration: BoxDecoration(
            color: widget.active ? Colors.red.withAlpha(40) : Colors.green.withAlpha(20),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: widget.active ? Colors.red : Colors.green.withAlpha(180),
              width: 1.5,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Drag-fill strip
              FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      color: (widget.active ? Colors.red : Colors.green).withAlpha(55),
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              // Success flash overlay
              AnimatedBuilder(
                animation: _flashAnim,
                builder: (_, __) => _flashAnim.value > 0
                    ? Opacity(
                        opacity: (1 - _flashAnim.value),
                        child: Container(
                          decoration: BoxDecoration(
                            color: (widget.active ? Colors.red : Colors.green)
                                .withAlpha((120 * (1 - _flashAnim.value)).round()),
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // Centre label
              Center(
                child: Text(
                  widget.active ? 'slide to cancel  >>' : 'slide to respond  >>',
                  style: TextStyle(
                    color: widget.active
                        ? Colors.white.withAlpha((255 * (1 - progress * 1.6).clamp(0.0, 1.0)).round())
                        : Colors.green.withAlpha((255 * (1 - progress * 1.6).clamp(0.0, 1.0)).round()),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              // Thumb
                Positioned(
                  left: _offset + 3,
                  top: 3,
                  bottom: 3,
                  child: Container(
                    width: _thumbSize - 6,
                    decoration: BoxDecoration(
                      color: widget.active ? Colors.red : Colors.green,
                      borderRadius: BorderRadius.circular(27),
                    ),
                    child: Icon(widget.active ? Icons.close : Icons.directions_run,
                        color: Colors.white, size: 22),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}



