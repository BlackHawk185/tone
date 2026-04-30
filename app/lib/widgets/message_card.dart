import 'package:flutter/material.dart';
import 'package:tone/models/app_event.dart';
import 'package:tone/utils/incident_theme.dart';
import 'package:tone/widgets/live_elapsed.dart';

class MessageCard extends StatefulWidget {
  final MessageEvent event;
  const MessageCard({super.key, required this.event});

  @override
  State<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<MessageCard>
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
    final isActive = event.isActive;
    final iTheme = IncidentTheme.of(
      event.isPriority ? 'PRIORITY TRAFFIC' : 'MESSAGE',
    );

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                color: isActive ? iTheme.color : Colors.grey.withAlpha(60),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      iTheme.icon,
                      color: isActive ? Colors.white : Colors.grey.shade400,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: event.text,
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.grey.shade400,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.6,
                              ),
                            ),
                            TextSpan(
                              text: ' — ${event.senderName}',
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white70
                                    : Colors.grey.shade500,
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
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.text,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    LiveElapsed(time: event.time),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
