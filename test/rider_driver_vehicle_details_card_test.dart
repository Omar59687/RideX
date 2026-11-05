import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/app/theme/app_theme.dart';
import 'package:ridex/features/trips/presentation/widgets/rider_driver_vehicle_details_card.dart';

const _driverName = 'Maya Haddad';
const _make = 'Hyundai';
const _model = 'Elantra';
const _color = 'Silver';
const _plate = '12-ABC';

RiderDriverVehicleDetailsDisplay _display({Set<String> missing = const {}}) {
  String? value(String field, String data) =>
      missing.contains(field) ? null : data;

  return RiderDriverVehicleDetailsDisplay(
    driverName: value('driverName', _driverName),
    ratingAverage: missing.contains('rating') ? null : 4.8,
    ratingCount: missing.contains('rating') ? null : 26,
    vehicleMake: value('vehicleMake', _make),
    vehicleModel: value('vehicleModel', _model),
    vehicleColor: value('vehicleColor', _color),
    registrationPlate: value('registrationPlate', _plate),
    seatCapacity: missing.contains('seatCapacity') ? null : 4,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  RiderDriverVehicleDetailsDisplay? details,
  ThemeData? theme,
  Size size = const Size(430, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: RiderDriverVehicleDetailsCard(details: details),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders all allowlisted Driver and Vehicle fields',
      (tester) async {
    await _pumpCard(tester, details: _display());

    expect(find.text(_driverName), findsOneWidget);
    expect(find.text('4.8 (26)'), findsOneWidget);
    expect(find.text(_make), findsOneWidget);
    expect(find.text(_model), findsOneWidget);
    expect(find.text(_color), findsOneWidget);
    expect(find.text(_plate), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Vehicle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each optional field independently renders Not available',
      (tester) async {
    const missingToKey = {
      'driverName': ValueKey('rider-driver-name'),
      'rating': ValueKey('rider-driver-rating'),
      'vehicleMake': ValueKey('rider-vehicle-make'),
      'vehicleModel': ValueKey('rider-vehicle-model'),
      'vehicleColor': ValueKey('rider-vehicle-color'),
      'registrationPlate': ValueKey('rider-vehicle-plate'),
      'seatCapacity': ValueKey('rider-vehicle-seats'),
    };

    for (final entry in missingToKey.entries) {
      final details = _display(missing: {entry.key});
      await _pumpCard(tester, details: details);
      final value = find.byKey(entry.value);
      expect(value, findsOneWidget, reason: entry.key);
      expect(
        tester.widget<Text>(value).data,
        RiderDriverVehicleDetailsCard.unavailableLabel,
        reason: '${entry.key} must show its own fallback',
      );
      final retainedValues = <String, String>{
        'driverName': details.driverName ?? 'Not available',
        'rating': details.ratingAverage == null
            ? 'Not available'
            : '${details.ratingAverage!.toStringAsFixed(1)} (${details.ratingCount})',
        'vehicleMake': details.vehicleMake ?? 'Not available',
        'vehicleModel': details.vehicleModel ?? 'Not available',
        'vehicleColor': details.vehicleColor ?? 'Not available',
        'registrationPlate': details.registrationPlate ?? 'Not available',
        'seatCapacity': details.seatCapacity?.toString() ?? 'Not available',
      };
      for (final other
          in missingToKey.entries.where((e) => e.key != entry.key)) {
        expect(
          tester.widget<Text>(find.byKey(other.value)).data,
          retainedValues[other.key],
          reason: '${other.key} must retain its supplied value',
        );
      }
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });

  testWidgets('all optional fields missing render explicit unknown values',
      (tester) async {
    await _pumpCard(
      tester,
      details: RiderDriverVehicleDetailsDisplay(),
    );

    expect(find.text('Not available'), findsNWidgets(7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing display data with unavailable removes stale content',
      (tester) async {
    await _pumpCard(tester, details: _display());
    expect(find.text(_driverName), findsOneWidget);
    expect(find.text(_plate), findsOneWidget);

    await _pumpCard(tester);
    expect(find.text(_driverName), findsNothing);
    expect(find.text(_make), findsNothing);
    expect(find.text(_plate), findsNothing);
    expect(
      find.text('Driver and vehicle details are unavailable.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable semantics contain no former Driver details',
      (tester) async {
    await _pumpCard(tester, details: _display());
    await _pumpCard(tester);

    final semantics = tester.ensureSemantics();
    final semanticsNode = tester.getSemantics(
      find.byType(RiderDriverVehicleDetailsCard),
    );
    expect(semanticsNode.label, 'Driver and vehicle details unavailable');
    expect(semanticsNode.label, isNot(contains(_driverName)));
    expect(semanticsNode.label, isNot(contains(_plate)));
    expect(semanticsNode.childrenCount, 0);
    semantics.dispose();
  });

  testWidgets('UUID-shaped strings are suppressed from text and semantics',
      (tester) async {
    const tripId = 'a1b2c3d4-e5f6-4a1b-8c2d-a1b2c3d4e5f6';
    const bookingId = 'b1c2d3e4-f5a6-4b1c-8d2e-b1c2d3e4f5a6';
    const driverId = '44444444-4444-4444-8444-444444444444';
    const vehicleId = '55555555-5555-4555-8555-555555555555';
    final details = RiderDriverVehicleDetailsDisplay(
      driverName: tripId,
      ratingAverage: 4.8,
      ratingCount: 26,
      vehicleMake: bookingId,
      vehicleModel: driverId,
      vehicleColor: vehicleId,
      registrationPlate: tripId.toUpperCase(),
      seatCapacity: 4,
    );
    await _pumpCard(tester, details: details);

    for (final key in [
      const ValueKey('rider-driver-name'),
      const ValueKey('rider-vehicle-make'),
      const ValueKey('rider-vehicle-model'),
      const ValueKey('rider-vehicle-color'),
      const ValueKey('rider-vehicle-plate'),
    ]) {
      expect(
        tester.widget<Text>(find.byKey(key)).data,
        RiderDriverVehicleDetailsCard.unavailableLabel,
      );
    }
    expect(find.text('12-ABC'), findsNothing);

    final rendered = tester.widgetList<Text>(find.byType(Text)).map((text) {
      final child = text.data;
      return child ?? text.textSpan?.toPlainText() ?? '';
    }).join(' ');
    for (final canary in [tripId, bookingId, driverId, vehicleId]) {
      expect(rendered.toLowerCase(), isNot(contains(canary.toLowerCase())));
    }

    final semantics = tester.ensureSemantics();
    final cardSemantics = tester.getSemantics(
      find.byType(RiderDriverVehicleDetailsCard),
    );
    for (final canary in [tripId, bookingId, driverId, vehicleId]) {
      expect(cardSemantics.label, isNot(contains(canary)));
      expect(cardSemantics.label, isNot(contains(canary.toUpperCase())));
    }
    expect(cardSemantics.label, contains('Registration plate: Not available'));
    expect(cardSemantics.childrenCount, 0);
    semantics.dispose();
  });

  testWidgets('valid non-UUID registration plates remain visible',
      (tester) async {
    await _pumpCard(tester, details: _display());
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('rider-vehicle-plate')))
          .data,
      _plate,
    );
    expect(find.text(_plate), findsOneWidget);
  });

  test('projection validates rating pairing, range, finiteness and capacity',
      () {
    expect(
      () => RiderDriverVehicleDetailsDisplay(ratingAverage: 4.5),
      throwsArgumentError,
    );
    expect(
      () => RiderDriverVehicleDetailsDisplay(ratingCount: 4),
      throwsArgumentError,
    );
    for (final rating in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -0.1,
      5.1
    ]) {
      expect(
        () => RiderDriverVehicleDetailsDisplay(
          ratingAverage: rating,
          ratingCount: 1,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => RiderDriverVehicleDetailsDisplay(
        ratingAverage: 4.5,
        ratingCount: -1,
      ),
      throwsArgumentError,
    );
    for (final capacity in [0, 13]) {
      expect(
        () => RiderDriverVehicleDetailsDisplay(seatCapacity: capacity),
        throwsArgumentError,
      );
    }
  });

  test('blank and out-of-contract display strings are normalized or rejected',
      () {
    final blank = RiderDriverVehicleDetailsDisplay(
      driverName: '   ',
      vehicleMake: '\n ',
      vehicleModel: '\t',
      vehicleColor: ' ',
      registrationPlate: ' ',
    );
    expect(blank.driverName, isNull);
    expect(blank.vehicleMake, isNull);
    expect(blank.vehicleModel, isNull);
    expect(blank.vehicleColor, isNull);
    expect(blank.registrationPlate, isNull);

    expect(
      () => RiderDriverVehicleDetailsDisplay(driverName: 'x' * 201),
      throwsArgumentError,
    );
    expect(
      () => RiderDriverVehicleDetailsDisplay(vehicleMake: 'x' * 101),
      throwsArgumentError,
    );
    expect(
      () => RiderDriverVehicleDetailsDisplay(vehicleModel: 'x' * 101),
      throwsArgumentError,
    );
    expect(
      () => RiderDriverVehicleDetailsDisplay(vehicleColor: 'x' * 51),
      throwsArgumentError,
    );
    expect(
      () => RiderDriverVehicleDetailsDisplay(registrationPlate: 'x' * 33),
      throwsArgumentError,
    );
  });

  test('string validation errors name the field without echoing input', () {
    const privateCanary = 'PRIVATE_DISPLAY_IDENTIFIER_CANARY';
    final rejectedInputs =
        <({String field, RiderDriverVehicleDetailsDisplay Function() build})>[
      (
        field: 'driverName',
        build: () => RiderDriverVehicleDetailsDisplay(
              driverName: '$privateCanary${'x' * 201}',
            ),
      ),
      (
        field: 'vehicleMake',
        build: () => RiderDriverVehicleDetailsDisplay(
              vehicleMake: '$privateCanary${'x' * 101}',
            ),
      ),
      (
        field: 'vehicleModel',
        build: () => RiderDriverVehicleDetailsDisplay(
              vehicleModel: '$privateCanary${'x' * 101}',
            ),
      ),
      (
        field: 'vehicleColor',
        build: () => RiderDriverVehicleDetailsDisplay(
              vehicleColor: '$privateCanary${'x' * 51}',
            ),
      ),
      (
        field: 'registrationPlate',
        build: () => RiderDriverVehicleDetailsDisplay(
              registrationPlate: '$privateCanary${'x' * 33}',
            ),
      ),
    ];

    for (final rejected in rejectedInputs) {
      ArgumentError? captured;
      try {
        rejected.build();
      } on ArgumentError catch (error) {
        captured = error;
      }
      expect(captured, isNotNull, reason: rejected.field);
      expect(captured.toString(), contains(rejected.field),
          reason: rejected.field);
      expect(captured.toString(), isNot(contains(privateCanary)),
          reason: rejected.field);
    }

    const shortPlateCanary = 'Q7';
    ArgumentError? shortPlateError;
    try {
      RiderDriverVehicleDetailsDisplay(registrationPlate: shortPlateCanary);
    } on ArgumentError catch (error) {
      shortPlateError = error;
    }
    expect(shortPlateError, isNotNull);
    expect(shortPlateError.toString(), contains('registrationPlate'));
    expect(shortPlateError.toString(), isNot(contains(shortPlateCanary)));

    final valid = RiderDriverVehicleDetailsDisplay(
      driverName: _driverName,
      registrationPlate: _plate,
    );
    expect(valid.driverName, _driverName);
    expect(valid.registrationPlate, _plate);
  });

  testWidgets(
      'maximum valid field lengths wrap at compact width and large text',
      (tester) async {
    final details = RiderDriverVehicleDetailsDisplay(
      driverName: 'D' * 200,
      ratingAverage: 5,
      ratingCount: 999999999,
      vehicleMake: 'M' * 100,
      vehicleModel: 'V' * 100,
      vehicleColor: 'C' * 50,
      registrationPlate: 'P' * 32,
      seatCapacity: 12,
    );
    await _pumpCard(
      tester,
      details: details,
      size: const Size(320, 640),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact width and large text scale remain usable',
      (tester) async {
    await _pumpCard(
      tester,
      details: _display(),
      size: const Size(320, 640),
      textScale: 2,
    );

    expect(find.text(_driverName), findsOneWidget);
    expect(find.text(_plate), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inherits both light and dark RideX themes', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await _pumpCard(tester, details: _display(), theme: theme);
      expect(find.text(_driverName), findsOneWidget);
      expect(
        Theme.of(tester.element(find.text(_driverName))).brightness,
        theme.brightness,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('provides accessible field labels and has no actions',
      (tester) async {
    await _pumpCard(tester, details: _display());

    final cardSemantics = tester.getSemantics(
      find.byType(RiderDriverVehicleDetailsCard),
    );
    for (final expected in [
      'Driver and vehicle details',
      'Driver name: $_driverName',
      'Driver rating: 4.8 (26)',
      'Vehicle make: $_make',
      'Vehicle model: $_model',
      'Vehicle color: $_color',
      'Registration plate: $_plate',
      'Seat capacity: 4',
    ]) {
      expect(cardSemantics.label, contains(expected));
      expect(cardSemantics.label.split(expected).length - 1, 1,
          reason: '$expected should be announced once');
    }
    expect(cardSemantics.childrenCount, 0);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(Navigator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is pumpable without ProviderScope or repository setup',
      (tester) async {
    await _pumpCard(tester, details: _display());

    expect(find.byType(RiderDriverVehicleDetailsCard), findsOneWidget);
    expect(find.text(_driverName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
