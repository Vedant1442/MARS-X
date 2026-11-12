import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/mission_repo.dart';
import '../../domain/routing/astar.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../domain/track/risk.dart';
import '../../shared/widgets/data_badge.dart';

class TerrainMapScreen extends ConsumerWidget {
  const TerrainMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gridAsync = ref.watch(terrainGridProvider);
    final st = ref.watch(plannerProvider);
    final notifier = ref.read(plannerProvider.notifier);

    return Column(
      children: [
        const HonestyBanner(),
        Expanded(
          child: gridAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Failed to load HiRISE DTM: $e')),
            data: (grid) => ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _LayerControls(st: st, notifier: notifier, grid: grid),
                const SizedBox(height: 8),
                _InteractiveMapCard(grid: grid, st: st, notifier: notifier),
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

  const _InteractiveMapCard({required this.grid, required this.st, required this.notifier});

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
                Widget mapWidget = GestureDetector(
                  onTapUp: (details) {
                    final dx = details.localPosition.dx / constraints.maxWidth;
                    final dy = details.localPosition.dy / constraints.maxHeight;
                    final x = (dx * grid.w).floor().clamp(0, grid.w - 1);
                    final y = (dy * grid.h).floor().clamp(0, grid.h - 1);
                    notifier.tapCell(grid, GridPoint(x, y));
                  },
                  child: CustomPaint(
                    painter: _TerrainPainter(grid: grid, st: st),
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                );
                if (st.tilt3D) {
                  mapWidget = Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0012)
                      ..rotateX(-0.55 * (st.verticalExag / 2.5).clamp(0.6, 1.4)),
                    child: mapWidget,
                  );
                }
                return Container(color: MarsTheme.mapBg, child: mapWidget);
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
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tap map: 1st = Start, 2nd = Destination', style: TextStyle(fontSize: 12, color: MarsTheme.dim)),
                DataBadge(st.layer == TerrainLayer.pressure ? DataType.simulated : DataType.derived),
              ],
            ),
          ),
        ],
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
    if (st.routes.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Tap Start and Destination on the map (or tap PRACTICE ROUTE) to compute Safest, Quickest, and Most Scientific routes.'),
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
      RouteMode.safest => 'SAFEST',
      RouteMode.fastest => 'QUICKEST',
      RouteMode.science => 'MOST SCIENTIFIC',
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
                Text('RISK ${risk.score}/100', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.marsDeep)),
                Text('SCI ${risk.scienceScore}/100', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: MarsTheme.atmosDeep)),
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

  _TerrainPainter({required this.grid, required this.st});

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / grid.w;
    final ch = size.height / grid.h;
    final paint = Paint();
    final elevSpan = (grid.maxElev - grid.minElev) == 0 ? 1.0 : (grid.maxElev - grid.minElev);

    for (var y = 0; y < grid.h; y++) {
      for (var x = 0; x < grid.w; x++) {
        final i = y * grid.w + x;
        final eL = grid.elev[y * grid.w + math.max(0, x - 1)];
        final eR = grid.elev[y * grid.w + math.min(grid.w - 1, x + 1)];
        final shade = (0.55 + (eL - eR) / 140.0).clamp(0.2, 1.15);

        double t;
        Color base;
        switch (st.layer) {
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
        canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.4, ch + 0.4), paint);

        if (st.showContours && x + 1 < grid.w && y + 1 < grid.h) {
          final b0 = (grid.elev[i] / 20.0).floor();
          final bx = (grid.elev[y * grid.w + x + 1] / 20.0).floor();
          final by = (grid.elev[(y + 1) * grid.w + x] / 20.0).floor();
          if (b0 != bx || b0 != by) {
            paint.color = const Color(0xAAFAF8F2);
            canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw, ch), paint);
          }
        }
      }
    }

    if (st.showTargets) {
      final tp = Paint()..color = MarsTheme.atmos;
      for (final t in kDemoTargets) {
        canvas.drawCircle(Offset((t.x + 0.5) * cw, (t.y + 0.5) * ch), 3.5, tp);
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
