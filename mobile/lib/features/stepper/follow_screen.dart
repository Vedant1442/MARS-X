import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../domain/routing/astar.dart';
import '../../domain/terrain/terrain_grid.dart';
import '../../domain/track/landmark_selector.dart';
import '../../shared/widgets/data_badge.dart';

enum FollowViewMode { photoCard, street360 }

class FollowScreen extends ConsumerStatefulWidget {
  const FollowScreen({super.key});

  @override
  ConsumerState<FollowScreen> createState() => _FollowScreenState();
}

class _FollowScreenState extends ConsumerState<FollowScreen> with SingleTickerProviderStateMixin {
  FollowViewMode _viewMode = FollowViewMode.photoCard;
  bool _showLost = false;

  // 360 View Controls
  double _camYaw = 0.0;
  double _camPitch = 0.0;
  Timer? _flyTimer;
  int? _flyPathIdx;

  @override
  void dispose() {
    _flyTimer?.cancel();
    super.dispose();
  }

  void _toggleFlyover(List<GridPoint> path) {
    if (_flyTimer != null) {
      _flyTimer?.cancel();
      setState(() {
        _flyTimer = null;
        _flyPathIdx = null;
      });
      return;
    }

    setState(() {
      _flyPathIdx = 0;
      _viewMode = FollowViewMode.street360;
    });

    _flyTimer = Timer.periodic(const Duration(milliseconds: 140), (t) {
      if (!mounted) return;
      setState(() {
        final curIdx = _flyPathIdx ?? 0;
        if (curIdx + 1 >= path.length) {
          t.cancel();
          _flyTimer = null;
          _flyPathIdx = null;
        } else {
          _flyPathIdx = curIdx + 1;
          // Dynamically adjust camera yaw to face forward along the path
          final p0 = path[curIdx];
          final p1 = path[curIdx + 1];
          final dx = (p1.x - p0.x).toDouble();
          final dy = (p1.y - p0.y).toDouble();
          if (dx != 0 || dy != 0) {
            _camYaw = math.atan2(dx, -dy);
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(terrainGridProvider).valueOrNull;
    final st = ref.watch(plannerProvider);
    final lms = ref.watch(landmarksProvider);
    final notifier = ref.read(plannerProvider.notifier);
    final route = st.activeRoute;

    if (grid == null || route == null || lms.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.explore_off_outlined, size: 48, color: MarsTheme.dim),
                SizedBox(height: 12),
                Text(
                  'NO ROUTE SELECTED',
                  style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Switch to the Map tab, select a Start and Destination, and tap "START 360° NAVIGATION" to guide the excursion.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: MarsTheme.dim),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final step = st.landmarkStep.clamp(0, lms.length - 1);
    final cur = lms[step];
    final nxt = step + 1 < lms.length ? lms[step + 1] : null;
    final hereIdx = _flyPathIdx ?? cur.pathIdx;

    final nearest = [...lms]
      ..removeWhere((l) => l.n == cur.n)
      ..sort((a, b) => (a.sM - cur.sM).abs().compareTo((b.sM - cur.sM).abs()));

    return Scaffold(
      backgroundColor: MarsTheme.bg,
      body: Column(
        children: [
          const HonestyBanner(),

          // Top Mode Switcher Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: MarsTheme.paper,
              border: Border(bottom: BorderSide(color: MarsTheme.line)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SegmentedButton<FollowViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: FollowViewMode.photoCard,
                      icon: Icon(Icons.photo_camera_outlined, size: 16),
                      label: Text('LANDMARK PHOTO', style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: FollowViewMode.street360,
                      icon: Icon(Icons.threesixty_outlined, size: 16),
                      label: Text('360° FLYOVER', style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (set) => setState(() => _viewMode = set.first),
                ),
                Text(
                  'STEP ${cur.n}/${lms.length}',
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // 1. MAIN VISUAL: PHOTO CARD vs 360 STREET VIEW
                if (_viewMode == FollowViewMode.photoCard)
                  _LandmarkPhotoCard(landmark: nxt ?? cur, isDestination: nxt == null)
                else
                  _Street360Viewport(
                    grid: grid,
                    route: route,
                    currentIdx: hereIdx,
                    currentLandmark: cur,
                    nextLandmark: nxt,
                    camYaw: _camYaw,
                    camPitch: _camPitch,
                    onPan: (dx, dy) {
                      setState(() {
                        _camYaw += dx * 0.008;
                        _camPitch = (_camPitch + dy * 0.006).clamp(-0.45, 0.45);
                      });
                    },
                    isPlaying: _flyTimer != null,
                    onTogglePlay: () => _toggleFlyover(route.path),
                  ),

                const SizedBox(height: 10),

                // 2. DEAD-RECKONING VECTOR TO NEXT LANDMARK
                if (nxt != null && cur.next != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MarsTheme.paper,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: MarsTheme.mars, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Transform.rotate(
                          angle: cur.next!.bearingDeg * math.pi / 180.0,
                          child: const Icon(Icons.navigation, size: 38, color: MarsTheme.mars),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'HEADING: ${cur.next!.bearingDeg.toStringAsFixed(0)}° ${cur.next!.cardinal} → NEXT: ${nxt.name}',
                                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Distance: ${(cur.next!.distM / 1000).toStringAsFixed(2)} km  ·  '
                                'Elev: ${cur.next!.dElevM >= 0 ? "+" : ""}${cur.next!.dElevM.toStringAsFixed(0)} m  ·  '
                                'Slope: ${cur.next!.slopeMinDeg.toStringAsFixed(0)}–${cur.next!.slopeMaxDeg.toStringAsFixed(0)}°  ·  '
                                '~${cur.next!.timeMin.toStringAsFixed(0)} min (SIM)',
                                style: const TextStyle(fontSize: 12, color: MarsTheme.dim),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                // 3. SCIENTIFIC CONTEXT & VISUAL CUE CARD
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MarsTheme.paper,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: MarsTheme.lineStrong),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('CURRENT LOCATION: ${cur.name}', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)),
                          const DataBadge(DataType.derived),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(cur.desc, style: const TextStyle(fontSize: 13)),
                      const Divider(height: 16),
                      const Text('SCIENTIFIC SIGNIFICANCE (PEER-REVIEWED)', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: MarsTheme.dim, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(cur.why, style: const TextStyle(fontSize: 12, color: MarsTheme.fg)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 4. STEPPER CONTROLS & I'M LOST TOOL
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: step > 0 ? () => notifier.setStep(step - 1) : null,
                        child: const Text('← PREV LANDMARK'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: MarsTheme.mars, foregroundColor: Colors.white),
                        onPressed: step < lms.length - 1 ? () => notifier.setStep(step + 1) : null,
                        child: const Text('REACHED · NEXT →'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _toggleFlyover(route.path),
                        icon: Icon(_flyTimer != null ? Icons.stop : Icons.threesixty, size: 18),
                        label: Text(_flyTimer != null ? 'STOP 360° FLYOVER' : 'PLAY 360° FLYOVER'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => setState(() => _showLost = !_showLost),
                      child: const Text("I'M LOST (RE-ANCHOR)"),
                    ),
                  ],
                ),

                if (_showLost) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191316),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD3A24C)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TRIANGULATE WITH 3 NEAREST VISIBLE LANDMARKS:', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFD3A24C), fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        for (final l in nearest.take(3))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${l.n}. ${l.name}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                            subtitle: Text(l.desc, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            trailing: Text(
                              '${(l.sM - cur.sM).abs().toStringAsFixed(0)} m',
                              style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFD3A24C)),
                            ),
                            onTap: () {
                              notifier.setStep(l.n - 1);
                              setState(() => _showLost = false);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photographic Visual Display for Next Landmark (Replaces the elevation chart)
class _LandmarkPhotoCard extends StatelessWidget {
  final Landmark landmark;
  final bool isDestination;

  const _LandmarkPhotoCard({required this.landmark, required this.isDestination});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF151012),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MarsTheme.lineStrong),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photographic Outcrop Scene
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _OutcropPainter(landmark: landmark),
                  ),
                ),

                // Top Badge Overlays
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFD3A24C)),
                    ),
                    child: Text(
                      isDestination ? 'DESTINATION OUTPOST' : 'TARGET: ${landmark.name.toUpperCase()}',
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('MASTCAM-Z / HiRISE ANALOG', style: TextStyle(color: Color(0xFFD3A24C), fontFamily: 'monospace', fontSize: 9)),
                  ),
                ),

                // Bottom HUD overlay on photo
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: Colors.black.withOpacity(0.65),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('COORDS: (${landmark.pt.x}, ${landmark.pt.y})', style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white)),
                        Text('DIST ALONG TRACK: ${(landmark.sM / 1000).toStringAsFixed(2)} km', style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFF06543))),
                      ],
                    ),
                  ),
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
                    Text(
                      'VISUAL FIELD PROFILE',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: MarsTheme.mars),
                    ),
                    const DataBadge(DataType.derived),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  landmark.desc,
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE5DDD8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Google 360-Style Interactive Panoramic Flyover Viewport
class _Street360Viewport extends StatelessWidget {
  final TerrainGrid grid;
  final RouteResult route;
  final int currentIdx;
  final Landmark currentLandmark;
  final Landmark? nextLandmark;
  final double camYaw;
  final double camPitch;
  final Function(double dx, double dy) onPan;
  final bool isPlaying;
  final VoidCallback onTogglePlay;

