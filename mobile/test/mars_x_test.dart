import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mars_x/domain/geo/mars_geodesy.dart';
import 'package:mars_x/domain/routing/astar.dart';
import 'package:mars_x/domain/terrain/terrain_grid.dart';
import 'package:mars_x/domain/track/landmark_selector.dart';
import 'package:mars_x/domain/track/risk.dart';

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
  });
}
