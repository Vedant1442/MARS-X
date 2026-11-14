// Quick 2D demo/practice screen for the routing core.
// Tap once = start, tap again = end. Shows 4 routes, pick one, then step through landmarks.
// Uses only Flutter SDK (no extra packages). The 3D map team can reuse the same PlanResult.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/routing/cost_model.dart';
import '../../domain/routing/demo_terrain.dart';
import '../../domain/routing/mars_grid.dart';
import '../../domain/routing/route_planner.dart';

const routeColors = {
  'fastest': Color(0xFFFFB300),
  'safest': Color(0xFF43A047),
  'science': Color(0xFF8E24AA),
  'balanced': Color(0xFF1E88E5),
};

class RouteDemoScreen extends StatefulWidget {
  const RouteDemoScreen({super.key});
  @override
  State<RouteDemoScreen> createState() => _RouteDemoScreenState();
}

class _RouteDemoScreenState extends State<RouteDemoScreen> {
  late final DemoTerrain demo = buildDemoTerrain();
  ui.Image? image;
  int? start, goal;
  PlanResult? result;
  String? selected;
  int step = 0; // landmark index the astronaut is walking to
  bool busy = false;

  @override
  void initState() {
    super.initState();
    _renderTerrain(demo.grid).then((img) => setState(() => image = img));
  }

  Future<void> _plan() async {
    setState(() => busy = true);
    final r = await compute(planRoutesInIsolate,
        PlanRequest(demo.grid, start!, goal!, demo.targets));
    setState(() {
      result = r;
      selected = r.routes['balanced'] != null ? 'balanced' : r.routes.keys.first;
      step = 0;
      busy = false;
    });
  }

  void _onTap(Offset local, Size size) {
    final g = demo.grid;
    final x = (local.dx / size.width * g.width).floor().clamp(0, g.width - 1);
    final y = (local.dy / size.height * g.height).floor().clamp(0, g.height - 1);
    final cell = g.index(x.toInt(), y.toInt());
    setState(() {
      if (start == null || goal != null) {
        start = cell;
        goal = null;
        result = null;
      } else {
        goal = cell;
      }
    });
    if (goal != null) _plan();
  }

  @override
  Widget build(BuildContext context) {
    final route = selected == null ? null : result?.routes[selected];
    return Scaffold(
      backgroundColor: const Color(0xFF120A08),
      appBar: AppBar(
        title: const Text('MARS-X  Practice (SIMULATED terrain)'),
        backgroundColor: const Color(0xFF3E1F14),
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth > c.maxHeight;
        // Square map that always fits: limited by height on laptops, by width on phones.
        final side = wide
            ? math.min(c.maxHeight, c.maxWidth * 0.62)
            : math.min(c.maxWidth, c.maxHeight * 0.55);
        final map = SizedBox(width: side, height: side, child: _map(Size(side, side)));
        final panel = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (busy) const LinearProgressIndicator(),
          if (start == null) const _Hint('Tap the map to set the START point'),
          if (start != null && goal == null) const _Hint('Now tap the END point'),
          if (result != null) _routeChips(),
          if (route != null) Expanded(child: _stepper(route)) else const Spacer(),
        ]);
        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [map, Expanded(child: panel)])
            : Column(children: [Center(child: map), Expanded(child: panel)]);
      }),
    );
  }

  Widget _map(Size size) => GestureDetector(
        onTapUp: (d) => _onTap(d.localPosition, size),
        child: CustomPaint(
          size: size,
          painter: _MapPainter(demo.grid, image, start, goal, result, selected, step),
        ),
      );

  Widget _routeChips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          for (final p in RouteProfile.all)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selected == p.id,
                selectedColor: routeColors[p.id]!.withValues(alpha: 0.35),
                onSelected: result!.routes[p.id] == null
                    ? null
                    : (_) => setState(() {
                          selected = p.id;
                          step = 0;
                        }),
                label: Text(result!.routes[p.id] == null
                    ? '${p.name}: no route'
                    : '${p.name}\n'
                        '${(result!.routes[p.id]!.stats.timeS / 60).toStringAsFixed(0)} min · '
                        'risk ${result!.routes[p.id]!.stats.risk.score.toStringAsFixed(0)} · '
                        'sci ${result!.routes[p.id]!.stats.scienceScore.toStringAsFixed(0)}'),
              ),
            ),
        ]),
      );

  Widget _stepper(PlannedRoute r) {
    final lm = r.landmarks[step];
    final t = lm.target;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Text(r.profile.why, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 8),
      Text('Landmark ${lm.order}/${r.landmarks.length}: ${lm.name}',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(
          'Head ${lm.legCompass} (${lm.legBearingDeg.toStringAsFixed(0)}°) for '
          '${lm.legDistanceM.toStringAsFixed(0)} m · ~${(lm.legTimeS / 60).toStringAsFixed(0)} min · '
          '${lm.legElevChangeM >= 0 ? '+' : ''}${lm.legElevChangeM.toStringAsFixed(0)} m',
          style: const TextStyle(color: Colors.orangeAccent)),
      Text(lm.description, style: const TextStyle(color: Colors.white70)),
      if (t != null) ...[
        const SizedBox(height: 8),
        Text('Why it matters: ${t.summary}', style: const TextStyle(color: Colors.white)),
        Wrap(spacing: 6, children: [
          for (final mn in t.minerals)
            Chip(label: Text(mn), backgroundColor: Colors.purple.shade200),
        ]),
        Text('Source: ${t.citation} [${t.dataType}]',
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      ],
      Text(
          'Route risk ${r.stats.risk.score.toStringAsFixed(0)} (${r.stats.risk.level}) · '
          'max slope ${r.stats.maxSlopeDeg.toStringAsFixed(0)}° · SIMULATED',
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      for (final n in r.notes) Text(n, style: const TextStyle(color: Colors.amber)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton(
            onPressed: step == 0 ? null : () => setState(() => step--), child: const Text('Back')),
        FilledButton(
            onPressed: step >= r.landmarks.length - 1 ? null : () => setState(() => step++),
            child: const Text('Reached it · Next')),
      ]),
    ]);
  }
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(12), child: Text(text, style: const TextStyle(color: Colors.white)));
}

