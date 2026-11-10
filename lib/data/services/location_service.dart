import 'package:geolocator/geolocator.dart';

class LocationLookupException implements Exception {
  final String message;

  const LocationLookupException(this.message);

  @override
  String toString() => message;
}

abstract class LocationService {
  Future<({double latitude, double longitude})> getCurrentCoordinates();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<({double latitude, double longitude})> getCurrentCoordinates() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationLookupException(
        'Location services are turned off. Enable GPS or search a city manually.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationLookupException(
          'Location permission denied. You can still search your city below.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationLookupException(
        'Location permission permanently denied in OS settings. Please search your city manually.',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    );
    return (latitude: position.latitude, longitude: position.longitude);
  }
}

