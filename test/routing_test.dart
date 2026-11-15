import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mars_x/domain/routing/astar.dart';
import 'package:mars_x/domain/routing/cost_model.dart';
import 'package:mars_x/domain/routing/demo_terrain.dart';
import 'package:mars_x/domain/routing/landmarks.dart';
import 'package:mars_x/domain/routing/mars_grid.dart';
import 'package:mars_x/domain/routing/route_planner.dart';

MarsGrid plane(double slopeDeg, {int n = 20}) {
  final z = Float32List(n * n);
  final t = math.tan(slopeDeg * math.pi / 180);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      z[y * n + x] = (x * 10 * t);
    }
  }
  return MarsGrid.fromLayers(width: n, height: n, cellSize: 10, elevation: z);
}

void main() {
  test('Mars geometry: 1 deg latitude ~ 59.27 km (not Earth 111 km)', () {
    expect(marsMetresPerDegLat / 1000, closeTo(59.27, 0.01));
  });

  test('Horn slope on a tilted plane equals the plane angle; flat is 0', () {
    expect(plane(12).slopeDeg[10 * 20 + 10], closeTo(12, 0.01));
    expect(plane(0).slopeDeg[10 * 20 + 10], closeTo(0, 1e-6));
  });

  test('nodata is impassable', () {
    final z = Float32List(100)..fillRange(0, 100, -2500);
    z[55] = double.nan;
    final g = MarsGrid.fromLayers(width: 10, height: 10, cellSize: 10, elevation: z);
    expect(CostModel(g, RouteProfile.fastest).passable[55], 0);
  });

  group('demo terrain routing', () {
    final demo = buildDemoTerrain(size: 120, cellSize: 10 * 400 / 120);
    final g = demo.grid;

    test('edge costs are positive for every profile', () {
      for (final p in RouteProfile.all) {
        final m = CostModel(g, p);
        for (var i = 0; i < g.cellCount; i += 97) {
          if (g.xOf(i) + 1 >= g.width) continue;
          final c = m.edgeCost(i, i + 1);
          expect(c > 0, isTrue);
        }
      }
    });

    test('A* matches Dijkstra and expands fewer nodes (random pairs)', () {
      final rnd = math.Random(1);
      for (final p in RouteProfile.all) {
        final m = CostModel(g, p);
        final ok = [for (var i = 0; i < g.cellCount; i++) if (m.passable[i] == 1) i];
        for (var k = 0; k < 15; k++) {
          final s = ok[rnd.nextInt(ok.length)], t = ok[rnd.nextInt(ok.length)];
          final a = aStar(m, s, t), d = aStar(m, s, t, dijkstra: true);
          expect(a == null, d == null);
          if (a == null) continue;
          expect(a.cost, closeTo(d!.cost, 1e-6 * math.max(1, d.cost)));
          expect(a.expanded <= d.expanded, isTrue);
          final sm = smoothPath(m, a.path);
          expect(validatePath(m, sm, s, t), isEmpty);
          expect(pathCost(m, sm) <= a.cost * 1.02 + 1e-6, isTrue);
        }
      }
    });

    test('planner returns 4 routes with sensible trade-offs and 5-6 landmarks', () {
      final full = buildDemoTerrain();
      final r = RoutePlanner(full.grid, full.targets)
          .planAll(full.grid.index(30, 40), full.grid.index(330, 360));
      final f = r.routes['fastest']!, s = r.routes['safest']!, sc = r.routes['science']!;
      expect(s.stats.maxSlopeDeg <= f.stats.maxSlopeDeg, isTrue);
      expect(sc.stats.scienceScore >= f.stats.scienceScore, isTrue);
      expect(sc.stats.timeS <= 1.5 * f.stats.timeS + 1, isTrue);
      for (final route in r.routes.values) {
        final lm = route!.landmarks;
        expect(lm.length, inInclusiveRange(5, 6));
        expect(lm.last.kind, 'destination');
        for (var i = 1; i < lm.length; i++) {
          expect(lm[i].distanceAlongM > lm[i - 1].distanceAlongM, isTrue);
        }
        final risk = route.stats.risk.score;
        expect(risk >= 0 && risk <= 100, isTrue);
      }
    });

    test('compass16', () {
      expect(compass16(0), 'N');
      expect(compass16(95), 'E');
      expect(compass16(350), 'N');
      expect(compass16(225), 'SW');
    });
  });
}
