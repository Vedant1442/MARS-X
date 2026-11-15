import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mission_repo.dart';
import '../domain/routing/astar.dart';
import '../domain/terrain/terrain_grid.dart';
import '../domain/track/landmark_selector.dart';
import '../domain/track/risk.dart';
import '../domain/terrain/jezero_landmark.dart';

enum TerrainLayer { imagery, hillshade, elevation, slope, roughness, pressure }

final terrainGridProvider = FutureProvider<TerrainGrid>((ref) async {
  final data = await rootBundle.load('assets/terrain/jezero-ctx-100m-elevation.bin');
  final metadataText = await rootBundle.loadString('assets/terrain/jezero-ctx-100m-elevation.json');
  final metadata = jsonDecode(metadataText) as Map<String, dynamic>;
  return TerrainGrid.fromCtxBytes(data.buffer.asUint8List(), metadata: metadata);
});

final ctxCraterRimPathsProvider = FutureProvider<List<List<List<double>>>>((ref) async {
  final text = await rootBundle.loadString('assets/terrain/jezero-ctx-crater-rim.geojson');
  final collection = jsonDecode(text) as Map<String, dynamic>;
  final paths = <List<List<double>>>[];
  for (final rawFeature in collection['features'] as List<dynamic>) {
    final feature = rawFeature as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final rawLines = geometry['type'] == 'MultiLineString'
        ? geometry['coordinates'] as List<dynamic>
        : <dynamic>[geometry['coordinates']];
    for (final rawLine in rawLines) {
      final line = (rawLine as List<dynamic>)
          .map((rawPoint) {
            final point = rawPoint as List<dynamic>;
            return <double>[(point[0] as num).toDouble(), (point[1] as num).toDouble()];
          })
          .toList(growable: false);
      if (line.length > 1) paths.add(line);
    }
  }
  return paths;
});

final jezeroLandmarksProvider = FutureProvider<List<JezeroLandmark>>((ref) async {
  final text = await rootBundle.loadString('assets/terrain/jezero-landmarks.geojson');
  final collection = jsonDecode(text) as Map<String, dynamic>;
  final features = collection['features'] as List<dynamic>;
  return features
      .map((feature) => JezeroLandmark.fromGeoJsonFeature(feature as Map<String, dynamic>))
      .toList(growable: false);
});

final roverStopsProvider = FutureProvider<List<RoverStop>>((ref) async {
  final text = await rootBundle.loadString('assets/terrain/perseverance-rover-stops.geojson');
  final collection = jsonDecode(text) as Map<String, dynamic>;
  final features = collection['features'] as List<dynamic>;
  return features
      .map((feature) => RoverStop.fromGeoJsonFeature(feature as Map<String, dynamic>))
      .toList(growable: false);
});

