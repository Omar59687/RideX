import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';

void main() {
  group('Phase 4 architecture boundaries', () {
    test('provider-neutral models do not import provider SDKs', () {
      for (final relativePath in _phaseFourModelFiles) {
        final source = _read(relativePath);
        expect(source, isNot(contains('package:google_maps_flutter/')),
            reason: relativePath);
        expect(source, isNot(contains('package:geolocator/')),
            reason: relativePath);
        expect(source, isNot(contains('package:supabase')),
            reason: relativePath);
      }
    });

    test('feature UI does not import provider SDKs directly', () {
      final featureDirectory = Directory(_path('lib/features'));
      final featureFiles = featureDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in featureFiles) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('package:google_maps_flutter/')),
            reason: file.path);
        expect(source, isNot(contains('package:geolocator/')),
            reason: file.path);
        expect(source, isNot(contains('package:supabase')), reason: file.path);
      }
    });

    test('provider SDK imports remain within approved Phase 4 boundaries', () {
      _expectImportsOnly(
        packageName: 'google_maps_flutter',
        allowedFiles: _googleMapAdapterFiles,
        scannedDirectories: const ['lib'],
      );
      _expectImportsOnly(
        packageName: 'geolocator',
        allowedFiles: _geolocatorAdapterFiles,
        scannedDirectories: const ['lib'],
      );
      _expectImportsOnly(
        packageName: 'supabase_flutter',
        allowedFiles: _phaseFourSupabaseFiles,
        scannedDirectories: const [
          'lib/app',
          'lib/core/providers',
          'lib/core/services/driver_location',
          'lib/core/services/places',
          'lib/core/services/routes',
        ],
        scannedFiles: const [
          'lib/core/services/supabase/supabase_client_provider.dart',
        ],
      );
    });

    test('route contracts retain provider-neutral geometry and metrics', () {
      final origin = LocationPoint(latitude: 31.95, longitude: 35.91);
      final destination = LocationPoint(latitude: 31.96, longitude: 35.92);
      final request = RouteRequest(
        origin: origin,
        destination: destination,
      );
      final result = RouteResult(
        request: request,
        geometry: [origin, destination],
        distanceMeters: 1500,
        durationSeconds: 420,
      );

      expect(result.geometry, hasLength(2));
      expect(result.distanceMeters, 1500);
      expect(result.durationSeconds, 420);
      expect(result.origin, origin);
      expect(result.destination, destination);
    });

    test('Driver location contracts retain mobility fields and association',
        () {
      final recordedAt = DateTime.utc(2026, 9, 27, 10);
      final receivedAt = recordedAt.add(const Duration(seconds: 2));
      final point = LocationPoint(
        latitude: 31.95,
        longitude: 35.91,
        accuracyMeters: 8,
      );
      final sample = DriverLocationSample(
        point: point,
        sequence: 4,
        recordedAt: recordedAt,
        tripId: 'trip-1',
        headingDegrees: 90,
        speedMetersPerSecond: 8.5,
      );
      final saved = SavedDriverLocation(
        point: point,
        sequence: sample.sequence,
        recordedAt: sample.recordedAt,
        receivedAt: receivedAt,
        tripId: sample.tripId,
        headingDegrees: sample.headingDegrees,
        speedMetersPerSecond: sample.speedMetersPerSecond,
      );
      const availability = DriverAvailability(
        state: DriverAvailabilityState.onTrip,
        activeTripId: 'trip-1',
      );

      expect(saved.sequence, 4);
      expect(saved.recordedAt, recordedAt);
      expect(saved.receivedAt, receivedAt);
      expect(saved.point.accuracyMeters, 8);
      expect(saved.headingDegrees, 90);
      expect(saved.speedMetersPerSecond, 8.5);
      expect(availability.canShareLocation, isTrue);
      expect(availability.activeTripId, saved.tripId);
    });
  });
}

const _phaseFourModelFiles = [
  'lib/core/models/current_location_state.dart',
  'lib/core/models/driver_availability.dart',
  'lib/core/models/driver_location.dart',
  'lib/core/models/location_point.dart',
  'lib/core/models/route_models.dart',
];

const _googleMapAdapterFiles = [
  'lib/core/widgets/google_current_location_map.dart',
  'lib/core/widgets/google_location_selection_map.dart',
];

const _geolocatorAdapterFiles = [
  'lib/core/services/location/location_service.dart',
  'lib/core/services/driver_location/geolocator_driver_gps_stream_service.dart',
];

const _phaseFourSupabaseFiles = [
  'lib/app/bootstrap.dart',
  'lib/core/providers/driver_tracking_providers.dart',
  'lib/core/providers/repositories_providers.dart',
  'lib/core/services/driver_location/supabase_driver_location_service.dart',
  'lib/core/services/driver_location/supabase_driver_tracking_connection.dart',
  'lib/core/services/places/supabase_place_service.dart',
  'lib/core/services/routes/supabase_route_service.dart',
  'lib/core/services/supabase/supabase_client_provider.dart',
];

void _expectImportsOnly({
  required String packageName,
  required List<String> allowedFiles,
  required List<String> scannedDirectories,
  List<String> scannedFiles = const [],
}) {
  final allowed = allowedFiles.toSet();
  final files = <String>{
    ...scannedFiles,
    for (final directory in scannedDirectories)
      ...Directory(_path(directory))
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map(_relativePath),
  };

  for (final relativePath in files) {
    final source = _read(relativePath);
    if (source.contains('package:$packageName/')) {
      expect(allowed, contains(relativePath), reason: relativePath);
    }
  }
}

String _read(String relativePath) =>
    File(_path(relativePath)).readAsStringSync();

String _path(String relativePath) =>
    Directory.current.uri.resolve(relativePath).toFilePath();

String _relativePath(File file) {
  final root = Directory.current.uri.toFilePath();
  final path = file.absolute.path;
  return path.substring(root.length).replaceAll('\\', '/');
}
