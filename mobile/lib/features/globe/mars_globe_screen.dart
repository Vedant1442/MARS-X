import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../shared/widgets/data_badge.dart';

class MarsSite {
  final String id;
  final String name;
  final double lat;
  final double lon;
  final String desc;
  final Color color;

  const MarsSite({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.desc,
    required this.color,
  });
}

const List<MarsSite> kMarsSites = [
  MarsSite(
    id: 'JEZERO',
    name: 'Jezero Crater',
    lat: 18.38,
    lon: 77.58,
    desc: 'Perseverance Rover (2021) · Ancient delta & lake basin · MARS-X AOI',
    color: Color(0xFFF06543),
  ),
  MarsSite(
    id: 'GALE',
    name: 'Gale Crater',
    lat: -5.40,
    lon: 137.80,
    desc: 'Curiosity Rover (2012) · Mount Sharp stratigraphy · RAD sensor archive',
    color: Color(0xFFE09F3E),
  ),
  MarsSite(
    id: 'OLYMPUS',
    name: 'Olympus Mons',
    lat: 18.65,
    lon: -133.80,
    desc: 'Largest planetary volcano in the Solar System (21.9 km elevation)',
    color: Color(0xFF9E8279),
  ),
  MarsSite(
    id: 'VALLES',
    name: 'Valles Marineris',
    lat: -13.90,
    lon: -59.20,
    desc: 'Giant tectonic canyon system stretching over 4,000 km',
    color: Color(0xFFB87D4B),
  ),
  MarsSite(
    id: 'ISIDIS',
    name: 'Isidis Planitia',
    lat: 12.90,
    lon: 87.00,
    desc: 'Major impact basin adjoining Jezero western rim',
    color: Color(0xFF996888),
  ),
];

class MarsGlobeScreen extends ConsumerStatefulWidget {
  const MarsGlobeScreen({super.key});

  @override
  ConsumerState<MarsGlobeScreen> createState() => _MarsGlobeScreenState();
}

