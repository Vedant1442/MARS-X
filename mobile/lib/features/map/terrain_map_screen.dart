import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/mission_repo.dart';
import '../../domain/routing/astar.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../domain/terrain/jezero_landmark.dart';
import '../../domain/track/risk.dart';
import '../../shared/widgets/data_badge.dart';

class TerrainMapScreen extends ConsumerWidget {
  const TerrainMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridAsync = ref.watch(terrainGridProvider);
    final landmarksAsync = ref.watch(jezeroLandmarksProvider);
    final roverStopsAsync = ref.watch(roverStopsProvider);
    final craterRimAsync = ref.watch(ctxCraterRimPathsProvider);
    final st = ref.watch(plannerProvider);
    final notifier = ref.read(plannerProvider.notifier);

    return Column(
      children: [
        const HonestyBanner(),
        Expanded(
          child: gridAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load crater-wide CTX terrain: $e')),
            data: (grid) => ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _CoverageSummary(grid: grid),
                const SizedBox(height: 8),
                _LayerControls(st: st, notifier: notifier, grid: grid),
                const SizedBox(height: 8),
                _InteractiveMapCard(
                  grid: grid,
                  st: st,
                  notifier: notifier,
                  landmarks: landmarksAsync.valueOrNull ?? const [],
                  roverStops: roverStopsAsync.valueOrNull ?? const [],
                  craterRimPaths: craterRimAsync.valueOrNull ?? const [],
                ),
                const SizedBox(height: 8),
                _LandmarksInfoCard(
                  grid: grid,
                  landmarks: landmarksAsync.valueOrNull ?? const [],
                  notifier: notifier,
                ),
                _RoverDataCard(
                  grid: grid,
                  roverStops: roverStopsAsync.valueOrNull ?? const [],
                ),
                if (st.statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: MarsTheme.paper,
                      border: Border.all(color: MarsTheme.lineStrong),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      st.statusMessage!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: MarsTheme.fg),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (st.inspected != null) _InspectorCard(grid: grid, pt: st.inspected!),
                const SizedBox(height: 12),
                _RoutesComparisonCard(grid: grid, st: st, notifier: notifier),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverageSummary extends StatelessWidget {
  final TerrainGrid grid;

  const _CoverageSummary({required this.grid});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('JEZERO · CRATER-WIDE MAP', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                DataBadge(DataType.observed),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Offline CTX coverage is about ${(grid.cellWidthM * grid.w / 1000).toStringAsFixed(0)} × ${(grid.cellHeightM * grid.h / 1000).toStringAsFixed(0)} km, including terrain around the crater. Route planning uses ${grid.w} × ${grid.h} elevation cells at 100 m spacing.',
              style: const TextStyle(fontSize: 12, color: MarsTheme.dim),
            ),
            const SizedBox(height: 3),
            const Text(
              'The map rectangle is the image-data footprint, not the crater rim. Pinch to zoom; small rocks are below this route grid’s resolution.',
              style: TextStyle(fontSize: 11, color: MarsTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerControls extends StatelessWidget {
  final PlannerState st;
  final PlannerNotifier notifier;
  final TerrainGrid grid;

  const _LayerControls({required this.st, required this.notifier, required this.grid});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final layer in TerrainLayer.values)
          ChoiceChip(
            label: Text(layer.name.toUpperCase(), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            selected: st.layer == layer,
            onSelected: (_) => notifier.setLayer(layer),
          ),
        FilterChip(
          label: const Text('CONTOURS', style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
          selected: st.showContours,
          onSelected: (_) => notifier.toggleContours(),
        ),
        FilterChip(
          label: const Text('3D TILT', style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
          selected: st.tilt3D,
          onSelected: (_) => notifier.toggleTilt3D(),
        ),
        ActionChip(
          label: const Text('PRACTICE ROUTE', style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
          onPressed: () => notifier.loadPracticeRoute(grid),
        ),
      ],
    );
  }
}

class _InteractiveMapCard extends StatelessWidget {
  final TerrainGrid grid;
  final PlannerState st;
  final PlannerNotifier notifier;
  final List<JezeroLandmark> landmarks;
  final List<RoverStop> roverStops;
  final List<List<List<double>>> craterRimPaths;

  const _InteractiveMapCard({required this.grid, required this.st, required this.notifier, required this.landmarks, required this.roverStops, required this.craterRimPaths});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: grid.w / grid.h,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mapWidget = GestureDetector(
                  onTapUp: (details) {
                    final dx = details.localPosition.dx / constraints.maxWidth;
                    final dy = details.localPosition.dy / constraints.maxHeight;
                    final x = (dx * grid.w).floor().clamp(0, grid.w - 1);
                    final y = (dy * grid.h).floor().clamp(0, grid.h - 1);
                    notifier.tapCell(grid, GridPoint(x, y));
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/terrain/jezero-ctx-overview.png',
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stack) => const ColoredBox(color: MarsTheme.mapBg),
                      ),
                      CustomPaint(
                        painter: _TerrainPainter(
                          grid: grid,
                          st: st,
                          landmarks: landmarks,
                          roverStops: roverStops,
                          craterRimPaths: craterRimPaths,
                          showTerrain: st.layer != TerrainLayer.imagery,
                        ),
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                    ],
                  ),
                );
                Widget interactiveMap = InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 8.0,
                  boundaryMargin: const EdgeInsets.all(36),
                  constrained: false,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: mapWidget,
                  ),
                );
                if (st.tilt3D) {
                  interactiveMap = Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateX(-0.55 * (st.verticalExag / 2.5).clamp(0.6, 1.4)),
                    child: interactiveMap,
                  );
                }
                return ClipRect(child: Container(color: MarsTheme.mapBg, child: interactiveMap));
              },
            ),
          ),
          if (st.tilt3D)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Text('EXAGGERATION', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: MarsTheme.dim)),
                  Expanded(
                    child: Slider(
                      min: 1.0,
                      max: 4.0,
                      value: st.verticalExag,
                      onChanged: notifier.setExag,
                    ),
                  ),
                  Text('${st.verticalExag.toStringAsFixed(1)}×', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  st.layer == TerrainLayer.imagery
                      ? 'Whole-crater CTX image. Pinch to zoom and pan; mapped rim segments are incomplete.'
                      : 'Colors are derived from the USGS 20 m CTX DEM on a 100 m route grid. Small rocks are not resolved.',
                  style: const TextStyle(fontSize: 11, color: MarsTheme.dim),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(child: Text('Full Jezero CTX footprint · tap to set Start, then Destination · gold dots: archived rover positions', style: TextStyle(fontSize: 12, color: MarsTheme.dim))),
                    DataBadge(
                      st.layer == TerrainLayer.imagery
                          ? DataType.observed
                          : st.layer == TerrainLayer.pressure
                              ? DataType.simulated
                              : DataType.derived,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LandmarksInfoCard extends StatelessWidget {
  final TerrainGrid grid;
  final List<JezeroLandmark> landmarks;
  final PlannerNotifier notifier;

  const _LandmarksInfoCard({required this.grid, required this.landmarks, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PUBLISHED POINTS & MAP LABELS', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              grid.georeference == null
                  ? 'Landmark coordinates are installed offline. This DEM has no geographic transform, so pins are withheld until the georeferenced terrain package is installed.'
                  : 'Coordinates are transformed into the crater-wide CTX grid. USGS label anchors place printed text; they are not feature centers.',
              style: const TextStyle(fontSize: 12, color: MarsTheme.dim),
            ),
            const Divider(),
            for (final landmark in landmarks)
              Builder(builder: (context) {
                final cell = grid.georeference?.cellFor(
                  landmark.longitudeEastDeg,
                  landmark.latitudePlanetocentricDeg,
                  grid.w,
                  grid.h,
                );
                final status = grid.georeference == null
                    ? 'NOT GEOREFERENCED'
                    : cell == null
                        ? 'OUTSIDE THIS DTM'
                        : 'PINNED';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(cell == null ? Icons.place_outlined : Icons.place, color: MarsTheme.marsDeep),
                  title: Text(landmark.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${landmark.latitudePlanetocentricDeg.toStringAsFixed(landmark.coordinateDigits)}° N, ${landmark.longitudeEastDeg.toStringAsFixed(landmark.coordinateDigits)}° E · $status\n${landmark.note}\n${landmark.sourceLabel}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  isThreeLine: true,
                  onTap: cell == null ? null : () => notifier.tapCell(grid, GridPoint(cell.x, cell.y)),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _RoverDataCard extends StatelessWidget {
  final TerrainGrid grid;
  final List<RoverStop> roverStops;

  const _RoverDataCard({required this.grid, required this.roverStops});

  @override
  Widget build(BuildContext context) {
    final visible = roverStops.where((stop) {
      final cell = grid.georeference?.cellFor(
        stop.longitudeEastDeg,
        stop.latitudePlanetocentricDeg,
        grid.w,
        grid.h,
      );
      return cell != null;
    }).length;
    final latest = roverStops.isEmpty ? null : roverStops.last;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PERSEVERANCE ARCHIVE POSITIONS', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(
              '${roverStops.length} offline per-sol positions from PDS PLACES Release 16; $visible fall inside the crater-wide CTX footprint.',
              style: const TextStyle(fontSize: 12, color: MarsTheme.dim),
            ),
            const SizedBox(height: 4),
            Text(
              'This map covers about ${(grid.cellWidthM * grid.w / 1000).toStringAsFixed(1)} × ${(grid.cellHeightM * grid.h / 1000).toStringAsFixed(1)} km of Jezero and surrounding terrain. Route calculations use the 100 m CTX grid; unknown cells remain unavailable and small obstacles are unresolved.',
              style: const TextStyle(fontSize: 11, color: MarsTheme.dim),
            ),
            const SizedBox(height: 4),
            const Text(
              'Positions may be interpolated localizations. They are not camera poses, panorama locations, or a complete wheel track. This archive ends at sol 1897 (2026-06-21).',
              style: TextStyle(fontSize: 11, color: MarsTheme.dim),
            ),
            if (latest != null) ...[
              const Divider(),
              Text('Latest bundled location: sol ${latest.sol} · ${latest.latitudePlanetocentricDeg.toStringAsFixed(4)}° N, ${latest.longitudeEastDeg.toStringAsFixed(4)}° E', style: const TextStyle(fontSize: 11)),
            ],
            const SizedBox(height: 4),
            const Text('Source: PDS Geosciences Node, Mars 2020 Rover PLACES, best_interp.csv. See DATA SOURCES in the project documentation.', style: TextStyle(fontSize: 10, color: MarsTheme.dim)),
          ],
        ),
      ),
    );
  }
}

class _InspectorCard extends StatelessWidget {
  final TerrainGrid grid;
  final GridPoint pt;

  const _InspectorCard({required this.grid, required this.pt});

  @override
  Widget build(BuildContext context) {
    final i = pt.y * grid.w + pt.x;
    final passable = grid.nodata[i] == 0 && grid.slope[i] <= MarsRouter.defaultMaxSlopeDeg;
    final coordinates = grid.georeference?.pointForCell(pt.x, pt.y, grid.w, grid.h);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('CELL (${pt.x}, ${pt.y})', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                DataBadge(passable ? DataType.derived : DataType.unknown),
              ],
            ),
            const Divider(),
            Text(
              'Elevation: ${grid.elev[i].toStringAsFixed(1)} m  ·  Slope: ${grid.slope[i].toStringAsFixed(1)}°  ·  '
              'Roughness: ${grid.rough[i].toStringAsFixed(2)}  ·  Rel. Pressure: ${grid.pressureRel(i).toStringAsFixed(3)} (SIMULATED)',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              coordinates == null
                  ? 'Mars coordinates: unavailable (terrain transform missing)'
                  : 'Mars coordinates (grid-cell center): ${coordinates.latitudePlanetocentricDeg.toStringAsFixed(3)}° N, ${coordinates.longitudeEastDeg.toStringAsFixed(3)}° E',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.dim),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutesComparisonCard extends ConsumerWidget {
  final TerrainGrid grid;
  final PlannerState st;
  final PlannerNotifier notifier;

  const _RoutesComparisonCard({required this.grid, required this.st, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (st.isPlanning) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Expanded(child: Text('Calculating route candidates across the whole crater…')),
            ],
          ),
        ),
      );
    }
    if (st.routes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Tap Start and Destination on the map (or PRACTICE ROUTE) to compare lower modeled-cost, distance-priority, and terrain-balanced candidates.'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('CANDIDATE ROUTES', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                DataBadge(DataType.modeled),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Duration uses a slope-adjusted 1.4 m/s base walking model. Suit, fatigue, science-stop and life-support constraints are not modeled.',
              style: TextStyle(fontSize: 11, color: MarsTheme.dim),
            ),
            const SizedBox(height: 8),
            for (final mode in RouteMode.values)
              if (st.routes[mode] != null) ...[
                _RouteTile(
                  mode: mode,
                  route: st.routes[mode]!,
                  risk: RiskModel.assess(grid, st.routes[mode]!),
                  selected: st.activeMode == mode,
                  onTap: () => notifier.setMode(mode),
                ),
                const SizedBox(height: 6),
              ],
            if (st.activeRoute != null && st.start != null && st.end != null)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () async {
                    final route = st.activeRoute!;
                    final rk = RiskModel.assess(grid, route);
                    await ref.read(missionRepoProvider).saveMission(SavedMission(
                          name: 'Jezero ${st.activeMode.name.toUpperCase()}',
                          mode: st.activeMode.name,
                          startX: st.start!.x,
                          startY: st.start!.y,
                          endX: st.end!.x,
                          endY: st.end!.y,
                          distanceM: route.distanceM,
                          riskScore: rk.score,
                          currentStep: st.landmarkStep,
                          createdAt: DateTime.now().toIso8601String(),
                          gridId: grid.gridId,
                        ));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mission saved to offline SQLite storage.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('SAVE MISSION OFFLINE'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  final RouteMode mode;
  final RouteResult route;
  final RiskAssessment risk;
  final bool selected;
  final VoidCallback onTap;

  const _RouteTile({
    required this.mode,
    required this.route,
    required this.risk,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      RouteMode.safest => 'LOWER MODELED COST',
      RouteMode.fastest => 'DISTANCE-PRIORITY',
      RouteMode.science => 'TERRAIN-BALANCED',
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? MarsTheme.panel : MarsTheme.ink,
          border: Border.all(color: selected ? MarsTheme.marsDeep : MarsTheme.line, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                    '${(route.distanceM / 1000).toStringAsFixed(2)} km · ${risk.estimatedTimeMin.toStringAsFixed(0)} min · Max slope ${route.maxSlopeDeg.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 12, color: MarsTheme.dim),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('MODEL ${risk.score}/100', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.marsDeep)),
                Text('SCI ${route.scienceHits.length} VERIFIED', style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: MarsTheme.atmosDeep)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TerrainPainter extends CustomPainter {
  final TerrainGrid grid;
  final PlannerState st;
  final List<JezeroLandmark> landmarks;
  final List<RoverStop> roverStops;
  final List<List<List<double>>> craterRimPaths;
  final bool showTerrain;

  _TerrainPainter({required this.grid, required this.st, required this.landmarks, required this.roverStops, required this.craterRimPaths, required this.showTerrain});

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / grid.w;
    final ch = size.height / grid.h;
    final paint = Paint();
    final elevSpan = (grid.maxElev - grid.minElev) == 0 ? 1.0 : (grid.maxElev - grid.minElev);

    if (showTerrain) {
      // Draw at screen resolution, not once per 100 m cell. The underlying
      // grid remains full resolution for route calculations and inspection.
      final displayCols = math.min(grid.w, math.max(1, size.width.ceil()));
      final displayRows = math.min(grid.h, math.max(1, size.height.ceil()));
      final stepX = (grid.w / displayCols).ceil();
      final stepY = (grid.h / displayRows).ceil();
      for (var y = 0; y < grid.h; y += stepY) {
        final blockH = math.min(stepY, grid.h - y);
        for (var x = 0; x < grid.w; x += stepX) {
          final blockW = math.min(stepX, grid.w - x);
          final sx = x + blockW ~/ 2;
          final sy = y + blockH ~/ 2;
          final i = sy * grid.w + sx;
          if (grid.nodata[i] != 0) {
            paint.color = const Color(0xFF16181B);
            canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, blockW * cw + 0.5, blockH * ch + 0.5), paint);
            paint
              ..color = const Color(0xFF55585A)
              ..strokeWidth = 0.7;
            canvas.drawLine(Offset(x * cw, (y + blockH) * ch), Offset((x + blockW) * cw, y * ch), paint);
            continue;
          }
          final eL = grid.elev[sy * grid.w + math.max(0, sx - stepX)];
          final eR = grid.elev[sy * grid.w + math.min(grid.w - 1, sx + stepX)];
          final shade = (0.55 + (eL - eR) / 140.0).clamp(0.2, 1.15);

          double t;
          Color base;
          switch (st.layer) {
            case TerrainLayer.imagery:
              base = const Color(0x00000000);
              t = 0;
              break;
            case TerrainLayer.slope:
              t = (grid.slope[i] / MarsRouter.defaultMaxSlopeDeg).clamp(0.0, 1.0);
              base = Color.lerp(const Color(0xFF2B2724), const Color(0xFFB85C43), t)!;
              break;
            case TerrainLayer.roughness:
              t = grid.rough[i].clamp(0.0, 1.0);
              base = Color.lerp(const Color(0xFF2B2724), const Color(0xFFD3A24C), t)!;
              break;
            case TerrainLayer.pressure:
              t = ((grid.elev[i] - grid.minElev) / elevSpan).clamp(0.0, 1.0);
              base = Color.lerp(const Color(0xFF789BA8), const Color(0xFF2A2F3D), t)!;
              break;
            case TerrainLayer.elevation:
              t = ((grid.elev[i] - grid.minElev) / elevSpan).clamp(0.0, 1.0);
              base = Color.lerp(const Color(0xFF2F3540), const Color(0xFFEFE2C8), t)!;
              break;
            case TerrainLayer.hillshade:
              t = ((grid.elev[i] - grid.minElev) / elevSpan).clamp(0.0, 1.0);
              base = Color.lerp(const Color(0xFF3E2D24), const Color(0xFFC2A284), t)!;
              break;
          }

          paint.color = Color.fromARGB(
            255,
            (base.red * shade).round().clamp(0, 255),
            (base.green * shade).round().clamp(0, 255),
            (base.blue * shade).round().clamp(0, 255),
          );
          canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, blockW * cw + 0.4, blockH * ch + 0.4), paint);

          if (st.showContours && x + stepX < grid.w && y + stepY < grid.h) {
            final contourIntervalM = 50.0;
            final b0 = (grid.elev[i] / contourIntervalM).floor();
            final bx = (grid.elev[sy * grid.w + math.min(grid.w - 1, sx + stepX)] / contourIntervalM).floor();
            final by = (grid.elev[math.min(grid.h - 1, sy + stepY) * grid.w + sx] / contourIntervalM).floor();
            if (b0 != bx || b0 != by) {
              paint.color = const Color(0xAAFAF8F2);
              canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, blockW * cw, blockH * ch), paint);
            }
          }
        }
      }
    }

    final georef = grid.georeference;
    if (georef != null) {
      final rimPaint = Paint()
        ..color = const Color(0xFFFFD34F)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (final line in craterRimPaths) {
        final path = Path();
        var first = true;
        for (final coordinate in line) {
          final cell = georef.positionFor(coordinate[0], coordinate[1], grid.w, grid.h);
          final point = Offset((cell.x + 0.5) * cw, (cell.y + 0.5) * ch);
          if (first) {
            path.moveTo(point.dx, point.dy);
            first = false;
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path, rimPaint);
      }

      for (final stop in roverStops) {
        final cell = georef.cellFor(stop.longitudeEastDeg, stop.latitudePlanetocentricDeg, grid.w, grid.h);
        if (cell == null) continue;
        final position = Offset((cell.x + 0.5) * cw, (cell.y + 0.5) * ch);
        canvas.drawCircle(position, 2.8, Paint()..color = const Color(0xFFF3C969));
        canvas.drawCircle(position, 1.7, Paint()..color = const Color(0xFF1C2A31));
      }

      for (final landmark in landmarks) {
        final cell = georef.cellFor(landmark.longitudeEastDeg, landmark.latitudePlanetocentricDeg, grid.w, grid.h);
        if (cell == null) continue;
        final position = Offset((cell.x + 0.5) * cw, (cell.y + 0.5) * ch);
        canvas.drawCircle(position, 7, Paint()..color = MarsTheme.paper);
        canvas.drawCircle(position, 4.5, Paint()..color = MarsTheme.marsDeep);
        final label = TextPainter(
          text: TextSpan(text: landmark.name, style: const TextStyle(color: Color(0xFFF5F1E8), fontSize: 10, fontWeight: FontWeight.w600, shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)])),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width * 0.45);
        label.paint(canvas, Offset(position.dx + 7, position.dy - label.height / 2));
      }
    }

    for (final entry in st.routes.entries) {
      final route = entry.value;
      if (route == null || route.path.length < 2) continue;
      final isFocus = entry.key == st.activeMode;
      final color = switch (entry.key) {
        RouteMode.safest => MarsTheme.sage,
        RouteMode.fastest => MarsTheme.atmos,
        RouteMode.science => MarsTheme.mars,
      };
      final rp = Paint()
        ..color = color.withOpacity(isFocus ? 1.0 : 0.45)
        ..strokeWidth = isFocus ? 3.0 : 1.6
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo((route.path.first.x + 0.5) * cw, (route.path.first.y + 0.5) * ch);
      for (final pt in route.path.skip(1)) {
        path.lineTo((pt.x + 0.5) * cw, (pt.y + 0.5) * ch);
      }
      canvas.drawPath(path, rp);
    }

    if (st.start != null) {
      canvas.drawCircle(
        Offset((st.start!.x + 0.5) * cw, (st.start!.y + 0.5) * ch),
        5.5,
        Paint()..color = MarsTheme.ink,
      );
    }
    if (st.end != null) {
      canvas.drawCircle(
        Offset((st.end!.x + 0.5) * cw, (st.end!.y + 0.5) * ch),
        5.5,
        Paint()..color = MarsTheme.mars,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter oldDelegate) => true;
}