final medaWeatherProvider = FutureProvider<Map<String, List<MedaReading>>>((ref) async {
  final text = await rootBundle.loadString('assets/terrain/meda-weather.json');
  final data = jsonDecode(text) as Map<String, dynamic>;
  final solsMap = data['sols'] as Map<String, dynamic>;
  final result = <String, List<MedaReading>>{};
  solsMap.forEach((solKey, list) {
    result[solKey] = (list as List<dynamic>)
        .map((e) => MedaReading.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  });
  return result;
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
  final bool isPlanning;
  final int selectedSol;
  final int selectedHour;
  final bool compareTraverse;
  final String scienceObjective;
  final bool showHazardCorridor;

  const PlannerState({
    this.start,
    this.end,
    this.inspected,
    this.activeMode = RouteMode.safest,
    this.layer = TerrainLayer.imagery,
    this.showContours = false,
    this.showTargets = true,
    this.tilt3D = false,
    this.verticalExag = 2.0,
    this.routes = const {},
    this.landmarkStep = 0,
    this.statusMessage,
    this.isPlanning = false,
    this.selectedSol = 20,
    this.selectedHour = 12,
    this.compareTraverse = false,
    this.scienceObjective = 'Delta Lacustrine & Biosignature Sampling',
    this.showHazardCorridor = false,
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
    bool? isPlanning,
    int? selectedSol,
    int? selectedHour,
    bool? compareTraverse,
    String? scienceObjective,
    bool? showHazardCorridor,
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
      isPlanning: isPlanning ?? this.isPlanning,
      selectedSol: selectedSol ?? this.selectedSol,
      selectedHour: selectedHour ?? this.selectedHour,
      compareTraverse: compareTraverse ?? this.compareTraverse,
      scienceObjective: scienceObjective ?? this.scienceObjective,
      showHazardCorridor: showHazardCorridor ?? this.showHazardCorridor,
    );
  }
}

class _RouteJob {
  final TerrainGrid grid;
  final GridPoint start;
  final GridPoint end;

  const _RouteJob({required this.grid, required this.start, required this.end});
}

List<RouteResult?> _computeRouteCandidates(_RouteJob job) {
  final fastest = MarsRouter.findRoute(job.grid, job.start, job.end, RouteWeights.forMode(RouteMode.fastest), RouteMode.fastest);
  final safest = MarsRouter.findRoute(job.grid, job.start, job.end, RouteWeights.forMode(RouteMode.safest), RouteMode.safest);
  final refDist = fastest?.distanceM ?? 10000.0;
  final science = MarsRouter.findScienceRouteWithDetourCap(
    job.grid,
    job.start,
    job.end,
    refDist,
    maxDetourRatio: 1.5,
  );
  return [safest, fastest, science];
}

class PlannerNotifier extends StateNotifier<PlannerState> {
  PlannerNotifier() : super(const PlannerState());
  int _routeRequest = 0;

  void tapCell(TerrainGrid grid, GridPoint raw) {
    final snapped = MarsRouter.snapToPassable(grid, raw);
    if (snapped == null) {
      state = state.copyWith(
        inspected: raw,
        statusMessage: 'No passable CTX cell within about ${(grid.cellM * 3).round()} m (slope > 25° or NoData nearby).',
      );
      return;
    }

    final snappedNote = (snapped != raw)
        ? 'Snapped to nearest passable cell (${snapped.x}, ${snapped.y}).'
        : null;

    if (state.start == null || (state.start != null && state.end != null)) {
      _routeRequest++;
      state = state.copyWith(
        start: snapped,
        clearEnd: true,
        inspected: snapped,
        routes: const {},
        isPlanning: false,
        landmarkStep: 0,
        statusMessage: snappedNote ?? 'Start set at (${snapped.x}, ${snapped.y}). Tap destination.',
      );
    } else {
      state = state.copyWith(
        end: snapped,
        inspected: snapped,
        statusMessage: snappedNote ?? 'Destination set at (${snapped.x}, ${snapped.y}). Ready to plan.',
      );
      unawaited(computeAllRoutes(grid));
    }
  }

  Future<void> computeAllRoutes(TerrainGrid grid) async {
    final s = state.start;
    final e = state.end;
    if (s == null || e == null) return;

    final request = ++_routeRequest;
    state = state.copyWith(isPlanning: true, statusMessage: 'Planning three candidate routes across the crater-wide terrain grid...');
    try {
      final results = await compute(_computeRouteCandidates, _RouteJob(grid: grid, start: s, end: e));
      if (!mounted || request != _routeRequest) return;
      final out = <RouteMode, RouteResult?>{
        for (var i = 0; i < RouteMode.values.length; i++) RouteMode.values[i]: results[i],
      };
      final found = out.values.any((route) => route != null);
      state = state.copyWith(
        routes: out,
        isPlanning: false,
        landmarkStep: 0,
        statusMessage: found ? null : 'No connected path was found between these points on the current 100 m terrain grid.',
        clearStatus: found,
      );
    } catch (error) {
      if (!mounted || request != _routeRequest) return;
      state = state.copyWith(isPlanning: false, statusMessage: 'Route calculation failed: $error');
    }
  }

  void loadPracticeRoute(TerrainGrid grid) {
    final georef = grid.georeference;
    if (georef == null) return;
    final landing = georef.cellFor(77.4509, 18.4446, grid.w, grid.h);
    final craterCenter = georef.cellFor(77.69, 18.41, grid.w, grid.h);
    if (landing == null || craterCenter == null) {
      state = state.copyWith(statusMessage: 'Practice locations are outside this installed terrain package.');
      return;
    }
    final s = MarsRouter.snapToPassable(grid, GridPoint(landing.x, landing.y), maxRadiusCells: 12);
    final e = MarsRouter.snapToPassable(grid, GridPoint(craterCenter.x, craterCenter.y), maxRadiusCells: 12);
    if (s == null || e == null) {
      state = state.copyWith(statusMessage: 'Could not find route endpoints near the landing site and crater-center reference.');
      return;
    }
    state = state.copyWith(
      start: s,
      end: e,
      inspected: s,
      statusMessage: 'Practice route: landing site to USGS gazetteer crater-center reference on the 100 m CTX grid.',
    );
    unawaited(computeAllRoutes(grid));
  }

  void setMode(RouteMode mode) => state = state.copyWith(activeMode: mode, landmarkStep: 0);
  void setLayer(TerrainLayer layer) => state = state.copyWith(layer: layer);
  void toggleContours() => state = state.copyWith(showContours: !state.showContours);
  void toggleTargets() => state = state.copyWith(showTargets: !state.showTargets);
  void toggleTilt3D() => state = state.copyWith(tilt3D: !state.tilt3D);
  void setExag(double v) => state = state.copyWith(verticalExag: v);
  void setStep(int step) => state = state.copyWith(landmarkStep: step);
  void setSol(int sol) => state = state.copyWith(selectedSol: sol);
  void setHour(int hour) => state = state.copyWith(selectedHour: hour);
  void toggleCompareTraverse() => state = state.copyWith(compareTraverse: !state.compareTraverse);
  void setScienceObjective(String obj) => state = state.copyWith(scienceObjective: obj);
  void toggleHazardCorridor() => state = state.copyWith(showHazardCorridor: !state.showHazardCorridor);
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
