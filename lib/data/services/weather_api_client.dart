import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/climate_condition.dart';

class AnonymizedCoordinate {
  final double latitude;
  final double longitude;

  const AnonymizedCoordinate(this.latitude, this.longitude);
}

class WeatherApiClient {
  final http.Client _client;

  WeatherApiClient({http.Client? client}) : _client = client ?? http.Client();

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

    final response = await _client.get(url);
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
}

