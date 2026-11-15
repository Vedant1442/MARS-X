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
  final String imagePath;
  final String significance;

  const ScienceTarget({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.type,
    required this.value,
    required this.conf,
    required this.note,
    this.imagePath = '',
    this.significance = '',
  });
}

const List<ScienceTarget> kDemoTargets = [
  ScienceTarget(
    id: 'octavia-butler-landing',
    name: 'Octavia E. Butler Landing Site',
    x: 98,
    y: 42,
    type: 'Landing Site',
    value: 0.95,
    conf: 'HIGH',
    note: 'Touchdown site of NASA Perseverance rover on February 18, 2021. Starting point of Mars 2020 mission to search for ancient microbial life.',
    imagePath: 'assets/landmarks/octavia-butler-landing.jpg',
    significance: 'Starting point of Perseverance exploration; exposed olivine-bearing basaltic floor regolith.',
  ),
  ScienceTarget(
    id: 'three-forks',
    name: 'Three Forks Sample Depot',
    x: 52,
    y: 34,
    type: 'Sample Depot',
    value: 0.98,
    conf: 'HIGH',
    note: 'Primary sample depot where Perseverance deposited 10 titanium sample tubes in a zigzag pattern as backup cache for Mars Sample Return (MSR).',
    imagePath: 'assets/landmarks/three-forks.jpg',
    significance: 'First extraterrestrial sample depot in human history; high-priority return cache.',
  ),
  ScienceTarget(
    id: 'enchanted-lake',
    name: 'Enchanted Lake',
    x: 46,
    y: 36,
    type: 'Lacustrine Outcrop',
    value: 0.94,
    conf: 'HIGH',
    note: 'Base of the delta front exposing finely laminated, thin-bedded mudstones deposited in ancient quiet lakebed waters.',
    imagePath: 'assets/landmarks/enchanted-lake.jpg',
    significance: 'Fine-grained lacustrine sediments with highest biosignature preservation potential.',
  ),
  ScienceTarget(
    id: 'hawksbill-gap',
    name: 'Hawksbill Gap',
    x: 38,
    y: 26,
    type: 'Delta Scarp Waypoint',
    value: 0.95,
    conf: 'HIGH',
    note: 'Strategic pass ascending the delta front where Perseverance collected samples with detected aromatic organic molecules (Scheller et al., Science 2022).',
    imagePath: 'assets/landmarks/hawksbill-gap.jpg',
    significance: 'Key delta traverse corridor exposing continuous vertical stratigraphy.',
  ),
  ScienceTarget(
    id: 'cape-nukshak',
    name: 'Cape Nukshak',
    x: 32,
    y: 22,
    type: 'Delta Promontory',
    value: 0.88,
    conf: 'HIGH',
    note: 'Prominent delta promontory exposing stacked sandstone layers and bottomset-to-foreset deltaic architectural transitions.',
    imagePath: 'assets/landmarks/cape-nukshak.jpg',
    significance: 'Exposes layered sedimentary rocks recording high-energy ancient river discharge pulses.',
  ),
  ScienceTarget(
    id: 'western-delta',
    name: 'Western Delta',
    x: 22,
    y: 28,
    type: 'Fluvial-Deltaic Fan',
    value: 0.96,
    conf: 'HIGH',
    note: 'Ancient river fan formed by Neretva Vallis where river sediments were deposited into Jezero lake 3.5 billion years ago.',
    imagePath: 'assets/landmarks/western-delta.jpg',
    significance: 'Clay and sulfate-bearing mudstones; prime zone for ancient astrobiological investigations.',
  ),
  ScienceTarget(
    id: 'neretva-vallis',
    name: 'Neretva Vallis Inflow Channel',
    x: 12,
    y: 38,
    type: 'Inflow Channel',
    value: 0.91,
    conf: 'HIGH',
    note: 'Major western breach canyon where ancient torrents of water cut through the Jezero crater rim to build the western fan.',
    imagePath: 'assets/landmarks/neretva-vallis.jpg',
    significance: 'Evidence of sustained, multi-phase hydrological cycles on early Mars.',
  ),
  ScienceTarget(
    id: 'bunsen-peak',
    name: 'Bunsen Peak',
    x: 26,
    y: 44,
    type: 'Topographic Peak',
    value: 0.89,
    conf: 'HIGH',
    note: 'Elevated rocky summit providing panoramic views of Neretva Vallis channel mouth, delta front, and surrounding floor units.',
    imagePath: 'assets/landmarks/bunsen-peak.jpg',
    significance: 'Strategic terrain observation point and prominent visual navigation landmark.',
  ),
  ScienceTarget(
    id: 'jurabi-point',
    name: 'Jurabi Point',
    x: 42,
    y: 40,
    type: 'Delta Front Waypoint',
    value: 0.84,
    conf: 'HIGH',
    note: 'Waypoint along the southern delta margin marking the transition between river-transported sandstones and deeper lake clays.',
    imagePath: 'assets/landmarks/jurabi-point.jpg',
    significance: 'Records dynamic water depth fluctuations during lake regression stages.',
  ),
  ScienceTarget(
    id: 'gnaraloo-bay',
    name: 'Gnaraloo Bay',
    x: 58,
    y: 24,
    type: 'Sedimentary Inlet',
    value: 0.85,
    conf: 'HIGH',
    note: 'Quiet embayment on the delta margin where fine suspended clays settled out of calm backwaters.',
    imagePath: 'assets/landmarks/gnaraloo-bay.jpg',
    significance: 'Low-energy depositional environment ideal for concentrating ancient organic geochemical traces.',
  ),
  ScienceTarget(
    id: 'belva-crater',
    name: 'Belva Crater Rim',
    x: 84,
    y: 16,
    type: 'Impact Crater',
    value: 0.90,
    conf: 'HIGH',
    note: '1-km impact crater that excavated deeply through delta sediments into underlying crater floor rocks, exposing giant megabreccia blocks (Beyssac et al., 2023).',
    imagePath: 'assets/landmarks/belva-crater.jpg',
    significance: 'Natural drill hole exposing subsurface crustal geology down to tens of metres.',
  ),
  ScienceTarget(
    id: 'jezero-crater-rim',
    name: 'Jezero Crater Rim',
    x: 6,
    y: 12,
    type: 'Crater Rim',
    value: 0.88,
    conf: 'HIGH',
    note: 'Ancient 45-km diameter impact basin rim formed ~3.5 Ga, towering hundreds of metres above the crater lake floor.',
    imagePath: 'assets/landmarks/jezero-crater-rim.jpg',
    significance: 'Provides boundary constraints for paleolake water levels and regional impact crater morphology.',
  ),
  ScienceTarget(
    id: 'sava-vallis',
    name: 'Sava Vallis Channel',
    x: 16,
    y: 18,
    type: 'Inflow Channel',
    value: 0.83,
    conf: 'HIGH',
    note: 'Secondary inflow valley entering from the northwest, contributing sediment to the northern portion of the Jezero delta complex.',
    imagePath: 'assets/landmarks/sava-vallis.jpg',
    significance: 'Proves Jezero received water from multiple tributary catchment areas.',
  ),
  ScienceTarget(
    id: 'ancient-lake-basin',
    name: 'Ancient Lake Basin Floor',
    x: 64,
    y: 58,
    type: 'Lake Basin Floor',
    value: 0.87,
    conf: 'HIGH',
    note: 'Flat floor of Jezero Crater, formerly submerged under more than 200 metres of freshwater during the Noachian/Hesperian boundary epoch.',
    imagePath: 'assets/landmarks/ancient-lake-basin.jpg',
    significance: 'Deep lake bottom sediments holding climate records of Mars early wet era.',
  ),
  ScienceTarget(
    id: 'pliva-vallis',
    name: 'Eastern Outlet Valley (Pliva Vallis)',
    x: 114,
    y: 52,
    type: 'Outflow Channel',
    value: 0.86,
    conf: 'HIGH',
    note: 'Outflow breach where water drained eastward out of Jezero, proving it was a stable open-basin lake with continuous freshwater flushing.',
    imagePath: 'assets/landmarks/pliva-vallis.jpg',
    significance: 'Stabilized water chemistry, avoiding hypersaline buildup and keeping the lake habitable.',
  ),
];