  const _Street360Viewport({
    required this.grid,
    required this.route,
    required this.currentIdx,
    required this.currentLandmark,
    required this.nextLandmark,
    required this.camYaw,
    required this.camPitch,
    required this.onPan,
    required this.isPlaying,
    required this.onTogglePlay,
  });

  @override
  Widget build(BuildContext context) {
    final curPt = route.path[currentIdx.clamp(0, route.path.length - 1)];
    final elev = grid.elev[curPt.y * grid.w + curPt.x];
    final slope = grid.slope[curPt.y * grid.w + curPt.x];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0C090A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD3A24C), width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          // 360 Panoramic View Canvas
          AspectRatio(
            aspectRatio: 16 / 10,
            child: GestureDetector(
              onPanUpdate: (details) => onPan(details.delta.dx, details.delta.dy),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _Mars360Painter(
                        grid: grid,
                        route: route,
                        currentIdx: currentIdx,
                        camYaw: camYaw,
                        camPitch: camPitch,
                        nextLandmark: nextLandmark,
                      ),
                    ),
                  ),

                  // Top 360° Compass Tape
                  Positioned(
                    top: 8,
                    left: 20,
                    right: 20,
                    child: _CompassTape(yaw: camYaw),
                  ),

                  // Center Reticle
                  const Center(
                    child: Icon(Icons.center_focus_strong, size: 24, color: Colors.white24),
                  ),

