import 'dart:math' as math;
import '../geo/mars_geodesy.dart';
import '../routing/astar.dart';
import '../terrain/terrain_grid.dart';
import 'risk.dart';

enum LandmarkKind { start, dest, science, terrain }

class LandmarkLeg {
  final double bearingDeg;
  final String cardinal;
  final double distM;
  final double dElevM;
  final double slopeMinDeg;
  final double slopeMaxDeg;
  final double timeMin;

  const LandmarkLeg({
    required this.bearingDeg,
    required this.cardinal,
    required this.distM,
    required this.dElevM,
    required this.slopeMinDeg,
    required this.slopeMaxDeg,
    required this.timeMin,
  });
}

class Landmark {
  final int n;
  final int pathIdx;
  final GridPoint pt;
  final double sM;
  final String name;
  final LandmarkKind kind;
  final String desc;
  final String why;
  final ScienceTarget? target;
  final String imagePath;
  LandmarkLeg? next;

  Landmark({
    required this.n,
    required this.pathIdx,
    required this.pt,
    required this.sM,
    required this.name,
    required this.kind,
    required this.desc,
    required this.why,
    this.target,
    this.imagePath = '',
    this.next,
  });
}

class _Candidate {
  final int k;
  final double score;
  final LandmarkKind kind;
  final String name;
  final String desc;
  final String why;
  final ScienceTarget? target;

  const _Candidate({
    required this.k,
    required this.score,
    required this.kind,
    required this.name,
    required this.desc,
    required this.why,
    this.target,
  });
}

