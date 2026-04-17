import 'package:flutter/material.dart';
import 'package:tone/models/incident.dart';
import 'package:tone/models/responder_status.dart';
import 'package:tone/models/response_role.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/response_service.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/utils/text_styles.dart';
import 'package:tone/widgets/info_tile.dart';

class RoleGroups extends StatelessWidget {
  final Incident incident;
  const RoleGroups({super.key, required this.incident});

  @override
  Widget build(BuildContext context) {
    final allRoles = ResponseRole.rolesForType(incident.serviceType);
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
            style: ToneTextStyles.sectionHeader),
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
