import 'package:flutter/material.dart';

class InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final Widget? suffix;
  final VoidCallback? onTap;

  const InfoTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.suffix,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(80), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 9,
                  color: color,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Flexible(
                child: Text(value,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    )),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 5),
                suffix!,
              ],
            ],
          ),
        ],
      ),
    );
    if (onTap != null) {
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: tile),
      );
    }
    return tile;
  }
}
