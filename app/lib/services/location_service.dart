import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';

/// Provides the device's current position and utilities for computing
/// straight-line distance + rough ETA to an incident.
///
/// TODO: replace Haversine ETA with Google Directions API for road distance
/// and real-traffic travel time once a Maps API key is provisioned.
class LocationService {
  static Position? _cached;

  /// Returns the device position, using a cached value if it is recent enough.
  /// Returns null if permission is denied or location is unavailable.
  static Future<Position?> getPosition() async {
    if (_cached != null) return _cached;

    final permission = await _ensurePermission();
    if (!permission) return null;

    try {
      _cached = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _cached;
    } catch (_) {
      return null;
    }
  }

  /// Straight-line distance in miles between the device and [incidentLat]/[incidentLng].
  static Future<double?> distanceMiles(double incidentLat, double incidentLng) async {
    final pos = await getPosition();
    if (pos == null) return null;
    final meters = Geolocator.distanceBetween(
      pos.latitude, pos.longitude, incidentLat, incidentLng,
    );
    return meters / 1609.344;
  }

  /// Rough ETA in minutes using Haversine distance ÷ assumed average speed.
  /// Assumes 35 mph average (mix of rural road + highway).
  ///
  /// TODO: replace with Google Directions / Mapbox ETA for road-accurate results.
  static Future<int?> etaMinutes(double incidentLat, double incidentLng) async {
    final miles = await distanceMiles(incidentLat, incidentLng);
    if (miles == null) return null;
    const avgSpeedMph = 35.0;
    return (miles / avgSpeedMph * 60).round().clamp(1, 9999);
  }

  /// Returns a formatted label like "3.2 mi · ~6 min", or null if no coords / no permission.
  static Future<String?> distanceLabel(double? lat, double? lng) async {
    if (lat == null || lng == null) return null;
    final miles = await distanceMiles(lat, lng);
    if (miles == null) return null;
    final eta = await etaMinutes(lat, lng);
    final dist = miles < 10 ? miles.toStringAsFixed(1) : miles.round().toString();
    return eta != null ? '$dist mi - ~$eta min' : '$dist mi';
  }

  static Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
