// MARS-X routing core: choose 5-6 navigation landmarks along a route (no-GPS navigation).
// Science claims come ONLY from ScienceTarget data (which must carry a citation).
// Terrain-only landmarks are described from terrain numbers, never with invented science.

import 'dart:math' as math;

import 'cost_model.dart';
import 'mars_grid.dart';

class ScienceTarget {
  final String id;
  final String name;
  final int cell; // grid cell index
  final double importance; // 0..1
  final String summary; // why it matters (from a cited source)
  final List<String> minerals; // e.g. ['olivine', 'carbonate'] -> highlighted in UI
  final String citation;
  final String? imageAsset; // HiRISE crop / Mastcam-Z photo bundled with the app
  final String dataType; // MEASURED / DERIVED / HISTORICAL / SIMULATED

  const ScienceTarget({
    required this.id,
    required this.name,
    required this.cell,
    required this.importance,
    required this.summary,
    this.minerals = const [],
    required this.citation,
    this.imageAsset,
    this.dataType = 'DERIVED',
  });
}

class Landmark {
  final int order; // 1..K
  final int cell;
  final double distanceAlongM;
  final String name;
  final String kind; // 'science', 'high point', 'low point', 'slope break', 'destination'
  final String description; // plain-language terrain description
  final ScienceTarget? target; // non-null => show "why it matters" card + minerals
  // Leg FROM the previous landmark (or start) TO this one:
  final double legDistanceM;
  final double legBearingDeg;
  final String legCompass; // 'NNE' etc. (map-north; Mars has no global magnetic field!)
  final double legTimeS;
  final double legElevChangeM;
  final double legMaxSlopeDeg;

  const Landmark({
    required this.order,
    required this.cell,
    required this.distanceAlongM,
    required this.name,
    required this.kind,
    required this.description,
    required this.target,
    required this.legDistanceM,
    required this.legBearingDeg,
    required this.legCompass,
    required this.legTimeS,
    required this.legElevChangeM,
    required this.legMaxSlopeDeg,
  });
}

String compass16(double deg) {
  const names = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
  return names[((deg % 360) / 22.5 + 0.5).floor() % 16];
}

class _Sample {
  final int pathIdx;
  final double s;
  double sci = 0, distinct = 0, score = 0;
  ScienceTarget? target;
  String kind = 'terrain';
  _Sample(this.pathIdx, this.s);
}