                  // Telemetry HUD bottom
                  Positioned(
                    bottom: 8,
                    left: 10,
                    right: 10,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ELEV: ${elev.toStringAsFixed(1)} m  ·  SLOPE: ${slope.toStringAsFixed(1)}°',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFF5F1E8)),
                          ),
                        ),
                        FloatingActionButton.small(
                          onPressed: onTogglePlay,
                          backgroundColor: MarsTheme.mars,
                          foregroundColor: Colors.white,
                          child: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF191316),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('DRAG TO LOOK 360° AROUND TERRAIN', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFFD3A24C))),
                Text(
                  'PROGRESS: ${((currentIdx / (route.path.length - 1)) * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 360° Perspective Compass Tape
class _CompassTape extends StatelessWidget {
  final double yaw;

  const _CompassTape({required this.yaw});

  @override
  Widget build(BuildContext context) {
    final deg = ((yaw * 180.0 / math.pi) % 360.0 + 360.0) % 360.0;
    final cardinal = deg < 22.5 || deg >= 337.5
        ? 'N'
        : deg < 67.5
            ? 'NE'
            : deg < 112.5
                ? 'E'
                : deg < 157.5
                    ? 'SE'
                    : deg < 202.5
                        ? 'S'
                        : deg < 247.5
                            ? 'SW'
                            : deg < 292.5
                                ? 'W'
                                : 'NW';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.70),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: Center(
        child: Text(
          'BEARING: ${deg.toStringAsFixed(0)}° $cardinal',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF5F1E8)),
        ),
      ),
    );
  }
}

/// Painter for Google 360-style view: horizon, ground, holographic route ribbon, landmark beacon
class _Mars360Painter extends CustomPainter {
  final TerrainGrid grid;
  final RouteResult route;
  final int currentIdx;
  final double camYaw;
  final double camPitch;
  final Landmark? nextLandmark;

