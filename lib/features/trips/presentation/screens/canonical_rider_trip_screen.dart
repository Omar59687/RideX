import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/rider_trip_cancellation.dart';
import 'package:ridex/core/models/rider_trip_lifecycle_state.dart';
import 'package:ridex/core/models/rider_trip_location.dart';
import 'package:ridex/core/providers/rider_booking_integration_providers.dart';
import 'package:ridex/core/providers/rider_trip_tracking_providers.dart';
import 'package:ridex/core/providers/trip_realtime_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_dialog.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/google_canonical_driver_map.dart';
import 'package:ridex/core/providers/session_providers.dart';

/// Cash-only canonical Rider Trip surface. Neither the route locators nor
/// Realtime payloads authorize display; the lifecycle controller rereads RLS.
class CanonicalRiderTripScreen extends ConsumerStatefulWidget {
  const CanonicalRiderTripScreen({
    super.key,
    required this.tripId,
    required this.bookingRequestId,
  });

  final String tripId;
  final String bookingRequestId;

  @override
  ConsumerState<CanonicalRiderTripScreen> createState() =>
      _CanonicalRiderTripScreenState();
}

class _CanonicalRiderTripScreenState
    extends ConsumerState<CanonicalRiderTripScreen> {
  Stream<RiderTripLocationUpdate>? _locationStream;
  String? _locationStreamKey;
  bool _cancelling = false;
  bool _rechecking = false;

  @override
  Widget build(BuildContext context) {
    if (!isCanonicalTripId(widget.tripId) ||
        !isCanonicalTripId(widget.bookingRequestId)) {
      return AppScaffold(
        title: 'Trip tracking',
        body: const Center(child: Text('Trip could not be verified.')),
      );
    }
    final request = RiderTripLifecycleRequest(
      tripId: widget.tripId,
      bookingRequestId: widget.bookingRequestId,
    );
    final state = ref.watch(riderTripLifecycleControllerProvider(request));
    final adapter = ref.watch(riderTripLocationAdapterProvider);
    final session = ref.watch(sessionControllerProvider);
    final streamKey = state.phase == RiderTripLifecyclePhase.verified &&
            state.trip != null &&
            adapter != null &&
            state.trip!.riderId.toLowerCase() == session.user?.id.toLowerCase()
        ? '${widget.tripId}:${state.trip!.driver.driverId}:${identityHashCode(adapter)}:${identityHashCode(session)}'
        : null;
    if (streamKey != _locationStreamKey) {
      _locationStreamKey = streamKey;
      _locationStream = streamKey == null || adapter == null
          ? null
          : adapter.watchTrip(widget.tripId);
    }

    final trip = state.trip;
    return AppScaffold(
      title: 'Trip tracking',
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.lg),
          Text(_lifecycleCopy(state)),
          if (state.phase == RiderTripLifecyclePhase.stale ||
              state.phase == RiderTripLifecyclePhase.unavailable)
            AppButton(
              label:
                  _rechecking ? 'Checking Trip status...' : 'Check Trip status',
              onPressed: _rechecking ? null : () => _recheck(request),
            ),
          if (trip != null && state.isVerified) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Trip ID: ${trip.tripId}'),
            Text('Trip status: ${trip.status.backendValue}'),
            Text('Cash booking: ${trip.bookingRequestId}'),
            Text('Trip version: ${trip.version}'),
            const SizedBox(height: AppSpacing.md),
            if (!trip.isTerminal && _locationStream != null)
              StreamBuilder<RiderTripLocationUpdate>(
                key: ValueKey(_locationStreamKey),
                stream: _locationStream,
                builder: (context, snapshot) {
                  final update = snapshot.hasError ? null : snapshot.data;
                  final location = update is RiderTripLocationSnapshot
                      ? update.location
                      : null;
                  if (location == null ||
                      location.tripId.toLowerCase() !=
                          trip.tripId.toLowerCase() ||
                      location.driverId.toLowerCase() !=
                          trip.driver.driverId.toLowerCase() ||
                      trip.riderId.toLowerCase() !=
                          session.user?.id.toLowerCase()) {
                    return const Text(
                        'Waiting for a fresh verified Driver location.');
                  }
                  return GoogleCanonicalDriverMap(
                    key: ValueKey(
                        'verified-driver-map-${trip.tripId}-${trip.driver.driverId}'),
                    location: location,
                  );
                },
              ),
            if (trip.status == DriverTripLifecycleStatus.accepted ||
                trip.status == DriverTripLifecycleStatus.driverArriving ||
                trip.status == DriverTripLifecycleStatus.driverArrived)
              AppButton(
                key: const ValueKey('canonical-trip-cancel'),
                label: _cancelling ? 'Cancelling trip' : 'Cancel trip',
                destructive: true,
                onPressed:
                    _cancelling ? null : () => _cancel(request, trip.version),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Return to Rider home',
            variant: AppButtonVariant.secondary,
            onPressed: () => context.go('/rider/home'),
          ),
        ],
      ),
    );
  }

  Future<void> _recheck(RiderTripLifecycleRequest request) async {
    if (_rechecking) return;
    setState(() => _rechecking = true);
    try {
      await ref
          .read(riderTripLifecycleControllerProvider(request).notifier)
          .refreshCanonically();
    } finally {
      if (mounted) setState(() => _rechecking = false);
    }
  }

  Future<void> _cancel(RiderTripLifecycleRequest request, int version) async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Cancel this trip?',
      message:
          'The assigned Trip will be cancelled through its canonical operation.',
      icon: Icons.warning_amber_rounded,
      confirmLabel: 'Cancel trip',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final tripId = widget.tripId;
    setState(() => _cancelling = true);
    final repository = ref.read(riderTripCancellationRepositoryProvider);
    final result = repository == null
        ? const RiderTripCancellationUnknown()
        : await repository.cancelTrip(
            tripId: tripId,
            expectedVersion: version,
            reasonCode: 'Changed my mind',
          );
    if (!mounted) return;
    setState(() => _cancelling = false);
    // Always reconcile canonical state after the RPC, including unknown races.
    ref.invalidate(riderTripLifecycleControllerProvider(request));
    if (result is RiderTripCancellationAccepted) {
      setState(() => _locationStream = null);
    }
  }
}

String _lifecycleCopy(RiderTripLifecycleState state) => switch (state.phase) {
      RiderTripLifecyclePhase.loading => 'Verifying your assigned Trip.',
      RiderTripLifecyclePhase.verified => 'Trip state is canonically verified.',
      RiderTripLifecyclePhase.stale =>
        'Trip state is being rechecked. Location is withheld.',
      RiderTripLifecyclePhase.unavailable =>
        'This Trip is unavailable or could not be authorized.',
      RiderTripLifecyclePhase.terminal =>
        'This Trip has ended. Driver location is cleared.',
    };
