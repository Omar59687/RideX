import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/features/booking/application/rider_search_controller.dart';

/// Standalone canonical surface. No production route or backend is wired yet.
class CanonicalRideSearchingScreen extends ConsumerStatefulWidget {
  const CanonicalRideSearchingScreen({
    super.key,
    required this.bookingRequestId,
    this.repository = const UnavailableRiderBookingSearchRepository(),
    this.softTimeout = const Duration(seconds: 90),
    this.readDeadline = const Duration(seconds: 15),
  });

  final String bookingRequestId;
  final RiderBookingSearchRepository repository;
  final Duration softTimeout;
  final Duration readDeadline;

  @override
  ConsumerState<CanonicalRideSearchingScreen> createState() =>
      _CanonicalRideSearchingScreenState();
}

class _CanonicalRideSearchingScreenState
    extends ConsumerState<CanonicalRideSearchingScreen> {
  late RiderSearchController _controller;
  late SessionState _controllerSession;
  String? _pinnedRiderId;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    final session = ref.read(sessionControllerProvider);
    _controllerSession = session;
    final riderId = _eligibleRiderId(session);
    final allowed = riderId != null &&
        (_pinnedRiderId == null ||
            _pinnedRiderId!.toLowerCase() == riderId.toLowerCase());
    if (allowed) _pinnedRiderId ??= riderId;
    final controller = RiderSearchController(
      bookingRequestId: widget.bookingRequestId,
      repository: widget.repository,
      readSession: () => ref.read(sessionControllerProvider),
      softTimeout: widget.softTimeout,
      readDeadline: widget.readDeadline,
    );
    _controller = controller;
    if (!allowed) {
      controller.invalidate();
      return;
    }
    Future<void>.microtask(() {
      if (mounted && identical(_controller, controller)) {
        unawaited(controller.refresh());
      }
    });
  }

  @override
  void didUpdateWidget(covariant CanonicalRideSearchingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bookingChanged =
        oldWidget.bookingRequestId != widget.bookingRequestId;
    if (bookingChanged ||
        !identical(oldWidget.repository, widget.repository) ||
        oldWidget.softTimeout != widget.softTimeout ||
        oldWidget.readDeadline != widget.readDeadline) {
      _controller.dispose();
      if (bookingChanged) _pinnedRiderId = null;
      _createController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (identical(next, _controllerSession)) return;
      _controller.sessionChanged(next);
      final riderId = _eligibleRiderId(next);
      if (riderId != null &&
          (_pinnedRiderId == null ||
              _pinnedRiderId!.toLowerCase() == riderId.toLowerCase())) {
        _controller.dispose();
        setState(_createController);
      }
    });
    return AppScaffold(
      title: 'Booking search status',
      showBack: false,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          final (title, message) = _copyFor(state.phase);
          final currentSession = ref.read(sessionControllerProvider);
          final riderId = _eligibleRiderId(currentSession);
          final booking = state.booking;
          final showVerified = !_controller.isSessionInvalidated &&
              identical(currentSession, _controllerSession) &&
              riderId != null &&
              riderId.toLowerCase() == _pinnedRiderId?.toLowerCase() &&
              booking != null &&
              booking.riderId.toLowerCase() == riderId.toLowerCase() &&
              booking.bookingRequestId.toLowerCase() ==
                  widget.bookingRequestId.toLowerCase();
          return ListView(
            children: [
              const SizedBox(height: AppSpacing.lg),
              Semantics(
                liveRegion: true,
                child: Text(
                  title,
                  key: const ValueKey('canonical-search-state'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(message),
              const SizedBox(height: AppSpacing.md),
              if (showVerified) ...[
                Text('Booking: ${booking.bookingRequestId}'),
                Text('Verified booking status: ${booking.status.backendValue}'),
              ],
              if (state.phase == RiderSearchPhase.loading) ...[
                const SizedBox(height: AppSpacing.md),
                const Center(child: CircularProgressIndicator()),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                key: const ValueKey('canonical-search-retry'),
                label: 'Check booking status',
                onPressed: _controller.canRetry
                    ? () => unawaited(_controller.refresh())
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              const AppButton(
                key: ValueKey('canonical-search-cancel'),
                label: 'Cancellation unavailable',
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('canonical-search-assignment'),
                label: state.phase == RiderSearchPhase.assignmentPending
                    ? 'Driver assignment pending verification'
                    : 'Driver assignment unavailable',
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'Cancellation and Driver details require separately verified '
                'backend capabilities. No new booking or payment is created here.',
              ),
            ],
          );
        },
      ),
    );
  }
}

String? _eligibleRiderId(SessionState session) {
  final user = session.user;
  if (session.status != SessionStatus.authenticated ||
      session.role != RideRole.rider ||
      user == null ||
      user.isBlocked ||
      !isCanonicalTripId(user.id)) {
    return null;
  }
  return user.id;
}

(String, String) _copyFor(RiderSearchPhase phase) => switch (phase) {
      RiderSearchPhase.loading => (
          'Checking your booking',
          'Verifying the original booking status.',
        ),
      RiderSearchPhase.waiting => (
          'Waiting for matching',
          'Your Cash booking is confirmed. Matching has not yet started.',
        ),
      RiderSearchPhase.searching => (
          'Searching for a driver',
          'Your original booking is being matched. Driver assignment is unverified.',
        ),
      RiderSearchPhase.timedOut => (
          'Taking longer than expected',
          'This is a display timeout only. Check the same booking for its status.',
        ),
      RiderSearchPhase.unresolved => (
          'Booking status unresolved',
          'We could not verify your original booking. No new request was made.',
        ),
      RiderSearchPhase.unavailable => (
          'Booking status unavailable',
          'A read failure left the outcome unknown. Check the same booking again.',
        ),
      RiderSearchPhase.expired => (
          'Search expired',
          'The original booking expired. No new booking was created.',
        ),
      RiderSearchPhase.failed => (
          'Search failed',
          'The original booking failed. Driver availability was not verified.',
        ),
      RiderSearchPhase.cancelled => (
          'Booking cancelled',
          'Cancellation was verified from the original booking status.',
        ),
      RiderSearchPhase.assignmentPending => (
          'Match reported',
          'An assigned Trip has not been verified. Driver details are unavailable.',
        ),
    };
