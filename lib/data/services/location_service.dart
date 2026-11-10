import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../domain/models/user_profile.dart';
import 'ip_location_service.dart';
import 'weather_api_client.dart';

export 'ip_location_service.dart'
    show LocationFailureReason, LocationLookupException;

abstract class LocationService {
  Future<({double latitude, double longitude})> getCurrentCoordinates();
}

abstract interface class PermissionAwareLocationService
    implements LocationService {
  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates({
    bool requestPermission = true,
  });
}

class GeolocatorLocationService implements PermissionAwareLocationService {
  const GeolocatorLocationService();

  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates({
    bool requestPermission = true,
  }) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        if (!requestPermission) {
          throw const LocationLookupException(
            'Location permission not granted.',
            reason: LocationFailureReason.permissionDenied,
          );
        }
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw const LocationLookupException(
            'Location permission denied. Using approximate public IP location.',
            reason: LocationFailureReason.permissionDenied,
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw const LocationLookupException(
          'Location permission permanently denied in OS settings.',
          reason: LocationFailureReason.permissionDeniedForever,
        );
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationLookupException(
          'Location services are turned off on this device.',
          reason: LocationFailureReason.serviceDisabled,
        );
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );
        return (latitude: position.latitude, longitude: position.longitude);
      } on LocationLookupException {
        rethrow;
      } on PermissionDeniedException {
        throw const LocationLookupException(
          'Location permission denied.',
          reason: LocationFailureReason.permissionDenied,
        );
      } on LocationServiceDisabledException {
        throw const LocationLookupException(
          'Location services are turned off on this device.',
          reason: LocationFailureReason.serviceDisabled,
        );
      } catch (_) {
        if (!kIsWeb) {
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null) {
              return (
                latitude: lastKnown.latitude,
                longitude: lastKnown.longitude,
              );
            }
          } catch (_) {}
        }
        throw const LocationLookupException(
          'Unable to acquire GPS fix.',
          reason: LocationFailureReason.unavailable,
        );
      }
    } on LocationLookupException {
      rethrow;
    } on PermissionDeniedException {
      throw const LocationLookupException(
        'Location permission denied.',
        reason: LocationFailureReason.permissionDenied,
      );
    } on LocationServiceDisabledException {
      throw const LocationLookupException(
        'Location services are turned off on this device.',
        reason: LocationFailureReason.serviceDisabled,
      );
    } on MissingPluginException {
      throw const LocationLookupException(
        'Device GPS plugin unavailable on this platform.',
        reason: LocationFailureReason.unavailable,
      );
    } on UnimplementedError {
      throw const LocationLookupException(
        'Device GPS unavailable on this platform.',
        reason: LocationFailureReason.unavailable,
      );
    } catch (_) {
      throw const LocationLookupException(
        'Unable to acquire GPS coordinates.',
        reason: LocationFailureReason.unavailable,
      );
    }
  }
}

enum ResolvedLocationSource { gps, ip }

class ResolvedLocation {
  final String name;
  final double latitude;
  final double longitude;
  final ResolvedLocationSource source;
  final LocationFailureReason? gpsFailureReason;

  const ResolvedLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.source,
    this.gpsFailureReason,
  });

  LocationMode get locationMode => source == ResolvedLocationSource.gps
      ? LocationMode.gps
      : LocationMode.ip;
}

class LocationResolver {
  final LocationService gpsService;
  final IpLocationService ipLocationService;
  final WeatherApiClient _anonymizer;

  LocationResolver({
    required this.gpsService,
    required this.ipLocationService,
    WeatherApiClient? anonymizer,
  }) : _anonymizer = anonymizer ?? WeatherApiClient();

  /// Attempts GPS location first (prompting permission when allowed),
  /// automatically falling back to public IP geolocation if GPS permission
  /// is denied, location services are off, or GPS acquisition fails.
  Future<ResolvedLocation> resolveLocation({
    bool requestGpsPermission = true,
  }) async {
    LocationFailureReason failureReason = LocationFailureReason.unavailable;

    try {
      final service = gpsService;
      final coords = service is PermissionAwareLocationService
          ? await service.getCurrentCoordinates(
              requestPermission: requestGpsPermission,
            )
          : await service.getCurrentCoordinates();
      final quantized = _anonymizer.anonymizeCoordinates(
        coords.latitude,
        coords.longitude,
      );
      return ResolvedLocation(
        name:
            'GPS (${quantized.latitude.toStringAsFixed(2)}, ${quantized.longitude.toStringAsFixed(2)})',
        latitude: quantized.latitude,
        longitude: quantized.longitude,
        source: ResolvedLocationSource.gps,
      );
    } on LocationLookupException catch (e) {
      failureReason = e.reason;
    } catch (_) {
      failureReason = LocationFailureReason.unavailable;
    }

    try {
      final ipLoc = await ipLocationService.lookupPublicIpLocation();
      final quantized = _anonymizer.anonymizeCoordinates(
        ipLoc.latitude,
        ipLoc.longitude,
      );
      return ResolvedLocation(
        name: ipLoc.displayLabel(
          quantizedLat: quantized.latitude,
          quantizedLon: quantized.longitude,
        ),
        latitude: quantized.latitude,
        longitude: quantized.longitude,
        source: ResolvedLocationSource.ip,
        gpsFailureReason: failureReason,
      );
    } catch (_) {
      throw LocationLookupException(
        _combinedFailureMessage(failureReason),
        reason: failureReason,
      );
    }
  }

  String _combinedFailureMessage(LocationFailureReason reason) {
    return switch (reason) {
      LocationFailureReason.permissionDenied =>
        'GPS permission denied and public IP lookup failed. Connect to the internet or search your city manually.',
      LocationFailureReason.permissionDeniedForever =>
        'GPS permission permanently denied and public IP lookup failed. Enable location in OS settings or search your city manually.',
      LocationFailureReason.serviceDisabled =>
        'Device GPS is turned off and public IP lookup failed. Enable GPS, connect to the internet, or search your city manually.',
      LocationFailureReason.unavailable =>
        'Unable to detect GPS or public IP location. Connect to the internet or search your city manually.',
    };
  }
}
