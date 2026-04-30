import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tone/widgets/info_tile.dart';

/// An InfoTile that counts elapsed time since [time], or counts down to it
/// if [time] is in the future. Direction is derived automatically.
class LiveElapsed extends StatefulWidget {
  final DateTime time;
  const LiveElapsed({super.key, required this.time});

  @override
  State<LiveElapsed> createState() => _LiveElapsedState();
}

class _LiveElapsedState extends State<LiveElapsed> {
  Timer? _timer;
  String _value = '';

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
    final v = _computeDelta();
    if (v != _value && mounted) setState(() => _value = v);
  }

  String _computeDelta() {
    final diff = DateTime.now().difference(widget.time);
    if (diff.isNegative) {
      // Countdown
      final abs = diff.abs();
      if (abs.inDays >= 1) {
        final h = abs.inHours % 24;
        return '${abs.inDays}d ${h}h';
      }
      if (abs.inHours >= 1) {
        final m = abs.inMinutes % 60;
        return '${abs.inHours}h ${m}m';
      }
      if (abs.inMinutes >= 1) {
        final s = abs.inSeconds % 60;
        return '${abs.inMinutes}m ${s.toString().padLeft(2, '0')}s';
      }
      return '${abs.inSeconds}s';
    }
    // Elapsed
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inDays < 1) {
      final s = diff.inSeconds % 60;
      return '${diff.inMinutes}m ${s.toString().padLeft(2, '0')}s';
    }
    return '${diff.inDays}d ${diff.inMinutes % (24 * 60)}m';
  }

  @override
  Widget build(BuildContext context) {
    if (_value.isEmpty) return const SizedBox.shrink();
    final isCountdown = widget.time.isAfter(DateTime.now());
    return InfoTile(
      icon: isCountdown ? Icons.timer_outlined : Icons.update,
      color: isCountdown ? Colors.teal : Colors.blueGrey,
      label: isCountdown ? 'STARTS IN' : 'ELAPSED',
      value: isCountdown ? 'T-$_value' : _value,
    );
  }
}
