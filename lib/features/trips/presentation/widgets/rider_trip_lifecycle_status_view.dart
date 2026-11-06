import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';

/// Displays only the verified canonical status contained in a lifecycle state.
///
/// This view deliberately does not expose Trip details. Stale and unavailable
/// states cannot fall back to a previously verified status or Trip data.
class RiderTripLifecycleStatusView extends StatelessWidget {
  const RiderTripLifecycleStatusView({
    super.key,
    required this.state,
  });

  final RiderTripLifecycleState state;

  @override
  Widget build(BuildContext context) {
    final status = switch (state.phase) {
      RiderTripLifecyclePhase.verified ||
      RiderTripLifecyclePhase.terminal =>
        state.trip?.status,
      RiderTripLifecyclePhase.loading ||
      RiderTripLifecyclePhase.stale ||
      RiderTripLifecyclePhase.unavailable =>
        null,
    };
    final copy = _copyFor(state.phase, status);
    final theme = Theme.of(context);

    return Semantics(
      container: true,
      liveRegion: true,
      label: copy.semanticLabel,
      child: ExcludeSemantics(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(copy.title, style: theme.textTheme.titleLarge),
                if (copy.description case final description?) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

_TripStatusCopy _copyFor(
  RiderTripLifecyclePhase phase,
  DriverTripLifecycleStatus? status,
) {
  return switch ((phase, status)) {
    (RiderTripLifecyclePhase.loading, _) =>
      const _TripStatusCopy('Checking trip status'),
    (RiderTripLifecyclePhase.stale, _) =>
      const _TripStatusCopy('Verifying current trip status'),
    (RiderTripLifecyclePhase.unavailable, _) =>
      const _TripStatusCopy('Trip status unavailable'),
    (RiderTripLifecyclePhase.verified, DriverTripLifecycleStatus.accepted) =>
      const _TripStatusCopy('Trip accepted'),
    (
      RiderTripLifecyclePhase.verified,
      DriverTripLifecycleStatus.driverArriving
    ) =>
      const _TripStatusCopy('Driver arriving'),
    (
      RiderTripLifecyclePhase.verified,
      DriverTripLifecycleStatus.driverArrived
    ) =>
      const _TripStatusCopy('Driver arrived'),
    (RiderTripLifecyclePhase.verified, DriverTripLifecycleStatus.inProgress) =>
      const _TripStatusCopy('Trip in progress'),
    (RiderTripLifecyclePhase.terminal, DriverTripLifecycleStatus.completed) =>
      const _TripStatusCopy(
        'Trip completed',
        description: 'Trip completion does not confirm payment or receipt.',
      ),
    (
      RiderTripLifecyclePhase.terminal,
      DriverTripLifecycleStatus.cancelledByRider
    ) =>
      const _TripStatusCopy('Trip cancelled by rider'),
    (
      RiderTripLifecyclePhase.terminal,
      DriverTripLifecycleStatus.cancelledByDriver
    ) =>
      const _TripStatusCopy('Trip cancelled by driver'),
    (
      RiderTripLifecyclePhase.terminal,
      DriverTripLifecycleStatus.cancelledByAdmin
    ) =>
      const _TripStatusCopy('Trip cancelled by admin'),
    (RiderTripLifecyclePhase.terminal, DriverTripLifecycleStatus.failed) =>
      const _TripStatusCopy('Trip failed'),
    (RiderTripLifecyclePhase.verified || RiderTripLifecyclePhase.terminal, _) =>
      const _TripStatusCopy('Trip status unavailable'),
  };
}

class _TripStatusCopy {
  const _TripStatusCopy(this.title, {this.description});

  final String title;
  final String? description;

  String get semanticLabel => switch (description) {
        final description? => '$title. $description',
        null => title,
      };
}
