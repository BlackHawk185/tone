import 'package:flutter/material.dart';
import 'package:tone/utils/map_launcher.dart';
import 'package:tone/widgets/info_tile.dart';

/// A reusable location tile widget that displays a location with an optional map hyperlink.
/// Used by both incidents and events to ensure consistent location hyperlink behavior.
class LocationTile extends StatelessWidget {
  final String locationText;
  final double? lat;
  final double? lng;
  final Color color;
  final String label;
  final IconData icon;

  const LocationTile({
    super.key,
    required this.locationText,
    this.lat,
    this.lng,
    this.color = Colors.orange,
    this.label = 'LOCATION',
    this.icon = Icons.location_on,
  });

  @override
  Widget build(BuildContext context) {
    return InfoTile(
      icon: icon,
      label: label,
      value: locationText,
      color: color,
      onTap: _shouldEnableMap ? () => openMap(lat!, lng!) : null,
    );
  }

  bool get _shouldEnableMap => lat != null && lng != null;
}
