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

class TerrainMapScreen extends ConsumerStatefulWidget {
  const TerrainMapScreen({super.key});

  @override
  ConsumerState<TerrainMapScreen> createState() => _TerrainMapScreenState();
}

class _TerrainMapScreenState extends ConsumerState<TerrainMapScreen> {
  final TransformationController _transController = TransformationController();
  bool _drawerExpanded = true;
  ScienceTarget? _selectedLandmark;

  @override
  void dispose() {
    _transController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final gridAsync = ref.watch(terrainGridProvider);
    final landmarksAsync = ref.watch(jezeroLandmarksProvider);
    final roverStopsAsync = ref.watch(roverStopsProvider);
    final craterRimAsync = ref.watch(ctxCraterRimPathsProvider);
    final st = ref.watch(plannerProvider);
    final notifier = ref.read(plannerProvider.notifier);

    return Scaffold(
      backgroundColor: MarsTheme.mapBg,
      body: gridAsync.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: MarsTheme.mars),
              SizedBox(height: 12),
              Text('Loading HiRISE Jezero DTM (35.99 m/px)...', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
        ),
        error: (e, _) => Center(child: Text('Failed to load HiRISE DTM: $e')),
        data: (grid) {
          return Stack(
            children: [
              // 1. FULL-SCREEN INTERACTIVE TERRAIN CANVAS
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    Widget canvasWidget = GestureDetector(
                      onTapUp: (details) {
                        // Invert current transformation matrix to find cell
                        final scenePoint = _transController.toScene(details.localPosition);
                        final dx = scenePoint.dx / constraints.maxWidth;
                        final dy = scenePoint.dy / constraints.maxHeight;
                        final x = (dx * grid.w).floor().clamp(0, grid.w - 1);
                        final y = (dy * grid.h).floor().clamp(0, grid.h - 1);

                        // Check if tapped near any of the 15 landmarks (within 3 cells)
                        ScienceTarget? hitLandmark;
                        for (final target in kDemoTargets) {
                          final dist = math.sqrt((target.x - x) * (target.x - x) + (target.y - y) * (target.y - y));
                          if (dist <= 3.5) {
                            hitLandmark = target;
                            break;
                          }
                        }

                        setState(() {
                          _selectedLandmark = hitLandmark;
                        });

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
                              landmarks: landmarksAsync.valueOrNull ?? const [],
                              roverStops: roverStopsAsync.valueOrNull ?? const [],
                              craterRimPaths: craterRimAsync.valueOrNull ?? const [],
                              showTerrain: st.layer != TerrainLayer.imagery,
                            ),
                            size: Size(constraints.maxWidth, constraints.maxHeight),
                          ),
                        ],
                      ),
                    );

                    if (st.tilt3D) {
                      canvasWidget = Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateX(-0.55 * (st.verticalExag / 2.5).clamp(0.6, 1.4)),
                        child: canvasWidget,
                      );
                    }

