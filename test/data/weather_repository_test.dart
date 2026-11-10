import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/weather_repository.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
  });

  tearDown(() async {
    await appDatabase.close();
  });

  group('WeatherApiClient (TDD)', () {
    test('anonymizes coordinates by rounding to 2 decimal places', () {
      final client = WeatherApiClient(client: http.Client());
      final anonymized = client.anonymizeCoordinates(30.267153, -97.743061);
      expect(anonymized.latitude, 30.27);
      expect(anonymized.longitude, -97.74);
    });

    test('parses Open-Meteo REST response correctly', () async {
      final mockResponse = {
        "current": {
          "temperature_2m": 31.0,
          "relative_humidity_2m": 38,
          "apparent_temperature": 35.2
        }
      };

      final mockClient = MockClient((request) async {
        expect(request.url.host, 'api.open-meteo.com');
        return http.Response(jsonEncode(mockResponse), 200);
      });

      final apiClient = WeatherApiClient(client: mockClient);
      final climate = await apiClient.fetchCurrentWeather(
        latitude: 30.267,
        longitude: -97.743,
      );

      expect(climate.temperatureCelsius, 31.0);
      expect(climate.relativeHumidity, 38.0);
      expect(climate.apparentTemperatureCelsius, 35.2);
    });
  });

  group('WeatherRepository Caching & Spike Detection (TDD)', () {
    test('fetches from API and caches locally in SQLite', () async {
      final db = await appDatabase.database;
      final mockResponse = {
        "current": {
          "temperature_2m": 31.0,
          "relative_humidity_2m": 38,
          "apparent_temperature": 35.2
        }
      };

      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        return http.Response(jsonEncode(mockResponse), 200);
      });

      final apiClient = WeatherApiClient(client: mockClient);
      final weatherRepo = WeatherRepository(db: db, apiClient: apiClient);

      // First call should query API
      final result1 = await weatherRepo.getOrFetchWeather(
        latitude: 30.27,
        longitude: -97.74,
      );
      expect(result1.temperatureCelsius, 31.0);
      expect(apiCallCount, 1);

      // Second call immediately within cache window (3 hours) should use cached DB
      final result2 = await weatherRepo.getOrFetchWeather(
        latitude: 30.27,
        longitude: -97.74,
      );
      expect(result2.temperatureCelsius, 31.0);
      expect(apiCallCount, 1); // No new network call!
    });

    test('falls back to cache when network throws exception', () async {
      final db = await appDatabase.database;

      // Seed cache directly with existing data
      await db.insert('weather_cache', {
        'id': 1,
        'timestamp': DateTime.now().subtract(const Duration(minutes: 30)).toIso8601String(),
        'temperature_celsius': 28.5,
        'relative_humidity': 42.0,
        'apparent_temperature_celsius': 30.1,
        'condition_label': 'Clear',
      });

      final failingClient = MockClient((request) async {
        throw http.ClientException('Offline network test');
      });

      final apiClient = WeatherApiClient(client: failingClient);
      final weatherRepo = WeatherRepository(db: db, apiClient: apiClient);

      final result = await weatherRepo.getOrFetchWeather(
        latitude: 30.27,
        longitude: -97.74,
      );

      expect(result.temperatureCelsius, 28.5);
      expect(result.relativeHumidity, 42.0);
    });

    test('detects rapid heat delta spike (>= +4°C in under 1 hour)', () {
      final weatherRepo = WeatherRepository(
        db: null,
        apiClient: WeatherApiClient(client: http.Client()),
      );

      final previous = ClimateCondition(
        temperatureCelsius: 27.0,
        relativeHumidity: 50.0,
      );
      final currentSpike = ClimateCondition(
        temperatureCelsius: 31.5, // +4.5°C
        relativeHumidity: 40.0,
      );
      final currentMild = ClimateCondition(
        temperatureCelsius: 29.0, // +2.0°C
        relativeHumidity: 45.0,
      );

      expect(weatherRepo.isHeatSpikeDelta(previous: previous, current: currentSpike), isTrue);
      expect(weatherRepo.isHeatSpikeDelta(previous: previous, current: currentMild), isFalse);
    });

    test('invalidates weather cache when coordinates change to another city', () async {
      final db = await appDatabase.database;
      int apiCallCount = 0;
      final mockClient = MockClient((request) async {
        apiCallCount++;
        final isAustin = request.url.queryParameters['latitude']?.startsWith('30.') ?? false;
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': isAustin ? 31.0 : 14.0,
              'relative_humidity_2m': isAustin ? 38 : 76,
              'apparent_temperature': isAustin ? 35.0 : 13.0,
            }
          }),
          200,
        );
      });

      final repo = WeatherRepository(
        db: db,
        apiClient: WeatherApiClient(client: mockClient),
      );

      final austin = await repo.getOrFetchWeatherWithMeta(
        latitude: 30.27,
        longitude: -97.74,
      );
      expect(austin.condition.temperatureCelsius, 31.0);
      expect(apiCallCount, 1);

      // Switching to Seattle immediately must bypass Austin's fresh cache
      final seattle = await repo.getOrFetchWeatherWithMeta(
        latitude: 47.61,
        longitude: -122.33,
      );
      expect(seattle.condition.temperatureCelsius, 14.0);
      expect(seattle.source, WeatherDataSource.liveApi);
      expect(apiCallCount, 2);
    });

    test('returns neutral offlineFallback when offline after switching to uncached city', () async {
      final db = await appDatabase.database;
      await db.insert('weather_cache', {
        'id': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'temperature_celsius': 38.0,
        'relative_humidity': 20.0,
        'apparent_temperature_celsius': 39.0,
        'condition_label': 'Live Weather',
        'latitude': 33.45,
        'longitude': -112.07,
      });

      final repo = WeatherRepository(
        db: db,
        apiClient: WeatherApiClient(
          client: MockClient((_) async => throw http.ClientException('Offline')),
        ),
      );

      final result = await repo.getOrFetchWeatherWithMeta(
        latitude: 51.51,
        longitude: -0.13,
      );
      expect(result.source, WeatherDataSource.offlineFallback);
      expect(result.condition.temperatureCelsius, 21.0);
    });

    test('searchCities parses Open-Meteo geocoding results cleanly', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.host, 'geocoding-api.open-meteo.com');
        return http.Response(
          jsonEncode({
            'results': [
              {
                'name': 'Denver',
                'country': 'United States',
                'admin1': 'Colorado',
                'latitude': 39.7392,
                'longitude': -104.9847,
              }
            ]
          }),
          200,
        );
      });

      final client = WeatherApiClient(client: mockClient);
      final results = await client.searchCities('Denver');
      expect(results.length, 1);
      expect(results.first.name, 'Denver');
      expect(results.first.displayName, 'Denver, Colorado, United States');
      expect(results.first.latitude, closeTo(39.74, 0.01));
    });
  });
}

