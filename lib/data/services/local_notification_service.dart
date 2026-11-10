import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../../domain/services/notification_scheduler.dart';

enum TestChimeStatus {
  sent,
  permissionDenied,
  unavailable,
}

abstract class NotificationService {
  bool get supportsScheduledNotifications => true;
  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> syncPacingSchedule({
    required List<HydrationChimeSlot> slots,
    required bool enabled,
  });
  Future<TestChimeStatus> showTestChime();
  Future<void> cancelAll();
}

class LocalNotificationService implements NotificationService {
  static const int _baseChimeId = 1000;
  static const int _maxManagedSlots = 12;
  static const String _channelId = 'hydrochime_pacing';
  static const String _channelName = 'Mindful Hydration Chimes';
  static const String _channelDesc =
      'Gentle spaced reminders to stay evenly hydrated during waking hours.';

  static bool _tzInitialized = false;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  bool get supportsScheduledNotifications =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.linux;

  void _ensureTimezonesInitialized() {
    if (_tzInitialized) return;
    tz_data.initializeTimeZones();
    _tzInitialized = true;
  }

  Future<void> _configureLocalTimeZone() async {
    _ensureTimezonesInitialized();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } on MissingPluginException {
      // Headless tests or unsupported hosts fall back cleanly to default tz.local.
    } catch (_) {
      // Unknown timezone identifier; fall back cleanly.
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open HydroChime'),
      windows: WindowsInitializationSettings(
        appName: 'HydroChime',
        appUserModelId: 'com.hydrochime.hydrochime',
        guid: 'a8d4c3e2-71c5-4b1e-9c0d-42a9e3b81201',
      ),
    );

    try {
      await _plugin.initialize(settings: settings);
      await _configureLocalTimeZone();
      _initialized = true;
    } on MissingPluginException {
      _initialized = false;
    } catch (_) {
      _initialized = false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    await initialize();
    if (!_initialized) return false;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return (await androidPlugin?.requestNotificationsPermission()) ?? true;
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return (await iosPlugin?.requestPermissions(
              alert: true,
              badge: false,
              sound: true,
            )) ??
            true;
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
        final macPlugin = _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        return (await macPlugin?.requestPermissions(
              alert: true,
              badge: false,
              sound: true,
            )) ??
            true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  NotificationDetails _buildDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
      ),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
  }

  @override
  Future<void> cancelAll() async {
    await initialize();
    if (!_initialized) return;
    try {
      for (int i = 0; i < _maxManagedSlots; i++) {
        await _plugin.cancel(id: _baseChimeId + i);
      }
    } catch (_) {}
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      try {
        await _plugin.cancelAll();
      } catch (_) {}
    } else if (!kIsWeb) {
      try {
        await _plugin.cancelAllPendingNotifications();
      } on UnimplementedError {
        // Desktop implementations without pending-notification cancellation ignore.
      } catch (_) {}
    }
  }

  @override
  Future<void> syncPacingSchedule({
    required List<HydrationChimeSlot> slots,
    required bool enabled,
  }) async {
    await initialize();
    if (!_initialized) return;

    await cancelAll();
    if (!enabled || slots.isEmpty || !supportsScheduledNotifications) return;

    final now = DateTime.now();
    final details = _buildDetails();

    final count = slots.length < _maxManagedSlots ? slots.length : _maxManagedSlots;
    for (int i = 0; i < count; i++) {
      final slot = slots[i];
      if (!slot.scheduledTime.isAfter(now)) continue;

      try {
        final tzTime = tz.TZDateTime.from(slot.scheduledTime, tz.local);
        await _plugin.zonedSchedule(
          id: _baseChimeId + i,
          title: slot.title,
          body: slot.body,
          scheduledDate: tzTime,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'pacing_chime_${slot.recommendedVolumeMl}',
        );
      } on UnimplementedError {
        // Platforms without OS background scheduler (e.g. Linux) skip safely.
        break;
      } catch (_) {
        // Ignore platform scheduling edge errors without crashing UI updates.
      }
    }
  }

  @override
  Future<TestChimeStatus> showTestChime() async {
    await initialize();
    if (!_initialized) return TestChimeStatus.unavailable;

    final granted = await requestPermissions();
    if (!granted) return TestChimeStatus.permissionDenied;

    try {
      await _plugin.show(
        id: _baseChimeId + _maxManagedSlots + 1,
        title: 'HydroChime • Mindful Hydration',
        body: 'Notifications are calibrated and active for your waking window.',
        notificationDetails: _buildDetails(),
        payload: 'test_chime',
      );
      return TestChimeStatus.sent;
    } catch (_) {
      return TestChimeStatus.unavailable;
    }
  }
}
