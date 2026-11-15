import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_x/domain/geo/mars_geodesy.dart';
import 'package:mars_x/domain/routing/astar.dart';
import 'package:mars_x/domain/terrain/terrain_grid.dart';
import 'package:mars_x/domain/track/landmark_selector.dart';
import 'package:mars_x/domain/track/risk.dart';
import 'package:mars_x/features/report/mission_report_screen.dart';

void main() {
  test('MarsGeodesy uses Mars radius (~59.27 km per degree latitude)', () {
    final d = MarsGeodesy.distanceM(77.4, 18.0, 77.4, 19.0);
    expect(d, closeTo(59274.7, 100.0));
  });

  test('A* matches Dijkstra cost and passes route validation', () {
    const w = 40;
    const h = 30;
    final elev = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        elev[y * w + x] = (x * 4.0) + ((y - 15).abs() * 1.5);
      }
    }
    final grid = TerrainGrid.fromElevation(w: w, h: h, cellM: 35.99, elev: elev);
    const a = GridPoint(2, 2);
    const b = GridPoint(35, 25);

    for (final mode in RouteMode.values) {
      final wt = RouteWeights.forMode(mode);
      final astar = MarsRouter.findRoute(grid, a, b, wt, mode, algorithm: SearchAlgorithm.astar);
      final dijk = MarsRouter.findRoute(grid, a, b, wt, mode, algorithm: SearchAlgorithm.dijkstra);
      expect(astar, isNotNull);
      expect(dijk, isNotNull);
      expect(astar!.totalCost, closeTo(dijk!.totalCost, 1e-4));
      expect(astar.nodesExpanded, lessThanOrEqualTo(dijk.nodesExpanded));
      expect(MarsRouter.validateRoute(grid, astar), isTrue);
    }
  });

  test('LandmarkSelector and RiskModel produce valid outputs', () {
    const w = 40;
    const h = 30;
    final grid = TerrainGrid.fromElevation(w: w, h: h, cellM: 35.99, elev: Float32List(w * h));
    final route = MarsRouter.findRoute(
      grid,
      const GridPoint(2, 15),
      const GridPoint(37, 15),
      RouteWeights.forMode(RouteMode.science),
      RouteMode.science,
    )!;
    final lms = LandmarkSelector.pick(grid, route);
    expect(lms.length, inInclusiveRange(5, 6));
    expect(lms.first.kind, LandmarkKind.start);
    expect(lms.last.kind, LandmarkKind.dest);

    final rk = RiskModel.assess(grid, route);
    expect(rk.score, inInclusiveRange(0, 100));
    expect(rk.consumables.crewSize, equals(2));
    expect(rk.consumables.totalEvaMin, greaterThan(0.0));
    expect(rk.consumables.oxygenKg, greaterThan(0.0));
    expect(rk.consumables.batteryKwh, greaterThan(0.0));
  });

  test('String-pulling path smoothing preserves 8-connected continuity and valid slope bounds', () {
    const w = 40;
    const h = 30;
    final elev = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        elev[y * w + x] = (x * 2.0);
      }
    }
    final grid = TerrainGrid.fromElevation(w: w, h: h, cellM: 35.99, elev: elev);
    final route = MarsRouter.findRoute(
      grid,
      const GridPoint(2, 5),
      const GridPoint(35, 25),
      RouteWeights.forMode(RouteMode.fastest),
      RouteMode.fastest,
    )!;

    expect(MarsRouter.validateRoute(grid, route), isTrue);
    expect(route.path.first, equals(const GridPoint(2, 5)));
    expect(route.path.last, equals(const GridPoint(35, 25)));
  });

  test('Science route with detour cap stays within 1.5x of fastest route', () {
    const w = 40;
    const h = 30;
    final grid = TerrainGrid.fromElevation(w: w, h: h, cellM: 35.99, elev: Float32List(w * h));
    const start = GridPoint(2, 10);
    const goal = GridPoint(36, 10);

    final fastest = MarsRouter.findRoute(
      grid,
      start,
      goal,
      RouteWeights.forMode(RouteMode.fastest),
      RouteMode.fastest,
    )!;

    final sciCapped = MarsRouter.findScienceRouteWithDetourCap(
      grid,
      start,
      goal,
      fastest.distanceM,
      maxDetourRatio: 1.5,
    )!;

    expect(sciCapped.distanceM, lessThanOrEqualTo(fastest.distanceM * 1.5 + 1e-3));
  });

  test('All three route profiles have defined advantages and compromises', () {
    for (final mode in RouteMode.values) {
      final tradeoff = kRouteTradeoffs.firstWhere((t) => t.mode == mode);
      expect(tradeoff.advantages, isNotEmpty);
      expect(tradeoff.compromises, isNotEmpty);
      expect(tradeoff.advantageSummary, isNotEmpty);
      expect(tradeoff.compromiseSummary, isNotEmpty);
    }
  });

  test('All 15 Jezero expedition landmarks are defined with coordinates and images', () {
    expect(kDemoTargets.length, equals(15));
    for (final t in kDemoTargets) {
      expect(t.name, isNotEmpty);
      expect(t.x, inInclusiveRange(0, 119));
      expect(t.y, inInclusiveRange(0, 75));
      expect(t.note, isNotEmpty);
      expect(t.imagePath, isNotEmpty);
      expect(t.significance, isNotEmpty);
    }
  });

  test('Three route profiles (Safest, Quickest, Scientific) produce measurably different routes across test pairs', () {
    const w = 60;
    const h = 50;
    final elev = Float32List(w * h);
    // Create an elevated ridge/scarp obstacle in the center
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var z = 0.0;
        // Central steep ridge between x=25 and x=35
        if (x >= 25 && x <= 35 && y >= 10 && y <= 40) {
          z = 250.0 * (1.0 - (x - 30).abs() / 6.0); // steep scarp
        } else if (y > 40) {
          z = (y - 40) * 2.0; // gentle bypass corridor
        }
        elev[y * w + x] = z;
      }
    }
    final grid = TerrainGrid.fromElevation(w: w, h: h, cellM: 35.99, elev: elev);

    final pairs = [
      (const GridPoint(10, 25), const GridPoint(50, 25)), // Spans across the steep ridge
      (const GridPoint(15, 15), const GridPoint(45, 35)), // Diagonal cross-ridge
      (const GridPoint(10, 30), const GridPoint(50, 45)), // Near bypass corridor
    ];

    for (final (start, goal) in pairs) {
      final fastest = MarsRouter.findRoute(grid, start, goal, RouteWeights.fastest, RouteMode.fastest)!;
      final safest = MarsRouter.findRoute(grid, start, goal, RouteWeights.safest, RouteMode.safest)!;
      final sci = MarsRouter.findScienceRouteWithDetourCap(grid, start, goal, fastest.distanceM, maxDetourRatio: 1.5)!;

      expect(safest.meanSlopeDeg, lessThanOrEqualTo(fastest.meanSlopeDeg));
      expect(fastest.distanceM, lessThanOrEqualTo(safest.distanceM + 1e-3));
      expect(sci.distanceM, lessThanOrEqualTo(fastest.distanceM * 1.5 + 1e-3));
      // Safest and fastest paths must not be completely identical across the ridge
      final isDifferent = safest.path.length != fastest.path.length ||
          safest.meanSlopeDeg != fastest.meanSlopeDeg ||
          safest.distanceM != fastest.distanceM;
      expect(isDifferent, isTrue);
    }
  });
}
