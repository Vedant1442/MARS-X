class JezeroLandmark {
  final String id;
  final String name;
  final String kind;
  final int coordinateDigits;
  final double longitudeEastDeg;
  final double latitudePlanetocentricDeg;
  final String source;
  final String sourceLabel;
  final String note;

  const JezeroLandmark({
    required this.id,
    required this.name,
    required this.kind,
    required this.coordinateDigits,
    required this.longitudeEastDeg,
    required this.latitudePlanetocentricDeg,
    required this.source,
    required this.sourceLabel,
    required this.note,
  });

  factory JezeroLandmark.fromGeoJsonFeature(Map<String, dynamic> feature) {
    final properties = feature['properties'] as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    if (geometry['type'] != 'Point') {
      throw const FormatException('Only point landmarks are supported by this first offline layer.');
    }
    final coordinates = geometry['coordinates'] as List<dynamic>;
    if (coordinates.length < 2) throw const FormatException('Point landmark requires longitude and latitude.');
    return JezeroLandmark(
      id: feature['id'] as String,
      name: properties['name'] as String,
      kind: properties['kind'] as String,
      coordinateDigits: (properties['coordinateDigits'] as num).toInt(),
      longitudeEastDeg: (coordinates[0] as num).toDouble(),
      latitudePlanetocentricDeg: (coordinates[1] as num).toDouble(),
      source: properties['source'] as String,
      sourceLabel: properties['sourceLabel'] as String,
      note: properties['note'] as String,
    );
  }
}

/// Archived rover localizations from PDS PLACES. These are not camera poses.
class RoverStop {
  final String id;
  final int sol;
  final double longitudeEastDeg;
  final double latitudePlanetocentricDeg;
  final String source;
  final String note;

  const RoverStop({
    required this.id,
    required this.sol,
    required this.longitudeEastDeg,
    required this.latitudePlanetocentricDeg,
    required this.source,
    required this.note,
  });

  factory RoverStop.fromGeoJsonFeature(Map<String, dynamic> feature) {
    final properties = feature['properties'] as Map<String, dynamic>;
    final geometry = feature['geometry'] as Map<String, dynamic>;
    if (geometry['type'] != 'Point') {
      throw const FormatException('Rover localizations must be point features.');
    }
    final coordinates = geometry['coordinates'] as List<dynamic>;
    return RoverStop(
      id: feature['id'] as String,
      sol: (properties['sol'] as num).toInt(),
      longitudeEastDeg: (coordinates[0] as num).toDouble(),
      latitudePlanetocentricDeg: (coordinates[1] as num).toDouble(),
      source: properties['sourceLabel'] as String,
      note: properties['note'] as String,
    );
  }
}
