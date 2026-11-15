// SIMULATED "Jezero-like" terrain for Practice mode and unit tests.
// It is NOT real data: it is labelled SIMULATED everywhere it is shown.
// Real terrain comes from the build-time pipeline (HiRISE/CTX DTM -> bundle).
//
// Features: tilted crater floor, raised delta with a steep front and one gentle ramp,
// small impact craters with rims, a dune field (soft ground), boulder patches,
// a low-confidence strip (CTX fallback) and a nodata patch.

import 'dart:math' as math;
import 'dart:typed_data';

import 'landmarks.dart';
import 'mars_grid.dart';

double _hash(int x, int y, int seed) {
  var h = (x * 374761393 + y * 668265263 + seed * 1442695041) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;
  h = h ^ (h >> 16);
  return (h & 0xFFFFFF) / 0xFFFFFF;
}

double _smooth(double t) => t * t * (3 - 2 * t);

double _valueNoise(double x, double y, int seed) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = _smooth(x - x0), fy = _smooth(y - y0);
  final a = _hash(x0, y0, seed), b = _hash(x0 + 1, y0, seed);
  final c = _hash(x0, y0 + 1, seed), d = _hash(x0 + 1, y0 + 1, seed);
  return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy;
}

double _smoothstep(double e0, double e1, double v) =>
    _smooth(math.min(1.0, math.max(0.0, (v - e0) / (e1 - e0))));

class DemoTerrain {
  final MarsGrid grid;
  final List<ScienceTarget> targets;
  DemoTerrain(this.grid, this.targets);
}

DemoTerrain buildDemoTerrain({int size = 400, double cellSize = 10}) {
  final w = size, h = size, n = w * h;
  final z = Float32List(n);
  final hazard = Float32List(n);
  final science = Float32List(n);
  final conf = Float32List(n);
  final blocked = Uint8List(n);
  final s = size / 400.0; // scale features with grid size

  // Delta: centre, plateau radius, front width; a ramp sector (gentle) to the SE.
  final dcx = 110 * s, dcy = 140 * s, dR = 85 * s;
  const rampDir = math.pi / 4; // pointing SE (x+, y+)
  final craters = [
    (250 * s, 120 * s, 22 * s, 12.0),
    (300 * s, 300 * s, 30 * s, 18.0),
    (170 * s, 330 * s, 15 * s, 8.0),
  ];

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      // Crater floor around -2550 m, rising gently to the west.
      var e = -2550.0 + (w - x) * cellSize * 0.004;

      // Delta plateau with a steep front (~25+ deg) except a gentle ramp sector.
      final dx = x - dcx, dy = y - dcy;
      final r = math.sqrt(dx * dx + dy * dy);
      final ang = math.atan2(dy, dx);
      var dAng = (ang - rampDir).abs();
      if (dAng > math.pi) dAng = 2 * math.pi - dAng;
      final rampness = 1 - _smoothstep(0.15, 0.35, dAng); // 1 inside ramp sector
      final frontWidth = (4 + 26 * rampness) * s; // cells
      e += 40 * (1 - _smoothstep(dR - frontWidth, dR, r));

      // Craters: bowl + raised rim.
      for (final (cx, cy, cr, depth) in craters) {
        final rr = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        if (rr < cr) e -= depth * (1 - (rr / cr) * (rr / cr));
        e += 0.35 * depth * math.exp(-math.pow((rr - cr) / (0.3 * cr), 2));
        // Boulders on the rims.
        if ((rr - cr).abs() < 2.5 * s && _hash(x, y, 7) > 0.8) blocked[i] = 1;
        if (rr < cr) science[i] = math.max(science[i], 0.45);
      }

      // Small-scale relief (affects roughness).
      e += 3.0 * _valueNoise(x / 25, y / 25, 1) + 0.6 * _valueNoise(x / 3, y / 3, 2);
      z[i] = e;

      // Dune field to the east: soft ground hazard.
      if (x > 270 * s && x < 350 * s && y > 40 * s && y < 230 * s) {
        hazard[i] = 0.45 + 0.55 * _valueNoise(x / 8, y / 8, 3);
      }

      // Science: delta front (sediments, carbonates) and a "margin" band.
      final frontBand = 1 - _smoothstep(0, 12 * s, (r - dR).abs());
      science[i] = math.max(science[i], 0.95 * frontBand);
      final mx = x - 300 * s, my = y - 300 * s;
      final marginR = math.sqrt(mx * mx + my * my);
      science[i] = math.max(science[i], 0.7 * (1 - _smoothstep(0, 10 * s, (marginR - 45 * s).abs())));
      science[i] = math.max(science[i], 0.1 + 0.1 * _valueNoise(x / 30, y / 30, 4));

      // Data confidence: CTX-only strip on the far east, nodata patch in a corner.
      conf[i] = x > 370 * s ? 0.4 : 1.0;
      if (x > 380 * s && y > 370 * s) z[i] = double.nan;
    }
  }

  final grid = MarsGrid.fromLayers(
    width: w,
    height: h,
    cellSize: cellSize,
    elevation: z,
    hazard: hazard,
    science: science,
    confidence: conf,
    blocked: blocked,
  );

  int cellAt(double x, double y) => grid.index(x.round(), y.round());
  final targets = [
    ScienceTarget(
      id: 'demo_delta_front',
      name: 'Delta front outcrop (demo)',
      cell: cellAt(dcx + dR * math.cos(rampDir), dcy + dR * math.sin(rampDir)),
      importance: 0.95,
      summary: 'DEMO TEXT: layered delta sediments, the kind of rock best suited to '
          'preserving signs of ancient life. Replace with cited text from the catalogue.',
      minerals: ['clay', 'carbonate'],
      citation: 'SIMULATED demo target',
      dataType: 'SIMULATED',
    ),
    ScienceTarget(
      id: 'demo_margin',
      name: 'Margin carbonate band (demo)',
      cell: cellAt(300 * s - 45 * s, 300 * s),
      importance: 0.8,
      summary: 'DEMO TEXT: carbonate-rich band that may record an old shoreline.',
      minerals: ['carbonate', 'olivine'],
      citation: 'SIMULATED demo target',
      dataType: 'SIMULATED',
    ),
    ScienceTarget(
      id: 'demo_crater',
      name: 'Small crater floor (demo)',
      cell: cellAt(170 * s, 330 * s),
      importance: 0.5,
      summary: 'DEMO TEXT: impact exposes deeper rock in the crater walls.',
      minerals: ['pyroxene'],
      citation: 'SIMULATED demo target',
      dataType: 'SIMULATED',
    ),
  ];
  return DemoTerrain(grid, targets);
}