class _MapPainter extends CustomPainter {
  final MarsGrid g;
  final ui.Image? img;
  final int? start, goal;
  final PlanResult? result;
  final String? selected;
  final int step;
  _MapPainter(this.g, this.img, this.start, this.goal, this.result, this.selected, this.step);

  Offset _pt(int cell, Size s) =>
      Offset((g.xOf(cell) + 0.5) / g.width * s.width, (g.yOf(cell) + 0.5) / g.height * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    if (img != null) {
      canvas.drawImageRect(img!, Rect.fromLTWH(0, 0, g.width.toDouble(), g.height.toDouble()),
          Offset.zero & size, Paint()..filterQuality = FilterQuality.low);
    }
    final res = result;
    if (res != null) {
      // Draw unselected first, selected on top.
      final ids = [...res.routes.keys.where((k) => k != selected), if (selected != null) selected!];
      for (final id in ids) {
        final r = res.routes[id];
        if (r == null) continue;
        final path = Path()..moveTo(_pt(r.cells.first, size).dx, _pt(r.cells.first, size).dy);
        for (final c in r.cells.skip(1)) {
          final p = _pt(c, size);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = id == selected ? 4 : 2
              ..color = routeColors[id]!.withValues(alpha: id == selected ? 1 : 0.5));
        if (id == selected) {
          for (final lm in r.landmarks) {
            final p = _pt(lm.cell, size);
            final current = lm.order - 1 == step;
            canvas.drawCircle(p, current ? 9 : 6, Paint()..color = current ? Colors.white : Colors.black87);
            final tp = TextPainter(
                text: TextSpan(
                    text: '${lm.order}',
                    style: TextStyle(color: current ? Colors.black : Colors.white, fontSize: 10)),
                textDirection: TextDirection.ltr)
              ..layout();
            tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
          }
        }
      }
    }
    if (start != null) canvas.drawCircle(_pt(start!, size), 7, Paint()..color = Colors.greenAccent);
    if (goal != null) canvas.drawCircle(_pt(goal!, size), 7, Paint()..color = Colors.redAccent);
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) =>
      o.img != img || o.start != start || o.goal != goal || o.result != result ||
      o.selected != selected || o.step != step;
}

/// Hillshade tinted Mars-orange, red where slope > 25 deg, yellow on soft ground.
Future<ui.Image> _renderTerrain(MarsGrid g) {
  final px = Uint8List(g.cellCount * 4);
  final az = 315 * math.pi / 180, alt = 45 * math.pi / 180;
  for (var y = 0; y < g.height; y++) {
    for (var x = 0; x < g.width; x++) {
      final i = g.index(x, y);
      final z = g.elevation[i];
      double shade = 0.6;
      if (!z.isNaN) {
        final zx = g.elevation[g.index(math.min(x + 1, g.width - 1), y)] -
            g.elevation[g.index(math.max(x - 1, 0), y)];
        final zy = g.elevation[g.index(x, math.min(y + 1, g.height - 1))] -
            g.elevation[g.index(x, math.max(y - 1, 0))];
        final slope = math.atan(3 * math.sqrt(zx * zx + zy * zy) / (2 * g.cellSize));
        final aspect = math.atan2(zy, -zx);
        shade = (math.cos(alt) * math.cos(slope) +
                math.sin(alt) * math.sin(slope) * math.cos(az - aspect))
            .clamp(0.0, 1.0)
            .toDouble();
      }
      var r = 190 * shade + 30, gg = 110 * shade + 20, b = 70 * shade + 15;
      if (z.isNaN) {
        r = gg = b = 20;
      } else if (g.slopeDeg[i] > 25 || g.blocked[i] == 1) {
        r = 220;
        gg = 40;
        b = 40;
      } else if (g.hazard[i] > 0.5) {
        r = math.min(255.0, r + 40);
        gg = math.min(255.0, gg + 40);
      }
      px[i * 4] = r.toInt();
      px[i * 4 + 1] = gg.toInt();
      px[i * 4 + 2] = b.toInt();
      px[i * 4 + 3] = 255;
    }
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, g.width, g.height, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}
