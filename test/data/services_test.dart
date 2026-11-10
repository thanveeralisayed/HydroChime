import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/weather_repository.dart';
import 'package:hydrochime/data/services/ip_location_service.dart';
import 'package:hydrochime/data/services/local_notification_service.dart';
import 'package:hydrochime/data/services/location_service.dart';
import 'package:hydrochime/data/services/vault_transfer_service.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
import 'package:hydrochime/domain/models/user_profile.dart';
import 'package:hydrochime/domain/services/notification_scheduler.dart';
import 'package:mocktail/mocktail.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class _MockNotificationsPlugin extends Mock
    implements FlutterLocalNotificationsPlugin {}

class _MockAndroidPlugin extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

class _StubGpsService implements PermissionAwareLocationService {
  final Future<({double latitude, double longitude})> Function(
    bool requestPermission,
  ) handler;

  _StubGpsService(this.handler);

  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates({
    bool requestPermission = true,
  }) =>
      handler(requestPermission);
}

class _StubIpService implements IpLocationService {
  final Future<IpLocationResult> Function() handler;
  int calls = 0;

  _StubIpService(this.handler);

  @override
  Future<IpLocationResult> lookupPublicIpLocation() {
    calls++;
    return handler();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tz_data.initializeTimeZones();
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime.now(tz.UTC));
    registerFallbackValue(AndroidScheduleMode.inexactAllowWhileIdle);
  });

  group('WeatherApiClient Timeout Protection', () {
    test('fetchCurrentWeather & searchCities throw TimeoutException on stalled requests and WeatherRepository falls back cleanly',
        () async {
      final hangingClient = MockClient((_) {
        return Completer<http.Response>().future;
      });
      final apiClient = WeatherApiClient(
        client: hangingClient,
        timeout: const Duration(milliseconds: 40),
      );

      await expectLater(
        () => apiClient.fetchCurrentWeather(latitude: 30.27, longitude: -97.74),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        () => apiClient.searchCities('Austin'),
        throwsA(isA<TimeoutException>()),
      );

      final appDb = AppDatabase.inMemory();
      final db = await appDb.database;
      addTearDown(appDb.close);

      final repo = WeatherRepository(db: db, apiClient: apiClient);
      final result = await repo.getOrFetchWeatherWithMeta(
        latitude: 30.27,
        longitude: -97.74,
      );
      expect(result.source, WeatherDataSource.offlineFallback);
      expect(result.condition.temperatureCelsius, 21.0);
    });
  });

  group('PlatformVaultTransferService Share & Platform Guards', () {
    test('forwards sharePositionOrigin and throws VaultTransferUnsupportedException on Linux or UnimplementedError',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('hydrochime_share_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      ShareParams? capturedParams;
      const origin = Rect.fromLTWH(12, 34, 80, 40);

      final service = PlatformVaultTransferService(
        isLinuxOverride: false,
        tempDirectoryProvider: () async => tempDir,
        shareInvoker: (params) async {
          capturedParams = params;
          return const ShareResult('shared', ShareResultStatus.success);
        },
      );

      final ok = await service.shareTextAsFile(
        content: 'id,volume\n1,250\n',
        fileName: 'history.csv',
        mimeType: 'text/csv',
        subject: 'History',
        sharePositionOrigin: origin,
      );
      expect(ok, isTrue);
      expect(capturedParams?.sharePositionOrigin, origin);
      expect(capturedParams?.files?.single.name, 'history.csv');

      final linuxService = PlatformVaultTransferService(
        isLinuxOverride: true,
        tempDirectoryProvider: () async => tempDir,
      );
      await expectLater(
        () => linuxService.shareTextAsFile(
          content: '{}',
          fileName: 'vault.json',
          mimeType: 'application/json',
          subject: 'Vault',
        ),
        throwsA(isA<VaultTransferUnsupportedException>()),
      );

      final unsupportedService = PlatformVaultTransferService(
        isLinuxOverride: false,
        tempDirectoryProvider: () async => tempDir,
        shareInvoker: (_) async => throw UnimplementedError(),
      );
      await expectLater(
        () => unsupportedService.shareTextAsFile(
          content: '{}',
          fileName: 'vault.json',
          mimeType: 'application/json',
          subject: 'Vault',
        ),
        throwsA(isA<VaultTransferUnsupportedException>()),
      );
    });
  });

  group('LocalNotificationService Status & Platform Scheduling', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('supportsScheduledNotifications is false on Linux and true on Android/Windows/iOS',
        () async {
      final service = LocalNotificationService();

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(service.supportsScheduledNotifications, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(service.supportsScheduledNotifications, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(service.supportsScheduledNotifications, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(service.supportsScheduledNotifications, isTrue);
    });

    test('showTestChime returns unavailable when plugin initialization fails cleanly',
        () async {
      final mockPlugin = _MockNotificationsPlugin();
      when(() => mockPlugin.initialize(settings: any(named: 'settings')))
          .thenThrow(MissingPluginException());

      final service = LocalNotificationService(plugin: mockPlugin);
      final status = await service.showTestChime();
      expect(status, TestChimeStatus.unavailable);
    });

    test('showTestChime returns permissionDenied when permission is declined, and sent when granted',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final mockPlugin = _MockNotificationsPlugin();
      final mockAndroid = _MockAndroidPlugin();

      when(() => mockPlugin.initialize(settings: any(named: 'settings')))
          .thenAnswer((_) async => true);
      when(() => mockPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()).thenReturn(mockAndroid);

      // 1) Permission denied
      when(() => mockAndroid.requestNotificationsPermission())
          .thenAnswer((_) async => false);
      final service = LocalNotificationService(plugin: mockPlugin);
      expect(await service.showTestChime(), TestChimeStatus.permissionDenied);

      // 2) Permission granted + show succeeds -> sent
      when(() => mockAndroid.requestNotificationsPermission())
          .thenAnswer((_) async => true);
      when(
        () => mockPlugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});
      expect(await service.showTestChime(), TestChimeStatus.sent);

      // 3) Permission granted + show throws -> unavailable
      when(
        () => mockPlugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenThrow(Exception('notification delivery error'));
      expect(await service.showTestChime(), TestChimeStatus.unavailable);
    });

    test('syncPacingSchedule skips scheduling on Linux while canceling safely',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;

      final mockPlugin = _MockNotificationsPlugin();
      when(() => mockPlugin.initialize(settings: any(named: 'settings')))
          .thenAnswer((_) async => true);
      when(() => mockPlugin.cancel(id: any(named: 'id')))
          .thenAnswer((_) async {});
      when(() => mockPlugin.cancelAllPendingNotifications())
          .thenAnswer((_) async {});

      final service = LocalNotificationService(plugin: mockPlugin);
      await service.syncPacingSchedule(
        slots: [
          HydrationChimeSlot(
            scheduledTime: DateTime.now().add(const Duration(hours: 1)),
            recommendedVolumeMl: 250,
            title: 'Hydrate',
            body: 'Sip 250 ml',
          ),
        ],
        enabled: true,
      );

      verifyNever(
        () => mockPlugin.zonedSchedule(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          payload: any(named: 'payload'),
        ),
      );
    });

    test('cancelAll calls plugin.cancelAll on Windows cleanly', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final mockPlugin = _MockNotificationsPlugin();
      when(() => mockPlugin.initialize(settings: any(named: 'settings')))
          .thenAnswer((_) async => true);
      when(() => mockPlugin.cancel(id: any(named: 'id')))
          .thenAnswer((_) async {});
      when(() => mockPlugin.cancelAll()).thenAnswer((_) async {});

      final service = LocalNotificationService(plugin: mockPlugin);
      await service.cancelAll();

      verify(() => mockPlugin.cancelAll()).called(1);
      verifyNever(() => mockPlugin.cancelAllPendingNotifications());
    });
  });

  group('HttpIpLocationService & LocationResolver Fallback (TDD)', () {
    test('HttpIpLocationService parses ipwho.is and falls back to geojs and ipapi.co',
        () async {
      final primaryClient = MockClient((req) async {
        expect(req.url.host, 'ipwho.is');
        return http.Response(
          jsonEncode({
            'success': true,
            'city': 'Bengaluru',
            'region': 'Karnataka',
            'country': 'India',
            'latitude': 12.9716,
            'longitude': 77.5946,
          }),
          200,
        );
      });
      final primary = await HttpIpLocationService(client: primaryClient)
          .lookupPublicIpLocation();
      expect(primary.city, 'Bengaluru');
      expect(primary.latitude, closeTo(12.9716, 0.0001));
      expect(
        primary.displayLabel(quantizedLat: 12.97, quantizedLon: 77.59),
        'Bengaluru (IP)',
      );

      // Fail ipwho.is (rate limit/error), succeed on geojs string coordinates
      final fallbackClient = MockClient((req) async {
        if (req.url.host == 'ipwho.is') {
          return http.Response(jsonEncode({'success': false}), 200);
        }
        if (req.url.host == 'get.geojs.io') {
          return http.Response(
            jsonEncode({
              'city': 'Munich',
              'region': 'Bavaria',
              'country': 'Germany',
              'latitude': '48.1351',
              'longitude': '11.5820',
            }),
            200,
          );
        }
        return http.Response('{}', 500);
      });
      final geoJsResult = await HttpIpLocationService(client: fallbackClient)
          .lookupPublicIpLocation();
      expect(geoJsResult.city, 'Munich');
      expect(geoJsResult.latitude, closeTo(48.1351, 0.0001));
      expect(geoJsResult.longitude, closeTo(11.582, 0.0001));

      // Fail both ipwho.is & geojs (nil coords), succeed on ipapi.co
      final thirdClient = MockClient((req) async {
        if (req.url.host == 'ipapi.co') {
          return http.Response(
            jsonEncode({
              'city': '',
              'region': 'Ontario',
              'country_name': 'Canada',
              'latitude': 43.6532,
              'longitude': -79.3832,
            }),
            200,
          );
        }
        if (req.url.host == 'get.geojs.io') {
          return http.Response(
            jsonEncode({'latitude': 'nil', 'longitude': 'nil'}),
            200,
          );
        }
        return http.Response('err', 503);
      });
      final ipApiResult = await HttpIpLocationService(client: thirdClient)
          .lookupPublicIpLocation();
      expect(
        ipApiResult.displayLabel(quantizedLat: 43.65, quantizedLon: -79.38),
        'Ontario (IP)',
      );

      // All failing -> throws LocationLookupException cleanly
      final failingClient = MockClient((_) async => http.Response('down', 503));
      await expectLater(
        () => HttpIpLocationService(client: failingClient)
            .lookupPublicIpLocation(),
        throwsA(isA<LocationLookupException>()),
      );
    });

    test('LocationResolver prefers GPS when granted and falls back to public IP when GPS denied or off',
        () async {
      bool? requestedFlag;
      final ipStub = _StubIpService(() async {
        return const IpLocationResult(
          latitude: 19.0760,
          longitude: 72.8777,
          city: 'Mumbai',
          country: 'India',
        );
      });

      // 1) GPS granted -> uses quantized GPS without calling IP service
      final gpsGrantedResolver = LocationResolver(
        gpsService: _StubGpsService((reqPerm) async {
          requestedFlag = reqPerm;
          return (latitude: 37.42199, longitude: -122.08405);
        }),
        ipLocationService: ipStub,
      );
      final gpsLoc =
          await gpsGrantedResolver.resolveLocation(requestGpsPermission: true);
      expect(requestedFlag, isTrue);
      expect(gpsLoc.source, ResolvedLocationSource.gps);
      expect(gpsLoc.locationMode, LocationMode.gps);
      expect(gpsLoc.name, 'GPS (37.42, -122.08)');
      expect(ipStub.calls, 0);

      // 2) GPS permission denied -> falls back seamlessly to Public IP
      final deniedResolver = LocationResolver(
        gpsService: _StubGpsService((_) async {
          throw const LocationLookupException(
            'Permission denied',
            reason: LocationFailureReason.permissionDenied,
          );
        }),
        ipLocationService: ipStub,
      );
      final ipLoc =
          await deniedResolver.resolveLocation(requestGpsPermission: true);
      expect(ipStub.calls, 1);
      expect(ipLoc.source, ResolvedLocationSource.ip);
      expect(ipLoc.locationMode, LocationMode.ip);
      expect(ipLoc.name, 'Mumbai (IP)');
      expect(ipLoc.latitude, 19.08);
      expect(ipLoc.longitude, 72.88);
      expect(ipLoc.gpsFailureReason, LocationFailureReason.permissionDenied);

      // 3) Both GPS and IP fail -> throws informative LocationLookupException
      final offlineResolver = LocationResolver(
        gpsService: _StubGpsService((_) async {
          throw const LocationLookupException(
            'Denied',
            reason: LocationFailureReason.permissionDenied,
          );
        }),
        ipLocationService: _StubIpService(() async {
          throw const LocationLookupException('No internet');
        }),
      );
      await expectLater(
        () => offlineResolver.resolveLocation(requestGpsPermission: true),
        throwsA(
          isA<LocationLookupException>().having(
            (e) => e.message,
            'message',
            contains('GPS permission denied and public IP lookup failed'),
          ),
        ),
      );
    });
  });
}

