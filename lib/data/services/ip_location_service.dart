import 'dart:convert';
import 'package:http/http.dart' as http;

enum LocationFailureReason {
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  unavailable,
}

class LocationLookupException implements Exception {
  final String message;
  final LocationFailureReason reason;

  const LocationLookupException(
    this.message, {
    this.reason = LocationFailureReason.unavailable,
  });

  @override
  String toString() => message;
}

class IpLocationResult {
  final double latitude;
  final double longitude;
  final String? city;
  final String? region;
  final String? country;

  const IpLocationResult({
    required this.latitude,
    required this.longitude,
    this.city,
    this.region,
    this.country,
  });

  String displayLabel({
    required double quantizedLat,
    required double quantizedLon,
  }) {
    final cleanCity = city?.trim();
    if (cleanCity != null && cleanCity.isNotEmpty) {
      return '$cleanCity (IP)';
    }
    final cleanRegion = region?.trim();
    if (cleanRegion != null && cleanRegion.isNotEmpty) {
      return '$cleanRegion (IP)';
    }
    final cleanCountry = country?.trim();
    if (cleanCountry != null && cleanCountry.isNotEmpty) {
      return '$cleanCountry (IP)';
    }
    return 'IP (${quantizedLat.toStringAsFixed(2)}, ${quantizedLon.toStringAsFixed(2)})';
  }
}

abstract class IpLocationService {
  Future<IpLocationResult> lookupPublicIpLocation();
}

class HttpIpLocationService implements IpLocationService {
  final http.Client _client;
  final Duration timeout;

  HttpIpLocationService({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client();

  static const Map<String, String> _requestHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'HydroChime/1.0',
  };

  @override
  Future<IpLocationResult> lookupPublicIpLocation() async {
    final endpoints = <Future<IpLocationResult?> Function()>[
      _fetchFromIpWhoIs,
      _fetchFromGeoJs,
      _fetchFromIpApiCo,
    ];

    for (final fetcher in endpoints) {
      try {
        final result = await fetcher();
        if (result != null) return result;
      } catch (_) {
        // Try next HTTPS geolocation provider.
      }
    }

    throw const LocationLookupException(
      'Unable to determine approximate location from public IP.',
      reason: LocationFailureReason.unavailable,
    );
  }

  Future<IpLocationResult?> _fetchFromIpWhoIs() async {
    final response = await _client
        .get(Uri.https('ipwho.is', '/'), headers: _requestHeaders)
        .timeout(timeout);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['success'] == false) return null;

    return _buildResult(
      latRaw: decoded['latitude'],
      lonRaw: decoded['longitude'],
      cityRaw: decoded['city'],
      regionRaw: decoded['region'],
      countryRaw: decoded['country'],
    );
  }

  Future<IpLocationResult?> _fetchFromGeoJs() async {
    final response = await _client
        .get(
          Uri.https('get.geojs.io', '/v1/ip/geo.json'),
          headers: _requestHeaders,
        )
        .timeout(timeout);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    return _buildResult(
      latRaw: decoded['latitude'],
      lonRaw: decoded['longitude'],
      cityRaw: decoded['city'],
      regionRaw: decoded['region'],
      countryRaw: decoded['country'],
    );
  }

  Future<IpLocationResult?> _fetchFromIpApiCo() async {
    final response = await _client
        .get(Uri.https('ipapi.co', '/json/'), headers: _requestHeaders)
        .timeout(timeout);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['error'] == true) return null;

    return _buildResult(
      latRaw: decoded['latitude'],
      lonRaw: decoded['longitude'],
      cityRaw: decoded['city'],
      regionRaw: decoded['region'],
      countryRaw: decoded['country_name'],
    );
  }

  IpLocationResult? _buildResult({
    required Object? latRaw,
    required Object? lonRaw,
    required Object? cityRaw,
    required Object? regionRaw,
    required Object? countryRaw,
  }) {
    final lat = _parseCoordinate(latRaw);
    final lon = _parseCoordinate(lonRaw);
    if (lat == null ||
        lon == null ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180) {
      return null;
    }

    return IpLocationResult(
      latitude: lat,
      longitude: lon,
      city: _cleanLabel(cityRaw),
      region: _cleanLabel(regionRaw),
      country: _cleanLabel(countryRaw),
    );
  }

  double? _parseCoordinate(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'nil') return null;
      return double.tryParse(trimmed);
    }
    return null;
  }

  String? _cleanLabel(Object? raw) {
    if (raw is! String) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'nil') return null;
    return trimmed;
  }
}

