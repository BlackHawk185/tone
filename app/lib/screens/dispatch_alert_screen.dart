import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tone/services/auth_service.dart';
import 'package:tone/services/location_service.dart';
import 'package:tone/services/response_service.dart';
import 'package:tone/utils/incident_theme.dart';

const _settingsChannel = MethodChannel('com.valence.tone/settings');

/// Full-screen "incoming call"-style alert for dispatch notifications.
/// Covers everything with a pulsing red edge glow until the responder
/// acknowledges. Designed to be impossible to miss.
class DispatchAlertScreen extends StatefulWidget {
  final String incidentId;
  final String incidentType;
  final String address;
  final String? natureOfCall;
  final List<String> units;

  const DispatchAlertScreen({
    super.key,
    required this.incidentId,
    required this.incidentType,
    required this.address,
    this.natureOfCall,
    this.units = const [],
  });

  @override
  State<DispatchAlertScreen> createState() => _DispatchAlertScreenState();
}

class _DispatchAlertScreenState extends State<DispatchAlertScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;
  Timer? _autoTimeout;
  bool _responding = false;

  // Swipe-to-respond state
  double _swipeOffset = 0;
  late AnimationController _snapBack;
  late Animation<double> _snapAnim;
  static const double _thumbSize = 60;
  static const double _triggerFraction = 0.80;

  @override
  void initState() {
    super.initState();
    // Immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Continuous pulsing red glow
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // Content fade-in
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Snap-back for swipe
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // Haptic burst to demand attention
    _fireHaptics();

    // Auto-dismiss after 2 minutes (navigate to incident instead)
    _autoTimeout = Timer(const Duration(minutes: 2), _dismiss);
  }

  void _fireHaptics() async {
    for (int i = 0; i < 5; i++) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  @override
  void dispose() {
    _cancelVibration();
    _autoTimeout?.cancel();
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    _snapBack.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _cancelVibration() {
    try {
      _settingsChannel.invokeMethod('cancelVibration');
    } catch (_) {}
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _viewIncident() {
    if (!mounted) return;
    Navigator.of(context).pop('view');
  }

  Future<void> _respond() async {
    if (_responding) return;
    setState(() => _responding = true);
    HapticFeedback.heavyImpact();

    final user = AuthService.currentUser;
    if (user != null) {
      final name =
          user.displayName ?? user.email?.split('@').first ?? 'Unknown';
      double? miles;
      int? eta;
      // We don't have lat/lng here so just respond without distance

      try {
        await ResponseService.updateStatus(
          incidentId: widget.incidentId,
          uid: user.uid,
          displayName: name,
          role: 'rig',
          distanceMiles: miles,
          etaMinutes: eta,
        );
      } catch (_) {}
    }

    if (mounted) Navigator.of(context).pop('responded');
  }

  // ── Swipe handlers ──
  void _onSwipeStart(DragStartDetails _) => _snapBack.stop();

  void _onSwipeUpdate(DragUpdateDetails d, double trackW) {
    if (_responding) return;
    final maxDrag = trackW - _thumbSize;
    setState(() {
      _swipeOffset = (_swipeOffset + d.delta.dx).clamp(0.0, maxDrag);
    });
    if (maxDrag > 0 && _swipeOffset / maxDrag >= _triggerFraction) {
      HapticFeedback.heavyImpact();
      setState(() => _swipeOffset = 0);
      _respond();
    }
  }

  void _onSwipeEnd(DragEndDetails _) {
    if (_swipeOffset == 0) return;
    final from = _swipeOffset;
    _snapAnim = Tween<double>(begin: from, end: 0).animate(
      CurvedAnimation(parent: _snapBack, curve: Curves.easeOut),
    )..addListener(() => setState(() => _swipeOffset = _snapAnim.value));
    _snapBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = IncidentTheme.of(widget.incidentType);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, child) {
            final glow = _pulseAnim.value;
            return Stack(
              fit: StackFit.expand,
              children: [
                // ── Pulsing edge glow ──
                _EdgeGlow(intensity: glow, color: theme.color),

                // ── Content ──
                FadeTransition(
                  opacity: _fadeAnim,
                  child: SafeArea(
                    child: Column(
                      children: [
                        const Spacer(flex: 3),

                        // ── INCIDENT TYPE ──
                        Text(
                          widget.incidentType,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.color,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),

                        // ── Nature of call ──
                        if (widget.natureOfCall != null &&
                            widget.natureOfCall!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              widget.natureOfCall!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withAlpha(200),
                                fontSize: 18,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 48),

                        // ── "Answer the call?" ──
                        Text(
                          'Answer the call?',
                          style: TextStyle(
                            color: Colors.white.withAlpha(120),
                            fontSize: 15,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 0.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),

                        const Spacer(flex: 3),

                        // ── Swipe to Respond ──
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                          child: LayoutBuilder(
                              builder: (context, constraints) {
                            final trackW = constraints.maxWidth;
                            final maxDrag = (trackW - _thumbSize)
                                .clamp(1.0, double.infinity);
                            final progress =
                                (_swipeOffset / maxDrag).clamp(0.0, 1.0);

                            return GestureDetector(
                              onHorizontalDragStart: _onSwipeStart,
                              onHorizontalDragUpdate: (d) =>
                                  _onSwipeUpdate(d, trackW),
                              onHorizontalDragEnd: _onSwipeEnd,
                              child: Container(
                                height: 68,
                                decoration: BoxDecoration(
                                  color: _responding
                                      ? Colors.green.withAlpha(60)
                                      : Colors.green.withAlpha(20),
                                  borderRadius: BorderRadius.circular(34),
                                  border: Border.all(
                                    color: Colors.green.withAlpha(180),
                                    width: 2,
                                  ),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    // Progress fill
                                    FractionallySizedBox(
                                      widthFactor: progress,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.green.withAlpha(60),
                                          borderRadius:
                                              BorderRadius.circular(34),
                                        ),
                                      ),
                                    ),
                                    // Label
                                    Center(
                                      child: _responding
                                          ? const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Text('RESPONDING...',
                                                    style: TextStyle(
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                      letterSpacing: 1.5,
                                                    )),
                                              ],
                                            )
                                          : Text(
                                              'SLIDE TO RESPOND  \u00BB',
                                              style: TextStyle(
                                                color: Colors.green.withAlpha(
                                                    (255 *
                                                            (1 -
                                                                    progress *
                                                                        1.6)
                                                                .clamp(
                                                                    0.0, 1.0))
                                                        .round()),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                                letterSpacing: 1.5,
                                              ),
                                            ),
                                    ),
                                    // Thumb
                                    if (!_responding)
                                      Positioned(
                                        left: _swipeOffset + 4,
                                        top: 4,
                                        bottom: 4,
                                        child: Container(
                                          width: _thumbSize - 8,
                                          decoration: BoxDecoration(
                                            color: Colors.green,
                                            borderRadius:
                                                BorderRadius.circular(30),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.green
                                                    .withAlpha(80),
                                                blurRadius: 12,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                              Icons.directions_run,
                                              color: Colors.white,
                                              size: 26),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),

                        const SizedBox(height: 24),

                        // ── Red hang-up button ──
                        GestureDetector(
                          onTap: _dismiss,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.shade700,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withAlpha(80),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 32),
                          ),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Draws a glowing border around all edges of the screen that pulses.
class _EdgeGlow extends StatelessWidget {
  final double intensity;
  final Color color;
  const _EdgeGlow({required this.intensity, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _EdgeGlowPainter(intensity: intensity, color: color),
        size: Size.infinite,
      ),
    );
  }
}

class _EdgeGlowPainter extends CustomPainter {
  final double intensity;
  final Color color;
  _EdgeGlowPainter({required this.intensity, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final glowWidth = 40.0 + 30.0 * intensity;

    // Top edge
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, glowWidth),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withAlpha((200 * intensity).round()),
            color.withAlpha(0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, glowWidth)),
    );

    // Bottom edge
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - glowWidth, size.width, glowWidth),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withAlpha((200 * intensity).round()),
            color.withAlpha(0),
          ],
        ).createShader(Rect.fromLTWH(
            0, size.height - glowWidth, size.width, glowWidth)),
    );

    // Left edge
    canvas.drawRect(
      Rect.fromLTWH(0, 0, glowWidth, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withAlpha((200 * intensity).round()),
            color.withAlpha(0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, glowWidth, size.height)),
    );

    // Right edge
    canvas.drawRect(
      Rect.fromLTWH(size.width - glowWidth, 0, glowWidth, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: [
            color.withAlpha((200 * intensity).round()),
            color.withAlpha(0),
          ],
        ).createShader(
            Rect.fromLTWH(size.width - glowWidth, 0, glowWidth, size.height)),
    );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter old) => old.intensity != intensity;
}
