// MARS-X routing core: terrain grid.
// Pure Dart (no Flutter imports) so it runs in an isolate and in unit tests.
//
// Cell layout: row-major, x = column (east), y = row (SOUTH, like an image).
// Index = y * width + x.

import 'dart:math' as math;
import 'dart:typed_data';

/// Mars mean radius in metres. NEVER use Earth-based distance helpers.
const double marsRadiusM = 3396190.0;

/// Metres per degree of latitude on Mars (~59,274.7 m).
const double marsMetresPerDegLat = 2 * math.pi * marsRadiusM / 360.0;

class MarsGrid {
  final int width;
  final int height;

  /// Cell size in metres (planning grid, e.g. 10 m).
  final double cellSize;

  /// Elevation in metres (MOLA areoid). NaN = nodata.
  final Float32List elevation;

  /// Terrain slope in degrees (Horn's method). Computed if not supplied.
  final Float32List slopeDeg;

  /// Surface roughness 0..1 (detrended local std dev, normalised).
  final Float32List roughness;

  /// Soft-ground / loose-regolith / dune hazard 0..1 (from geology or thermal inertia).
  final Float32List hazard;

  /// Scientific value 0..1 (geologic unit weights + proximity to cited targets).
  final Float32List science;

  /// Data confidence 0..1 (1 = HiRISE DTM, ~0.4 = CTX fallback, 0 = nodata edge).
  final Float32List confidence;

  /// 1 = hard obstacle (boulder field, mapped scarp, nodata). Never entered.
  final Uint8List blocked;

  /// Planetocentric lon/lat (east-positive) of the CENTRE of cell (0,0).
  final double originLon;
  final double originLat;

  MarsGrid._({
    required this.width,
    required this.height,
    required this.cellSize,
    required this.elevation,
    required this.slopeDeg,
    required this.roughness,
    required this.hazard,
    required this.science,
    required this.confidence,
    required this.blocked,
    required this.originLon,
    required this.originLat,
  });

  /// Build a grid from layers. Missing layers get safe defaults;
  /// slope and roughness are derived from elevation when not given.
  factory MarsGrid.fromLayers({
    required int width,
    required int height,
    required double cellSize,
    required Float32List elevation,
    Float32List? slopeDeg,
    Float32List? roughness,
    Float32List? hazard,
    Float32List? science,
    Float32List? confidence,
    Uint8List? blocked,
    double originLon = 77.4,
    double originLat = 18.5,
    double roughnessRefM = 0.5,
  }) {
    final n = width * height;
    if (elevation.length != n) {
      throw ArgumentError('elevation has ${elevation.length} cells, expected $n');
    }
    final derived = (slopeDeg == null || roughness == null)
        ? _deriveSlopeAndRoughness(width, height, cellSize, elevation, roughnessRefM)
        : null;
    final blk = blocked ?? Uint8List(n);
    for (var i = 0; i < n; i++) {
      if (elevation[i].isNaN) blk[i] = 1; // nodata is always impassable
    }
    return MarsGrid._(
      width: width,
      height: height,
      cellSize: cellSize,
      elevation: elevation,
      slopeDeg: slopeDeg ?? derived!.$1,
      roughness: roughness ?? derived!.$2,
      hazard: hazard ?? Float32List(n),
      science: science ?? Float32List(n),
      confidence: confidence ?? (Float32List(n)..fillRange(0, n, 1.0)),
      blocked: blk,
      originLon: originLon,
      originLat: originLat,
    );
  }

  int get cellCount => width * height;
  int index(int x, int y) => y * width + x;
  int xOf(int i) => i % width;
  int yOf(int i) => i ~/ width;
  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  // ---------- Mars geodesy (local equirectangular, Mars radius) ----------

  double get _metresPerDegLon =>
      marsMetresPerDegLat * math.cos(originLat * math.pi / 180.0);

  /// Cell (may be fractional) -> lon/lat degrees. Returns (lon, lat).
  (double, double) cellToLonLat(double x, double y) {
    final lon = originLon + x * cellSize / _metresPerDegLon;
    final lat = originLat - y * cellSize / marsMetresPerDegLat; // rows go south
    return (lon, lat);
  }

  /// lon/lat -> nearest cell index, or -1 if outside the grid.
  int lonLatToCell(double lon, double lat) {
    final x = ((lon - originLon) * _metresPerDegLon / cellSize).round();
    final y = ((originLat - lat) * marsMetresPerDegLat / cellSize).round();
    return inBounds(x, y) ? index(x, y) : -1;
  }

  /// Horizontal distance in metres between two cells.
  double distanceM(int a, int b) {
    final dx = (xOf(a) - xOf(b)).toDouble();
    final dy = (yOf(a) - yOf(b)).toDouble();
    return math.sqrt(dx * dx + dy * dy) * cellSize;
  }

  /// Map bearing from a to b in degrees (0 = north, 90 = east).
  double bearingDeg(int a, int b) {
    final east = (xOf(b) - xOf(a)).toDouble();
    final north = (yOf(a) - yOf(b)).toDouble(); // row increases southward
    final deg = math.atan2(east, north) * 180.0 / math.pi;
    return (deg + 360.0) % 360.0;
  }
}

/// Horn (1981) slope + detrended roughness on a 3x3 window.
(Float32List, Float32List) _deriveSlopeAndRoughness(
    int w, int h, double cs, Float32List z, double refM) {
  final slope = Float32List(w * h);
  final rough = Float32List(w * h);
  double at(int x, int y, double fallback) {
    x = math.min(math.max(x, 0), w - 1);
    y = math.min(math.max(y, 0), h - 1);
    final v = z[y * w + x];
    return v.isNaN ? fallback : v;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = z[y * w + x];
      if (c.isNaN) {
        slope[y * w + x] = 90;
        rough[y * w + x] = 1;
        continue;
      }
      final a = at(x - 1, y - 1, c), b = at(x, y - 1, c), cc = at(x + 1, y - 1, c);
      final d = at(x - 1, y, c), f = at(x + 1, y, c);
      final g = at(x - 1, y + 1, c), hh = at(x, y + 1, c), i = at(x + 1, y + 1, c);
      final dzdx = ((cc + 2 * f + i) - (a + 2 * d + g)) / (8 * cs);
      final dzdy = ((g + 2 * hh + i) - (a + 2 * b + cc)) / (8 * cs);
      slope[y * w + x] =
          math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy)) * 180.0 / math.pi;

      // Roughness: std dev of residuals after removing the fitted plane.
      var ss = 0.0;
      for (var oy = -1; oy <= 1; oy++) {
        for (var ox = -1; ox <= 1; ox++) {
          final plane = c + dzdx * ox * cs + dzdy * oy * cs;
          final r = at(x + ox, y + oy, c) - plane;
          ss += r * r;
        }
      }
      rough[y * w + x] = math.min(1.0, math.sqrt(ss / 9.0) / refM);
    }
  }
  return (slope, rough);
}
