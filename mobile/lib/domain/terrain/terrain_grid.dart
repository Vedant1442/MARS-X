import 'dart:math' as math;
import 'dart:typed_data';

enum DataType { observed, derived, modeled, unknown, simulated }

class ScienceTarget {
  final String id;
  final String name;
  final int x;
  final int y;
  final String type;
  final double value;
  final String conf;
  final String note;

  const ScienceTarget({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.type,
    required this.value,
    required this.conf,
    required this.note,
  });
}

const List<ScienceTarget> kDemoTargets = [
  ScienceTarget(
    id: 'T1',
    name: 'Demo target A',
    x: 44,
    y: 34,
    type: 'Placeholder, sedimentary-type',
    value: 0.86,
    conf: 'MEDIUM',
    note: 'Placeholder science target at a demonstration location. Not a mapped or published feature.',
  ),
  ScienceTarget(
    id: 'T2',
    name: 'Demo target B',
    x: 66,
    y: 41,
    type: 'Placeholder, spectral-type',
    value: 0.92,
    conf: 'LOW',
    note: 'Placeholder science target. No spectral data has been ingested; value is an expert-style weight for the demo.',
  ),
  ScienceTarget(
    id: 'T3',
    name: 'Demo target C',
    x: 86,
    y: 60,
    type: 'Placeholder, impact-type',
    value: 0.61,
    conf: 'HIGH',
    note: 'Placeholder science target at a demonstration location. Not a mapped or published feature.',
  ),
  ScienceTarget(
    id: 'T4',
    name: 'Demo target D',
    x: 26,
    y: 42,
    type: 'Placeholder, fluvial-type',
    value: 0.78,
    conf: 'MEDIUM',
    note: 'Placeholder science target at a demonstration location. Not a mapped or published feature.',
  ),
  ScienceTarget(
    id: 'T5',
    name: 'Demo target E',
    x: 98,
    y: 30,
    type: 'Placeholder, thermal-type',
    value: 0.55,
    conf: 'LOW',
    note: 'Placeholder science target. No thermal product has been ingested.',
  ),
];

/// Terrain planning grid loaded from the bundled HiRISE DTM binary (jezero-dem.bin).
class TerrainGrid {
  static const int gridW = 120;
  static const int gridH = 76;
  static const int hiW = 480;
  static const int hiH = 304;
  static const double defaultCellM = 35.99;
  static const double scaleHeightM = 11100.0;

  final int w;
  final int h;
  final double cellM;
  final Float32List elev;
  final Float32List slope;
  final Float32List rough;
  final Float32List unc;
  final Uint8List nodata;
  final double minElev;
  final double maxElev;
  final String terrainSource;

  TerrainGrid({
    required this.w,
    required this.h,
    required this.cellM,
    required this.elev,
    required this.slope,
    required this.rough,
    required this.unc,
    required this.nodata,
    required this.minElev,
    required this.maxElev,
    required this.terrainSource,
  });

  /// Relative simulated pressure P(h)/P_ref = exp(-(h - h_min) / H).
  double pressureRel(int idx) {
    return math.exp(-(elev[idx] - minElev) / scaleHeightM);
  }

  /// Build from the bundled 480x304 Int16 LE decimetre DEM buffer.
  factory TerrainGrid.fromHiRiseBytes(Uint8List bytes, {double cellM = defaultCellM}) {
    final bd = ByteData.sublistView(bytes);
    final elev = Float32List(gridW * gridH);

    for (var gy = 0; gy < gridH; gy++) {
      for (var gx = 0; gx < gridW; gx++) {
        var sum = 0.0;
        for (var by = 0; by < 4; by++) {
          for (var bx = 0; bx < 4; bx++) {
            final hx = gx * 4 + bx;
            final hy = gy * 4 + by;
            final v = bd.getInt16((hy * hiW + hx) * 2, Endian.little);
            sum += v / 10.0;
          }
        }
        elev[gy * gridW + gx] = sum / 16.0;
      }
    }

    return TerrainGrid.fromElevation(
      w: gridW,
      h: gridH,
      cellM: cellM,
      elev: elev,
      terrainSource: 'USGS HiRISE DTM (DTEEC_045994_1985_046060_1985_U01)',
    );
  }

  /// Compute derived slope, roughness, and modeled uncertainty from any elevation grid.
  factory TerrainGrid.fromElevation({
    required int w,
    required int h,
    required double cellM,
    required Float32List elev,
    Uint8List? nodata,
    String terrainSource = 'SYNTHETIC',
  }) {
    final nd = nodata ?? Uint8List(w * h);
    final slope = Float32List(w * h);
    final rough = Float32List(w * h);
    final unc = Float32List(w * h);

    double g(int x, int y) {
      final cx = x.clamp(0, w - 1);
      final cy = y.clamp(0, h - 1);
      return elev[cy * w + cx];
    }

    var minE = double.infinity;
    var maxE = double.negativeInfinity;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (nd[i] != 0) continue;
        final dzdx = (g(x + 1, y) - g(x - 1, y)) / (2.0 * cellM);
        final dzdy = (g(x, y + 1) - g(x, y - 1)) / (2.0 * cellM);
        slope[i] = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy)) * 180.0 / math.pi;

        var s = 0.0;
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            s += (g(x + kx, y + ky) - elev[i]).abs();
          }
        }
        rough[i] = math.min(1.0, s / 9.0 / 60.0);

        final edge = math.min(math.min(x, y), math.min(w - 1 - x, h - 1 - y)) / 12.0;
        unc[i] = math.min(1.0, 0.12 + 0.25 * (1.0 - math.min(1.0, edge)) + rough[i] * 0.4);

        if (elev[i] < minE) minE = elev[i];
        if (elev[i] > maxE) maxE = elev[i];
      }
    }

    return TerrainGrid(
      w: w,
      h: h,
      cellM: cellM,
      elev: elev,
      slope: slope,
      rough: rough,
      unc: unc,
      nodata: nd,
      minElev: minE.isFinite ? minE : 0.0,
      maxElev: maxE.isFinite ? maxE : 0.0,
      terrainSource: terrainSource,
    );
  }
}
