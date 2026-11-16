import 'dart:math' as math;
import 'dart:typed_data';
import '../terrain/terrain_grid.dart';
import '../track/mission_config.dart';

export '../terrain/terrain_grid.dart' show GridPoint;

enum RouteMode { safest, fastest, science }

enum SearchAlgorithm { astar, dijkstra }

enum ScienceCampaignObjective {
  deltaLacustrine(
    id: 'delta_lacustrine',
    name: 'Delta Lacustrine & Biosignature Sampling',
    description: 'Target fine-grained clay/mudstone bottomsets and delta front strata optimal for organic preservation.',
    targetIds: {'enchanted-lake', 'hawksbill-gap', 'three-forks', 'western-delta', 'bunsen-peak'},
  ),
  craterBasement(
    id: 'crater_basement',
    name: 'Crater Basement & Impact Megabreccia',
    description: 'Sample pre-Noachian crustal basement and impact shock melt excavated during the Isidis impact event.',
    targetIds: {'belva-crater', 'jezero-crater-rim', 'ancient-lake-basin', 'octavia-butler-landing'},
  ),
  fluvialHydrology(
    id: 'fluvial_hydrology',
    name: 'Fluvial Inflow Hydrology & Canyon Outcrops',
    description: 'Examine catastrophic paleoflood inflow breaches, boulder conglomerates, and fluvial deposition bars.',
    targetIds: {'neretva-vallis', 'cape-nukshak', 'jurabi-point', 'sava-vallis', 'pliva-vallis'},
  );

  final String id;
  final String name;
  final String description;
  final Set<String> targetIds;

  const ScienceCampaignObjective({
    required this.id,
    required this.name,
    required this.description,
    required this.targetIds,
  });
}

class ScienceTargetContribution {
  final ScienceTarget target;
  final double distanceM;
  final double baseValue;
  final double objectiveMultiplier;
  final double points;
  final String justification;

  const ScienceTargetContribution({
    required this.target,
    required this.distanceM,
    required this.baseValue,
    required this.objectiveMultiplier,
    required this.points,
    required this.justification,
  });
}

class ScienceBreakdown {
  final ScienceCampaignObjective objective;
  final int totalScore;
  final List<ScienceTargetContribution> contributions;
  final List<ScienceTarget> unvisitedTargets;

  const ScienceBreakdown({
    required this.objective,
    required this.totalScore,
    required this.contributions,
    required this.unvisitedTargets,
  });
}


class RouteWeights {
  final double s;
  final double r;
  final double u;
  final double h;

  const RouteWeights({
    required this.s,
    required this.r,
    required this.u,
    required this.h,
  });

  static const RouteWeights defaultScience = RouteWeights(s: 35, r: 20, u: 15, h: 15);
  static const RouteWeights safest = RouteWeights(s: 70, r: 25, u: 10, h: 15);
  static const RouteWeights fastest = RouteWeights(s: 10, r: 5, u: 2, h: 5);

  static RouteWeights forMode(RouteMode mode) {
    switch (mode) {
      case RouteMode.safest:
        return safest;
      case RouteMode.fastest:
        return fastest;
      case RouteMode.science:
        return defaultScience;
    }
  }
}

class RouteResult {
  final RouteMode mode;
  final SearchAlgorithm algorithm;
  final List<GridPoint> path;
  final double distanceM;
  final double totalCost;
  final double maxSlopeDeg;
  final double meanSlopeDeg;
  final double meanRough;
  final double meanUnc;
  final double elevGainM;
  final double exposureShare;
  final List<ScienceTarget> scienceHits;
  final double scienceValue;
  final String confidence;
  final int nodesExpanded;

  const RouteResult({
    required this.mode,
    required this.algorithm,
    required this.path,
    required this.distanceM,
    required this.totalCost,
    required this.maxSlopeDeg,
    required this.meanSlopeDeg,
    required this.meanRough,
    required this.meanUnc,
    required this.elevGainM,
    required this.exposureShare,
    required this.scienceHits,
    required this.scienceValue,
    required this.confidence,
    required this.nodesExpanded,
  });
}

class _MinHeap {
  final List<double> _f = [];
  final List<int> _idx = [];

  bool get isNotEmpty => _f.isNotEmpty;

  void push(double f, int idx) {
    _f.add(f);
    _idx.add(idx);
    var k = _f.length - 1;
    while (k > 0) {
      final p = (k - 1) >> 1;
      if (_f[p] <= _f[k]) break;
      _swap(p, k);
      k = p;
    }
  }

