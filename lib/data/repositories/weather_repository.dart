import 'package:sqflite/sqflite.dart';
import '../../domain/models/climate_condition.dart';
import '../services/weather_api_client.dart';

enum WeatherDataSource {
  liveApi,
  localCache,
  offlineFallback,
}

class WeatherTelemetryResult {
  final ClimateCondition condition;
  final DateTime updatedAt;
  final WeatherDataSource source;

  const WeatherTelemetryResult({
    required this.condition,
    required this.updatedAt,
    required this.source,
  });
}

class WeatherRepository {
  final Database? db;
  final WeatherApiClient _apiClient;
  static const Duration cacheDuration = Duration(hours: 3);

  WeatherRepository({
    this.db,
    WeatherApiClient? apiClient,
  }) : _apiClient = apiClient ?? WeatherApiClient();

  /// Retrieves weather telemetry from the local cache if fresh (< 3h),
  /// otherwise queries the Open-Meteo API and updates local SQLite.
  Future<ClimateCondition> getOrFetchWeather({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final result = await getOrFetchWeatherWithMeta(
      latitude: latitude,
      longitude: longitude,
      forceRefresh: forceRefresh,
    );
    return result.condition;
  }

  Future<WeatherTelemetryResult> getOrFetchWeatherWithMeta({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    final coord = _apiClient.anonymizeCoordinates(latitude, longitude);

    // 1. Check local cache unless forced (only valid for matching coordinates)
    if (db != null && !forceRefresh) {
      final cached = await _getCachedWeather();
      if (cached != null && _coordinatesMatch(cached, coord)) {
        final timestamp = DateTime.parse(cached['timestamp'] as String);
        if (DateTime.now().difference(timestamp) < cacheDuration) {
          return WeatherTelemetryResult(
            condition: _conditionFromCache(cached),
            updatedAt: timestamp,
            source: WeatherDataSource.localCache,
          );
        }
      }
    }

    // 2. Fetch fresh weather from API
    try {
      final fresh = await _apiClient.fetchCurrentWeather(
        latitude: latitude,
        longitude: longitude,
      );
      final now = DateTime.now();

      if (db != null) {
        await _saveToCache(
          fresh,
          latitude: coord.latitude,
          longitude: coord.longitude,
          timestamp: now,
        );
      }
      return WeatherTelemetryResult(
        condition: fresh,
        updatedAt: now,
        source: WeatherDataSource.liveApi,
      );
    } catch (_) {
      // 3. Fallback to existing cache only if coordinates match or legacy cache has no coords
      if (db != null) {
        final cached = await _getCachedWeather();
        if (cached != null && _coordinatesMatchOrUnset(cached, coord)) {
          return WeatherTelemetryResult(
            condition: _conditionFromCache(cached),
            updatedAt: DateTime.parse(cached['timestamp'] as String),
            source: WeatherDataSource.localCache,
          );
        }
      }
      // Ultimate default fallback if device is completely offline on first launch
      return WeatherTelemetryResult(
        condition: const ClimateCondition(
          temperatureCelsius: 21.0,
          relativeHumidity: 50.0,
          apparentTemperatureCelsius: 21.0,
        ),
        updatedAt: DateTime.now(),
        source: WeatherDataSource.offlineFallback,
      );
    }
  }

  bool _coordinatesMatch(
    Map<String, dynamic> cached,
    AnonymizedCoordinate target,
  ) {
    final cachedLat = (cached['latitude'] as num?)?.toDouble();
    final cachedLon = (cached['longitude'] as num?)?.toDouble();
    if (cachedLat == null || cachedLon == null) return false;
    return (cachedLat - target.latitude).abs() <= 0.02 &&
        (cachedLon - target.longitude).abs() <= 0.02;
  }

  bool _coordinatesMatchOrUnset(
    Map<String, dynamic> cached,
    AnonymizedCoordinate target,
  ) {
    final cachedLat = (cached['latitude'] as num?)?.toDouble();
    final cachedLon = (cached['longitude'] as num?)?.toDouble();
    if (cachedLat == null || cachedLon == null) return true;
    return (cachedLat - target.latitude).abs() <= 0.02 &&
        (cachedLon - target.longitude).abs() <= 0.02;
  }

  ClimateCondition _conditionFromCache(Map<String, dynamic> cached) {
    return ClimateCondition(
      temperatureCelsius: (cached['temperature_celsius'] as num).toDouble(),
      relativeHumidity: (cached['relative_humidity'] as num).toDouble(),
      apparentTemperatureCelsius:
          (cached['apparent_temperature_celsius'] as num?)?.toDouble(),
    );
  }

  Future<Map<String, dynamic>?> _getCachedWeather() async {
    final maps = await db!.query(
      'weather_cache',
      where: 'id = ?',
      whereArgs: [1],
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  Future<void> _saveToCache(
    ClimateCondition condition, {
    required double latitude,
    required double longitude,
    DateTime? timestamp,
  }) async {
    await db!.insert(
      'weather_cache',
      {
        'id': 1,
        'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
        'temperature_celsius': condition.temperatureCelsius,
        'relative_humidity': condition.relativeHumidity,
        'apparent_temperature_celsius': condition.apparentTemperatureCelsius,
        'condition_label': 'Live Weather',
        'latitude': latitude,
        'longitude': longitude,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Heat delta spike detection (+4°C shift within 1 hour)
  bool isHeatSpikeDelta({
    required ClimateCondition previous,
    required ClimateCondition current,
  }) {
    return (current.temperatureCelsius - previous.temperatureCelsius) >= 4.0;
  }
}
