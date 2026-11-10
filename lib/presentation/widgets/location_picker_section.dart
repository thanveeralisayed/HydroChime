import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../data/services/location_service.dart';
import '../../data/services/weather_api_client.dart';
import '../../domain/models/user_profile.dart';
import '../providers/hydration_providers.dart';

class LocationSelection {
  final String name;
  final double latitude;
  final double longitude;
  final LocationMode mode;

  const LocationSelection(
    this.name,
    this.latitude,
    this.longitude, {
    this.mode = LocationMode.manual,
  });
}

const List<LocationSelection> kDefaultCityPresets = [
  LocationSelection('Austin', 30.27, -97.74),
  LocationSelection('Seattle', 47.61, -122.33),
  LocationSelection('Phoenix', 33.45, -112.07),
  LocationSelection('New York', 40.71, -74.01),
  LocationSelection('London', 51.51, -0.13),
  LocationSelection('Tokyo', 35.68, 139.77),
];

class LocationPickerSection extends ConsumerStatefulWidget {
  final LocationSelection selected;
  final ValueChanged<LocationSelection> onSelected;
  final WidgetRef rootRef;

  const LocationPickerSection({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.rootRef,
  });

  @override
  ConsumerState<LocationPickerSection> createState() =>
      _LocationPickerSectionState();
}

class _LocationPickerSectionState extends ConsumerState<LocationPickerSection> {
  final TextEditingController _searchController = TextEditingController();
  bool _locatingGps = false;
  bool _searchingCity = false;
  List<GeocodedLocation> _searchResults = const [];
  String? _statusError;
  String? _statusInfo;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _detectGps() async {
    setState(() {
      _locatingGps = true;
      _statusError = null;
      _statusInfo = null;
    });
    try {
      final resolved = await widget.rootRef
          .read(locationResolverProvider)
          .resolveLocation(requestGpsPermission: true);
      if (!mounted) return;
      final infoMessage = resolved.source == ResolvedLocationSource.ip
          ? switch (resolved.gpsFailureReason) {
              LocationFailureReason.permissionDenied ||
              LocationFailureReason.permissionDeniedForever =>
                'GPS permission not granted — located via public IP.',
              LocationFailureReason.serviceDisabled =>
                'Device GPS is off — located via public IP.',
              _ => 'GPS unavailable — located via public IP.',
            }
          : null;
      setState(() => _statusInfo = infoMessage);
      widget.onSelected(
        LocationSelection(
          resolved.name,
          resolved.latitude,
          resolved.longitude,
          mode: resolved.locationMode,
        ),
      );
    } on LocationLookupException catch (e) {
      if (mounted) setState(() => _statusError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _statusError =
              'Unable to detect GPS or public IP location.',
        );
      }
    } finally {
      if (mounted) setState(() => _locatingGps = false);
    }
  }

  Future<void> _runCitySearch() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _statusInfo = null;
        _statusError = 'Enter at least 2 characters to search.';
      });
      return;
    }

    setState(() {
      _searchingCity = true;
      _statusError = null;
      _statusInfo = null;
    });
    try {
      final results = await widget.rootRef
          .read(weatherApiClientProvider)
          .searchCities(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _statusError = 'No matching cities found for "$query".';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusError = 'City search requires an active internet connection.';
        });
      }
    } finally {
      if (mounted) setState(() => _searchingCity = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = HydroChimeColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('city_search_input'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runCitySearch(),
                style: TextStyle(color: palette.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search city worldwide...',
                  hintStyle:
                      TextStyle(color: palette.textTertiary, fontSize: 12),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: palette.primaryVital),
                  ),
                  suffixIcon: IconButton(
                    key: const Key('city_search_submit'),
                    tooltip: 'Search city',
                    onPressed: _searchingCity ? null : _runCitySearch,
                    icon: _searchingCity
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: palette.primaryAtmosphere,
                            ),
                          )
                        : Icon(
                            Icons.search,
                            size: 18,
                            color: palette.primaryAtmosphere,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('gps_location_button'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.borderSubtle),
                foregroundColor: palette.primaryAtmosphere,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _locatingGps ? null : _detectGps,
              icon: _locatingGps
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: palette.primaryAtmosphere,
                      ),
                    )
                  : const Icon(Icons.my_location, size: 15),
              label: const Text('GPS', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        if (_statusInfo != null) ...[
          const SizedBox(height: 6),
          Text(
            _statusInfo!,
            style: TextStyle(color: palette.primaryAtmosphere, fontSize: 11),
          ),
        ],
        if (_statusError != null) ...[
          const SizedBox(height: 6),
          Text(
            _statusError!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ],
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _searchResults.map((hit) {
              final isSelected =
                  (widget.selected.latitude - hit.latitude).abs() < 0.02 &&
                      (widget.selected.longitude - hit.longitude).abs() < 0.02;
              return ChoiceChip(
                label: Text(
                  hit.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected
                        ? (palette.isDark ? Colors.black : Colors.white)
                        : palette.textPrimary,
                  ),
                ),
                selected: isSelected,
                selectedColor: palette.primaryVital,
                backgroundColor: palette.surfaceCard,
                side: BorderSide(color: palette.borderSubtle),
                onSelected: (_) {
                  setState(() {
                    _statusError = null;
                    _statusInfo = null;
                  });
                  widget.onSelected(
                    LocationSelection(
                      hit.name,
                      hit.latitude,
                      hit.longitude,
                      mode: LocationMode.manual,
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: kDefaultCityPresets.map((city) {
            final isSelected = widget.selected.name == city.name;
            return ChoiceChip(
              label: Text(
                city.name,
                style: TextStyle(
                  color: isSelected
                      ? (palette.isDark ? Colors.black : Colors.white)
                      : palette.textPrimary,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              selectedColor: palette.primaryVital,
              backgroundColor: palette.surfaceCard,
              side: BorderSide(color: palette.borderSubtle),
              onSelected: (_) {
                setState(() {
                  _statusError = null;
                  _statusInfo = null;
                });
                widget.onSelected(city);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          'Active region: ${widget.selected.name} (${widget.selected.latitude.toStringAsFixed(2)}, ${widget.selected.longitude.toStringAsFixed(2)})',
          style: TextStyle(
            color: palette.primaryAtmosphere,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
