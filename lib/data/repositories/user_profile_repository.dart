import 'package:sqflite/sqflite.dart';
import '../../domain/models/user_profile.dart';

class UserProfileRepository {
  final Database _db;

  UserProfileRepository(this._db);

  Future<UserProfile> getUserProfile() async {
    final maps = await _db.query('user_profile', where: 'id = ?', whereArgs: [1]);
    if (maps.isEmpty) {
      return UserProfile.defaultProfile;
    }
    return UserProfile.fromMap(maps.first);
  }

  Future<void> updateProfile(UserProfile profile) async {
    await _db.insert(
      'user_profile',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateWeight(double weightKg) async {
    final profile = await getUserProfile();
    await updateProfile(profile.copyWith(weightKg: weightKg));
  }

  Future<void> updateCustomBaseline(int? baselineMl) async {
    final profile = await getUserProfile();
    await updateProfile(profile.copyWith(customBaselineMl: baselineMl));
  }

  Future<void> updateDailyActivityMinutes(int minutes) async {
    final profile = await getUserProfile();
    await updateProfile(profile.copyWith(dailyActivityMinutes: minutes));
  }

  Future<void> setWeatherAdaptation(bool enabled) async {
    final profile = await getUserProfile();
    await updateProfile(profile.copyWith(weatherAdaptationEnabled: enabled));
  }

  Future<void> setMindfulPacing(bool enabled) async {
    final profile = await getUserProfile();
    await updateProfile(profile.copyWith(mindfulPacingEnabled: enabled));
  }

  Future<void> updateActiveWindow(int startHour, int endHour) async {
    final profile = await getUserProfile();
    await updateProfile(
      profile.copyWith(
        activeWindowStartHour: startHour,
        activeWindowEndHour: endHour,
      ),
    );
  }

  Future<void> setDarkMode(bool isDark) async {
    final profile = await getUserProfile();
    await updateProfile(profile.copyWith(isDarkMode: isDark));
  }

  Future<void> updateLocation(
    String cityName,
    double latitude,
    double longitude, {
    LocationMode locationMode = LocationMode.manual,
  }) async {
    final profile = await getUserProfile();
    await updateProfile(
      profile.copyWith(
        cityName: cityName,
        latitude: latitude,
        longitude: longitude,
        locationMode: locationMode,
      ),
    );
  }
}
