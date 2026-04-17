import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:tone/models/incident.dart';
import 'package:tone/utils/incident_theme.dart';

class CallDetailsCard extends StatelessWidget {
  final Incident incident;
  final dynamic theme; // IncidentTheme
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  const CallDetailsCard({
    super.key,
    required this.incident,
    required this.theme,
    required this.expanded,
    required this.onToggle,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final hasNarrative = incident.narrative.isNotEmpty;
    final multiService = IncidentTheme.isMultiService(incident.unitCodes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        gradient: multiService
            ? LinearGradient(
                colors: [
                  IncidentTheme.emsColor.withAlpha(25),
                  IncidentTheme.fireColor.withAlpha(50),
                ],
              )
            : null,
        color: multiService ? null : theme.color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: multiService
              ? IncidentTheme.emsColor.withAlpha(80)
              : theme.color.withAlpha(80),
          width: 1,
        ),
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
                  child: multiService
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.medical_services, color: IncidentTheme.emsColor, size: 14),
                            const SizedBox(width: 2),
                            Icon(Icons.local_fire_department, color: IncidentTheme.fireColor, size: 14),
                          ],
                        )
                      : Icon(theme.icon, color: theme.color, size: 14),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: incident.primaryDisplay,
                          style: TextStyle(
                            color: theme.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                        if (incident.serviceType == 'BOTH' || (incident.serviceType.isNotEmpty && incident.serviceType != incident.primaryDisplay))
                          TextSpan(
                            text: '\n${incident.serviceType == 'BOTH' ? 'Multi-Agency' : incident.serviceType}',
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
