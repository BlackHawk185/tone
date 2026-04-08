import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tone/widgets/info_tile.dart';

/// An InfoTile whose ELAPSED value ticks every second.
class LiveElapsed extends StatefulWidget {
  final String dispatchTime;
  const LiveElapsed({super.key, required this.dispatchTime});

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
    if (widget.dispatchTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(widget.dispatchTime);
      final diff = DateTime.now().difference(dt);
      if (diff.isNegative) return '';
      if (diff.inSeconds < 60) return '${diff.inSeconds}s';
      if (diff.inDays < 1) {
        final s = diff.inSeconds % 60;
        return '${diff.inMinutes}m ${s.toString().padLeft(2, '0')}s';
      }
      return '${diff.inDays}d ${diff.inMinutes % (24 * 60)}m';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_value.isEmpty) return const SizedBox.shrink();
    return InfoTile(
      icon: Icons.update,
      color: Colors.blueGrey,
      label: 'ELAPSED',
      value: _value,
    );
  }
}
