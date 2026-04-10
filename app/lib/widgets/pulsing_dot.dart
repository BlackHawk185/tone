import 'package:flutter/material.dart';

/// A solid dot with an expanding ring that pulses outward like a sonar ping.
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({super.key, this.color = Colors.green, this.size = 8});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    // Ring expands from 1x to 2.5x the dot size
    _ringScale = Tween<double>(begin: 1.0, end: 2.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    // Ring fades out as it expands
    _ringOpacity = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size * 2.5,
      height: size * 2.5,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            // Expanding ring
            Opacity(
              opacity: _ringOpacity.value,
              child: Transform.scale(
                scale: _ringScale.value,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.color,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            // Solid center dot
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