                    return InteractiveViewer(
                      transformationController: _transController,
                      minScale: 0.8,
                      maxScale: 6.0,
                      boundaryMargin: const EdgeInsets.all(120),
                      child: canvasWidget,
                    );
                  },
                ),
              ),

              // 2. TOP FLOATING CONTROLS: LAYER PILLS & ACTION BUTTONS
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: MarsTheme.paper.withOpacity(0.90),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MarsTheme.lineStrong),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final layer in TerrainLayer.values)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(layer.name.toUpperCase(), style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                                  selected: st.layer == layer,
                                  onSelected: (_) => notifier.setLayer(layer),
                                ),
                              ),
                            FilterChip(
                              label: const Text('CONTOURS', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                              selected: st.showContours,
                              onSelected: (_) => notifier.toggleContours(),
                            ),
                            const SizedBox(width: 4),
                            FilterChip(
                              label: const Text('3D TILT', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                              selected: st.tilt3D,
                              onSelected: (_) => notifier.toggleTilt3D(),
                            ),
                            const SizedBox(width: 4),
                            ActionChip(
                              avatar: const Icon(Icons.photo_library_outlined, size: 14),
                              label: const Text('15 LANDMARKS', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: MarsTheme.paper,
                                  builder: (ctx) => DraggableScrollableSheet(
                                    expand: false,
                                    initialChildSize: 0.78,
                                    maxChildSize: 0.94,
                                    minChildSize: 0.45,
                                    builder: (ctx, scrollCtrl) => _MappedLandmarksSheet(
                                      grid: grid,
                                      notifier: notifier,
                                      scrollController: scrollCtrl,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 4),
                            ActionChip(
                              avatar: const Icon(Icons.refresh, size: 14),
                              label: const Text('RESET', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                              onPressed: _resetZoom,
                            ),
                            const SizedBox(width: 4),
                            ActionChip(
                              avatar: const Icon(Icons.flag_outlined, size: 14),
                              label: const Text('PRACTICE', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                              onPressed: () => notifier.loadPracticeRoute(grid),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3D Vertical Exaggeration Slider if 3D Tilt enabled
                    if (st.tilt3D) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: MarsTheme.paper.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: MarsTheme.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('3D EXAG: ', style: TextStyle(fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold)),
                            SizedBox(
                              width: 140,
                              height: 30,
                              child: Slider(
                                min: 1.0,
                                max: 4.0,
                                value: st.verticalExag,
                                onChanged: notifier.setExag,
                              ),
                            ),
                            Text('${st.verticalExag.toStringAsFixed(1)}×', style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                          ],
                        ),
                      ),
                    ],

                    // Status / Tap Guidance Pill
                    if (st.statusMessage != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF191316).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFD3A24C)),
                        ),
                        child: Text(
                          st.statusMessage!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFF5F1E8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 3. TOP-RIGHT FLOATING CELL INSPECTOR / LANDMARK CALLOUT
              if (_selectedLandmark != null)
                Positioned(
                  top: 90,
                  right: 8,
                  child: _LandmarkMapCard(
                    target: _selectedLandmark!,
                    onClose: () => setState(() => _selectedLandmark = null),
                  ),
                )
              else if (st.inspected != null)
                Positioned(
                  top: 90,
                  right: 8,
                  child: _FloatingInspector(grid: grid, pt: st.inspected!),
                ),

              // 4. BOTTOM FLOATING ACTION DRAWER / ROUTE SELECTOR
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: _BottomRouteSheet(
                  grid: grid,
                  st: st,
                  notifier: notifier,
                  isExpanded: _drawerExpanded,
                  onToggleExpand: () => setState(() => _drawerExpanded = !_drawerExpanded),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LandmarkMapCard extends StatelessWidget {
  final ScienceTarget target;
  final VoidCallback onClose;

  const _LandmarkMapCard({required this.target, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF191316).withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD3A24C), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (target.imagePath.isNotEmpty)
            Stack(
              children: [
                Image.asset(
                  target.imagePath,
                  height: 90,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                    color: Color(0xFFF5F1E8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Coord: (${target.x}, ${target.y}) · ${target.type}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Color(0xFFD3A24C)),
                ),
                const SizedBox(height: 4),
                Text(
                  target.note,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Color(0xFFD6CBC7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingInspector extends StatelessWidget {
  final TerrainGrid grid;
  final GridPoint pt;

  const _FloatingInspector({required this.grid, required this.pt});

  @override
  Widget build(BuildContext context) {
    final i = pt.y * grid.w + pt.x;
    final passable = grid.nodata[i] == 0 && grid.slope[i] <= MarsRouter.defaultMaxSlopeDeg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF191316).withOpacity(0.90),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: passable ? const Color(0xFF7FA99B) : const Color(0xFFC3423F)),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('POINT (${pt.x}, ${pt.y})', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: passable ? const Color(0xFF395B50) : const Color(0xFF8B2624),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(passable ? 'PASSABLE' : 'HAZARD', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Elev: ${grid.elev[i].toStringAsFixed(1)} m · Slope: ${grid.slope[i].toStringAsFixed(1)}°\n'
            'Rough: ${grid.rough[i].toStringAsFixed(2)} · Pres: ${grid.pressureRel(i).toStringAsFixed(2)} (SIM)',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFD6CBC7)),
          ),
        ],
      ),
    );
  }
}

class _BottomRouteSheet extends ConsumerWidget {
  final TerrainGrid grid;
  final PlannerState st;
  final PlannerNotifier notifier;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _BottomRouteSheet({
    required this.grid,
    required this.st,
    required this.notifier,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (st.routes.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: MarsTheme.paper.withOpacity(0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MarsTheme.lineStrong),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                st.start == null
                    ? '1. Tap any cell to set START position.'
                    : '2. Tap destination cell to compute routes.',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.tonal(
              onPressed: () => notifier.loadPracticeRoute(grid),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('DEMO ROUTE', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MarsTheme.paper.withOpacity(0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MarsTheme.lineStrong),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.route, size: 16, color: MarsTheme.mars),
                  SizedBox(width: 6),
                  Text('ROUTE PROFILES', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
              IconButton(
                icon: Icon(isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 20),
                onPressed: onToggleExpand,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          if (isExpanded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (final mode in RouteMode.values)
                  if (st.routes[mode] != null)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _RoutePill(
                          mode: mode,
                          route: st.routes[mode]!,
                          risk: RiskModel.assess(grid, st.routes[mode]!),
                          selected: st.activeMode == mode,
                          onTap: () => notifier.setMode(mode),
                        ),
                      ),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: MarsTheme.ink,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: MarsTheme.line),
              ),
              child: Text(
                switch (st.activeMode) {
                  RouteMode.safest =>
                    'GAINED: Lowest slope hazard (≤18°) & highest suit reserve.  |  COMPROMISED: +25–40% detour distance & time.',
                  RouteMode.fastest =>
                    'GAINED: Shortest distance & fastest travel time.  |  COMPROMISED: Steeper slopes (up to 25°) & higher O₂ burn.',
                  RouteMode.science =>
                    'GAINED: Max science targets & sample diversity (≤1.5× detour cap).  |  COMPROMISED: Longer EVA & higher consumables.',
                },
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: MarsTheme.dim),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: MarsTheme.mars,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      // Navigate straight to Follow Tab!
                      ref.read(tabIndexProvider.notifier).state = 2;
                    },
                    icon: const Icon(Icons.explore, size: 16),
                    label: const Text('START 360° NAVIGATION →', style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Save Mission Offline',
                  icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                  onPressed: () async {
                    final route = st.activeRoute;
                    if (route != null && st.start != null && st.end != null) {
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
                          const SnackBar(content: Text('Mission saved to offline SQLite database.')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MappedLandmarksSheet extends StatefulWidget {
  final TerrainGrid grid;
  final PlannerNotifier notifier;
  final ScrollController scrollController;

  const _MappedLandmarksSheet({
    required this.grid,
    required this.notifier,
    required this.scrollController,
  });

  @override
  State<_MappedLandmarksSheet> createState() => _MappedLandmarksSheetState();
}

class _MappedLandmarksSheetState extends State<_MappedLandmarksSheet> {
  String _cat = 'ALL';

  @override
  Widget build(BuildContext context) {
    final filtered = _cat == 'ALL'
        ? kMappedJezeroLandmarks
        : kMappedJezeroLandmarks.where((l) => l.category == _cat).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('15 MAPPED JEZERO LANDMARKS', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('Authoritative USGS SIM 3464, FU Berlin WFS & NASA PDS Register', style: TextStyle(fontSize: 11, color: MarsTheme.dim)),
                ],
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final entry in [
                ('ALL', 'ALL (15)'),
                ('geological_features', 'GEOLOGICAL (6)'),
                ('rover_exploration', 'ROVER EXPLORATION (6)'),
                ('points_of_interest', 'POINTS OF INTEREST (3)'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(entry.$2, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                    selected: _cat == entry.$1,
                    onSelected: (_) => setState(() => _cat = entry.$1),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 12),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (context, idx) {
              final l = filtered[idx];
              final cell = (l.lonEast != null && l.latDeg != null)
                  ? widget.grid.georeference?.cellFor(l.lonEast!, l.latDeg!, widget.grid.w, widget.grid.h)
                  : null;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            l.assetPath,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1F1917)),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${l.geometryType.toUpperCase()} · ${l.subcategory.toUpperCase()}',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: Colors.white),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: DataBadge(l.isObserved ? DataType.observed : DataType.derived),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(l.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              ),
                              if (l.latDeg != null && l.lonEast != null)
                                Text(
                                  '${l.latDeg!.toStringAsFixed(3)}°N, ${l.lonEast!.toStringAsFixed(3)}°E',
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: MarsTheme.dim),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(l.geologicalDescription, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('Significance: ${l.scientificSignificance}', style: const TextStyle(fontSize: 11, color: MarsTheme.dim)),
                          if (l.perseveranceHistory != null) ...[
                            const SizedBox(height: 4),
                            Text('Rover History: ${l.perseveranceHistory}', style: const TextStyle(fontSize: 11, color: MarsTheme.marsDeep)),
                          ],
                          if (l.panoramaInfo != null) ...[
                            const SizedBox(height: 4),
                            Text('Mastcam-Z Panorama: ${l.panoramaInfo}', style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: MarsTheme.atmosDeep)),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text('Source: ${l.sourceName}', style: const TextStyle(fontFamily: 'monospace', fontSize: 9, color: MarsTheme.dim)),
                              ),
                              if (cell != null)
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    widget.notifier.tapCell(widget.grid, GridPoint(cell.x, cell.y));
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.place, size: 14),
                                  label: const Text('SET ON MAP', style: TextStyle(fontFamily: 'monospace', fontSize: 10)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoutePill extends StatelessWidget {
  final RouteMode mode;
  final RouteResult route;
  final RiskAssessment risk;
  final bool selected;
  final VoidCallback onTap;

  const _RoutePill({
    required this.mode,
    required this.route,
    required this.risk,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      RouteMode.safest => 'SAFEST',
      RouteMode.fastest => 'QUICKEST',
      RouteMode.science => 'SCIENTIFIC',
    };
    final accentColor = switch (mode) {
      RouteMode.safest => MarsTheme.sage,
      RouteMode.fastest => MarsTheme.atmos,
      RouteMode.science => MarsTheme.mars,
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accentColor.withOpacity(0.15) : MarsTheme.ink,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? accentColor : MarsTheme.line,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: selected ? accentColor : MarsTheme.fg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              '${(route.distanceM / 1000).toStringAsFixed(2)} km',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
            Text(
              '${risk.estimatedTimeMin.toStringAsFixed(0)} min · Max ${route.maxSlopeDeg.toStringAsFixed(1)}°',
              style: const TextStyle(fontSize: 8.5, color: MarsTheme.dim),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'RISK ${risk.score}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: risk.score > 60 ? MarsTheme.mars : MarsTheme.dim,
                  ),
                ),
                const Text(' · ', style: TextStyle(fontSize: 8, color: MarsTheme.dim)),
                Text(
                  'SCI ${risk.scienceScore}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: mode == RouteMode.science ? MarsTheme.mars : MarsTheme.dim,
                  ),
                ),
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

  _TerrainPainter({
    required this.grid,
    required this.st,
    this.landmarks = const [],
    this.roverStops = const [],
    this.craterRimPaths = const [],
    this.showTerrain = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / grid.w;
    final ch = size.height / grid.h;
    final paint = Paint();
    final elevSpan = (grid.maxElev - grid.minElev) == 0 ? 1.0 : (grid.maxElev - grid.minElev);

    if (showTerrain) {
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
            final b0 = (grid.elev[i] / 50.0).floor();
            final bx = (grid.elev[sy * grid.w + math.min(grid.w - 1, sx + stepX)] / 50.0).floor();
            final by = (grid.elev[math.min(grid.h - 1, sy + stepY) * grid.w + sx] / 50.0).floor();
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
          text: TextSpan(
            text: landmark.name,
            style: const TextStyle(
              color: Color(0xFFF5F1E8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: size.width * 0.45);
        label.paint(canvas, Offset(position.dx + 7, position.dy - label.height / 2));
      }
    }

    // Cited Science Targets (All 15 Jezero Landmarks)
    if (st.showTargets) {
      for (final t in kDemoTargets) {
        final cx = (t.x + 0.5) * cw;
        final cy = (t.y + 0.5) * ch;

        // Outer glow
        canvas.drawCircle(Offset(cx, cy), 5.5, Paint()..color = const Color(0x66F06543));
        // Inner circle
        canvas.drawCircle(Offset(cx, cy), 3.5, Paint()..color = const Color(0xFFF06543));
        // Border
        canvas.drawCircle(
          Offset(cx, cy),
          3.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }

    // Traversed Routes
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
        ..strokeWidth = isFocus ? 3.5 : 1.8
        ..style = PaintingStyle.stroke;
      final path = Path();
      path.moveTo((route.path.first.x + 0.5) * cw, (route.path.first.y + 0.5) * ch);
      for (final pt in route.path.skip(1)) {
        path.lineTo((pt.x + 0.5) * cw, (pt.y + 0.5) * ch);
      }
      canvas.drawPath(path, rp);
    }

    // Start / End Markers
    if (st.start != null) {
      canvas.drawCircle(
        Offset((st.start!.x + 0.5) * cw, (st.start!.y + 0.5) * ch),
        6.5,
        Paint()..color = const Color(0xFF0D0A0B),
      );
      canvas.drawCircle(
        Offset((st.start!.x + 0.5) * cw, (st.start!.y + 0.5) * ch),
        4.5,
        Paint()..color = const Color(0xFF7FA99B),
      );
    }
    if (st.end != null) {
      canvas.drawCircle(
        Offset((st.end!.x + 0.5) * cw, (st.end!.y + 0.5) * ch),
        6.5,
        Paint()..color = const Color(0xFF0D0A0B),
      );
      canvas.drawCircle(
        Offset((st.end!.x + 0.5) * cw, (st.end!.y + 0.5) * ch),
        4.5,
        Paint()..color = const Color(0xFFF06543),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter oldDelegate) => true;
}
