import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/widgets/info_tile.dart';
import 'package:tone/widgets/live_elapsed.dart';

class EventCard extends StatefulWidget {
  final CalendarEvent event;
  const EventCard({super.key, required this.event});

  @override
  State<EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<EventCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
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
    final event = widget.event;
    final eventColor = Color(event.color);
    final isDone = event.status == 'completed' || event.status == 'cancelled';
    final headerColor = isDone ? Colors.grey.withAlpha(60) : eventColor.withAlpha(200);

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
            onTap: () => context.push('/event/${event.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header — colored bar with title (emoji included naturally)
                Container(
                  color: headerColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event,
                        color: isDone ? Colors.grey.shade400 : Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            color: isDone ? Colors.grey.shade400 : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 0.6,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDone)
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
                            event.status.toUpperCase(),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            LiveElapsed(time: event.time),
                            if (event.location != null) ...[
                              const SizedBox(width: 8),
                              InfoTile(
                                icon: Icons.location_on,
                                label: 'LOCATION',
                                value: event.location!,
                                color: isDone ? Colors.grey : Colors.orange,
                                onTap: event.lat != null && event.lng != null
                                    ? () => openMap(event.lat!, event.lng!)
                                    : null,
                              ),
                            ],
                            if (event.attendees.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              InfoTile(
                                icon: Icons.people,
                                label: 'GOING',
                                value:
                                    '${event.attendees.values.where((v) => v == 'going').length}',
                                color: isDone ? Colors.grey : Colors.green,
                              ),
                            ],
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
}
