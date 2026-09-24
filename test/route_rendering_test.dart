import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/location_point.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/widgets/google_location_selection_map.dart';
import 'package:ridex/core/widgets/route_status_panel.dart';

import 'helpers/recording_error_reporter.dart';

void main() {
  test('builds route halo and live polylines from provider-neutral geometry',
      () {
    final geometry = [
      LocationPoint(latitude: 31.95, longitude: 35.91),
      LocationPoint(latitude: 31.98, longitude: 35.95),
    ];

    final polylines = buildRoutePolylines(
      geometry: geometry,
      routeColor: Colors.blue,
      haloColor: Colors.white,
    );

    expect(polylines, hasLength(2));
    expect(
      polylines.map((line) => line.polylineId),
      containsAll(const [PolylineId('route-halo'), PolylineId('route-live')]),
    );
    expect(polylines.every((line) => line.points.length == 2), isTrue);
    final bounds = routeBounds(geometry)!;
    expect(bounds.southwest, const LatLng(31.95, 35.91));
    expect(bounds.northeast, const LatLng(31.98, 35.95));
  });

  testWidgets('shows service-backed distance and duration', (tester) async {
    final request = RouteRequest(
      origin: LocationPoint(latitude: 31.95, longitude: 35.91),
      destination: LocationPoint(latitude: 31.98, longitude: 35.95),
    );
    final state = RouteState.ready(
      RouteResult(
        request: request,
        geometry: [request.origin, request.destination],
        distanceMeters: 5420,
        durationSeconds: 721,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RouteStatusPanel(state: state, onRetry: () {}),
        ),
      ),
    );

    expect(find.text('5.4 km | 13 min'), findsOneWidget);
    expect(find.text('Traffic-aware driving route'), findsOneWidget);
  });

  testWidgets('distinguishes a recoverable network failure', (tester) async {
    final request = RouteRequest(
      origin: LocationPoint(latitude: 31.95, longitude: 35.91),
      destination: LocationPoint(latitude: 31.98, longitude: 35.95),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RouteStatusPanel(
            state: RouteState.failure(
              request,
              RouteFailure.networkFailure,
            ),
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('route-network-failure')), findsOneWidget);
    expect(find.text('Network failure'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining(rawErrorCanary), findsNothing);
  });
}