const List<ScienceTarget> kVerifiedScienceTargets = kDemoTargets;

class MarsGridReference {
  final double centerX;
  final double centerY;
  final double stepX;
  final double stepY;
  final double radiusM;
  /// X-axis scale used by the source equirectangular projection.
  /// CTX uses cos(standard parallel); the local HiRISE grid uses 1.0.
  final double longitudeScaleCos;

  const MarsGridReference({
    required this.centerX,
    required this.centerY,
    required this.stepX,
    required this.stepY,
    this.radiusM = MarsGeodesy.marsRadiusM,
    this.longitudeScaleCos = 1.0,
  });

  ({double x, double y}) positionFor(
    double longitudeEastDeg,
    double latitudePlanetocentricDeg,
    int width,
    int height,
  ) {
    final xM = radiusM * longitudeScaleCos * longitudeEastDeg * math.pi / 180.0;
    final yM = radiusM * latitudePlanetocentricDeg * math.pi / 180.0;
    return (
      x: (xM - centerX) / stepX + (width - 1) / 2.0,
      y: (centerY - yM) / stepY + (height - 1) / 2.0,
    );
  }

  ({int x, int y})? cellFor(double longitudeEastDeg, double latitudePlanetocentricDeg, int width, int height) {
    final position = positionFor(longitudeEastDeg, latitudePlanetocentricDeg, width, height);
    final x = position.x.round();
    final y = position.y.round();
    if (x < 0 || y < 0 || x >= width || y >= height) return null;
    return (x: x, y: y);
  }

