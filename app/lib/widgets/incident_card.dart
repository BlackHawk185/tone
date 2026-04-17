import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tone/models/incident.dart';
import 'package:tone/models/response_role.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/location_service.dart';
import 'package:tone/utils/incident_theme.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/widgets/bounce_on_change.dart';
import 'package:tone/widgets/info_tile.dart';
import 'package:tone/widgets/live_elapsed.dart';
import 'package:tone/widgets/pulsing_dot.dart';

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
    final iTheme = IncidentTheme.of(
      incident.serviceType,
      unitCodes: incident.unitCodes,
    );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: InkWell(
            onTap: () => context.push('/incident/${incident.incidentId}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Coloured type header
                Builder(
                  builder: (context) {
                    final multiService =
                        isActive &&
                        IncidentTheme.isMultiService(incident.unitCodes);
                    return Container(
                      decoration: BoxDecoration(
                        gradient: multiService
                            ? LinearGradient(
                                colors: [
                                  IncidentTheme.emsColor.withAlpha(160),
                                  IncidentTheme.fireColor.withAlpha(200),
                                ],
                              )
                            : null,
                        color: multiService
                            ? null
                            : (isActive
                                  ? iTheme.color
                                  : Colors.grey.withAlpha(60)),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            iTheme.icon,
                            color: isActive
                                ? Colors.white
                                : Colors.grey.shade400,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: incident.primaryDisplay,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.grey.shade400,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 11,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                  if (incident.isMessage)
                                    TextSpan(
                                      text: ' — ${incident.address}',
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white70
                                            : Colors.grey.shade500,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 11,
                                        letterSpacing: 0.3,
                                      ),
                                    )
                                  else if (incident.serviceType == 'BOTH' ||
                                      (incident.serviceType.isNotEmpty &&
                                          incident.serviceType !=
                                              incident.primaryDisplay))
                                    TextSpan(
                                      text:
                                          ' — ${incident.serviceType == 'BOTH' ? 'Multi-Agency' : incident.serviceType}',
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : Colors.grey.shade500,
                                        fontWeight: FontWeight.w400,
                                        fontSize: 12,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                    );
                  },
                ),

                // Body
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: incident.isMessage
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              incident.primaryDisplay,
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
                                    final allRoles = ResponseRole.rolesForType(
                                      incident.serviceType,
                                    );
                                    final roleCount = <String, int>{};
                                    for (final r
                                        in incident.responders.values) {
                                      roleCount[r.role] =
                                          (roleCount[r.role] ?? 0) + 1;
                                    }
                                    return allRoles
                                        .where(
                                          (role) =>
                                              roleCount.containsKey(role.id),
                                        )
                                        .map((role) {
                                          final isMyRole =
                                              myStatus?.role == role.id;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: BounceOnChange(
                                              bounceKey: isMyRole
                                                  ? myStatus!.role
                                                  : 'inactive',
                                              child: InfoTile(
                                                icon: role.icon,
                                                label: role.label.toUpperCase(),
                                                value: '${roleCount[role.id]}',
                                                color: isActive
                                                    ? (role.id == 'delayed'
                                                          ? Colors.amber
                                                          : Colors.green)
                                                    : Colors.grey,
                                                suffix: (isActive && isMyRole)
                                                    ? const PulsingDot(
                                                        color: Colors.green,
                                                      )
                                                    : null,
                                              ),
                                            ),
                                          );
                                        });
                                  }(),
                                  if (isActive && _distEtaFuture != null)
                                    FutureBuilder<_DistEta?>(
                                      future: _distEtaFuture,
                                      builder: (context, snap) {
                                        if (snap.data == null)
                                          return const SizedBox.shrink();
                                        return _FadeIn(
                                          child: Row(
                                            children: [
                                              const SizedBox(width: 8),
                                              InfoTile(
                                                icon: Icons.timer_outlined,
                                                label: 'ETA',
                                                value:
                                                    '~${snap.data!.etaMin} min',
                                                color: Colors.purple,
                                                onTap:
                                                    incident.lat != null &&
                                                        incident.lng != null
                                                    ? () => openMap(
                                                        incident.lat!,
                                                        incident.lng!,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                              InfoTile(
                                                icon: Icons.near_me,
                                                label: 'DISTANCE',
                                                value:
                                                    '${snap.data!.distStr} mi',
                                                color: Colors.blue,
                                                onTap:
                                                    incident.lat != null &&
                                                        incident.lng != null
                                                    ? () => openMap(
                                                        incident.lat!,
                                                        incident.lng!,
                                                      )
                                                    : null,
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  InfoTile(
                                    icon: Icons.location_on,
                                    label: 'ADDRESS',
                                    value: incident.address,
                                    color: tileColor(Colors.orange),
                                    onTap:
                                        incident.lat != null &&
                                            incident.lng != null
                                        ? () => openMap(
                                            incident.lat!,
                                            incident.lng!,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  LiveElapsed(
                                    dispatchTime: incident.dispatchTime,
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
    final distStr = miles < 10
        ? miles.toStringAsFixed(1)
        : miles.round().toString();
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
