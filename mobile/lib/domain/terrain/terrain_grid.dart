import 'dart:math' as math;
import 'dart:typed_data';
import '../geo/mars_geodesy.dart';

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

/// No science targets are bundled until their coordinates and provenance are
/// available. This prevents demonstration points from influencing a route.
const List<ScienceTarget> kVerifiedScienceTargets = [];

class MarsGridReference {
  final double centerX;
  final double centerY;
  final double stepX;
  final double stepY;
  final double radiusM;

  const MarsGridReference({
    required this.centerX,
    required this.centerY,
    required this.stepX,
    required this.stepY,
    this.radiusM = MarsGeodesy.marsRadiusM,
  });

  ({int x, int y})? cellFor(double longitudeEastDeg, double latitudePlanetocentricDeg, int width, int height) {
    final xM = radiusM * longitudeEastDeg * math.pi / 180.0;
    final yM = radiusM * latitudePlanetocentricDeg * math.pi / 180.0;
    final x = ((xM - centerX) / stepX).round();
    final y = ((centerY - yM) / stepY).round();
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    return (x: x, y: y);
  }

  ({double longitudeEastDeg, double latitudePlanetocentricDeg}) pointForCell(int x, int y) {
    return (
      longitudeEastDeg: (centerX + x * stepX) / radiusM * 180.0 / math.pi,
      latitudePlanetocentricDeg: (centerY - y * stepY) / radiusM * 180.0 / math.pi,
    );
  }
}

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
  final double cellWidthM;
  final double cellHeightM;
  final Float32List elev;
  final Float32List slope;
  final Float32List rough;
  final Float32List unc;
  final Uint8List nodata;
  final double minElev;
  final double maxElev;
  final String terrainSource;
  final MarsGridReference? georeference;

  TerrainGrid({
    required this.w,
    required this.h,
    required this.cellM,
    required this.cellWidthM,
    required this.cellHeightM,
    required this.elev,
    required this.slope,
    required this.rough,
    required this.unc,
    required this.nodata,
    required this.minElev,
    required this.maxElev,
    required this.terrainSource,
    this.georeference,
  });

  /// Relative simulated pressure P(h)/P_ref = exp(-(h - h_min) / H).
  double pressureRel(int idx) {
    return math.exp(-(elev[idx] - minElev) / scaleHeightM);
  }

  double distanceForCellDelta(num dx, num dy) {
    final eastM = dx.toDouble() * cellWidthM;
    final northM = dy.toDouble() * cellHeightM;
    return math.sqrt(eastM * eastM + northM * northM);
  }

  /// Build from the bundled 480x304 Int16 LE decimetre DEM buffer.
  factory TerrainGrid.fromHiRiseBytes(
    Uint8List bytes, {
    double cellM = defaultCellM,
    Map<String, dynamic>? metadata,
  }) {
    final bd = ByteData.sublistView(bytes);
    final elev = Float32List(gridW * gridH);
    final nodata = Uint8List(gridW * gridH);

    for (var gy = 0; gy < gridH; gy++) {
      for (var gx = 0; gx < gridW; gx++) {
        var sum = 0.0;
        var count = 0;
        for (var by = 0; by < 4; by++) {
          for (var bx = 0; bx < 4; bx++) {
            final hx = gx * 4 + bx;
            final hy = gy * 4 + by;
            final v = bd.getInt16((hy * hiW + hx) * 2, Endian.little);
            if (v == -32768) {
              nodata[gy * gridW + gx] = 1;
              continue;
            }
            sum += v / 10.0;
            count++;
          }
        }
        elev[gy * gridW + gx] = count == 0 ? 0 : sum / count;
      }
    }

    final ref = metadata != null && metadata['gridCenterX'] is num && metadata['gridCenterY'] is num
        ? MarsGridReference(
            centerX: (metadata['gridCenterX'] as num).toDouble(),
            centerY: (metadata['gridCenterY'] as num).toDouble(),
            stepX: ((metadata['gridStepXM'] as num?)?.toDouble() ?? cellM),
            stepY: ((metadata['gridStepYM'] as num?)?.toDouble() ?? cellM),
            radiusM: ((metadata['radiusM'] as num?)?.toDouble() ?? MarsGeodesy.marsRadiusM),
          )
        : null;

    return TerrainGrid.fromElevation(
      w: gridW,
      h: gridH,
      cellM: cellM,
      cellWidthM: (metadata?['cellWidthM'] as num?)?.toDouble() ?? cellM,
      cellHeightM: (metadata?['cellHeightM'] as num?)?.toDouble() ?? cellM,
      elev: elev,
      nodata: nodata,
      georeference: ref,
      terrainSource: metadata?['source'] as String? ?? 'USGS HiRISE DTM (DTEEC_045994_1985_046060_1985_U01)',
    );
  }

  /// Compute derived slope, roughness, and modeled uncertainty from any elevation grid.
  factory TerrainGrid.fromElevation({
    required int w,
    required int h,
    required double cellM,
    double? cellWidthM,
    double? cellHeightM,
    required Float32List elev,
    Uint8List? nodata,
    String terrainSource = 'SYNTHETIC',
    MarsGridReference? georeference,
  }) {
    final nd = nodata ?? Uint8List(w * h);
    final sourceNoData = Uint8List.fromList(nd);
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
        var touchesNoData = false;
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            final nx = x + kx;
            final ny = y + ky;
            if (nx >= 0 && ny >= 0 && nx < w && ny < h && sourceNoData[ny * w + nx] != 0) {
              touchesNoData = true;
            }
          }
        }
        if (touchesNoData) {
          nd[i] = 1;
          continue;
        }
        final dzdx = (g(x + 1, y) - g(x - 1, y)) / (2.0 * (cellWidthM ?? cellM));
        final dzdy = (g(x, y + 1) - g(x, y - 1)) / (2.0 * (cellHeightM ?? cellM));
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
      cellWidthM: cellWidthM ?? cellM,
      cellHeightM: cellHeightM ?? cellM,
      elev: elev,
      slope: slope,
      rough: rough,
      unc: unc,
      nodata: nd,
      minElev: minE.isFinite ? minE : 0.0,
      maxElev: maxE.isFinite ? maxE : 0.0,
      terrainSource: terrainSource,
      georeference: georeference,
    );
  }
}
