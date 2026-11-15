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

class MappedLandmarkEntry {
  final String id;
  final String name;
  final String category;
  final String subcategory;
  final String geometryType;
  final double? lonEast;
  final double? latDeg;
  final String assetPath;
  final String geologicalDescription;
  final String scientificSignificance;
  final String? perseveranceHistory;
  final String sourceName;
  final String geometryNote;
  final String? panoramaInfo;
  final bool isObserved;

  const MappedLandmarkEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.subcategory,
    required this.geometryType,
    required this.assetPath,
    required this.geologicalDescription,
    required this.scientificSignificance,
    required this.sourceName,
    required this.geometryNote,
    this.lonEast,
    this.latDeg,
    this.perseveranceHistory,
    this.panoramaInfo,
    this.isObserved = false,
  });
}

const List<MappedLandmarkEntry> kMappedJezeroLandmarks = [
  MappedLandmarkEntry(
    id: 'jezero-rim',
    name: 'Jezero Crater rim',
    category: 'geological_features',
    subcategory: 'crater rim',
    geometryType: 'GeometryCollection',
    assetPath: 'assets/images/landmarks/jezero-crater-rim.jpg',
    geologicalDescription: 'Impact crater rim; mapped from USGS SIM 3464 crater-rim crest lines and rim-unit polygons.',
    scientificSignificance: 'Defines basin boundary and relief; rim breaching records past hydrology.',
    sourceName: 'USGS SIM 3464 geologic unit polygons',
    geometryNote: 'GeometryCollection of USGS SIM 3464 mapped components clipped to DEM bounds.',
    panoramaInfo: 'Lookout Hill (Sol 1356–1358 · Mastcam-Z)',
  ),
  MappedLandmarkEntry(
    id: 'western-delta',
    name: 'Western Delta',
    category: 'geological_features',
    subcategory: 'delta/fan deposit',
    geometryType: 'GeometryCollection',
    lonEast: 77.38,
    latDeg: 18.46,
    assetPath: 'assets/images/landmarks/western-delta.jpg',
    geologicalDescription: 'Western fluvio-deltaic fan deposits at the mouth of Neretva Vallis.',
    scientificSignificance: 'Preserves fluvial and lacustrine deposits and potential biosignature-bearing sediments.',
    perseveranceHistory: 'Perseverance explored the western fan and sampled its sedimentary succession.',
    sourceName: 'USGS SIM 3464 geologic unit polygons',
    geometryNote: 'GeometryCollection of USGS SIM 3464 western fan unit polygons clipped to DEM coverage.',
  ),
  MappedLandmarkEntry(
    id: 'neretva-vallis',
    name: 'Neretva Vallis',
    category: 'geological_features',
    subcategory: 'inlet valley/channel',
    geometryType: 'MultiLineString',
    lonEast: 77.20,
    latDeg: 18.55,
    assetPath: 'assets/images/landmarks/neretva-vallis.jpg',
    geologicalDescription: 'Inlet valley/channel entering Jezero from the west/northwest.',
    scientificSignificance: 'Records fluvial transport into the paleolake; rover observations include fluvio-lacustrine strata.',
    perseveranceHistory: 'Perseverance investigated the inlet channel including Tuff Cliff / Bright Angel region.',
    sourceName: 'FU Berlin Jezero WFS channel-lines; USGS Planetary Nomenclature center',
    geometryNote: 'FU Berlin WFS channel component spatially matched by official Gazetteer representative point.',
    panoramaInfo: 'Neretva Vallis (Sol 1155 · Mastcam-Z)',
  ),
  MappedLandmarkEntry(
    id: 'sava-vallis',
    name: 'Sava Vallis',
    category: 'geological_features',
    subcategory: 'inlet valley/channel',
    geometryType: 'MultiLineString',
    lonEast: 77.13,
    latDeg: 19.09,
    assetPath: 'assets/images/landmarks/sava-vallis.jpg',
    geologicalDescription: 'Named western/northern inlet valley system in regional nomenclature.',
    scientificSignificance: 'Evidence for northern fluvial inflow to Jezero basin.',
    sourceName: 'FU Berlin Jezero WFS channel-lines; USGS Planetary Nomenclature center',
    geometryNote: 'FU Berlin WFS channel component spatially matched by official Gazetteer representative point.',
  ),
  MappedLandmarkEntry(
    id: 'eastern-outlet',
    name: 'Eastern Outlet Valley (Pliva Vallis)',
    category: 'geological_features',
    subcategory: 'outlet valley/channel',
    geometryType: 'MultiLineString',
    lonEast: 78.35,
    latDeg: 18.67,
    assetPath: 'assets/images/landmarks/pliva-vallis.jpg',
    geologicalDescription: 'The eastern outlet channel is officially named Pliva Vallis; Eastern Outlet Valley is a descriptive synonym.',
    scientificSignificance: 'Records overflow/drainage and episodic open-basin fluvial activity.',
    sourceName: 'FU Berlin Jezero WFS channel-lines; USGS Planetary Nomenclature center',
    geometryNote: 'FU Berlin WFS channel component spatially matched by official Gazetteer representative point.',
  ),
  MappedLandmarkEntry(
    id: 'ancient-lake-basin',
    name: 'Ancient lake basin',
    category: 'geological_features',
    subcategory: 'paleolake basin',
    geometryType: 'Polygon',
    lonEast: 77.55,
    latDeg: 18.42,
    assetPath: 'assets/images/landmarks/ancient-lake-basin.jpg',
    geologicalDescription: 'Jezero hosted an ancient lake; reconstructed lake extents vary with inferred water level and time.',
    scientificSignificance: 'Habitability context and depositional setting for delta/lacustrine sediments.',
    perseveranceHistory: 'Mission investigates rocks formed in and around the paleolake.',
    sourceName: 'FU Berlin Jezero WFS possible paleo lake-level',
    geometryNote: 'One possible reconstructed lake-level polygon, not a definitive basin boundary.',
  ),
  MappedLandmarkEntry(
    id: 'landing',
    name: 'Octavia E. Butler Landing Site',
    category: 'rover_exploration',
    subcategory: 'landing site',
    geometryType: 'Point',
    lonEast: 77.4509,
    latDeg: 18.4446,
    assetPath: 'assets/images/landmarks/octavia-butler-landing.jpg',
    geologicalDescription: 'Perseverance touchdown location on the Máaz formation crater floor.',
    scientificSignificance: 'Mission entry point for in-situ exploration.',
    perseveranceHistory: 'Touchdown on Sol 0, 18 February 2021.',
    sourceName: 'Stack et al. 2023 Science Advances',
    geometryNote: 'Mapped authoritative touchdown coordinate.',
    panoramaInfo: 'Octavia E. Butler Landing Site (Sol 3 and 11 · Mastcam-Z)',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'three-forks',
    name: 'Three Forks',
    category: 'rover_exploration',
    subcategory: 'sample depot / waypoint',
    geometryType: 'MultiPoint',
    lonEast: 77.402,
    latDeg: 18.450,
    assetPath: 'assets/images/landmarks/three-forks.jpg',
    geologicalDescription: 'Named location of Perseverance sample depot near the base of the western fan.',
    scientificSignificance: 'Preserves 10 cached titanium sample tubes for Mars Sample Return.',
    perseveranceHistory: 'Ten sample tubes deposited during December 2022–January 2023.',
    sourceName: 'FU Berlin Jezero interactive map WFS panoramas',
    geometryNote: 'Two named Mastcam-Z viewpoints at Three Forks, not individual tube coordinates.',
    panoramaInfo: 'Three Forks Sample Depot #1 (Sol 670 · Mastcam-Z)',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'hawksbill-gap',
    name: 'Hawksbill Gap',
    category: 'rover_exploration',
    subcategory: 'delta-front waypoint / outcrop',
    geometryType: 'Point',
    lonEast: 77.4059,
    latDeg: 18.4586,
    assetPath: 'assets/images/landmarks/hawksbill-gap.jpg',
    geologicalDescription: 'Named passage/outcrop area in the western delta front, associated with the Shenandoah formation.',
    scientificSignificance: 'Exposes delta-front sedimentary stratigraphy and sulfate/clay mudstones.',
    perseveranceHistory: 'Perseverance traversed and sampled in the delta-front campaign.',
    sourceName: 'NASA PDS Mars 2020 Initial Reports, Volume 2',
    geometryNote: 'PDS-reported rover/sample acquisition localization associated with the named outcrop.',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'belva-crater',
    name: 'Belva Crater',
    category: 'rover_exploration',
    subcategory: 'impact crater / rover stop',
    geometryType: 'Point',
    lonEast: 77.3686,
    latDeg: 18.4827,
    assetPath: 'assets/images/landmarks/belva-crater.jpg',
    geologicalDescription: 'Named ~900 m impact crater and nearby rover observation area on the upper western fan.',
    scientificSignificance: 'Provides deep vertical exposure into delta stratigraphy.',
    perseveranceHistory: 'Visited and imaged by Perseverance during the upper fan campaign.',
    sourceName: 'FU Berlin Jezero interactive map WFS panoramas',
    geometryNote: 'Source-georeferenced Mastcam-Z panorama viewpoint.',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'enchanted-lake',
    name: 'Enchanted Lake',
    category: 'rover_exploration',
    subcategory: 'informal waypoint / target',
    geometryType: 'Point',
    lonEast: 77.4014,
    latDeg: 18.4507,
    assetPath: 'assets/images/landmarks/enchanted-lake.jpg',
    geologicalDescription: 'Informal named sedimentary outcrop/area at the base of the western fan.',
    scientificSignificance: 'Layered sedimentary rocks preserve facies consistent with subaqueous deposition.',
    perseveranceHistory: 'Perseverance worked in the Enchanted Lake area during Sols 420–426.',
    sourceName: 'FU Berlin Jezero interactive map WFS panoramas',
    geometryNote: 'Source-georeferenced Mastcam-Z panorama viewpoint.',
    panoramaInfo: 'Enchanted Lake (Sol 566–586 · Mastcam-Z)',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'cape-nukshak',
    name: 'Cape Nukshak',
    category: 'rover_exploration',
    subcategory: 'delta-front outcrop / waypoint',
    geometryType: 'Point',
    lonEast: 77.4014,
    latDeg: 18.4507,
    assetPath: 'assets/images/landmarks/cape-nukshak.jpg',
    geologicalDescription: 'Named section/outcrop along eastern scarp of the western delta, in the Shenandoah formation.',
    scientificSignificance: 'Exposes lower delta sequence and facies architecture.',
    perseveranceHistory: 'Perseverance investigated the section during delta-front campaign.',
    sourceName: 'NASA PDS Mars 2020 Initial Reports, Volume 2',
    geometryNote: 'PDS-reported rover/sample acquisition localization associated with the named outcrop.',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'bunsen-peak',
    name: 'Bunsen Peak',
    category: 'points_of_interest',
    subcategory: 'informal waypoint / sampled rock',
    geometryType: 'Point',
    lonEast: 77.3272,
    latDeg: 18.4918,
    assetPath: 'assets/images/landmarks/bunsen-peak.jpg',
    geologicalDescription: 'Prominent rock on a ridge in the Margin unit; sample source for Comet Geyser.',
    scientificSignificance: 'Sampled sedimentary rock characterizes the carbonate-bearing Margin unit.',
    perseveranceHistory: 'Perseverance collected its 27th named sample at Bunsen Peak on Sol 1088.',
    sourceName: 'FU Berlin Jezero interactive map WFS panoramas',
    geometryNote: 'Source-georeferenced Mastcam-Z panorama viewpoint.',
    panoramaInfo: 'Bunsen Peak & Neretva Vallis (Sol 1074–1082 · Mastcam-Z)',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'jurabi-point',
    name: 'Jurabi Point',
    category: 'points_of_interest',
    subcategory: 'informal waypoint / traverse area',
    geometryType: 'Point',
    lonEast: 77.3472,
    latDeg: 18.4955,
    assetPath: 'assets/images/landmarks/jurabi-point.jpg',
    geologicalDescription: 'Named waypoint in the Margin Unit campaign.',
    scientificSignificance: 'Provides context for the rover exploration of carbonate-bearing margin terrain.',
    perseveranceHistory: 'NASA reports Perseverance arrived at Jurabi Point on Sol 958.',
    sourceName: 'NASA Science, Here Comes the Sun; PDS PLACES',
    geometryNote: 'Last PDS PLACES rover localization on Sol 958.',
    isObserved: true,
  ),
  MappedLandmarkEntry(
    id: 'gnaraloo-bay',
    name: 'Gnaraloo Bay',
    category: 'points_of_interest',
    subcategory: 'informal waypoint / erosional window',
    geometryType: 'Point',
    lonEast: 77.3516,
    latDeg: 18.4965,
    assetPath: 'assets/images/landmarks/gnaraloo-bay.jpg',
    geologicalDescription: 'Erosional window through the western fan apex exposing underlying Margin Unit.',
    scientificSignificance: 'Exposes the fan-Margin unconformity and stratigraphic relations.',
    perseveranceHistory: 'NASA reports Perseverance drove into Gnaraloo Bay on Sol 959.',
    sourceName: 'AGU 2025 Margin Unit stratigraphy paper',
    geometryNote: 'Last PDS PLACES rover localization on Sol 959.',
    isObserved: true,
  ),
];