  ({double longitudeEastDeg, double latitudePlanetocentricDeg}) pointForCell(int x, int y, int width, int height) {
    return (
      longitudeEastDeg: (centerX + (x - (width - 1) / 2.0) * stepX) / (radiusM * longitudeScaleCos) * 180.0 / math.pi,
      latitudePlanetocentricDeg: (centerY - (y - (height - 1) / 2.0) * stepY) / radiusM * 180.0 / math.pi,
    );
  }
}

/// Terrain grids for the whole-crater CTX DEM and the landing-site HiRISE DTM.
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
  final String gridId;
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
    this.gridId = 'unknown_grid_v1',
    this.georeference,
  });

  /// Relative simulated pressure P(h)/P_ref = exp(-(h - h_min) / H).
  double pressureRel(int idx) {
    return math.exp(-(elev[idx] - minElev) / scaleHeightM);
  }

  /// Authentic barometric pressure in Pascals computed from Perseverance MEDA baseline.
  double pressurePa(int idx, {double basePressurePa = 750.0}) {
    return MedaWeatherModel.barometricPressurePa(elev[idx], basePressurePa);
  }

  double distanceForCellDelta(num dx, num dy) {
    final eastM = dx.toDouble() * cellWidthM;
    final northM = dy.toDouble() * cellHeightM;
    return math.sqrt(eastM * eastM + northM * northM);
  }

  /// Extract full-resolution corridor cross-section and hazard flags along the route path (P2).
  CorridorProfile extractCorridorProfile(List<GridPoint> path) {
    if (path.isEmpty) {
      return const CorridorProfile(
        totalDistanceM: 0,
        minElevationM: 0,
        maxElevationM: 0,
        maxSlopeDeg: 0,
        meanSlopeDeg: 0,
        points: [],
        hazardScarpCount: 0,
      );
    }
    final pts = <CorridorPoint>[];
    var cumulativeM = 0.0;
    var minE = double.infinity;
    var maxE = -double.infinity;
    var maxS = 0.0;
    var sumS = 0.0;
    var scarpCount = 0;

    for (var k = 0; k < path.length; k++) {
      final p = path[k];
      final i = p.y * w + p.x;
      if (k > 0) {
        cumulativeM += distanceForCellDelta(p.x - path[k - 1].x, p.y - path[k - 1].y);
      }
      final e = elev[i];
      final s = slope[i];
      final r = rough[i];
      if (e < minE) minE = e;
      if (e > maxE) maxE = e;
      if (s > maxS) maxS = s;
      sumS += s;
      final isScarp = s >= 15.0;
      if (isScarp) scarpCount++;

      pts.add(CorridorPoint(
        distanceM: cumulativeM,
        elevationM: e,
        slopeDeg: s,
        roughness: r,
        isHazardScarp: isScarp,
        isRoughHazard: r >= 0.40,
      ));
    }

    return CorridorProfile(
      totalDistanceM: cumulativeM,
      minElevationM: minE.isFinite ? minE : 0,
      maxElevationM: maxE.isFinite ? maxE : 0,
      maxSlopeDeg: maxS,
      meanSlopeDeg: sumS / path.length,
      points: pts,
      hazardScarpCount: scarpCount,
    );
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
            longitudeScaleCos: ((metadata['longitudeScaleCos'] as num?)?.toDouble() ?? 1.0),
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
      gridId: metadata?['gridId'] as String? ?? 'jezero_hirise_patch_v1',
    );
  }

  /// Build the whole-crater route grid from signed 16-bit metre elevations.
  /// The asset is aggregated from the USGS 20 m CTX DEM to 100 m cells.
  factory TerrainGrid.fromCtxBytes(
    Uint8List bytes, {
    required Map<String, dynamic> metadata,
  }) {
    final w = (metadata['width'] as num).toInt();
    final h = (metadata['height'] as num).toInt();
    final noDataValue = (metadata['noDataValue'] as num).toInt();
    if (bytes.length != w * h * 2) {
      throw FormatException('CTX elevation asset has ${bytes.length} bytes; expected ${w * h * 2}.');
    }
    final data = ByteData.sublistView(bytes);
    final elev = Float32List(w * h);
    final nodata = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      final value = data.getInt16(i * 2, Endian.little);
      if (value == noDataValue) {
        nodata[i] = 1;
      } else {
        elev[i] = value.toDouble();
      }
    }
    final stepX = (metadata['cellProjectedM'] as List<dynamic>)[0] as num;
    final stepY = (metadata['cellProjectedM'] as List<dynamic>)[1] as num;
    return TerrainGrid.fromElevation(
      w: w,
      h: h,
      cellM: (metadata['cellM'] as num).toDouble(),
      cellWidthM: (metadata['cellWidthGroundM'] as num).toDouble(),
      cellHeightM: (metadata['cellHeightGroundM'] as num).toDouble(),
      elev: elev,
      nodata: nodata,
      terrainSource: metadata['source'] as String? ?? 'USGS M20 Jezero CTX DEM, aggregated to 100 m',
      gridId: metadata['gridId'] as String? ?? 'jezero_ctx_100m_v1',
      georeference: MarsGridReference(
        centerX: (metadata['gridCenterX'] as num).toDouble(),
        centerY: (metadata['gridCenterY'] as num).toDouble(),
        stepX: stepX.toDouble(),
        stepY: stepY.toDouble(),
        radiusM: (metadata['sphereRadiusM'] as num).toDouble(),
        longitudeScaleCos: (metadata['longitudeScaleCos'] as num).toDouble(),
      ),
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
    String gridId = 'unknown_grid_v1',
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
      gridId: gridId,
      georeference: georeference,
    );
  }
}

