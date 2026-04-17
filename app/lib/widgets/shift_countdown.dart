import 'dart:async';
import 'package:flutter/material.dart';

IconData roleIcon(String role) {
  switch (role.toLowerCase()) {
    case 'pcp':
      return Icons.medical_information;
    case 'driver':
      return Icons.directions_car;
    default:
      return Icons.person;
  }
}

class ShiftCountdown extends StatefulWidget {
  final DateTime shiftEnd;
  final Color? color;
  const ShiftCountdown({super.key, required this.shiftEnd, this.color});

  @override
  State<ShiftCountdown> createState() => _ShiftCountdownState();
}

class _ShiftCountdownState extends State<ShiftCountdown> {
  Timer? _timer;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    final diff = widget.shiftEnd.difference(DateTime.now());
    if (diff.isNegative) {
      if (mounted) setState(() => _label = 'ENDED');
      return;
    }
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    final v = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    if (v != _label && mounted) setState(() => _label = v);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label,
      style: TextStyle(
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        color: widget.color ?? Colors.green.shade500,
        letterSpacing: 0.5,
      ),
    );
  }
}
