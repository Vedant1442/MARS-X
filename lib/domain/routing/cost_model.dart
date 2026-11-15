// MARS-X routing core: route profiles, walking model and edge costs.
//
// Edge cost = walking TIME (seconds) x a penalty FACTOR.
//   * time comes from a Tobler-style hiking curve (uphill and steep downhill are slower).
//   * factor = 1 + safety penalties - science bonus, floored so it stays positive (A* needs that).
// Every number here is a SIMULATION ASSUMPTION, shown in the app's methodology screen.

import 'dart:math' as math;
import 'dart:typed_data';

import 'mars_grid.dart';

/// Suited-astronaut walking model (SIMULATED).
class WalkModel {
  /// Peak speed in m/s, reached on a gentle ~3 deg downhill. Flat ground is ~84% of this.
  /// 1.0 m/s peak = ~3 km/h on the flat: plausible for a pressurised suit + tools (assumption).
  final double peakSpeed;

  /// Slope (deg) above which ANY profile refuses a cell. Also the risk-score reference.
  final double absoluteMaxSlopeDeg;

  /// Slope (deg) considered "caution" for risk scoring.
  final double cautionSlopeDeg;

  /// Total walking time budget, outbound + walk-back (seconds).
  final double walkingBudgetS;

  const WalkModel({
    this.peakSpeed = 1.0,
    this.absoluteMaxSlopeDeg = 25,
    this.cautionSlopeDeg = 10,
    this.walkingBudgetS = 4 * 3600,
  });

  /// Tobler's hiking function shape: v = peak * exp(-3.5 * |grade + 0.05|).
  double speed(double grade) => peakSpeed * math.exp(-3.5 * (grade + 0.05).abs());
}

class RouteProfile {
  final String id;
  final String name;
  final String why; // one-line "why this route?" text

  final double maxSlopeDeg; // hard limit on cell slope
  final double maxCrossSlopeDeg; // hard limit on side-slope (fall risk when traversing a hillside)
  final double maxHazard; // cells with hazard above this are excluded

  final double wSlope; // terrain steepness
  final double wRough; // rocks / uneven ground
  final double wCross; // side-slope while walking
  final double wDownhill; // steep descents (slip risk, harder in a suit)
  final double wHazard; // soft sand / dunes / loose regolith
  final double wUncertainty; // low-confidence elevation data
  final double wScience; // science attraction (bonus, reduces cost)

  /// Science routes may not take more than detourCap x the fastest route's time. 0 = no cap.
  final double detourCap;

  const RouteProfile({
    required this.id,
    required this.name,
    required this.why,
    required this.maxSlopeDeg,
    required this.maxCrossSlopeDeg,
    required this.maxHazard,
    required this.wSlope,
    required this.wRough,
    required this.wCross,
    required this.wDownhill,
    required this.wHazard,
    required this.wUncertainty,
    required this.wScience,
    this.detourCap = 0,
  });

  RouteProfile copyWith({double? wScience, double? maxSlopeDeg}) => RouteProfile(
        id: id,
        name: name,
        why: why,
        maxSlopeDeg: maxSlopeDeg ?? this.maxSlopeDeg,
        maxCrossSlopeDeg: maxCrossSlopeDeg,
        maxHazard: maxHazard,
        wSlope: wSlope,
        wRough: wRough,
        wCross: wCross,
        wDownhill: wDownhill,
        wHazard: wHazard,
        wUncertainty: wUncertainty,
        wScience: wScience ?? this.wScience,
        detourCap: detourCap,
      );

  // ---- The four routes shown to the user (weights are tunable assumptions) ----

  static const fastest = RouteProfile(
    id: 'fastest',
    name: 'Fastest',
    why: 'Minimises walking time; accepts steeper and rougher ground.',
    maxSlopeDeg: 25,
    maxCrossSlopeDeg: 18,
    maxHazard: 0.85,
    wSlope: 0.2,
    wRough: 0.2,
    wCross: 0.2,
    wDownhill: 0.2,
    wHazard: 0.5,
    wUncertainty: 0.1,
    wScience: 0,
  );

  static const safest = RouteProfile(
    id: 'safest',
    name: 'Safest',
    why: 'Stays on gentle, smooth, well-mapped ground even if it takes longer.',
    maxSlopeDeg: 15,
    maxCrossSlopeDeg: 10,
    maxHazard: 0.5,
    wSlope: 3.0,
    wRough: 2.0,
    wCross: 2.5,
    wDownhill: 2.0,
    wHazard: 4.0,
    wUncertainty: 1.5,
    wScience: 0,
  );

  static const science = RouteProfile(
    id: 'science',
    name: 'Most scientific',
    why: 'Detours past high-value geology, capped at 1.5x the fastest time.',
    maxSlopeDeg: 20,
    maxCrossSlopeDeg: 14,
    maxHazard: 0.7,
    wSlope: 0.8,
    wRough: 0.6,
    wCross: 0.6,
    wDownhill: 0.6,
    wHazard: 1.0,
    wUncertainty: 0.3,
    wScience: 0.7,
    detourCap: 1.5,
  );

  static const balanced = RouteProfile(
    id: 'balanced',
    name: 'Best of both',
    why: 'Good science on safe ground, capped at 1.3x the fastest time.',
    maxSlopeDeg: 18,
    maxCrossSlopeDeg: 12,
    maxHazard: 0.6,
    wSlope: 1.5,
    wRough: 1.0,
    wCross: 1.2,
    wDownhill: 1.0,
    wHazard: 2.0,
    wUncertainty: 0.8,
    wScience: 0.45,
    detourCap: 1.3,
  );

