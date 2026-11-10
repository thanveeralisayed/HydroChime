import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/intake_log_repository.dart';
import 'package:hydrochime/data/repositories/user_profile_repository.dart';
import 'package:hydrochime/data/repositories/weather_repository.dart';
import 'package:hydrochime/data/services/ip_location_service.dart';
import 'package:hydrochime/data/services/local_notification_service.dart';
import 'package:hydrochime/data/services/location_service.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/beverage_type.dart';
import 'package:hydrochime/domain/models/climate_condition.dart';
import 'package:hydrochime/domain/models/intake_log.dart';
import 'package:hydrochime/domain/models/user_profile.dart';
import 'package:hydrochime/domain/services/notification_scheduler.dart';
import 'package:hydrochime/presentation/providers/hydration_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class TestClimateNotifier extends CurrentClimateNotifier {
  @override
  ClimateCondition build() {
    return const ClimateCondition(
      temperatureCelsius: 31.0,
      relativeHumidity: 38.0,
    );
  }
}

class _RecordingGpsService implements PermissionAwareLocationService {
  final List<bool> requestPermissionArgs = [];
  Future<({double latitude, double longitude})> Function(bool requestPermission)
      handler;

  _RecordingGpsService(this.handler);

  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates({
    bool requestPermission = true,
  }) {
    requestPermissionArgs.add(requestPermission);
    return handler(requestPermission);
  }
}

class _StubIpLocationService implements IpLocationService {
  Future<IpLocationResult> Function() handler;
  int calls = 0;

  _StubIpLocationService(this.handler);

  @override
  Future<IpLocationResult> lookupPublicIpLocation() {
    calls++;
    return handler();
  }
}

class _SpyNotificationService implements NotificationService {
  final List<({bool enabled, int slotCount})> calls = [];
  bool supportsScheduled = true;

  @override
  bool get supportsScheduledNotifications => supportsScheduled;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> syncPacingSchedule({
    required List<HydrationChimeSlot> slots,
    required bool enabled,
  }) async {
    calls.add((enabled: enabled, slotCount: slots.length));
  }

  @override
  Future<TestChimeStatus> showTestChime() async => TestChimeStatus.sent;

  @override
  Future<void> cancelAll() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late IntakeLogRepository intakeLogRepository;
  late UserProfileRepository userProfileRepository;
  late ProviderContainer container;