  int pop() {
    final top = _idx[0];
    final lastF = _f.removeLast();
    final lastIdx = _idx.removeLast();
    if (_f.isNotEmpty) {
      _f[0] = lastF;
      _idx[0] = lastIdx;
      var k = 0;
      for (;;) {
        final l = 2 * k + 1;
        final r = l + 1;
        var m = k;
        if (l < _f.length && _f[l] < _f[m]) m = l;
        if (r < _f.length && _f[r] < _f[m]) m = r;
        if (m == k) break;
        _swap(m, k);
        k = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final tf = _f[a];
    _f[a] = _f[b];
    _f[b] = tf;
    final ti = _idx[a];
    _idx[a] = _idx[b];
    _idx[b] = ti;
  }
}

/// Pure-Dart 8-connected A* / Dijkstra terrain router (PLAN section 6.3).
/// Uses Float32List g-scores, Int32List parent pointers, and an array binary heap.
class MarsRouter {
  static const double defaultMaxSlopeDeg = MissionConfig.maxPassableSlopeDeg;
  static const double exposureDeg = 15.0;

  static RouteResult? findRoute(
    TerrainGrid grid,
    GridPoint start,
    GridPoint goal,
    RouteWeights weights,
    RouteMode mode, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
    SearchAlgorithm algorithm = SearchAlgorithm.astar,
    List<ScienceTarget> targets = kVerifiedScienceTargets,
  }) {
    final w = grid.w;
    final h = grid.h;

    double stepCost(int i, int j, int nx, int ny, double stepDistM) {
      if (grid.nodata[j] != 0 || grid.slope[j] > maxSlopeDeg) {
        return double.infinity;
      }
      final sl = grid.slope[j];
      final slNorm = sl / maxSlopeDeg;
      final slQuad = slNorm * slNorm;
      final dhPlus = math.max(0.0, grid.elev[j] - grid.elev[i]);

      double mult;
      if (mode == RouteMode.fastest) {
        // Quickest prioritizes distance and time with minimal slope penalty
        mult = 1.0 + MissionConfig.quickestWeightSlope * slQuad + MissionConfig.quickestWeightRoughness * grid.rough[j];
        return stepDistM * mult + MissionConfig.quickestWeightAscent * dhPlus;
      } else if (mode == RouteMode.safest) {
        // Safest heavily penalizes slopes (quadratic), roughness, and ascents
        mult = 1.0 + MissionConfig.safestWeightSlope * slQuad + MissionConfig.safestWeightRoughness * grid.rough[j] + MissionConfig.safestWeightUncertainty * grid.unc[j];
        return stepDistM * mult + MissionConfig.safestWeightAscent * dhPlus;
      } else {
        // Science mode balances safety and target attraction
        mult = 1.0 + MissionConfig.scienceWeightSlope * slQuad + MissionConfig.scienceWeightRoughness * grid.rough[j] + MissionConfig.scienceWeightUncertainty * grid.unc[j];
        var c = stepDistM * mult + MissionConfig.scienceWeightAscent * dhPlus;
        for (final t in targets) {
          final d = math.sqrt((nx - t.x) * (nx - t.x) + (ny - t.y) * (ny - t.y));
          if (d < 6.0) {
            c *= (1.0 - 0.55 * t.value * (1.0 - d / 6.0));
          }
        }
        return math.max(0.1, c);
      }
    }

    final si = start.y * w + start.x;
    final ti = goal.y * w + goal.x;
    if (grid.nodata[si] != 0 || grid.slope[si] > maxSlopeDeg ||
        grid.nodata[ti] != 0 || grid.slope[ti] > maxSlopeDeg) {
      return null;
    }

    final n = w * h;
    final g = Float32List(n)..fillRange(0, n, double.infinity);
    final from = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    final heap = _MinHeap();

    double heuristic(int x, int y) {
      if (algorithm == SearchAlgorithm.dijkstra) return 0.0;
      final dx = (x - goal.x).abs();
      final dy = (y - goal.y).abs();
      final straightLineM = grid.distanceForCellDelta(dx, dy);
      return straightLineM * (mode == RouteMode.science ? 0.45 : 1.0);
    }

    g[si] = 0.0;
    heap.push(heuristic(start.x, start.y), si);
    var expanded = 0;

    while (heap.isNotEmpty) {
      final i = heap.pop();
      if (closed[i] != 0) continue;
      closed[i] = 1;
      expanded++;
      if (i == ti) break;

      final x = i % w;
      final y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (closed[j] != 0) continue;
          final stepDistM = grid.distanceForCellDelta(dx, dy);
          final c = stepCost(i, j, nx, ny, stepDistM);
          if (!c.isFinite) continue;
          final ng = g[i] + c;
          if (ng < g[j]) {
            g[j] = ng;
            from[j] = i;
            heap.push(ng + heuristic(nx, ny), j);
          }
        }
      }
    }

    if (from[ti] == -1 && si != ti) return null;