  static const all = [fastest, safest, science, balanced];
}

/// Precomputed per-profile cost tables. Build once per (grid, profile).
class CostModel {
  static const double factorFloor = 0.25;

  final MarsGrid grid;
  final RouteProfile profile;
  final WalkModel walk;

  /// Non-directional part of the penalty factor per cell.
  final Float32List cellFactor;

  /// 1 if a cell can be entered under this profile.
  final Uint8List passable;

  /// tan(slope) per cell, cached for cross-slope maths.
  final Float32List _tanSlope;

  /// Lower bound of any edge factor -> keeps the A* heuristic admissible.
  final double minFactor;

  final double _tanCaution;
  final double _tanMax;

  CostModel._(this.grid, this.profile, this.walk, this.cellFactor, this.passable,
      this._tanSlope, this.minFactor)
      : _tanCaution = math.tan(walk.cautionSlopeDeg * math.pi / 180),
        _tanMax = math.tan(profile.maxSlopeDeg * math.pi / 180);

  factory CostModel(MarsGrid g, RouteProfile p, [WalkModel walk = const WalkModel()]) {
    final n = g.cellCount;
    final cf = Float32List(n);
    final pass = Uint8List(n);
    final tanS = Float32List(n);
    final maxSlope = math.min(p.maxSlopeDeg, walk.absoluteMaxSlopeDeg);
    var minCf = double.infinity;
    for (var i = 0; i < n; i++) {
      final s = g.slopeDeg[i];
      tanS[i] = math.tan(math.min(s, 89.0) * math.pi / 180);
      final ok = g.blocked[i] == 0 && !g.elevation[i].isNaN && s <= maxSlope && g.hazard[i] <= p.maxHazard;
      if (!ok) continue;
      pass[i] = 1;
      final sn = s / maxSlope;
      final f = 1.0 +
          p.wSlope * sn * sn +
          p.wRough * g.roughness[i] +
          p.wHazard * g.hazard[i] +
          p.wUncertainty * (1.0 - g.confidence[i]) -
          p.wScience * g.science[i];
      cf[i] = f;
      if (f < minCf) minCf = f;
    }
    final minFactor = math.max(factorFloor, minCf.isFinite ? minCf : 1.0);
    return CostModel._(g, p, walk, cf, pass, tanS, minFactor);
  }

  /// Seconds-equivalent cost of stepping from cell a to neighbouring cell b.
  /// Returns double.infinity if the step is not allowed.
  double edgeCost(int a, int b) {
    if (passable[a] == 0 || passable[b] == 0) return double.infinity;
    final g = grid;
    final ax = g.xOf(a), ay = g.yOf(a), bx = g.xOf(b), by = g.yOf(b);
    final dx = bx - ax, dy = by - ay;
    if (dx.abs() > 1 || dy.abs() > 1 || (dx == 0 && dy == 0)) return double.infinity;
    if (dx != 0 && dy != 0) {
      // No corner cutting past obstacles on diagonal moves.
      if (passable[g.index(bx, ay)] == 0 || passable[g.index(ax, by)] == 0) {
        return double.infinity;
      }
    }
    final dist = (dx != 0 && dy != 0) ? g.cellSize * math.sqrt2 : g.cellSize;
    final dz = g.elevation[b] - g.elevation[a];
    final grade = dz / dist; // + uphill, - downhill
    final along = grade.abs();
    if (along > _tanMax) return double.infinity;

    // Cross-slope: terrain gradient component perpendicular to walking direction.
    final tanTerrain = 0.5 * (_tanSlope[a] + _tanSlope[b]);
    final cross2 = tanTerrain * tanTerrain - along * along;
    final crossDeg = cross2 > 0 ? math.atan(math.sqrt(cross2)) * 180 / math.pi : 0.0;
    if (crossDeg > profile.maxCrossSlopeDeg) return double.infinity;

    final time = math.sqrt(dist * dist + dz * dz) / walk.speed(grade);

    final cr = crossDeg / profile.maxCrossSlopeDeg;
    var downhill = 0.0;
    if (-grade > _tanCaution && _tanMax > _tanCaution) {
      downhill = math.min(1.0, math.max(0.0, (-grade - _tanCaution) / (_tanMax - _tanCaution)));
    }
    final factor = math.max(
        factorFloor,
        0.5 * (cellFactor[a] + cellFactor[b]) +
            profile.wCross * cr * cr +
            profile.wDownhill * downhill);
    return time * factor;
  }

  /// Admissible lower bound of the cost from a to b (octile distance at peak speed).
  double heuristic(int a, int b) {
    final dx = (grid.xOf(a) - grid.xOf(b)).abs();
    final dy = (grid.yOf(a) - grid.yOf(b)).abs();
    final mn = math.min(dx, dy), mx = math.max(dx, dy);
    final octile = (mx - mn) + mn * math.sqrt2;
    return octile * grid.cellSize / walk.peakSpeed * minFactor;
  }

  /// Pure walking time (seconds) of a single step, no penalties. Used for ETAs.
  double stepTime(int a, int b) {
    final dist = grid.distanceM(a, b);
    final dz = grid.elevation[b] - grid.elevation[a];
    return math.sqrt(dist * dist + dz * dz) / walk.speed(dz / dist);
  }
}
