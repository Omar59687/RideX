import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/core/mocks/mock_data.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/route_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/route_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/features/booking/presentation/screens/vehicle_type_selection_screen.dart';

void main() {
  testWidgets('vehicle progression stays disabled until route is ready',
      (tester) async {
    final repository = _PendingRouteRepository();
    final container = ProviderContainer(
      overrides: [routeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    container.read(bookingControllerProvider.notifier)
      ..setPickup(MockData.locations[0])
      ..setDestination(MockData.locations[1])
      ..setVehicleType(MockData.vehicleTypes.first);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const VehicleTypeSelectionScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('route-loading')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(AppButton),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_progressionButton(tester).onPressed, isNull);

    repository.complete();
    await tester.pump();

    expect(container.read(routeControllerProvider).status, RouteStatus.ready);
    expect(_progressionButton(tester).onPressed, isNotNull);
  });
}

AppButton _progressionButton(WidgetTester tester) => tester.widget<AppButton>(
      find.byType(AppButton),
    );

class _PendingRouteRepository implements RouteRepository {
  final _completer = Completer<RouteResult>();
  RouteRequest? _request;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) {
    _request = request;
    return _completer.future;
  }

  void complete() {
    final request = _request!;
    _completer.complete(
      RouteResult(
        request: request,
        geometry: [request.origin, request.destination],
        distanceMeters: 5000,
        durationSeconds: 600,
      ),
    );
  }
}