    final path = <GridPoint>[];
    for (var k = ti; k != -1; k = from[k]) {
      path.add(GridPoint(k % w, k ~/ w));
    }
    final ordered = path.reversed.toList();
    final smoothed = smoothPath(grid, ordered, maxSlopeDeg: maxSlopeDeg, mode: mode);

    return _buildMetrics(grid, smoothed, g[ti], mode, algorithm, expanded, targets);
  }

  /// Check 8-connected line of sight between two grid points using Bresenham.
  static bool hasLineOfSight(
    TerrainGrid grid,
    GridPoint a,
    GridPoint b, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
  }) {
    final pts = bresenhamLine(a, b);
    for (final pt in pts) {
      if (pt.x < 0 || pt.x >= grid.w || pt.y < 0 || pt.y >= grid.h) return false;
      final i = pt.y * grid.w + pt.x;
      if (grid.nodata[i] != 0 || grid.slope[i] > maxSlopeDeg) return false;
    }
    return true;
  }

  /// Standard 8-connected Bresenham line rasterizer.
  static List<GridPoint> bresenhamLine(GridPoint p0, GridPoint p1) {
    final pts = <GridPoint>[];
    var x0 = p0.x;
    var y0 = p0.y;
    final x1 = p1.x;
    final y1 = p1.y;
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx - dy;

    while (true) {
      pts.add(GridPoint(x0, y0));
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x0 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y0 += sy;
      }
    }
    return pts;
  }

  /// String-pulling path smoothing (PLAN section 6.3).
  /// Removes unnecessary staircase waypoints across passable line-of-sight cells,
  /// preserving 8-connected continuity and strict terrain exclusions.
  static List<GridPoint> smoothPath(
    TerrainGrid grid,
    List<GridPoint> path, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
    RouteMode mode = RouteMode.fastest,
  }) {
    if (path.length <= 2) return path;

    final waypoints = <GridPoint>[path.first];
    var curr = 0;
    // In Safest mode, string-pulling only shortcuts across very gentle terrain (<= 6.0°)
    // to strictly preserve detours around steeper slopes, scarps, and rough ground.
    final losSlopeLimit = (mode == RouteMode.safest) ? 6.0 : maxSlopeDeg;

    while (curr < path.length - 1) {
      var next = path.length - 1;
      // Greedily find the furthest visible waypoint along the path
      while (next > curr + 1) {
        if (hasLineOfSight(grid, path[curr], path[next], maxSlopeDeg: losSlopeLimit)) {
          break;
        }
        next--;
      }
      waypoints.add(path[next]);
      curr = next;
    }

    // Reconstruct 8-connected path between smoothed waypoints
    final fullSmoothed = <GridPoint>[waypoints.first];
    for (var i = 1; i < waypoints.length; i++) {
      final leg = bresenhamLine(waypoints[i - 1], waypoints[i]);
      // Skip first point of leg as it duplicates previous end
      for (var j = 1; j < leg.length; j++) {
        fullSmoothed.add(leg[j]);
      }
    }

    return fullSmoothed;
  }

  /// Plan routes with detour-capping: ensures Science route length <= 1.5x Fastest route.
  static RouteResult? findScienceRouteWithDetourCap(
    TerrainGrid grid,
    GridPoint start,
    GridPoint goal,
    double fastestDistM, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
    double maxDetourRatio = 1.5,
    List<ScienceTarget> targets = kDemoTargets,
  }) {
    var currentWeights = RouteWeights.defaultScience;
    RouteResult? bestResult;

    for (var attempt = 0; attempt < 3; attempt++) {
      final res = findRoute(
        grid,
        start,
        goal,
        currentWeights,
        RouteMode.science,
        maxSlopeDeg: maxSlopeDeg,
        targets: targets,
      );
      if (res == null) return bestResult;
      bestResult = res;

      final cap = fastestDistM * maxDetourRatio;
      if (res.distanceM <= cap) {
        return res; // Within acceptable detour ratio
      }

      // Detour cap exceeded: progressively increase distance weight / reduce detour
      currentWeights = RouteWeights(
        s: currentWeights.s,
        r: currentWeights.r,
        u: currentWeights.u,
        h: currentWeights.h * 1.8,
      );
    }
    return bestResult;
  }

  /// Snap an impassable tap to the nearest passable cell within ~100 m (3 cells).
  static GridPoint? snapToPassable(
    TerrainGrid grid,
    GridPoint pt, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
    int maxRadiusCells = 3,
  }) {
    for (var r = 0; r <= maxRadiusCells; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          final nx = pt.x + dx;
          final ny = pt.y + dy;
          if (nx < 0 || ny < 0 || nx >= grid.w || ny >= grid.h) continue;
          final i = ny * grid.w + nx;
          if (grid.nodata[i] == 0 && grid.slope[i] <= maxSlopeDeg) {
            return GridPoint(nx, ny);
          }
        }
      }
    }
    return null;
  }

  /// Validate continuity and hard slope/nodata exclusions.
  static bool validateRoute(
    TerrainGrid grid,
    RouteResult route, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
  }) {
    final p = route.path;
    if (p.isEmpty) return false;
    for (final pt in p) {
      final i = pt.y * grid.w + pt.x;
      if (grid.nodata[i] != 0 || grid.slope[i] > maxSlopeDeg) return false;
    }
    for (var k = 1; k < p.length; k++) {
      final dx = (p[k].x - p[k - 1].x).abs();
      final dy = (p[k].y - p[k - 1].y).abs();
      if (math.max(dx, dy) != 1) return false;
    }
    return true;
  }

  static RouteResult _buildMetrics(
    TerrainGrid grid,
    List<GridPoint> path,
    double totalCost,
    RouteMode mode,
    SearchAlgorithm algorithm,
    int expanded,
    List<ScienceTarget> targets,
  ) {
    var dist = 0.0;
    var maxSlope = 0.0;
    var sumSlope = 0.0;
    var sumRough = 0.0;
    var sumUnc = 0.0;
    var elevGain = 0.0;
    var exposed = 0;

    for (var k = 0; k < path.length; k++) {
      final p = path[k];
      final i = p.y * grid.w + p.x;
      if (grid.slope[i] > maxSlope) maxSlope = grid.slope[i];
      if (grid.slope[i] > exposureDeg) exposed++;
      sumSlope += grid.slope[i];
      sumRough += grid.rough[i];
      sumUnc += grid.unc[i];
      if (k > 0) {
        final q = path[k - 1];
        dist += grid.distanceForCellDelta(p.x - q.x, p.y - q.y);
        final dz = grid.elev[i] - grid.elev[q.y * grid.w + q.x];
        if (dz > 0) elevGain += dz;
      }
    }

    final n = path.length;
    final meanUnc = sumUnc / n;
    final sciHits = targets
        .where((t) => path.any((p) => math.sqrt((p.x - t.x) * (p.x - t.x) + (p.y - t.y) * (p.y - t.y)) < 4.0))
        .toList();
    final sciVal = sciHits.fold<double>(0.0, (a, t) => a + t.value);
    final conf = meanUnc < 0.3 ? 'MEDIUM' : (meanUnc < 0.5 ? 'LOW' : 'VERY LOW');

    return RouteResult(
      mode: mode,
      algorithm: algorithm,
      path: path,
      distanceM: dist,
      totalCost: totalCost,
      maxSlopeDeg: maxSlope,
      meanSlopeDeg: sumSlope / n,
      meanRough: sumRough / n,
      meanUnc: meanUnc,
      elevGainM: elevGain,
      exposureShare: exposed / n,
      scienceHits: sciHits,
      scienceValue: sciVal,
      confidence: conf,
      nodesExpanded: expanded,
    );
  }

  /// Explainable breakdown of scientific yield for a route under a chosen objective (P4).
  static ScienceBreakdown explainScienceScore(
    TerrainGrid grid,
    RouteResult route, {
    ScienceCampaignObjective objective = ScienceCampaignObjective.deltaLacustrine,
    List<ScienceTarget> targets = kDemoTargets,
  }) {
    final contribs = <ScienceTargetContribution>[];
    final unvisited = <ScienceTarget>[];
    var rawScore = 0.0;

    for (final t in targets) {
      double minDistCells = double.infinity;
      for (final p in route.path) {
        final d = math.sqrt((p.x - t.x) * (p.x - t.x) + (p.y - t.y) * (p.y - t.y));
        if (d < minDistCells) minDistCells = d;
      }
      final distM = minDistCells * grid.cellM;
      if (minDistCells <= 6.0) {
        final isMatch = objective.targetIds.contains(t.id);
        final multiplier = isMatch ? 1.5 : 1.0;
        final proximityFactor = (1.0 - minDistCells / 6.0);
        final pts = t.value * 25.0 * multiplier * proximityFactor;
        rawScore += pts;
        contribs.add(ScienceTargetContribution(
          target: t,
          distanceM: distM,
          baseValue: t.value,
          objectiveMultiplier: multiplier,
          points: pts,
          justification: isMatch
              ? 'Primary objective match: ${t.significance}'
              : 'Secondary landmark: ${t.note}',
        ));
      } else {
        unvisited.add(t);
      }
    }

    final finalScore = rawScore.round().clamp(0, 100);
    return ScienceBreakdown(
      objective: objective,
      totalScore: finalScore,
      contributions: contribs,
      unvisitedTargets: unvisited,
    );
  }
}
