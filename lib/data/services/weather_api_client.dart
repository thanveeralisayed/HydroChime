import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/climate_condition.dart';

class AnonymizedCoordinate {
  final double latitude;
  final double longitude;

  const AnonymizedCoordinate(this.latitude, this.longitude);
}

class GeocodedLocation {
  final String name;
  final String? admin1;
  final String? country;
  final double latitude;
  final double longitude;

  const GeocodedLocation({
    required this.name,
    this.admin1,
    this.country,
    required this.latitude,
    required this.longitude,
  });

  String get displayName {
    final parts = [name, if (admin1 != null && admin1!.isNotEmpty) admin1!, if (country != null && country!.isNotEmpty) country!];
    return parts.join(', ');
  }
}

class WeatherApiClient {
  final http.Client _client;
  final Duration timeout;

  WeatherApiClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  /// Coarse geohash/coordinate anonymization (rounds to 2 decimal places ~1.1km).
  AnonymizedCoordinate anonymizeCoordinates(double lat, double lon) {
    final roundedLat = (lat * 100).roundToDouble() / 100;
    final roundedLon = (lon * 100).roundToDouble() / 100;
    return AnonymizedCoordinate(roundedLat, roundedLon);
  }

  /// Fetches real-time temperature and relative humidity from Open-Meteo REST endpoint.
  Future<ClimateCondition> fetchCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    final coord = anonymizeCoordinates(latitude, longitude);
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=${coord.latitude}&longitude=${coord.longitude}&current=temperature_2m,relative_humidity_2m,apparent_temperature',
    );

    final response = await _client.get(url).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch weather: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;

    return ClimateCondition(
      temperatureCelsius: (current['temperature_2m'] as num).toDouble(),
      relativeHumidity: (current['relative_humidity_2m'] as num).toDouble(),
      apparentTemperatureCelsius:
          (current['apparent_temperature'] as num?)?.toDouble(),
    );
  }

  /// Searches worldwide locations via Open-Meteo Geocoding API (no API key needed).
  Future<List<GeocodedLocation>> searchCities(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final uri = Uri.https(
      'geocoding-api.open-meteo.com',
      '/v1/search',
      {
        'name': trimmed,
        'count': '6',
        'language': 'en',
        'format': 'json',
      },
    );

    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw Exception('Failed to search cities: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawResults = decoded['results'];
    if (rawResults is! List) return const [];

    return rawResults.whereType<Map<String, dynamic>>().map((item) {
      return GeocodedLocation(
        name: item['name'] as String,
        admin1: item['admin1'] as String?,
        country: item['country'] as String?,
        latitude: (item['latitude'] as num).toDouble(),
        longitude: (item['longitude'] as num).toDouble(),
      );
    }).toList();
  }
}