class _MarsGlobeScreenState extends ConsumerState<MarsGlobeScreen> with SingleTickerProviderStateMixin {
  double _yaw = 77.58 * math.pi / 180.0; // Initially centered on Jezero
  double _pitch = -18.38 * math.pi / 180.0;
  double _scale = 1.0;
  MarsSite? _selectedSite = kMarsSites.first;
  ui.Image? _usgsTexture;
  bool _autoRotate = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadTexture();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadTexture() async {
    try {
      final data = await rootBundle.load('assets/images/mars-color-1k.jpg');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _usgsTexture = frame.image;
        });
      }
    } catch (_) {
      // Texture is optional; vector globe will render if absent
    }
  }

  void _centerOnSite(MarsSite site) {
    setState(() {
      _selectedSite = site;
      _yaw = site.lon * math.pi / 180.0;
      _pitch = -site.lat * math.pi / 180.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0A0B),
      body: Stack(
        children: [
          // 3D Interactive Globe
          GestureDetector(
            onScaleUpdate: (details) {
              setState(() {
                if (details.scale != 1.0) {
                  _scale = (_scale * details.scale).clamp(0.8, 2.5);
                } else {
                  _yaw += details.focalPointDelta.dx * 0.008;
                  _pitch = (_pitch - details.focalPointDelta.dy * 0.008).clamp(-math.pi / 2.2, math.pi / 2.2);
                }
              });
            },
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _Globe3DPainter(
                    yaw: _yaw,
                    pitch: _pitch,
                    scale: _scale,
                    texture: _usgsTexture,
                    selectedSite: _selectedSite,
                    pulse: _pulseController.value,
                  ),
                );
              },
            ),
          ),

          // Top Mission Control Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'MARS-X · GLOBAL CONTEXT',
                        style: TextStyle(
                          color: Color(0xFFF5F1E8),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'USGS Viking/MOLA Global Mosaic · R = 3,396.19 km',
                        style: TextStyle(
                          color: const Color(0xFFF5F1E8).withValues(alpha: 0.7),
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const DataBadge(DataType.observed),
                ],
              ),
            ),
          ),

          // Planetary Feature Chips at Top
          Positioned(
            top: 70,
            left: 12,
            right: 12,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final site in kMarsSites)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          site.name.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: _selectedSite?.id == site.id ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: _selectedSite?.id == site.id,
                        selectedColor: site.color.withValues(alpha: 0.3),
                        side: BorderSide(
                          color: _selectedSite?.id == site.id ? site.color : Colors.white24,
                        ),
                        onSelected: (_) => _centerOnSite(site),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom Action Panel: Selected Site Telemetry & Explore Button
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF191316).withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF06543).withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _selectedSite?.color ?? const Color(0xFFF06543),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (_selectedSite?.name ?? 'MARS SURFACE').toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFF5F1E8),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _selectedSite != null
                            ? '${_selectedSite!.lat.abs().toStringAsFixed(2)}°${_selectedSite!.lat >= 0 ? "N" : "S"}, ${_selectedSite!.lon.abs().toStringAsFixed(2)}°${_selectedSite!.lon >= 0 ? "E" : "W"}'
                            : '',
                        style: const TextStyle(
                          color: Color(0xFFD3A24C),
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedSite?.desc ?? 'Drag to rotate the Mars globe. Tap a planetary feature above to inspect.',
                    style: TextStyle(
                      color: const Color(0xFFF5F1E8).withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF06543),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () {
                        // Switch directly to the Map screen
                        ref.read(tabIndexProvider.notifier).state = 1;
                      },
                      icon: const Icon(Icons.terrain, size: 18),
                      label: const Text(
                        'ENTER JEZERO CRATER HI-RES MAP (35.99 m/px) →',
                        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Globe3DPainter extends CustomPainter {
  final double yaw;
  final double pitch;
  final double scale;
  final ui.Image? texture;
  final MarsSite? selectedSite;
  final double pulse;

  _Globe3DPainter({
    required this.yaw,
    required this.pitch,
    required this.scale,
    required this.texture,
    required this.selectedSite,
    required this.pulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 30);
    final radius = math.min(size.width, size.height) * 0.38 * scale;

    // Atmospheric Glow Outer Halo
    final haloPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius * 1.25,
        [
          const Color(0x66F06543),
          const Color(0x22C3423F),
          Colors.transparent,
        ],
        [0.75, 0.90, 1.0],
      );
    canvas.drawCircle(center, radius * 1.25, haloPaint);

    // Planet Base Sphere
    final spherePaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
        radius * 1.4,
        [
          const Color(0xFFC75D38),
          const Color(0xFFA24323),
          const Color(0xFF5E2114),
          const Color(0xFF2B0E08),
        ],
        [0.0, 0.45, 0.8, 1.0],
      );
    canvas.drawCircle(center, radius, spherePaint);

    // Render USGS Texture / Surface Features
    if (texture != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

      // Draw textured surface projected with yaw
      final texW = texture!.width.toDouble();
      final texH = texture!.height.toDouble();
      final normYaw = (yaw / (2 * math.pi)) % 1.0;
      final shiftX = normYaw * radius * 4.0;

      final src1 = Rect.fromLTWH(0, 0, texW, texH);
      final dst1 = Rect.fromCenter(
        center: Offset(center.dx - shiftX, center.dy),
        width: radius * 4.0,
        height: radius * 2.0,
      );
      final texPaint = Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: 0.75);

      canvas.drawImageRect(texture!, src1, dst1, texPaint);

      // Wrap-around duplicate
      final dst2 = Rect.fromCenter(
        center: Offset(center.dx - shiftX + radius * 4.0, center.dy),
        width: radius * 4.0,
        height: radius * 2.0,
      );
      canvas.drawImageRect(texture!, src1, dst2, texPaint);

      // Night / Shadow shading overlay
      final shadowPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - radius, center.dy - radius),
          Offset(center.dx + radius, center.dy + radius),
          [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55),
          ],
        );
      canvas.drawCircle(center, radius, shadowPaint);

      canvas.restore();
    }

    // Planetary Graticule Lines (Latitude & Longitude)
    final gridPaint = Paint()
      ..color = const Color(0x33F5F1E8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw Longitude Lines
    for (var lonDeg = -180; lonDeg < 180; lonDeg += 30) {
      final lonRad = lonDeg * math.pi / 180.0;
      final path = Path();
      var first = true;
      for (var latDeg = -85; latDeg <= 85; latDeg += 5) {
        final latRad = latDeg * math.pi / 180.0;
        final pt3d = _projectLatLon(latRad, lonRad, yaw, pitch);
        if (pt3d.z > 0) {
          final sx = center.dx + pt3d.x * radius;
          final sy = center.dy - pt3d.y * radius;
          if (first) {
            path.moveTo(sx, sy);
            first = false;
          } else {
            path.lineTo(sx, sy);
          }
        } else {
          first = true;
        }
      }
      canvas.drawPath(path, gridPaint);
    }

    // Draw Latitude Lines
    for (var latDeg = -60; latDeg <= 60; latDeg += 30) {
      final latRad = latDeg * math.pi / 180.0;
      final path = Path();
      var first = true;
      for (var lonDeg = -180; lonDeg <= 180; lonDeg += 6) {
        final lonRad = lonDeg * math.pi / 180.0;
        final pt3d = _projectLatLon(latRad, lonRad, yaw, pitch);
        if (pt3d.z > 0) {
          final sx = center.dx + pt3d.x * radius;
          final sy = center.dy - pt3d.y * radius;
          if (first) {
            path.moveTo(sx, sy);
            first = false;
          } else {
            path.lineTo(sx, sy);
          }
        } else {
          first = true;
        }
      }
      canvas.drawPath(path, gridPaint);
    }

    // Draw Planetary Site Markers
    for (final site in kMarsSites) {
      final latRad = site.lat * math.pi / 180.0;
      final lonRad = site.lon * math.pi / 180.0;
      final pt3d = _projectLatLon(latRad, lonRad, yaw, pitch);

      // Only draw if on front hemisphere (z > 0)
      if (pt3d.z > 0.05) {
        final sx = center.dx + pt3d.x * radius;
        final sy = center.dy - pt3d.y * radius;

        final isSelected = selectedSite?.id == site.id;
        final isJezero = site.id == 'JEZERO';

        // Outer pulsing ring for Jezero
        if (isJezero) {
          final pulseRadius = 12.0 + pulse * 10.0;
          final pulsePaint = Paint()
            ..color = site.color.withValues(alpha: 0.5 * (1.0 - pulse))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0;
          canvas.drawCircle(Offset(sx, sy), pulseRadius, pulsePaint);
        }

        // Marker Dot
        final dotPaint = Paint()
          ..color = isSelected ? Colors.white : site.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(sx, sy), isSelected ? 5.5 : 4.0, dotPaint);

        // Border
        final borderPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        canvas.drawCircle(Offset(sx, sy), isSelected ? 5.5 : 4.0, borderPaint);

        // Text Label
        final span = TextSpan(
          text: site.name,
          style: TextStyle(
            color: isSelected ? const Color(0xFFF5F1E8) : const Color(0xFFD3A24C),
            fontFamily: 'monospace',
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            fontSize: isSelected ? 11 : 9,
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 4, offset: Offset(1, 1)),
            ],
          ),
        );
        final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(sx + 8, sy - tp.height / 2));
      }
    }
  }

  static _Vector3 _projectLatLon(double lat, double lon, double yaw, double pitch) {
    // Spherical to 3D Cartesian
    final x0 = math.cos(lat) * math.sin(lon - yaw);
    final y0 = math.sin(lat);
    final z0 = math.cos(lat) * math.cos(lon - yaw);

    // Apply Pitch rotation around X axis
    final y1 = y0 * math.cos(pitch) - z0 * math.sin(pitch);
    final z1 = y0 * math.sin(pitch) + z0 * math.cos(pitch);

    return _Vector3(x0, y1, z1);
  }

  @override
  bool shouldRepaint(covariant _Globe3DPainter old) {
    return old.yaw != yaw ||
        old.pitch != pitch ||
        old.scale != scale ||
        old.selectedSite != selectedSite ||
        old.pulse != pulse ||
        old.texture != texture;
  }
}

class _Vector3 {
  final double x;
  final double y;
  final double z;
  const _Vector3(this.x, this.y, this.z);
}