  _Mars360Painter({
    required this.grid,
    required this.route,
    required this.currentIdx,
    required this.camYaw,
    required this.camPitch,
    required this.nextLandmark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final horizonY = size.height * (0.5 + camPitch);

    // 1. Martian Sky Gradient (Butterscotch / Amber)
    final skyPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, horizonY),
        [
          const Color(0xFF8B4F35),
          const Color(0xFFBA6E47),
          const Color(0xFFDF9B6E),
        ],
      );
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, horizonY), skyPaint);

    // 2. Martian Ground Gradient (Rust Red / Ochre Regolith)
    final groundPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, horizonY),
        Offset(0, size.height),
        [
          const Color(0xFF7E3821),
          const Color(0xFF5A2213),
          const Color(0xFF38120B),
        ],
      );
    canvas.drawRect(Rect.fromLTRB(0, horizonY, size.width, size.height), groundPaint);

    // 3. Distant Crater Rim Mountain Silhouettes
    final mountainPaint = Paint()
      ..color = const Color(0xFF5E2B1A)
      ..style = PaintingStyle.fill;
    final mPath = Path()..moveTo(0, horizonY);
    for (var x = 0.0; x <= size.width; x += 20) {
      final angle = camYaw + (x / size.width - 0.5) * 1.8;
      final h = 18.0 * math.sin(angle * 3.0) + 12.0 * math.cos(angle * 5.0);
      mPath.lineTo(x, horizonY - h.clamp(2.0, 35.0));
    }
    mPath.lineTo(size.width, horizonY);
    mPath.close();
    canvas.drawPath(mPath, mountainPaint);

    // 4. Ground Perspective Grid Lines
    final gridLinePaint = Paint()
      ..color = const Color(0x22F5F1E8)
      ..strokeWidth = 1.0;
    for (var i = -4; i <= 4; i++) {
      final startX = size.width / 2 + i * (size.width / 4);
      canvas.drawLine(Offset(size.width / 2, horizonY), Offset(startX, size.height), gridLinePaint);
    }

    // 5. Projected Holographic Route Ribbon
    final curPt = route.path[currentIdx.clamp(0, route.path.length - 1)];
    final pathPaint = Paint()
      ..color = const Color(0xFFF06543)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final lookAhead = math.min(route.path.length - 1, currentIdx + 18);
    final ribPath = Path();
    var started = false;

    for (var k = currentIdx; k <= lookAhead; k++) {
      final pt = route.path[k];
      final dx = (pt.x - curPt.x).toDouble();
      final dy = (pt.y - curPt.y).toDouble();
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 0.1 && k == currentIdx) {
        ribPath.moveTo(size.width / 2, size.height - 20);
        started = true;
        continue;
      }

      final angle = math.atan2(dx, -dy) - camYaw;
      final normAngle = (angle + math.pi) % (2 * math.pi) - math.pi;

      if (normAngle.abs() < 1.4) {
        final screenX = size.width / 2 + (normAngle / 1.4) * (size.width / 2);
        final screenY = horizonY + (1.0 / (dist + 0.8)) * (size.height - horizonY) * 0.9;
        if (!started) {
          ribPath.moveTo(screenX, screenY);
          started = true;
        } else {
          ribPath.lineTo(screenX, screenY);
        }
      }
    }
    canvas.drawPath(ribPath, pathPaint);

    // 6. Next Landmark Holographic Beacon on Horizon
    if (nextLandmark != null) {
      final lpt = nextLandmark!.pt;
      final ldx = (lpt.x - curPt.x).toDouble();
      final ldy = (lpt.y - curPt.y).toDouble();
      final lAngle = math.atan2(ldx, -ldy) - camYaw;
      final normLAngle = (lAngle + math.pi) % (2 * math.pi) - math.pi;

      if (normLAngle.abs() < 1.4) {
        final bx = size.width / 2 + (normLAngle / 1.4) * (size.width / 2);
        final by = horizonY - 45;

        // Vertical glowing science beacon
        final beaconPaint = Paint()
          ..shader = ui.Gradient.linear(
            Offset(bx, by),
            Offset(bx, horizonY + 30),
            [
              const Color(0xFFD3A24C),
              const Color(0xFFF06543),
              Colors.transparent,
            ],
          )
          ..strokeWidth = 3.0;
        canvas.drawLine(Offset(bx, by), Offset(bx, horizonY + 30), beaconPaint);

        // Beacon Target Reticle
        canvas.drawCircle(Offset(bx, by), 6.0, Paint()..color = const Color(0xFFD3A24C));
        canvas.drawCircle(Offset(bx, by), 6.0, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Mars360Painter old) {
    return old.currentIdx != currentIdx ||
        old.camYaw != camYaw ||
        old.camPitch != camPitch ||
        old.nextLandmark != nextLandmark;
  }
}

/// Outcrop Painter for authentic geological photo presentation of each landmark
class _OutcropPainter extends CustomPainter {
  final Landmark landmark;

  _OutcropPainter({required this.landmark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sky gradient
    final sky = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h * 0.45),
        [const Color(0xFF945237), const Color(0xFFD48B62)],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.45), sky);

    // Ground plane
    final ground = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, h * 0.45),
        Offset(0, h),
        [const Color(0xFF8B3A22), const Color(0xFF4A180D)],
      );
    canvas.drawRect(Rect.fromLTWH(0, h * 0.45, w, h * 0.55), ground);

    // Dynamic geological features according to landmark identity
    final rockPaint = Paint()..color = const Color(0xFF6B2D1B);
    final strataPaint = Paint()
      ..color = const Color(0xFFC48E68)
      ..strokeWidth = 2.0;

    if (landmark.name.contains('Kodiak')) {
      // Draw flat-topped Kodiak Butte mesa with stratification
      final mesa = Path()
        ..moveTo(w * 0.20, h * 0.48)
        ..lineTo(w * 0.32, h * 0.22)
        ..lineTo(w * 0.68, h * 0.22)
        ..lineTo(w * 0.80, h * 0.48)
        ..close();
      canvas.drawPath(mesa, rockPaint);
      // Dipping foreset beds
      canvas.drawLine(Offset(w * 0.36, h * 0.26), Offset(w * 0.64, h * 0.26), strataPaint);
      canvas.drawLine(Offset(w * 0.34, h * 0.32), Offset(w * 0.66, h * 0.32), strataPaint);
      canvas.drawLine(Offset(w * 0.30, h * 0.38), Offset(w * 0.70, h * 0.38), strataPaint);
    } else if (landmark.name.contains('Séítah')) {
      // Layered dark olivine ridges and dunes
      for (var r = 0; r < 4; r++) {
        final ry = h * (0.35 + r * 0.12);
        final rPath = Path()
          ..moveTo(0, ry)
          ..quadraticBezierTo(w * 0.3, ry - 20, w * 0.6, ry)
          ..quadraticBezierTo(w * 0.85, ry + 15, w, ry - 10)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(rPath, Paint()..color = Color.fromARGB(255, 60 + r * 15, 30 + r * 10, 20 + r * 8));
      }
    } else if (landmark.name.contains('Belva')) {
      // Impact crater rim with large ejecta blocks
      final craterRim = Path()
        ..moveTo(0, h * 0.38)
        ..lineTo(w * 0.45, h * 0.30)
        ..lineTo(w * 0.75, h * 0.42)
        ..lineTo(w, h * 0.34)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(craterRim, rockPaint);
      // Boulder ejecta blocks
      canvas.drawRect(Rect.fromLTWH(w * 0.40, h * 0.44, 24, 18), Paint()..color = const Color(0xFF38150E));
      canvas.drawRect(Rect.fromLTWH(w * 0.62, h * 0.50, 32, 22), Paint()..color = const Color(0xFF38150E));
      canvas.drawRect(Rect.fromLTWH(w * 0.22, h * 0.55, 18, 14), Paint()..color = const Color(0xFF38150E));
    } else {
      // Stratified delta front scarp
      final scarp = Path()
        ..moveTo(0, h * 0.28)
        ..lineTo(w * 0.55, h * 0.36)
        ..lineTo(w, h * 0.25)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(scarp, rockPaint);
      canvas.drawLine(Offset(0, h * 0.34), Offset(w, h * 0.34), strataPaint);
      canvas.drawLine(Offset(0, h * 0.40), Offset(w, h * 0.40), strataPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OutcropPainter old) => old.landmark != landmark;
}
