// MARS-X routing core: plans Fastest / Safest / Most scientific / Best-of-both routes.
//
// Flutter usage (keeps the UI smooth by running in a background isolate):
//   final result = await compute(planRoutesInIsolate, PlanRequest(grid, start, goal, targets));

import 'astar.dart';
import 'cost_model.dart';
import 'landmarks.dart';
import 'mars_grid.dart';
import 'risk.dart';

class PlannedRoute {
  final RouteProfile profile; // the profile actually used (wScience may be reduced by the detour cap)
  final List<int> cells;
  final RouteStats stats;
  final List<Landmark> landmarks;
  final int nodesExpanded;
  final List<String> notes; // shown to user, e.g. "start snapped 30 m to passable ground"

  const PlannedRoute(this.profile, this.cells, this.stats, this.landmarks,
      this.nodesExpanded, this.notes);
}

class PlanResult {
  /// Keyed by profile id. Value is null when no route exists under that profile's limits.
  final Map<String, PlannedRoute?> routes;
  final Map<String, String> failures; // profile id -> reason
  const PlanResult(this.routes, this.failures);
}

class PlanRequest {
  final MarsGrid grid;
  final int start;
  final int goal;
  final List<ScienceTarget> targets;
  final WalkModel walk;
  final List<RouteProfile> profiles;
  const PlanRequest(this.grid, this.start, this.goal, this.targets,
      {this.walk = const WalkModel(), this.profiles = RouteProfile.all});
}

/// Top-level function so it can be passed to Flutter's compute().
PlanResult planRoutesInIsolate(PlanRequest r) =>
    RoutePlanner(r.grid, r.targets, walk: r.walk).planAll(r.start, r.goal, profiles: r.profiles);

class RoutePlanner {
  final MarsGrid grid;
  final List<ScienceTarget> targets;
  final WalkModel walk;
  final double snapRadiusM;

  RoutePlanner(this.grid, this.targets,
      {this.walk = const WalkModel(), this.snapRadiusM = 100});

  PlanResult planAll(int start, int goal, {List<RouteProfile> profiles = RouteProfile.all}) {
    final routes = <String, PlannedRoute?>{};
    final failures = <String, String>{};

    // Fastest first: its time is the reference for detour caps.
    final ordered = [
      ...profiles.where((p) => p.detourCap == 0),
      ...profiles.where((p) => p.detourCap > 0),
    ];
    double? fastestTime;

    for (final p in ordered) {
      try {
        final route = _planOne(p, start, goal, fastestTime);
        routes[p.id] = route;
        if (p.id == RouteProfile.fastest.id) fastestTime = route.stats.timeS;
      } on RouteFailure catch (e) {
        routes[p.id] = null;
        failures[p.id] = e.message;
      }
    }
    return PlanResult(routes, failures);
  }

  PlannedRoute _planOne(RouteProfile profile, int start, int goal, double? fastestTime) {
    var p = profile;
    for (var attempt = 0; attempt < 5; attempt++) {
      final m = CostModel(grid, p, walk);
      final notes = <String>[];
      final s = _snap(m, start, 'Start', notes);
      final gl = _snap(m, goal, 'End', notes);
      final res = aStar(m, s, gl);
      if (res == null) {
        throw RouteFailure('No route within ${p.name} limits '
            '(max slope ${p.maxSlopeDeg.toStringAsFixed(0)} deg). '
            'Try other points or relax the limits.');
      }
      final cells = smoothPath(m, res.path);
      final problems = validatePath(m, cells, s, gl);
      if (problems.isNotEmpty) {
        throw RouteFailure('Internal check failed: ${problems.join(', ')}');
      }
      final stats = computeStats(grid, m, cells);

      // Detour cap for science-seeking profiles.
      if (p.detourCap > 0 &&
          fastestTime != null &&
          stats.timeS > p.detourCap * fastestTime &&
          p.wScience > 0) {
        p = p.copyWith(wScience: attempt == 3 ? 0.0 : p.wScience * 0.5);
        continue;
      }
      if (p.wScience < profile.wScience) {
        notes.add('Science weight reduced to ${p.wScience.toStringAsFixed(2)} '
            'to respect the ${profile.detourCap}x detour cap.');
      }
      final lms = selectLandmarks(grid, m, cells, targets);
      return PlannedRoute(p, cells, stats, lms, res.expanded, notes);
    }
    throw RouteFailure('Could not satisfy the detour cap.');
  }

  int _snap(CostModel m, int cell, String label, List<String> notes) {
    final snapped = snapToPassable(m, cell, snapRadiusM);
    if (snapped < 0) {
      throw RouteFailure('$label point is on impassable ground for ${m.profile.name} '
          'and no safe ground within ${snapRadiusM.toStringAsFixed(0)} m.');
    }
    if (snapped != cell) {
      notes.add('$label moved ${grid.distanceM(cell, snapped).toStringAsFixed(0)} m '
          'to the nearest passable ground.');
    }
    return snapped;
  }
}

class RouteFailure implements Exception {
  final String message;
  RouteFailure(this.message);
  @override
  String toString() => message;
}
