import 'dart:convert';
import 'package:http/http.dart' as http;

class MedaEnvironmentData {
  final int sol;
  final String dataType;
  final String instrument;
  final String citation;
  final int sampleCount;
  final double airTempMin;
  final double airTempMax;
  final double airTempMean;
  final double groundTempMin;
  final double groundTempMax;
  final double groundTempMean;
  final String lmstSpan;

  const MedaEnvironmentData({
    required this.sol,
    required this.dataType,
    required this.instrument,
    required this.citation,
    required this.sampleCount,
    required this.airTempMin,
    required this.airTempMax,
    required this.airTempMean,
    required this.groundTempMin,
    required this.groundTempMax,
    required this.groundTempMean,
    required this.lmstSpan,
  });

  factory MedaEnvironmentData.fromJson(Map<String, dynamic> json) {
    final air = json['air_temperature'] as Map<String, dynamic>? ?? {};
    final ground = json['ground_brightness_temperature'] as Map<String, dynamic>? ?? {};

    return MedaEnvironmentData(
      sol: json['sol'] as int? ?? 20,
      dataType: json['data_type'] as String? ?? 'MEASURED',
      instrument: json['instrument'] as String? ?? 'Mars 2020 MEDA',
      citation: json['citation'] as String? ?? '',
      sampleCount: json['sample_count'] as int? ?? 0,
      airTempMin: (air['min'] as num?)?.toDouble() ?? 0.0,
      airTempMax: (air['max'] as num?)?.toDouble() ?? 0.0,
      airTempMean: (air['mean'] as num?)?.toDouble() ?? 0.0,
      groundTempMin: (ground['min'] as num?)?.toDouble() ?? 0.0,
      groundTempMax: (ground['max'] as num?)?.toDouble() ?? 0.0,
      groundTempMean: (ground['mean'] as num?)?.toDouble() ?? 0.0,
      lmstSpan: json['lmst_span'] as String? ?? '',
    );
  }
}

class BackendStatus {
  final bool isConnected;
  final String? version;
  final String? terrainSource;
  final String? message;

  const BackendStatus({
    required this.isConnected,
    this.version,
    this.terrainSource,
    this.message,
  });
}

class BackendMappedLandmark {
  final String id;
  final String name;
  final int x;
  final int y;
  final double lon;
  final double lat;
  final String type;
  final double value;
  final String imageUrl;
  final String significance;
  final String perseveranceHistory;

  const BackendMappedLandmark({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.lon,
    required this.lat,
    required this.type,
    required this.value,
    required this.imageUrl,
    required this.significance,
    required this.perseveranceHistory,
  });

  factory BackendMappedLandmark.fromJson(Map<String, dynamic> json) {
    return BackendMappedLandmark(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      x: (json['x'] as num?)?.toInt() ?? 60,
      y: (json['y'] as num?)?.toInt() ?? 38,
      lon: (json['lon'] as num?)?.toDouble() ?? 77.45,
      lat: (json['lat'] as num?)?.toDouble() ?? 18.44,
      type: json['type'] as String? ?? 'Landmark',
      value: (json['value'] as num?)?.toDouble() ?? 0.85,
      imageUrl: json['image_url'] as String? ?? '',
      significance: json['significance'] as String? ?? '',
      perseveranceHistory: json['perseverance_history'] as String? ?? '',
    );
  }
}

class MarsXApiService {
  static const String baseUrl = 'https://api-production-14018b03.up.railway.app';
  static final http.Client _client = http.Client();

  /// Check connectivity to deployed Railway backend.
  static Future<BackendStatus> checkHealth() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return BackendStatus(
          isConnected: true,
          version: data['bundle_version'] as String?,
          terrainSource: data['terrain_source'] as String?,
        );
      }
      return BackendStatus(
        isConnected: false,
        message: 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return BackendStatus(
        isConnected: false,
        message: e.toString(),
      );
    }
  }

  /// Fetch real MEDA observations from Railway backend for a given sol.
  static Future<MedaEnvironmentData?> fetchEnvironment({int sol = 20}) async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/environment?sol=$sol'))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return MedaEnvironmentData.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetch the 15 mapped Jezero expedition landmarks from the unified backend.
  static Future<List<BackendMappedLandmark>> fetchMappedLandmarks() async {
    try {
      final res = await _client
          .get(Uri.parse('$baseUrl/api/landmarks/mapped'))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['landmarks'] as List<dynamic>? ?? const [];
        return list
            .whereType<Map<String, dynamic>>()
            .map(BackendMappedLandmark.fromJson)
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Compare routes (Safest, Fastest, Science, Balanced) with trade-offs and 2-crew EVA consumables.
  static Future<Map<String, dynamic>?> compareRoutes({
    double startLon = 77.40672,
    double startLat = 18.38200,
    double goalLon = 77.42689,
    double goalLat = 18.37400,
  }) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/api/routes/compare'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'start': {'lon': startLon, 'lat': startLat},
              'goal': {'lon': goalLon, 'lat': goalLat},
              'profiles': const ['safety', 'fastest', 'science', 'balanced'],
              'include_dijkstra': true,
              'constraints': const {
                'max_slope_deg': 25.0,
                'return_to_base': false,
                'eva_budget_min': 480,
              },
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
