import 'dart:math' as math;

/// Planetocentric Mars geodesy using Mars's mean radius (3,396,190 m).
/// Never uses Earth-radius library helpers.
class MarsGeodesy {
  static const double marsRadiusM = 3396190.0;

  /// Surface distance in metres between two planetocentric [lon, lat] points (degrees).
  static double distanceM(double lon1, double lat1, double lon2, double lat2) {
    final phi1 = lat1 * math.pi / 180.0;
    final phi2 = lat2 * math.pi / 180.0;
    final dPhi = (lat2 - lat1) * math.pi / 180.0;
    final dLam = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) * math.sin(dLam / 2) * math.sin(dLam / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a));
    return marsRadiusM * c;
  }

  /// Metres per degree of latitude on Mars (~59,274.7 m).
  static double metresPerLatDeg() => (math.pi / 180.0) * marsRadiusM;

  /// Bearing in degrees [0, 360) from grid delta (dx, dy) where -y is North.
  static double gridBearingDeg(num dx, num dy) {
    return (math.atan2(dx.toDouble(), -dy.toDouble()) * 180.0 / math.pi + 360.0) % 360.0;
  }

  static String cardinal(double bearingDeg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[(bearingDeg / 45.0).round() % 8];
  }
}