/// Picks K landmarks (K = 6 for routes > 1.5 km, else 5). The last one is the destination.
List<Landmark> selectLandmarks(
  MarsGrid g,
  CostModel m,
  List<int> path,
  List<ScienceTarget> targets, {
  double sampleEveryM = 25,
  double targetRadiusM = 150,
  int? k,
}) {
  if (path.length < 2) return const [];
  // Cumulative distance along the path.
  final cum = List<double>.filled(path.length, 0);
  for (var i = 1; i < path.length; i++) {
    cum[i] = cum[i - 1] + g.distanceM(path[i - 1], path[i]);
  }
  final L = cum.last;
  final K = k ?? (L > 1500 ? 6 : 5);

  // 1. Samples every ~25 m (excluding start and goal).
  final samples = <_Sample>[];
  var next = sampleEveryM;
  for (var i = 1; i < path.length - 1; i++) {
    if (cum[i] >= next) {
      samples.add(_Sample(i, cum[i]));
      next = cum[i] + sampleEveryM;
    }
  }

  // 2. Score candidates: science value + terrain distinctiveness.
  double elevAtS(double s) {
    var lo = 0, hi = cum.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] < s) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return g.elevation[path[lo]].toDouble();
  }

  var maxCurv = 1e-6, maxProm = 1e-6;
  final curv = List<double>.filled(samples.length, 0);
  final prom = List<double>.filled(samples.length, 0);
  for (var j = 0; j < samples.length; j++) {
    final s = samples[j].s;
    final z = elevAtS(s);
    final zb = elevAtS(math.max(0.0, s - 50)), za = elevAtS(math.min(L, s + 50));
    curv[j] = (za - 2 * z + zb).abs(); // slope break
    var sum = 0.0;
    var n = 0;
    for (var o = -100.0; o <= 100.0; o += 25) {
      sum += elevAtS(math.min(L, math.max(0.0, s + o)));
      n++;
    }
    prom[j] = z - sum / n; // + high point, - low point
    maxCurv = math.max(maxCurv, curv[j]);
    maxProm = math.max(maxProm, prom[j].abs());
  }

  for (var j = 0; j < samples.length; j++) {
    final smp = samples[j];
    final cell = path[smp.pathIdx];
    smp.sci = g.science[cell].toDouble();
    // Nearest cited target within radius.
    double bestD = double.infinity;
    for (final t in targets) {
      final d = g.distanceM(cell, t.cell);
      if (d <= targetRadiusM && d < bestD) {
        bestD = d;
        smp.target = t;
      }
    }
    var penalty = 0.0;
    if (smp.target != null) {
      smp.sci = math.max(smp.sci, smp.target!.importance);
      penalty = 0.2 * bestD / targetRadiusM;
    }
    final c = curv[j] / maxCurv, p = prom[j].abs() / maxProm;
    smp.distinct = math.max(c, p);
    smp.kind = smp.target != null
        ? 'science'
        : (p >= c ? (prom[j] >= 0 ? 'high point' : 'low point') : 'slope break');
    smp.score = 0.6 * smp.sci + 0.4 * smp.distinct - penalty;
  }

  // 3. Dynamic programming: choose K-1 intermediate samples + destination,
  //    maximising score with gap limits around the ideal spacing L/K.
  List<int>? choose(double minF, double maxF) {
    final ideal = L / K;
    final gMin = minF * ideal, gMax = maxF * ideal;
    final need = K - 1;
    final N = samples.length;
    if (need == 0) return [];
    if (N < need) return null;
    const neg = -1e18;
    final dp = List.generate(need, (_) => List<double>.filled(N, neg));
    final back = List.generate(need, (_) => List<int>.filled(N, -1));
    for (var i = 0; i < N; i++) {
      final gap = samples[i].s;
      if (gap >= gMin && gap <= gMax) dp[0][i] = samples[i].score;
    }
    for (var r = 1; r < need; r++) {
      for (var i = 0; i < N; i++) {
        for (var p = 0; p < i; p++) {
          if (dp[r - 1][p] == neg) continue;
          final gap = samples[i].s - samples[p].s;
          if (gap < gMin || gap > gMax) continue;
          final v = dp[r - 1][p] + samples[i].score;
          if (v > dp[r][i]) {
            dp[r][i] = v;
            back[r][i] = p;
          }
        }
      }
    }
    var best = -1;
    var bestV = neg;
    for (var i = 0; i < N; i++) {
      final gap = L - samples[i].s;
      if (dp[need - 1][i] != neg && gap >= gMin && gap <= gMax && dp[need - 1][i] > bestV) {
        bestV = dp[need - 1][i];
        best = i;
      }
    }
    if (best < 0) return null;
    final picked = <int>[];
    for (var r = need - 1, i = best; r >= 0; r--) {
      picked.add(i);
      i = back[r][i];
    }
    return picked.reversed.toList();
  }

  var picked = choose(0.5, 1.8) ?? choose(0.3, 2.5);
  if (picked == null) {
    // Fallback: evenly spaced terrain landmarks.
    picked = [];
    for (var r = 1; r < K; r++) {
      final target = L * r / K;
      var bi = 0;
      for (var j = 0; j < samples.length; j++) {
        if ((samples[j].s - target).abs() < (samples[bi].s - target).abs()) bi = j;
      }
      if (samples.isNotEmpty && !picked.contains(bi)) picked.add(bi);
    }
  }

  // 4. Build landmark records with leg info.
  final stops = <(int pathIdx, _Sample? smp)>[
    for (final j in picked) (samples[j].pathIdx, samples[j]),
    (path.length - 1, null), // destination
  ];
  final out = <Landmark>[];
  var prevIdx = 0;
  for (var o = 0; o < stops.length; o++) {
    final (pi, smp) = stops[o];
    final cell = path[pi];
    final prevCell = path[prevIdx];
    var legTime = 0.0, legMax = 0.0;
    for (var q = prevIdx + 1; q <= pi; q++) {
      legTime += m.stepTime(path[q - 1], path[q]);
      legMax = math.max(legMax, g.slopeDeg[path[q]].toDouble());
    }
    final bearing = g.bearingDeg(prevCell, cell);
    final dz = (g.elevation[cell] - g.elevation[prevCell]).toDouble();
    final kind = smp == null ? 'destination' : smp.kind;
    final t = smp?.target;
    final name = t?.name ??
        (kind == 'destination' ? 'Destination' : 'Waypoint ${o + 1} (${kind})');
    out.add(Landmark(
      order: o + 1,
      cell: cell,
      distanceAlongM: cum[pi],
      name: name,
      kind: kind,
      description: _describe(g, cell, kind, dz, legMax),
      target: t,
      legDistanceM: cum[pi] - cum[prevIdx],
      legBearingDeg: bearing,
      legCompass: compass16(bearing),
      legTimeS: legTime,
      legElevChangeM: dz,
      legMaxSlopeDeg: legMax,
    ));
    prevIdx = pi;
  }
  return out;
}

String _describe(MarsGrid g, int cell, String kind, double dz, double legMax) {
  final climb = dz.abs() < 2
      ? 'mostly level'
      : (dz > 0 ? 'climbing ${dz.toStringAsFixed(0)} m' : 'descending ${(-dz).toStringAsFixed(0)} m');
  final ground = g.roughness[cell] > 0.6
      ? 'rocky, uneven ground'
      : (g.hazard[cell] > 0.4 ? 'possible soft sand' : 'firm ground');
  final what = switch (kind) {
    'high point' => 'Local high point: good spot to look back and sight the next landmark.',
    'low point' => 'Local low point: the ground rises around you.',
    'slope break' => 'Slope changes here: watch your footing.',
    'science' => 'Science stop.',
    _ => 'End of traverse.',
  };
  return '$what Leg is $climb, max slope ${legMax.toStringAsFixed(0)} deg; $ground.';
}
