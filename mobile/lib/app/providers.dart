import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mission_repo.dart';
import '../domain/routing/astar.dart';
import '../domain/terrain/terrain_grid.dart';
import '../domain/track/landmark_selector.dart';
import '../domain/track/risk.dart';

enum TerrainLayer { hillshade, elevation, slope, roughness, pressure }

final terrainGridProvider = FutureProvider<TerrainGrid>((ref) async {
  final data = await rootBundle.load('assets/terrain/jezero-dem.bin');
  return TerrainGrid.fromHiRiseBytes(data.buffer.asUint8List());
});

class PlannerState {
  final GridPoint? start;
  final GridPoint? end;
  final GridPoint? inspected;
  final RouteMode activeMode;
  final TerrainLayer layer;
  final bool showContours;
  final bool showTargets;
  final bool tilt3D;
  final double verticalExag;
  final Map<RouteMode, RouteResult?> routes;
  final int landmarkStep;
  final String? statusMessage;

  const PlannerState({
    this.start,
    this.end,
    this.inspected,
    this.activeMode = RouteMode.safest,
    this.layer = TerrainLayer.hillshade,
    this.showContours = false,
    this.showTargets = true,
    this.tilt3D = false,
    this.verticalExag = 2.0,
    this.routes = const {},
    this.landmarkStep = 0,
    this.statusMessage,
  });

  RouteResult? get activeRoute => routes[activeMode];

  PlannerState copyWith({
    GridPoint? start,
    bool clearStart = false,
    GridPoint? end,
    bool clearEnd = false,
    GridPoint? inspected,
    RouteMode? activeMode,
    TerrainLayer? layer,
    bool? showContours,
    bool? showTargets,
    bool? tilt3D,
    double? verticalExag,
    Map<RouteMode, RouteResult?>? routes,
    int? landmarkStep,
    String? statusMessage,
    bool clearStatus = false,
  }) {
    return PlannerState(
      start: clearStart ? null : (start ?? this.start),
      end: clearEnd ? null : (end ?? this.end),
      inspected: inspected ?? this.inspected,
      activeMode: activeMode ?? this.activeMode,
      layer: layer ?? this.layer,
      showContours: showContours ?? this.showContours,
      showTargets: showTargets ?? this.showTargets,
      tilt3D: tilt3D ?? this.tilt3D,
      verticalExag: verticalExag ?? this.verticalExag,
      routes: routes ?? this.routes,
      landmarkStep: landmarkStep ?? this.landmarkStep,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
    );
  }
}

class PlannerNotifier extends StateNotifier<PlannerState> {
  PlannerNotifier() : super(const PlannerState());

  void tapCell(TerrainGrid grid, GridPoint raw) {
    final snapped = MarsRouter.snapToPassable(grid, raw);
    if (snapped == null) {
      state = state.copyWith(
        inspected: raw,
        statusMessage: 'Impassable cell (slope > 25° or no data). No passable cell within 100 m.',
      );
      return;
    }

    final snappedNote = (snapped != raw)
        ? 'Snapped to nearest passable cell (${snapped.x}, ${snapped.y}).'
        : null;

    if (state.start == null || (state.start != null && state.end != null)) {
      state = state.copyWith(
        start: snapped,
        clearEnd: true,
        inspected: snapped,
        routes: const {},
        landmarkStep: 0,
        statusMessage: snappedNote ?? 'Start set at (${snapped.x}, ${snapped.y}). Tap destination.',
      );
    } else {
      state = state.copyWith(
        end: snapped,
        inspected: snapped,
        statusMessage: snappedNote ?? 'Destination set at (${snapped.x}, ${snapped.y}). Ready to plan.',
      );
      computeAllRoutes(grid);
    }
  }

  void computeAllRoutes(TerrainGrid grid) {
    final s = state.start;
    final e = state.end;
    if (s == null || e == null) return;

    final out = <RouteMode, RouteResult?>{};
    // Compute fastest route first as reference for detour cap
    final fastest = MarsRouter.findRoute(grid, s, e, RouteWeights.forMode(RouteMode.fastest), RouteMode.fastest);
    out[RouteMode.fastest] = fastest;

    // Compute safest route with terrain risk weights
    out[RouteMode.safest] = MarsRouter.findRoute(grid, s, e, RouteWeights.forMode(RouteMode.safest), RouteMode.safest);

    // Compute science route respecting <= 1.5x detour cap relative to fastest
    final refDist = fastest?.distanceM ?? 10000.0;
    out[RouteMode.science] = MarsRouter.findScienceRouteWithDetourCap(
      grid,
      s,
      e,
      refDist,
      maxDetourRatio: 1.5,
    );

    state = state.copyWith(routes: out, landmarkStep: 0, clearStatus: true);
  }

  void loadPracticeRoute(TerrainGrid grid) {
    final s = MarsRouter.snapToPassable(grid, const GridPoint(10, 38), maxRadiusCells: 12);
    final e = MarsRouter.snapToPassable(grid, const GridPoint(106, 40), maxRadiusCells: 12);
    if (s == null || e == null) return;
    state = state.copyWith(start: s, end: e, inspected: s);
    computeAllRoutes(grid);
  }

  void setMode(RouteMode mode) => state = state.copyWith(activeMode: mode, landmarkStep: 0);
  void setLayer(TerrainLayer layer) => state = state.copyWith(layer: layer);
  void toggleContours() => state = state.copyWith(showContours: !state.showContours);
  void toggleTargets() => state = state.copyWith(showTargets: !state.showTargets);
  void toggleTilt3D() => state = state.copyWith(tilt3D: !state.tilt3D);
  void setExag(double v) => state = state.copyWith(verticalExag: v);
  void setStep(int step) => state = state.copyWith(landmarkStep: step);
}

final plannerProvider = StateNotifierProvider<PlannerNotifier, PlannerState>((ref) {
  return PlannerNotifier();
});

final landmarksProvider = Provider<List<Landmark>>((ref) {
  final grid = ref.watch(terrainGridProvider).valueOrNull;
  final route = ref.watch(plannerProvider).activeRoute;
  if (grid == null || route == null) return const [];
  return LandmarkSelector.pick(grid, route);
});

final riskProvider = Provider<RiskAssessment?>((ref) {
  final grid = ref.watch(terrainGridProvider).valueOrNull;
  final route = ref.watch(plannerProvider).activeRoute;
  if (grid == null || route == null) return null;
  return RiskModel.assess(grid, route);
});

final missionRepoProvider = Provider<MissionRepo>((ref) => MissionRepo());

final tabIndexProvider = StateProvider<int>((ref) => 0);
