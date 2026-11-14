import 'dart:math' as math;
import '../routing/astar.dart';
import '../terrain/terrain_grid.dart';

class RiskPart {
  final String key;
  final String label;
  final double value;
  final double weight;

  const RiskPart({
    required this.key,
    required this.label,
    required this.value,
    required this.weight,
  });
}

class RiskAssessment {
  final int score;
  final String level;
  final double estimatedTimeMin;
  final int scienceScore;
  final List<RiskPart> parts;

  const RiskAssessment({
    required this.score,
    required this.level,
    required this.estimatedTimeMin,
    required this.scienceScore,
    required this.parts,
  });
}

class RiskModel {
  static const double cautionDeg = 10.0;
  static const double timeBudgetMin = 480.0;

  static double speedMps(double slopeDeg) {
    return math.max(0.2, 1.4 * (1.0 - slopeDeg / (MarsRouter.defaultMaxSlopeDeg * 1.3)));
  }

  static double legTimeMin(TerrainGrid grid, List<GridPoint> path) {
    var sec = 0.0;
    for (var k = 1; k < path.length; k++) {
      final a = path[k - 1];
      final b = path[k];
      final i = b.y * grid.w + b.x;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final d = grid.distanceForCellDelta(dx, dy);
      sec += d / speedMps(grid.slope[i]);
    }
    return sec / 60.0;
  }

  static RiskAssessment assess(TerrainGrid grid, RouteResult route) {
    final p = route.path;
    final n = p.length;
    var len = 0.0;
    var cautionLen = 0.0;
    var lowConfCount = 0;

    for (var k = 0; k < n; k++) {
      final idx = p[k].y * grid.w + p[k].x;
      if (grid.unc[idx] > 0.5) lowConfCount++;
      if (k > 0) {
        final d = grid.distanceForCellDelta(p[k].x - p[k - 1].x, p[k].y - p[k - 1].y);
        len += d;
        if (grid.slope[idx] > cautionDeg) cautionLen += d;
      }
    }

    final timeMin = legTimeMin(grid, p);
    final parts = [
      RiskPart(
        key: 'max',
        label: 'Peak slope vs limit',
        value: math.min(1.0, route.maxSlopeDeg / MarsRouter.defaultMaxSlopeDeg),
        weight: 0.30,
      ),
      RiskPart(
        key: 'caution',
        label: 'Length above ${cautionDeg.toInt()}°',
        value: len > 0 ? cautionLen / len : 0.0,
        weight: 0.25,
      ),
      RiskPart(
        key: 'rough',
        label: 'Mean roughness',
        value: math.min(1.0, route.meanRough),
        weight: 0.20,
      ),
      RiskPart(
        key: 'unc',
        label: 'Low-confidence share',
        value: lowConfCount / n,
        weight: 0.15,
      ),
      RiskPart(
        key: 'time',
        label: 'Time vs budget',
        value: math.min(1.0, timeMin / timeBudgetMin),
        weight: 0.10,
      ),
    ];

    final score = (100.0 * parts.fold<double>(0.0, (a, x) => a + x.value * x.weight)).round();
    final level = score < 25
        ? 'LOW'
        : score < 50
            ? 'MODERATE'
            : score < 75
                ? 'HIGH'
                : 'VERY HIGH';
    final sciScore = math.min(100, (route.scienceValue * 45.0).round());

    return RiskAssessment(
      score: score,
      level: level,
      estimatedTimeMin: timeMin,
      scienceScore: sciScore,
      parts: parts,
    );
  }
}
