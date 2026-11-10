import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hydrochime/data/database/app_database.dart';
import 'package:hydrochime/data/repositories/weather_repository.dart';
import 'package:hydrochime/data/services/local_notification_service.dart';
import 'package:hydrochime/data/services/vault_transfer_service.dart';
import 'package:hydrochime/data/services/weather_api_client.dart';
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
}

