import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

class SwipeToRespond extends StatefulWidget {
  final bool active;
  final bool updating;
  final VoidCallback onRespond;

  const SwipeToRespond({
    super.key,
    required this.active,
    required this.updating,
    required this.onRespond,
  });

  @override
  State<SwipeToRespond> createState() => _SwipeToRespondState();
}

class _SwipeToRespondState extends State<SwipeToRespond>
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
