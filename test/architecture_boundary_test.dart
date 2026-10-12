import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/models/driver_availability.dart';
import 'package:ridex/core/models/driver_location.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';

void main() {
  group('Phase 4 architecture boundaries', () {
    test('provider-neutral models do not import provider SDKs', () {
      for (final file in _dartFilesUnder('lib/core/models')) {
        final directives = _providerDirectives(file);
        expect(directives, isEmpty, reason: _relativePath(file));
      }
    });

    test('feature UI does not import provider SDKs directly', () {
      for (final file in _dartFilesUnder('lib/features')) {
        final directives = _providerDirectives(file);
        expect(directives, isEmpty, reason: _relativePath(file));
      }
    });

    test(
        'provider SDK directives remain within explicit infrastructure boundaries',
        () {
      final allFiles = _dartFilesUnder('lib');
      for (final file in allFiles) {
        for (final directive in _providerDirectives(file)) {
          final relativePath = _relativePath(file);
          final allowedFiles = _allowedFilesFor(directive.packageName);
          expect(
            allowedFiles,
            contains(relativePath),
            reason: '$directive in $relativePath',
          );
        }
      }
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

const _googleMapAdapterFiles = {
  'lib/core/widgets/google_current_location_map.dart',
  'lib/core/widgets/google_location_selection_map.dart',
};

const _geolocatorAdapterFiles = {
  'lib/core/services/location/geolocator_location_service.dart',
  'lib/core/services/driver_location/geolocator_driver_gps_stream_service.dart',
};

const _supabaseInfrastructureFiles = {
  'lib/app/bootstrap.dart',
  'lib/core/providers/driver_tracking_providers.dart',
  'lib/core/providers/repositories_providers.dart',
  'lib/core/repositories/supabase_auth_repository.dart',
  'lib/core/repositories/supabase_profile_repository.dart',
  'lib/core/services/driver_location/supabase_driver_location_service.dart',
  'lib/core/services/driver_location/supabase_driver_tracking_connection.dart',
  'lib/core/services/fare/supabase_fare_lock_reader.dart',
  'lib/core/services/places/supabase_place_service.dart',
  'lib/core/services/routes/supabase_route_service.dart',
  'lib/core/services/supabase/auth_service.dart',
  'lib/core/services/supabase/profile_service.dart',
  'lib/core/services/supabase/supabase_client_provider.dart',
};

Iterable<File> _dartFilesUnder(String relativeDirectory) {
  return Directory(_path(relativeDirectory))
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

Set<_ProviderDirective> _providerDirectives(File file) {
  final source = file.readAsStringSync();
  final directives = <_ProviderDirective>{};
  for (final packageName in const [
    'google_maps_flutter',
    'geolocator',
    'supabase',
    'supabase_flutter',
  ]) {
    final pattern = RegExp(
      "^\\s*(?:import|export)\\s+['\"]package:$packageName/[^'\"]+['\"]",
      multiLine: true,
    );
    if (pattern.hasMatch(source)) {
      directives.add(_ProviderDirective(packageName));
    }
  }
  return directives;
}

Set<String> _allowedFilesFor(String packageName) {
  return switch (packageName) {
    'google_maps_flutter' => _googleMapAdapterFiles,
    'geolocator' => _geolocatorAdapterFiles,
    'supabase' || 'supabase_flutter' => _supabaseInfrastructureFiles,
    _ => const {},
  };
}

String _path(String relativePath) =>
    Directory.current.uri.resolve(relativePath).toFilePath();

String _relativePath(File file) {
  final root = Directory.current.uri.toFilePath();
  return file.absolute.path.substring(root.length).replaceAll('\\', '/');
}

class _ProviderDirective {
  const _ProviderDirective(this.packageName);

  final String packageName;

  @override
  bool operator ==(Object other) =>
      other is _ProviderDirective && other.packageName == packageName;

  @override
  int get hashCode => packageName.hashCode;

  @override
  String toString() => 'package:$packageName';
}
