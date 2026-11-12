import 'dart:math' as math;
import 'dart:typed_data';
import '../terrain/terrain_grid.dart';

enum RouteMode { safest, fastest, science }

enum SearchAlgorithm { astar, dijkstra }

class GridPoint {
  final int x;
  final int y;

  const GridPoint(this.x, this.y);

  @override
  bool operator ==(Object other) => other is GridPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
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

  static const RouteWeights defaultScience = RouteWeights(s: 40, r: 25, u: 20, h: 15);
  static const RouteWeights safest = RouteWeights(s: 50, r: 30, u: 15, h: 5);
  static const RouteWeights fastest = RouteWeights(s: 15, r: 10, u: 5, h: 70);

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
  static const double defaultMaxSlopeDeg = 25.0;
  static const double exposureDeg = 15.0;

  static RouteResult? findRoute(
    TerrainGrid grid,
    GridPoint start,
    GridPoint goal,
    RouteWeights weights,
    RouteMode mode, {
    double maxSlopeDeg = defaultMaxSlopeDeg,
    SearchAlgorithm algorithm = SearchAlgorithm.astar,
    List<ScienceTarget> targets = kDemoTargets,
  }) {
    final w = grid.w;
    final h = grid.h;
    final sum = (weights.s + weights.r + weights.u + weights.h) == 0
        ? 1.0
        : (weights.s + weights.r + weights.u + weights.h);
    final ws = weights.s / sum;
    final wr = weights.r / sum;
    final wu = weights.u / sum;
    final wh = weights.h / sum;

    double cellCost(int i, int x, int y) {
      if (grid.nodata[i] != 0 || grid.slope[i] > maxSlopeDeg) {
        return double.infinity;
      }
      var c = ws * (grid.slope[i] / maxSlopeDeg) +
          wr * grid.rough[i] +
          wu * grid.unc[i] +
          wh;
      if (mode == RouteMode.science) {
        for (final t in targets) {
          final d = math.sqrt((x - t.x) * (x - t.x) + (y - t.y) * (y - t.y));
          if (d < 6.0) {
            c *= 1.0 - 0.55 * t.value * (1.0 - d / 6.0);
          }
        }
      }
      return math.max(0.05, c);
    }

    final si = start.y * w + start.x;
    final ti = goal.y * w + goal.x;
    if (!cellCost(si, start.x, start.y).isFinite ||
        !cellCost(ti, goal.x, goal.y).isFinite) {
      return null;
    }

    final n = w * h;
    final g = Float32List(n)..fillRange(0, n, double.infinity);
    final from = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    final heap = _MinHeap();

    final minC = math.max(0.05, mode == RouteMode.science ? wh * 0.45 : wh);
    double heuristic(int x, int y) {
      if (algorithm == SearchAlgorithm.dijkstra) return 0.0;
      final dx = (x - goal.x).abs();
      final dy = (y - goal.y).abs();
      final octile = (dx + dy) + (math.sqrt2 - 2.0) * math.min(dx, dy);
      return octile * minC;
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
          final c = cellCost(j, nx, ny);
          if (!c.isFinite) continue;
          final step = (dx != 0 && dy != 0) ? math.sqrt2 : 1.0;
          final ng = g[i] + c * step;
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

    return _buildMetrics(grid, ordered, g[ti], mode, algorithm, expanded, targets);
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
        dist += math.sqrt((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)) * grid.cellM;
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
}