class MedaReading {
  final int hour;
  final double airTempC;
  final double groundTempC;
  final double? relativeHumidityPct;
  final double basePressurePa;
  final String status;

  const MedaReading({
    required this.hour,
    required this.airTempC,
    required this.groundTempC,
    this.relativeHumidityPct,
    required this.basePressurePa,
    required this.status,
  });

  factory MedaReading.fromJson(Map<String, dynamic> json) {
    return MedaReading(
      hour: (json['hour'] as num?)?.toInt() ?? 0,
      airTempC: (json['air_temp_c'] as num?)?.toDouble() ?? -30.0,
      groundTempC: (json['ground_temp_c'] as num?)?.toDouble() ?? -20.0,
      relativeHumidityPct: (json['relative_humidity_pct'] as num?)?.toDouble(),
      basePressurePa: (json['base_pressure_pa'] as num?)?.toDouble() ?? 750.0,
      status: json['status'] as String? ?? 'MODELED',
    );
  }
}

class MedaWeatherModel {
  static const double baseLandingElevM = -2560.0;
  static const double scaleHeightM = 11100.0; // Mars atmospheric scale height
  static const double mslRadDoseRateMicroSvPerMin = 0.445; // 26.7 uSv/hr (Hassler et al., 2014)

  static double barometricPressurePa(double elevM, double basePressurePa) {
    return basePressurePa * math.exp(-(elevM - baseLandingElevM) / scaleHeightM);
  }

  static double radiationDoseMicroSv(double durationMin) {
    return durationMin * mslRadDoseRateMicroSvPerMin;
  }
}

class CorridorPoint {
  final double distanceM;
  final double elevationM;
  final double slopeDeg;
  final double roughness;
  final bool isHazardScarp; // slope >= 15.0 deg
  final bool isRoughHazard; // roughness >= 0.40

  const CorridorPoint({
    required this.distanceM,
    required this.elevationM,
    required this.slopeDeg,
    required this.roughness,
    required this.isHazardScarp,
    required this.isRoughHazard,
  });
}

class CorridorProfile {
  final double totalDistanceM;
  final double minElevationM;
  final double maxElevationM;
  final double maxSlopeDeg;
  final double meanSlopeDeg;
  final List<CorridorPoint> points;
  final int hazardScarpCount;

  const CorridorProfile({
    required this.totalDistanceM,
    required this.minElevationM,
    required this.maxElevationM,
    required this.maxSlopeDeg,
    required this.meanSlopeDeg,
    required this.points,
    required this.hazardScarpCount,
  });
}
