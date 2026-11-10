class UserProfile {
  static const Object _unset = Object();

  final double weightKg;
  final int? customBaselineMl;
  final int dailyActivityMinutes;
  final int activeWindowStartHour; // e.g. 7 (7:00 AM)
  final int activeWindowEndHour; // e.g. 22 (10:00 PM)
  final bool weatherAdaptationEnabled;
  final bool mindfulPacingEnabled;
  final bool isDarkMode;
  final String cityName;
  final double latitude;
  final double longitude;

  const UserProfile({
    required this.weightKg,
    this.customBaselineMl,
    this.dailyActivityMinutes = 0,
    required this.activeWindowStartHour,
    required this.activeWindowEndHour,
    required this.weatherAdaptationEnabled,
    required this.mindfulPacingEnabled,
    this.isDarkMode = true,
    this.cityName = 'Austin',
    this.latitude = 30.27,
    this.longitude = -97.74,
  });

  int get effectiveBaselineMl => customBaselineMl ?? (weightKg * 35).round();

  UserProfile copyWith({
    double? weightKg,
    Object? customBaselineMl = _unset,
    int? dailyActivityMinutes,
    int? activeWindowStartHour,
    int? activeWindowEndHour,
    bool? weatherAdaptationEnabled,
    bool? mindfulPacingEnabled,
    bool? isDarkMode,
    String? cityName,
    double? latitude,
    double? longitude,
  }) {
    return UserProfile(
      weightKg: weightKg ?? this.weightKg,
      customBaselineMl: identical(customBaselineMl, _unset)
          ? this.customBaselineMl
          : customBaselineMl as int?,
      dailyActivityMinutes: dailyActivityMinutes ?? this.dailyActivityMinutes,
      activeWindowStartHour:
          activeWindowStartHour ?? this.activeWindowStartHour,
      activeWindowEndHour: activeWindowEndHour ?? this.activeWindowEndHour,
      weatherAdaptationEnabled:
          weatherAdaptationEnabled ?? this.weatherAdaptationEnabled,
      mindfulPacingEnabled: mindfulPacingEnabled ?? this.mindfulPacingEnabled,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      cityName: cityName ?? this.cityName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'weight_kg': weightKg,
      'custom_baseline_ml': customBaselineMl,
      'daily_activity_minutes': dailyActivityMinutes,
      'active_window_start_hour': activeWindowStartHour,
      'active_window_end_hour': activeWindowEndHour,
      'weather_adaptation_enabled': weatherAdaptationEnabled ? 1 : 0,
      'mindful_pacing_enabled': mindfulPacingEnabled ? 1 : 0,
      'is_dark_mode': isDarkMode ? 1 : 0,
      'city_name': cityName,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      weightKg: (map['weight_kg'] as num).toDouble(),
      customBaselineMl: map['custom_baseline_ml'] as int?,
      dailyActivityMinutes: (map['daily_activity_minutes'] as int?) ?? 0,
      activeWindowStartHour: map['active_window_start_hour'] as int,
      activeWindowEndHour: map['active_window_end_hour'] as int,
      weatherAdaptationEnabled: (map['weather_adaptation_enabled'] as int) == 1,
      mindfulPacingEnabled: (map['mindful_pacing_enabled'] as int) == 1,
      isDarkMode: ((map['is_dark_mode'] as int?) ?? 1) == 1,
      cityName: (map['city_name'] as String?) ?? 'Austin',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 30.27,
      longitude: (map['longitude'] as num?)?.toDouble() ?? -97.74,
    );
  }

  static const defaultProfile = UserProfile(
    weightKg: 70.0,
    customBaselineMl: null,
    dailyActivityMinutes: 0,
    activeWindowStartHour: 7,
    activeWindowEndHour: 22,
    weatherAdaptationEnabled: true,
    mindfulPacingEnabled: true,
    isDarkMode: true,
    cityName: 'Austin',
    latitude: 30.27,
    longitude: -97.74,
  );
}
