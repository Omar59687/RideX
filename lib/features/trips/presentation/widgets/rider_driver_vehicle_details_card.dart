import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';

/// Allowlisted, immutable display projection for the Driver/Vehicle card.
///
/// This is presentation data, not evidence of assignment or authorization.
/// A future production caller may populate it only after an approved trusted
/// composition has verified the exact assigned Trip and Rider.
@immutable
class RiderDriverVehicleDetailsDisplay {
  RiderDriverVehicleDetailsDisplay({
    String? driverName,
    double? ratingAverage,
    int? ratingCount,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleColor,
    String? registrationPlate,
    this.seatCapacity,
  })  : driverName = _optionalText(driverName, 'driverName', 200),
        ratingAverage = ratingAverage,
        ratingCount = ratingCount,
        vehicleMake = _optionalText(vehicleMake, 'vehicleMake', 100),
        vehicleModel = _optionalText(vehicleModel, 'vehicleModel', 100),
        vehicleColor = _optionalText(vehicleColor, 'vehicleColor', 50),
        registrationPlate = _optionalText(
          registrationPlate,
          'registrationPlate',
          32,
          minimumLength: 3,
        ) {
    if ((ratingAverage == null) != (ratingCount == null)) {
      throw ArgumentError(
          'ratingAverage and ratingCount must be provided together.');
    }
    if (ratingAverage != null &&
        (!ratingAverage.isFinite || ratingAverage < 0 || ratingAverage > 5)) {
      throw ArgumentError.value(ratingAverage, 'ratingAverage');
    }
    if (ratingCount != null && ratingCount < 0) {
      throw ArgumentError.value(ratingCount, 'ratingCount');
    }
    if (seatCapacity != null && (seatCapacity! < 1 || seatCapacity! > 12)) {
      throw ArgumentError.value(seatCapacity, 'seatCapacity');
    }
  }

  final String? driverName;
  final double? ratingAverage;
  final int? ratingCount;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? registrationPlate;
  final int? seatCapacity;
}

/// Standalone display-only information card.
///
/// Passing `null` represents unavailable evidence and renders no Driver or
/// Vehicle values. The widget performs no authorization, I/O, or navigation.
class RiderDriverVehicleDetailsCard extends StatelessWidget {
  const RiderDriverVehicleDetailsCard({
    super.key,
    required this.details,
  });

  static const unavailableLabel = 'Not available';

  final RiderDriverVehicleDetailsDisplay? details;

  @override
  Widget build(BuildContext context) {
    final current = details;
    if (current == null) {
      return Semantics(
        container: true,
        label: 'Driver and vehicle details unavailable',
        child: ExcludeSemantics(
          child: const Card(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('Driver and vehicle details are unavailable.'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final ratingText = current.ratingAverage == null
        ? unavailableLabel
        : '${current.ratingAverage!.toStringAsFixed(1)}'
            '${current.ratingCount == null ? '' : ' (${current.ratingCount})'}';
    final semanticFields = <String>[
      'Driver name: ${_value(current.driverName)}',
      'Driver rating: $ratingText',
      'Vehicle make: ${_value(current.vehicleMake)}',
      'Vehicle model: ${_value(current.vehicleModel)}',
      'Vehicle color: ${_value(current.vehicleColor)}',
      'Registration plate: ${_value(current.registrationPlate)}',
      'Seat capacity: ${current.seatCapacity?.toString() ?? unavailableLabel}',
    ];

    return Semantics(
      container: true,
      label: 'Driver and vehicle details. ${semanticFields.join('. ')}.',
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: const Icon(Icons.person_outline_rounded),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Driver',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _DetailRow(
                  fieldKey: const ValueKey('rider-driver-name'),
                  label: 'Name',
                  value: _value(current.driverName),
                ),
                _DetailRow(
                  fieldKey: const ValueKey('rider-driver-rating'),
                  label: 'Rating',
                  value: ratingText,
                ),
                const Divider(height: AppSpacing.lg),
                Text('Vehicle', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                _DetailRow(
                  fieldKey: const ValueKey('rider-vehicle-make'),
                  label: 'Make',
                  value: _value(current.vehicleMake),
                ),
                _DetailRow(
                  fieldKey: const ValueKey('rider-vehicle-model'),
                  label: 'Model',
                  value: _value(current.vehicleModel),
                ),
                _DetailRow(
                  fieldKey: const ValueKey('rider-vehicle-color'),
                  label: 'Color',
                  value: _value(current.vehicleColor),
                ),
                _DetailRow(
                  fieldKey: const ValueKey('rider-vehicle-plate'),
                  label: 'Plate',
                  value: _value(current.registrationPlate),
                ),
                _DetailRow(
                  fieldKey: const ValueKey('rider-vehicle-seats'),
                  label: 'Seats',
                  value: current.seatCapacity?.toString() ?? unavailableLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.fieldKey,
    required this.label,
    required this.value,
  });

  final ValueKey<String> fieldKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final valueWidget = Text(
          value,
          key: fieldKey,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
          softWrap: true,
        );
        if (constraints.maxWidth < 340) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpacing.xxs),
                valueWidget,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(label, style: theme.textTheme.bodySmall),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(flex: 3, child: valueWidget),
            ],
          ),
        );
      },
    );
  }
}

String _value(String? value) {
  final normalized = _optionalText(value, 'displayValue', 2048);
  return normalized ?? RiderDriverVehicleDetailsCard.unavailableLabel;
}

String? _optionalText(
  String? value,
  String name,
  int maximumLength, {
  int minimumLength = 1,
}) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty || isCanonicalTripId(trimmed)) {
    return null;
  }
  if (trimmed.length < minimumLength || trimmed.length > maximumLength) {
    throw ArgumentError(
      '$name must contain $minimumLength to $maximumLength characters after trimming.',
    );
  }
  return trimmed;
}