  setUp(() async {
    appDatabase = AppDatabase.inMemory();
    final db = await appDatabase.database;
    intakeLogRepository = IntakeLogRepository(db);
    userProfileRepository = UserProfileRepository(db);

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(AsyncData(db)),
        intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeLogRepository)),
        userProfileRepositoryProvider.overrideWithValue(AsyncData(userProfileRepository)),
        currentClimateProvider.overrideWith(() => TestClimateNotifier()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await appDatabase.close();
  });

  group('HydrationNotifier (State Management TDD)', () {
    test('initializes cleanly from async databaseProvider without requireValue crash',
        () async {
      final asyncDb = AppDatabase.inMemory();
      final startupContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(asyncDb),
          currentClimateProvider.overrideWith(() => TestClimateNotifier()),
        ],
      );
      addTearDown(() async {
        startupContainer.dispose();
        await asyncDb.close();
      });

      final state = await startupContainer.read(hydrationNotifierProvider.future);
      expect(state.targetVolumeMl, 3185);
      expect(state.currentVolumeMl, 0);
    });

    test('initializes with target calculated from profile and climate', () async {
      final state = await container.read(hydrationNotifierProvider.future);
      // 70kg weight, 31°C heat -> baseline 2450 * 1.30 = 3185 mL (without activity)
      expect(state.targetVolumeMl, 3185);
      expect(state.currentVolumeMl, 0);
      expect(state.percentage, 0.0);
      expect(state.remainingMl, 3185);
    });

    test('includes dailyActivityMinutes and customBaselineMl in target breakdown',
        () async {
      await userProfileRepository.updateDailyActivityMinutes(35);
      container.invalidate(userProfileProvider);

      var state = await container.read(hydrationNotifierProvider.future);
      // (2450 + 420) * 1.30 = 3731 mL
      expect(state.targetVolumeMl, 3731);
      expect(state.breakdown.activityMl, 420);

      await userProfileRepository.updateCustomBaseline(3000);
      await userProfileRepository.updateDailyActivityMinutes(0);
      container.invalidate(userProfileProvider);

      state = await container.read(hydrationNotifierProvider.future);
      // 3000 * 1.30 = 3900 mL
      expect(state.breakdown.baselineMl, 3000);
      expect(state.targetVolumeMl, 3900);
    });

    test('logging water increments volume and updates progress fraction', () async {
      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(amountMl: 500, type: BeverageType.water);

      final state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 500);
      expect(state.remainingMl, 2685);
      expect(state.recentLogs.length, 1);
      expect(state.recentLogs.first.volumeMl, 500);
    });

    test('logging electrolytes applies bioavailability multiplier (1.45x)', () async {
      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(amountMl: 350, type: BeverageType.electrolytes);

      final state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 508); // 350 * 1.45
    });

    test('filters today logs and deletes & restores log cleanly', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await intakeLogRepository.insertLog(IntakeLog(
        timestamp: yesterday,
        volumeMl: 1000,
        beverageType: BeverageType.water,
        effectiveVolumeMl: 1000,
      ));

      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(amountMl: 250, type: BeverageType.water);

      var state = await container.read(hydrationNotifierProvider.future);
      // Yesterday's log should not appear in today's volume or today's recentLogs
      expect(state.currentVolumeMl, 250);
      expect(state.recentLogs.length, 1);

      final inserted = state.recentLogs.first;
      await notifier.deleteLog(inserted.id!);

      state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 0);
      expect(state.recentLogs, isEmpty);

      await notifier.restoreLog(inserted);
      state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 250);
      expect(state.recentLogs.length, 1);

      // Updating existing log volume & type recalculates effective total
      final saved = state.recentLogs.first;
      await notifier.updateLog(
        id: saved.id!,
        volumeMl: 400,
        type: BeverageType.electrolytes,
        timestamp: saved.timestamp,
      );
      state = await container.read(hydrationNotifierProvider.future);
      expect(state.currentVolumeMl, 580); // 400 * 1.45
      expect(state.recentLogs.first.beverageType, BeverageType.electrolytes);
    });

    test('weatherSyncProvider fetches live weather and updates climate state',
        () async {
      int calls = 0;
      final mockClient = MockClient((request) async {
        calls++;
        final temp = calls == 1 ? 26.0 : 32.0; // +6°C spike on refresh!
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': temp,
              'relative_humidity_2m': 45,
              'apparent_temperature': temp + 1.5,
            }
          }),
          200,
        );
      });

      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final weatherContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(
            AsyncData(UserProfileRepository(db)),
          ),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(client: mockClient),
          ),
        ],
      );
      addTearDown(() async {
        weatherContainer.dispose();
        await weatherDb.close();
      });

      final syncState = await weatherContainer.read(weatherSyncProvider.future);
      expect(syncState.condition.temperatureCelsius, 26.0);
      expect(syncState.heatSpikeDetected, isFalse);
      expect(
        weatherContainer.read(currentClimateProvider).temperatureCelsius,
        26.0,
      );

      await weatherContainer
          .read(weatherSyncProvider.notifier)
          .refreshWeather(forceRefresh: true);
      final refreshed = await weatherContainer.read(weatherSyncProvider.future);
      expect(refreshed.condition.temperatureCelsius, 32.0);
      expect(refreshed.heatSpikeDetected, isTrue);
      expect(
        weatherContainer.read(currentClimateProvider).temperatureCelsius,
        32.0,
      );
      expect(refreshed.previousCondition?.temperatureCelsius, 26.0);
    });

    test('weatherSyncProvider uses temperate 21C offlineFallback on initial offline startup',
        () async {
      final offlineClient = MockClient((_) async {
        throw http.ClientException('Offline');
      });

      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final offlineContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(
            AsyncData(UserProfileRepository(db)),
          ),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(client: offlineClient),
          ),
        ],
      );
      addTearDown(() async {
        offlineContainer.dispose();
        await weatherDb.close();
      });

      final syncState = await offlineContainer.read(weatherSyncProvider.future);
      expect(syncState.source, WeatherDataSource.offlineFallback);
      expect(syncState.condition.temperatureCelsius, 21.0);
      expect(
        offlineContainer.read(currentClimateProvider).temperatureCelsius,
        21.0,
      );
    });

    test('does not raise false heatSpikeDetected on hot launch, offline->live recovery, or city switch',
        () async {
      // 1) Hot initial startup (36°C vs 31°C initialPlaceholder = +5°C) must NOT trigger spike
      final mockClient = MockClient((req) async {
        final lat = req.url.queryParameters['latitude'] ?? '';
        final isPhoenix = lat.startsWith('33.');
        final isCold = lat.startsWith('47.');
        final temp = isPhoenix ? 38.0 : (isCold ? 15.0 : 36.0);
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': temp,
              'relative_humidity_2m': 40,
              'apparent_temperature': temp + 1.0,
            }
          }),
          200,
        );
      });

      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final profileRepo = UserProfileRepository(db);
      final hotContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(AsyncData(profileRepo)),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(client: mockClient),
          ),
        ],
      );
      addTearDown(() async {
        hotContainer.dispose();
        await weatherDb.close();
      });

      final initial = await hotContainer.read(weatherSyncProvider.future);
      expect(initial.condition.temperatureCelsius, 36.0);
      expect(initial.heatSpikeDetected, isFalse);

      // 2) City switch from cold (Seattle 15°C) to hot (Phoenix 38°C) must NOT trigger spike
      await profileRepo.updateLocation('Seattle', 47.61, -122.33);
      hotContainer.invalidate(userProfileProvider);
      final seattleState = await hotContainer.read(weatherSyncProvider.future);
      expect(seattleState.condition.temperatureCelsius, 15.0);
      expect(seattleState.heatSpikeDetected, isFalse);

      await profileRepo.updateLocation('Phoenix', 33.45, -112.07);
      hotContainer.invalidate(userProfileProvider);
      final phoenixState = await hotContainer.read(weatherSyncProvider.future);
      expect(phoenixState.condition.temperatureCelsius, 38.0);
      expect(phoenixState.heatSpikeDetected, isFalse);

      // 3) Offline fallback (21°C) -> Live hot weather (36°C) must NOT trigger spike
      bool isOffline = true;
      final recoveryClient = MockClient((_) async {
        if (isOffline) throw http.ClientException('Offline');
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 36.0,
              'relative_humidity_2m': 35,
              'apparent_temperature': 38.0,
            }
          }),
          200,
        );
      });
      final recoveryDb = AppDatabase.inMemory();
      final rDb = await recoveryDb.database;
      final recoveryContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(rDb)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(rDb)),
          ),
          userProfileRepositoryProvider.overrideWithValue(
            AsyncData(UserProfileRepository(rDb)),
          ),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(client: recoveryClient),
          ),
        ],
      );
      addTearDown(() async {
        recoveryContainer.dispose();
        await recoveryDb.close();
      });

      final offline = await recoveryContainer.read(weatherSyncProvider.future);
      expect(offline.source, WeatherDataSource.offlineFallback);
      expect(offline.condition.temperatureCelsius, 21.0);
      expect(offline.heatSpikeDetected, isFalse);

      isOffline = false;
      final recovered = await recoveryContainer
          .read(weatherSyncProvider.notifier)
          .refreshWeather(forceRefresh: true);
      expect(recovered!.source, WeatherDataSource.liveApi);
      expect(recovered.condition.temperatureCelsius, 36.0);
      expect(recovered.heatSpikeDetected, isFalse);
    });

    test('pacingScheduleProvider syncs NotificationService, respects pause, and exposes osSchedulingSupported',
        () async {
      final spyNotifications = _SpyNotificationService()..supportsScheduled = false;
      final db = await appDatabase.database;
      final pacingContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(AsyncData(intakeLogRepository)),
          userProfileRepositoryProvider.overrideWithValue(AsyncData(userProfileRepository)),
          currentClimateProvider.overrideWith(() => TestClimateNotifier()),
          notificationServiceProvider.overrideWithValue(spyNotifications),
        ],
      );
      addTearDown(pacingContainer.dispose);

      final initialPacing = await pacingContainer.read(pacingScheduleProvider.future);
      expect(initialPacing.osSchedulingSupported, isFalse);
      expect(spyNotifications.calls, hasLength(1));
      expect(spyNotifications.calls.last.enabled, isTrue);

      await userProfileRepository.setMindfulPacing(false);
      pacingContainer.invalidate(userProfileProvider);
      await pacingContainer.read(pacingScheduleProvider.future);
      expect(spyNotifications.calls.length, greaterThanOrEqualTo(2));
      expect(spyNotifications.calls.last.enabled, isFalse);
      expect(spyNotifications.calls.last.slotCount, 0);
    });

    test('refreshIfNewDay triggers reload when crossing midnight & custom timestamp works',
        () async {
      final customTime = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        8,
        15,
      );
      final notifier = container.read(hydrationNotifierProvider.notifier);
      await notifier.logHydration(
        amountMl: 300,
        type: BeverageType.water,
        timestamp: customTime,
      );

      final before = await container.read(hydrationNotifierProvider.future);
      expect(before.recentLogs.single.timestamp.hour, 8);
      expect(before.recentLogs.single.timestamp.minute, 15);

      // Same day check is a fast no-op
      await notifier.refreshIfNewDay(now: DateTime.now());
      // Simulated next day triggers rebuild
      await notifier.refreshIfNewDay(
        now: DateTime.now().add(const Duration(days: 1)),
      );
      final after = await container.read(hydrationNotifierProvider.future);
      expect(after.currentVolumeMl, 300);
    });
  });

  group('LocationBootstrapNotifier (GPS Permission + Public IP Fallback)', () {
    test('requests GPS on auto startup and uses GPS coordinates for weather when granted',
        () async {
      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final profileRepo = UserProfileRepository(db);
      final gpsSpy = _RecordingGpsService(
        (_) async => (latitude: 47.6062, longitude: -122.3321),
      );
      final ipSpy = _StubIpLocationService(
        () async => throw Exception('IP should not be called when GPS succeeds'),
      );

      String? requestedLat;
      final weatherClient = WeatherApiClient(
        client: MockClient((req) async {
          requestedLat = req.url.queryParameters['latitude'];
          return http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': 16.0,
                'relative_humidity_2m': 78,
                'apparent_temperature': 15.0,
              }
            }),
            200,
          );
        }),
      );

      final bootContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(AsyncData(profileRepo)),
          locationServiceProvider.overrideWithValue(gpsSpy),
          ipLocationServiceProvider.overrideWithValue(ipSpy),
          weatherApiClientProvider.overrideWithValue(weatherClient),
        ],
      );
      addTearDown(() async {
        bootContainer.dispose();
        await weatherDb.close();
      });

      final state = await bootContainer
          .read(locationBootstrapProvider.notifier)
          .resolveOnStartup();
      expect(state.status, StartupLocationStatus.resolvedGps);
      expect(gpsSpy.requestPermissionArgs, [true]);
      expect(ipSpy.calls, 0);

      final saved = await profileRepo.getUserProfile();
      expect(saved.cityName, 'GPS (47.61, -122.33)');
      expect(saved.locationMode, LocationMode.gps);
      expect(requestedLat, '47.61');
      expect(
        bootContainer.read(currentClimateProvider).temperatureCelsius,
        16.0,
      );
    });

    test('falls back to public IP when user denies GPS permission and fetches IP weather',
        () async {
      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final profileRepo = UserProfileRepository(db);
      final gpsSpy = _RecordingGpsService((_) async {
        throw const LocationLookupException(
          'Denied by user',
          reason: LocationFailureReason.permissionDenied,
        );
      });
      final ipSpy = _StubIpLocationService(
        () async => const IpLocationResult(
          latitude: 12.9716,
          longitude: 77.5946,
          city: 'Bengaluru',
          region: 'Karnataka',
          country: 'India',
        ),
      );

      String? fetchedLat;
      String? fetchedLon;
      final weatherClient = WeatherApiClient(
        client: MockClient((req) async {
          fetchedLat = req.url.queryParameters['latitude'];
          fetchedLon = req.url.queryParameters['longitude'];
          return http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': 32.0,
                'relative_humidity_2m': 48,
                'apparent_temperature': 34.0,
              }
            }),
            200,
          );
        }),
      );

      final bootContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(AsyncData(profileRepo)),
          locationServiceProvider.overrideWithValue(gpsSpy),
          ipLocationServiceProvider.overrideWithValue(ipSpy),
          weatherApiClientProvider.overrideWithValue(weatherClient),
        ],
      );
      addTearDown(() async {
        bootContainer.dispose();
        await weatherDb.close();
      });

      final state = await bootContainer
          .read(locationBootstrapProvider.notifier)
          .resolveOnStartup();
      expect(state.status, StartupLocationStatus.resolvedIp);
      expect(gpsSpy.requestPermissionArgs, [true]);
      expect(ipSpy.calls, 1);

      final saved = await profileRepo.getUserProfile();
      expect(saved.cityName, 'Bengaluru (IP)');
      expect(saved.locationMode, LocationMode.ip);
      expect(saved.latitude, 12.97);
      expect(saved.longitude, 77.59);
      expect(fetchedLat, '12.97');
      expect(fetchedLon, '77.59');

      expect(
        bootContainer.read(currentClimateProvider).temperatureCelsius,
        32.0,
      );
      // Verify HydrationNotifier updated daily target for 32C Bengaluru weather (2450 * 1.30 = 3185)
      final hydration = await bootContainer.read(hydrationNotifierProvider.future);
      expect(hydration.targetVolumeMl, 3185);
    });

    test('skips GPS prompt when manual city selected and avoids re-prompting on resume retry',
        () async {
      final weatherDb = AppDatabase.inMemory();
      final db = await weatherDb.database;
      final profileRepo = UserProfileRepository(db);
      await profileRepo.updateLocation('Kyoto', 35.01, 135.77);

      final gpsSpy = _RecordingGpsService((_) async => (latitude: 0.0, longitude: 0.0));
      final ipSpy = _StubIpLocationService(
        () async => const IpLocationResult(
          latitude: 19.08,
          longitude: 72.88,
          city: 'Mumbai',
        ),
      );

      final manualContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(db)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(db)),
          ),
          userProfileRepositoryProvider.overrideWithValue(AsyncData(profileRepo)),
          locationServiceProvider.overrideWithValue(gpsSpy),
          ipLocationServiceProvider.overrideWithValue(ipSpy),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(client: MockClient((_) async => throw Exception('offline'))),
          ),
        ],
      );
      addTearDown(() async {
        manualContainer.dispose();
        await weatherDb.close();
      });

      final manualState = await manualContainer
          .read(locationBootstrapProvider.notifier)
          .resolveOnStartup();
      expect(manualState.status, StartupLocationStatus.manualSkipped);
      expect(gpsSpy.requestPermissionArgs, isEmpty);
      expect(ipSpy.calls, 0);

      // Simulate offline startup failure followed by network recovery on resume
      final recoveryDb = AppDatabase.inMemory();
      final rDb = await recoveryDb.database;
      final recoveryProfileRepo = UserProfileRepository(rDb);
      bool online = false;
      final retryGps = _RecordingGpsService((_) async {
        throw const LocationLookupException(
          'Denied',
          reason: LocationFailureReason.permissionDenied,
        );
      });
      final retryIp = _StubIpLocationService(() async {
        if (!online) throw const LocationLookupException('Offline');
        return const IpLocationResult(
          latitude: 19.076,
          longitude: 72.877,
          city: 'Mumbai',
        );
      });
      final retryContainer = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(AsyncData(rDb)),
          intakeLogRepositoryProvider.overrideWithValue(
            AsyncData(IntakeLogRepository(rDb)),
          ),
          userProfileRepositoryProvider
              .overrideWithValue(AsyncData(recoveryProfileRepo)),
          locationServiceProvider.overrideWithValue(retryGps),
          ipLocationServiceProvider.overrideWithValue(retryIp),
          weatherApiClientProvider.overrideWithValue(
            WeatherApiClient(
              client: MockClient(
                (_) async => http.Response(
                  jsonEncode({
                    'current': {
                      'temperature_2m': 30.0,
                      'relative_humidity_2m': 60,
                      'apparent_temperature': 32.0,
                    }
                  }),
                  200,
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(() async {
        retryContainer.dispose();
        await recoveryDb.close();
      });

      final firstAttempt = await retryContainer
          .read(locationBootstrapProvider.notifier)
          .resolveOnStartup();
      expect(firstAttempt.status, StartupLocationStatus.failed);
      expect(retryGps.requestPermissionArgs, [true]);

      online = true;
      final resumedState = await retryContainer
          .read(locationBootstrapProvider.notifier)
          .retryIfFailedOnResume();
      expect(resumedState.status, StartupLocationStatus.resolvedIp);
      // Should NOT double-prompt GPS permission in the same session!
      expect(retryGps.requestPermissionArgs, [true, false]);
      expect(
        (await recoveryProfileRepo.getUserProfile()).cityName,
        'Mumbai (IP)',
      );
    });
  });
}