/// DP-based 5-6 landmark selector for no-GPS navigation (PLAN section 6.5).
class LandmarkSelector {
  static List<Landmark> pick(
    TerrainGrid grid,
    RouteResult route, {
    List<ScienceTarget> targets = kDemoTargets,
  }) {
    final p = route.path;
    final n = p.length;
    if (n < 2) return [];

    int at(int k) => p[k].y * grid.w + p[k].x;

    final s = List<double>.filled(n, 0.0);
    for (var k = 1; k < n; k++) {
      s[k] = s[k - 1] +
          math.sqrt((p[k].x - p[k - 1].x) * (p[k].x - p[k - 1].x) +
                  (p[k].y - p[k - 1].y) * (p[k].y - p[k - 1].y)) *
              grid.cellM;
    }

    final totalLen = s[n - 1];
    final kCount = totalLen < 6000 ? 5 : 6;
    final legs = kCount - 1;

    List<double> head(int k) {
      final a = p[math.max(0, k - 2)];
      final b = p[math.min(n - 1, k + 2)];
      final d = math.sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
      final denom = d == 0 ? 1.0 : d;
      return [(b.x - a.x) / denom, (b.y - a.y) / denom];
    }

    String side(int k) {
      double g(int x, int y) =>
          grid.elev[y.clamp(0, grid.h - 1) * grid.w + x.clamp(0, grid.w - 1)];
      final dx = -(g(p[k].x + 2, p[k].y) - g(p[k].x - 2, p[k].y));
      final dy = -(g(p[k].x, p[k].y + 2) - g(p[k].x, p[k].y - 2));
      final h = head(k);
      final cr = h[0] * dy - h[1] * dx;
      final mag = math.sqrt(dx * dx + dy * dy);
      if (mag < 8) return '';
      return cr > 0 ? 'ground drops to your right' : 'ground drops to your left';
    }

    final cands = <int, _Candidate>{};
    for (final t in targets) {
      var best = -1;
      var bd = 999.0;
      for (var k = 0; k < n; k++) {
        final d = math.sqrt((p[k].x - t.x) * (p[k].x - t.x) + (p[k].y - t.y) * (p[k].y - t.y));
        if (d < bd) {
          bd = d;
          best = k;
        }
      }
      if (bd <= 4.0 && best > 0 && best < n - 1) {
        final score = 0.6 * t.value + 0.4 * 0.5 - bd * 0.04;
        if (!cands.containsKey(best) || cands[best]!.score < score) {
          final offset = bd < 1.5 ? 'On the route' : 'About ${(bd * grid.cellM).toStringAsFixed(0)} m off the route';
          final sDesc = side(best);
          cands[best] = _Candidate(
            k: best,
            score: score,
            kind: LandmarkKind.science,
            name: t.name,
            desc: '${t.type}. $offset; ${sDesc.isNotEmpty ? sDesc : "gentle terrain"}.',
            why: '${t.note} Importance ${t.value.toStringAsFixed(2)} (simulated expert weight).',
            target: t,
          );
        }
      }
    }

    for (var k = 4; k < n - 4; k++) {
      final e = grid.elev[at(k)];
      final win = List.generate(9, (j) => grid.elev[at(k - 4 + j)]);
      final mx = win.reduce(math.max);
      final mn = win.reduce(math.min);
      final brk = (grid.slope[at(k)] - grid.slope[at(k - 3)]).abs();
      var name = '';
      var desc = '';
      var dScore = 0.0;
      if (e == mx && mx - mn > 25) {
        name = 'Ridge crest';
        dScore = math.min(1.0, (mx - mn) / 150.0);
        final sDesc = side(k);
        desc = 'Local high point, ${sDesc.isNotEmpty ? sDesc : "ground falls away"}.';
      } else if (e == mn && mx - mn > 25) {
        name = 'Local low';
        dScore = math.min(1.0, (mx - mn) / 150.0);
        desc = 'Local low point; ground rises ahead.';
      } else if (brk > 7) {
        name = 'Slope break';
        dScore = math.min(1.0, brk / 15.0);
        desc = 'Slope changes from ${grid.slope[at(k - 3)].toStringAsFixed(0)}° to ${grid.slope[at(k)].toStringAsFixed(0)}°.';
      }
      if (name.isNotEmpty && !cands.containsKey(k)) {
        cands[k] = _Candidate(
          k: k,
          score: 0.4 * dScore,
          kind: LandmarkKind.terrain,
          name: name,
          desc: desc,
          why: 'Terrain landmark derived from the HiRISE elevation model.',
        );
      }
    }

    final list = cands.values.toList()..sort((a, b) => a.k.compareTo(b.k));
    final lo = (0.5 * totalLen) / legs;
    final hi = (1.8 * totalLen) / legs;
    final m = kCount - 2;

    var mids = <_Candidate>[];
    if (list.isNotEmpty && m > 0) {
      final bestV = List.generate(m + 1, (_) => List.filled(list.length, double.negativeInfinity));
      final prev = List.generate(m + 1, (_) => List.filled(list.length, -1));
      for (var i = 0; i < list.length; i++) {
        final sk = s[list[i].k];
        if (sk >= lo && sk <= hi) {
          bestV[1][i] = list[i].score;
        }
      }
      for (var j = 2; j <= m; j++) {
        for (var i = 0; i < list.length; i++) {
          for (var h = 0; h < list.length; h++) {
            final gap = s[list[i].k] - s[list[h].k];
            if (gap >= lo && gap <= hi && bestV[j - 1][h].isFinite) {
              final candV = bestV[j - 1][h] + list[i].score;
              if (candV > bestV[j][i]) {
                bestV[j][i] = candV;
                prev[j][i] = h;
              }
            }
          }
        }
      }
      var bv = double.negativeInfinity;
      var bi = -1;
      for (var i = 0; i < list.length; i++) {
        final gap = totalLen - s[list[i].k];
        if (gap >= lo && gap <= hi && bestV[m][i] > bv) {
          bv = bestV[m][i];
          bi = i;
        }
      }
      if (bi >= 0) {
        final picked = <int>[];
        var i = bi;
        for (var j = m; j >= 1; j--) {
          picked.insert(0, i);
          i = prev[j][i];
        }
        mids = picked.map((idx) => list[idx]).toList();
      }
    }

    if (mids.length < m) {
      mids = List.generate(m, (j) {
        final targetDist = (totalLen * (j + 1)) / legs;
        var k = s.indexWhere((v) => v >= targetDist);
        if (k < 0) k = n - 2;
        k = k.clamp(1, n - 2);
        final near = list.where((c) => (s[c.k] - targetDist).abs() < lo * 0.6).toList();
        if (near.isNotEmpty) return near.first;
        final sDesc = side(k);
        return _Candidate(
          k: k,
          score: 0,
          kind: LandmarkKind.terrain,
          name: 'Waypoint',
          desc: 'Evenly spaced waypoint; ${sDesc.isNotEmpty ? sDesc : "gentle terrain"}.',
          why: 'Evenly spaced fallback landmark. No science claim is made for it.',
        );
      });
    }

    final out = <Landmark>[
      Landmark(
        n: 1,
        pathIdx: 0,
        pt: p[0],
        sM: 0.0,
        name: 'Start Point',
        kind: LandmarkKind.start,
        desc: 'Traverse departure coordinates. Observe local regolith and bearing before departure.',
        why: 'Base reference point for dead-reckoning excursion vectors.',
        imagePath: 'assets/landmarks/octavia-butler-landing.jpg',
      ),
      for (var j = 0; j < mids.length; j++)
        Landmark(
          n: j + 2,
          pathIdx: mids[j].k,
          pt: p[mids[j].k],
          sM: s[mids[j].k],
          name: mids[j].name,
          kind: mids[j].kind,
          desc: mids[j].desc,
          why: mids[j].why,
          target: mids[j].target,
          imagePath: mids[j].target?.imagePath ?? 'assets/landmarks/western-delta.jpg',
        ),
      Landmark(
        n: kCount,
        pathIdx: n - 1,
        pt: p[n - 1],
        sM: s[n - 1],
        name: 'Destination Outpost',
        kind: LandmarkKind.dest,
        desc: 'Final target waypoint of the excursion track.',
        why: 'Planned expedition destination. Establish sample depot cache and communications link.',
        imagePath: 'assets/landmarks/three-forks.jpg',
      ),
    ];

    for (var j = 0; j < out.length - 1; j++) {
      final a = out[j];
      final b = out[j + 1];
      final seg = p.sublist(a.pathIdx, b.pathIdx + 1);
      final sl = seg.map((q) => grid.slope[q.y * grid.w + q.x]).toList();
      final bearing = MarsGeodesy.gridBearingDeg(b.pt.x - a.pt.x, b.pt.y - a.pt.y);
      a.next = LandmarkLeg(
        bearingDeg: bearing,
        cardinal: MarsGeodesy.cardinal(bearing),
        distM: b.sM - a.sM,
        dElevM: grid.elev[b.pt.y * grid.w + b.pt.x] - grid.elev[a.pt.y * grid.w + a.pt.x],
        slopeMinDeg: sl.reduce(math.min),
        slopeMaxDeg: sl.reduce(math.max),
        timeMin: RiskModel.legTimeMin(grid, seg),
      );
    }

    return out;
  }
}
