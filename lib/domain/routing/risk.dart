// MARS-X routing core: route statistics, risk score (0-100) and science score.
// All weights/thresholds are SIMULATION ASSUMPTIONS and must be shown in the UI.

import 'dart:math' as math;

import 'cost_model.dart';
import 'mars_grid.dart';

class RiskBreakdown {
  final double pMax; // max slope / absolute limit
  final double pCaution; // share of length above caution slope
  final double pCross; // max side-slope / 20 deg
  final double pRough; // mean roughness
  final double pHazard; // mean soft-ground hazard
  final double pUncertainty; // mean (1 - data confidence)
  final double pTime; // (outbound + walk-back) / walking budget

  const RiskBreakdown({
    required this.pMax,
    required this.pCaution,
    required this.pCross,
    required this.pRough,
    required this.pHazard,
    required this.pUncertainty,
    required this.pTime,
  });

  static const weights = {
    'Max slope': 0.25,
    'Steep share': 0.20,
    'Side-slope': 0.15,
    'Roughness': 0.15,
    'Soft ground': 0.10,
    'Data gaps': 0.05,
    'Time budget': 0.10,
  };

  Map<String, double> get parts => {
        'Max slope': pMax,
        'Steep share': pCaution,
        'Side-slope': pCross,
        'Roughness': pRough,
        'Soft ground': pHazard,
        'Data gaps': pUncertainty,
        'Time budget': pTime,
      };

  double get score {
    var s = 0.0;
    parts.forEach((k, v) => s += weights[k]! * math.min(1.0, math.max(0.0, v)));
    return math.min(100.0, math.max(0.0, 100 * s));
  }

  String get level {
    final s = score;
    if (s < 25) return 'Low';
    if (s < 50) return 'Moderate';
    if (s < 75) return 'High';
    return 'Very high';
  }
}

class RouteStats {
  final double lengthM;
  final double timeS; // outbound walking time (SIMULATED)
  final double returnTimeS; // walking back the same way (SIMULATED)
  final double maxSlopeDeg;
  final double maxCrossSlopeDeg;
  final double gainM;
  final double lossM;
  final double scienceScore; // 0..100
  final RiskBreakdown risk;

  /// Elevation profile: (distance along route m, elevation m) per path cell.
  final List<(double, double)> profile;

  const RouteStats({
    required this.lengthM,
    required this.timeS,
    required this.returnTimeS,
    required this.maxSlopeDeg,
    required this.maxCrossSlopeDeg,
    required this.gainM,
    required this.lossM,
    required this.scienceScore,
    required this.risk,
    required this.profile,
  });
}

RouteStats computeStats(MarsGrid g, CostModel m, List<int> path) {
  final walk = m.walk;
  var length = 0.0, time = 0.0, back = 0.0, gain = 0.0, loss = 0.0;
  var maxSlope = 0.0, maxCross = 0.0, cautionLen = 0.0;
  var roughSum = 0.0, hazSum = 0.0, uncSum = 0.0, sciSum = 0.0;
  final prof = <(double, double)>[(0.0, g.elevation[path.first].toDouble())];

  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i];
    final d = g.distanceM(a, b);
    final dz = (g.elevation[b] - g.elevation[a]).toDouble();
    length += d;
    time += m.stepTime(a, b);
    back += m.stepTime(b, a);
    if (dz > 0) {
      gain += dz;
    } else {
      loss -= dz;
    }

    final s = 0.5 * (g.slopeDeg[a] + g.slopeDeg[b]);
    maxSlope = math.max(maxSlope, math.max(g.slopeDeg[a], g.slopeDeg[b]).toDouble());
    if (s > walk.cautionSlopeDeg) cautionLen += d;

    final along = (dz / d).abs();
    final tanT = math.tan(s * math.pi / 180);
    final c2 = tanT * tanT - along * along;
    if (c2 > 0) maxCross = math.max(maxCross, math.atan(math.sqrt(c2)) * 180 / math.pi);

    roughSum += d * 0.5 * (g.roughness[a] + g.roughness[b]);
    hazSum += d * 0.5 * (g.hazard[a] + g.hazard[b]);
    uncSum += d * (1 - 0.5 * (g.confidence[a] + g.confidence[b]));
    sciSum += d * 0.5 * (g.science[a] + g.science[b]);
    prof.add((length, g.elevation[b].toDouble()));
  }
  final L = math.max(length, 1e-6);
  final risk = RiskBreakdown(
    pMax: maxSlope / walk.absoluteMaxSlopeDeg,
    pCaution: cautionLen / L,
    pCross: maxCross / 20.0,
    pRough: roughSum / L,
    pHazard: hazSum / L,
    pUncertainty: uncSum / L,
    pTime: (time + back) / walk.walkingBudgetS,
  );
  return RouteStats(
    lengthM: length,
    timeS: time,
    returnTimeS: back,
    maxSlopeDeg: maxSlope,
    maxCrossSlopeDeg: maxCross,
    gainM: gain,
    lossM: loss,
    scienceScore: 100 * sciSum / L,
    risk: risk,
    profile: prof,
  );
}
