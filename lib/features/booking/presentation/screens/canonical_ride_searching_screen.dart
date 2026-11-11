import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/rider_booking_cancellation.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/rider_cancellation_providers.dart';
import 'package:ridex/core/providers/rider_booking_integration_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/models/rider_matching_request.dart';
import 'package:ridex/core/models/rider_assigned_trip.dart';
import 'package:ridex/features/booking/application/rider_booking_integration_gate.dart';
import 'package:ridex/core/repositories/rider_booking_search_repository.dart';
import 'package:ridex/core/repositories/rider_trip_tracking_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_dialog.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/features/booking/application/rider_search_controller.dart';

/// Canonical Cash searching surface. Production routing remains behind the
/// compile-time integration gate.
class CanonicalRideSearchingScreen extends ConsumerStatefulWidget {
  const CanonicalRideSearchingScreen({
    super.key,
    required this.bookingRequestId,
    this.repository,
    this.tripTrackingRepository,
    this.matchingRepository,
    this.readConfirmedReference,
    this.onAssignmentVerified,
    this.allowAutomaticMatching = true,
    this.softTimeout = const Duration(seconds: 90),
    this.readDeadline = const Duration(seconds: 15),
  });

  final String bookingRequestId;
  final RiderBookingSearchRepository? repository;
  final RiderTripTrackingRepository? tripTrackingRepository;
  final RiderMatchingRequestRepository? matchingRepository;
  final ConfirmedBookingReference? Function()? readConfirmedReference;
  final ValueChanged<RiderAssignedTrip>? onAssignmentVerified;
  final bool allowAutomaticMatching;
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
  Route<dynamic>? _cancellationDialogRoute;
  NavigatorState? _cancellationDialogNavigator;
  String? _navigatedTripId;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController({bool? automaticallyStartMatching}) {
    final session = ref.read(sessionControllerProvider);
    _controllerSession = session;
    final riderId = _eligibleRiderId(session);
    final allowed = riderId != null &&
        (_pinnedRiderId == null ||
            _pinnedRiderId!.toLowerCase() == riderId.toLowerCase());
    if (allowed) _pinnedRiderId ??= riderId;
    final controller = RiderSearchController(
      bookingRequestId: widget.bookingRequestId,
      repository: widget.repository ??
          ref.read(riderBookingSearchRepositoryProvider),
      cancellationCoordinator: ref.read(riderCancellationCoordinatorProvider),
      tripTrackingRepository: widget.tripTrackingRepository ??
          ref.read(riderTripTrackingRepositoryProvider),
      matchingRepository: widget.matchingRepository ??
          (riderCashMatchingIntegrationEnabled
              ? ref.read(riderMatchingRequestRepositoryProvider)
              : null),
      readConfirmedReference: widget.readConfirmedReference ??
          () => _confirmedReferenceFor(ref, widget.bookingRequestId),
      automaticallyStartMatching:
          automaticallyStartMatching ?? widget.allowAutomaticMatching,
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
        !identical(
            oldWidget.tripTrackingRepository, widget.tripTrackingRepository) ||
        !identical(oldWidget.matchingRepository, widget.matchingRepository) ||
        !identical(oldWidget.readConfirmedReference,
            widget.readConfirmedReference) ||
        !identical(oldWidget.onAssignmentVerified,
            widget.onAssignmentVerified) ||
        oldWidget.softTimeout != widget.softTimeout ||
        oldWidget.readDeadline != widget.readDeadline ||
        oldWidget.allowAutomaticMatching != widget.allowAutomaticMatching) {
      _dismissCancellationDialog();
      _controller.dispose();
      if (bookingChanged) _pinnedRiderId = null;
      if (bookingChanged) _navigatedTripId = null;
      _createController();
    }
  }

  @override
  void dispose() {
    _dismissCancellationDialog();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirmCancellation() async {
    final controller = _controller;
    Route<dynamic>? openedRoute;
    final reason = await _showCancellationReasonDialog(
      context,
      onOpened: (dialogContext) {
        openedRoute = ModalRoute.of(dialogContext);
        _cancellationDialogRoute = openedRoute;
        _cancellationDialogNavigator =
            Navigator.of(dialogContext, rootNavigator: true);
      },
      onClosing: () {
        if (openedRoute != null &&
            identical(_cancellationDialogRoute, openedRoute)) {
          _cancellationDialogRoute = null;
          _cancellationDialogNavigator = null;
        }
      },
    );
    if (openedRoute != null &&
        identical(_cancellationDialogRoute, openedRoute)) {
      _cancellationDialogRoute = null;
      _cancellationDialogNavigator = null;
    }
    if (!mounted || !identical(controller, _controller) || reason == null) {
      return;
    }
    unawaited(controller.cancelBooking(reasonCode: reason));
  }

  void _dismissCancellationDialog() {
    final route = _cancellationDialogRoute;
    final navigator = _cancellationDialogNavigator;
    _cancellationDialogRoute = null;
    _cancellationDialogNavigator = null;
    if (route == null || navigator == null) return;
    Future<void>.microtask(() {
      if (navigator.mounted &&
          route.isActive &&
          identical(route.navigator, navigator)) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (previous, next) {
      if (identical(next, _controllerSession)) return;
      _dismissCancellationDialog();
      _controller.sessionChanged(next);
      final riderId = _eligibleRiderId(next);
      if (riderId != null &&
          (_pinnedRiderId == null ||
              _pinnedRiderId!.toLowerCase() == riderId.toLowerCase())) {
        _controller.dispose();
        setState(() => _createController(automaticallyStartMatching: false));
      }
    });
    return AppScaffold(
      title: 'Booking search status',
      showBack: false,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final state = _controller.state;
          _scheduleVerifiedNavigation(state);
          final (title, message) = _copyFor(
            state.phase,
            assignmentVerified:
                state.phase == RiderSearchPhase.assignmentPending &&
                    state.assignment == RiderAssignmentVerification.verified,
          );
          final cancellationCopy = _cancellationCopy(state);
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
              if (cancellationCopy != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    cancellationCopy.$1,
                    key: const ValueKey('canonical-search-cancellation'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(cancellationCopy.$2),
              ],
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
              if (state.phase == RiderSearchPhase.noCandidates ||
                  state.matchingFailure != null ||
                  _controller.canRetryMatching) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_matchingMessage(state)),
                AppButton(
                  key: const ValueKey('canonical-matching-retry'),
                  label: state.phase == RiderSearchPhase.noCandidates
                      ? 'Check candidates again'
                      : 'Continue matching',
                  variant: AppButtonVariant.secondary,
                  onPressed: _controller.canRetryMatching
                      ? () => unawaited(_controller.retryMatching())
                      : null,
                ),
              ],
              if (state.matchingInProgress) ...[
                const SizedBox(height: AppSpacing.sm),
                const Text('Matching request is pending. Check the canonical booking status; it will not be resent automatically.'),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('canonical-search-cancel'),
                label: 'Cancel booking',
                destructive: true,
                onPressed: _controller.canCancel
                    ? () => unawaited(_confirmCancellation())
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('canonical-search-assignment'),
                label: _assignmentLabel(state),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                key: const ValueKey('canonical-search-back'),
                label: 'Back to booking',
                variant: AppButtonVariant.secondary,
                onPressed: ModalRoute.of(context)?.isCurrent == true &&
                        Navigator.of(context).canPop()
                    ? () {
                        final route = ModalRoute.of(context);
                        final navigator = Navigator.of(context);
                        if (mounted &&
                            route?.isCurrent == true &&
                            identical(route?.navigator, navigator) &&
                            navigator.canPop()) {
                          navigator.pop();
                        }
                      }
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'This screen tracks the original Cash booking. It cannot create '
                'another booking or process a payment.',
              ),
            ],
          );
        },
      ),
    );
  }

  void _scheduleVerifiedNavigation(RiderSearchViewState state) {
    final trip = state.verifiedTrip;
    final callback = widget.onAssignmentVerified;
    if (trip == null || callback == null ||
        trip.tripId.toLowerCase() == _navigatedTripId?.toLowerCase() ||
        !identical(ref.read(sessionControllerProvider), _controllerSession) ||
        trip.bookingRequestId.toLowerCase() !=
            widget.bookingRequestId.toLowerCase() ||
        trip.riderId.toLowerCase() != _pinnedRiderId?.toLowerCase() ||
        trip.paymentMethod.name != 'cash') return;
    _navigatedTripId = trip.tripId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(ref.read(sessionControllerProvider),
          _controllerSession)) callback(trip);
    });
  }
}

ConfirmedBookingReference? _confirmedReferenceFor(
  WidgetRef ref,
  String bookingId,
) {
  final session = ref.read(sessionControllerProvider);
  final riderId = _eligibleRiderId(session);
  if (riderId == null) return null;
  for (final reference in ref.read(confirmedBookingReferencesProvider)) {
    if (reference.command.bookingRequestId.toLowerCase() ==
            bookingId.toLowerCase() &&
        reference.command.riderId.toLowerCase() == riderId.toLowerCase()) {
      return reference;
    }
  }
  return null;
}

String _matchingMessage(RiderSearchViewState state) {
  if (state.phase == RiderSearchPhase.noCandidates) {
    return 'No eligible Driver was returned for this attempt. The booking remains canonical and can be checked again.';
  }
  return switch (state.matchingFailure) {
    RiderMatchingFailure.conflict => 'The booking changed while matching. Check its canonical status before another attempt.',
    RiderMatchingFailure.invalidReference ||
    RiderMatchingFailure.invalidResponse => 'Matching could not verify this booking reference. No Trip navigation is available.',
    RiderMatchingFailure.unauthorized => 'This account is not authorized to request matching.',
    RiderMatchingFailure.unavailable || null => 'The matching result is unknown. Check this same booking; no automatic retry was sent.',
  };
}

Future<String?> _showCancellationReasonDialog(
  BuildContext context, {
  required void Function(BuildContext) onOpened,
  required void Function() onClosing,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      onOpened(dialogContext);
      var selected = riderCancellationReasonOptions.first;
      return StatefulBuilder(
        builder: (context, setState) {
          return AppDialog(
            title: 'Cancel this booking?',
            message: 'Choose a reason for cancelling this booking.',
            icon: Icons.close,
            destructive: true,
            confirmLabel: 'Cancel booking',
            cancelLabel: 'Keep booking',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final reason in riderCancellationReasonOptions)
                  RadioListTile<String>(
                    key: ValueKey('cancellation-reason-$reason'),
                    title: Text(reason),
                    value: reason,
                    groupValue: selected,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => selected = value);
                    },
                  ),
              ],
            ),
            onCancel: () {
              onClosing();
              Navigator.of(dialogContext).pop();
            },
            onConfirm: () {
              onClosing();
              Navigator.of(dialogContext).pop(selected);
            },
          );
        },
      );
    },
  );
}

String _assignmentLabel(RiderSearchViewState state) {
  if (state.phase != RiderSearchPhase.assignmentPending) {
    return 'Driver assignment unavailable';
  }
  return switch (state.assignment) {
    RiderAssignmentVerification.notRequested =>
      'Driver assignment pending verification',
    RiderAssignmentVerification.loading => 'Verifying assigned Trip',
    RiderAssignmentVerification.verified =>
      'Assignment verified. Driver details are not displayed in this slice.',
    RiderAssignmentVerification.unverified => 'No verified assigned Trip yet',
    RiderAssignmentVerification.unavailable =>
      'Assignment verification unavailable',
    RiderAssignmentVerification.invalid =>
      'Assigned Trip evidence could not be verified',
  };
}

(String, String)? _cancellationCopy(RiderSearchViewState state) {
  return switch (state.cancellation) {
    RiderCancellationPhase.idle => null,
    RiderCancellationPhase.cancelling => (
        'Cancelling booking',
        'Waiting for the booking service to confirm the cancellation.',
      ),
    RiderCancellationPhase.uncertain => (
        'Cancellation outcome unknown',
        'The request may or may not have been received. A new cancellation is '
            'not sent automatically. Check this same booking for an '
            'authoritative status.',
      ),
    RiderCancellationPhase.rejected => switch (state.rejection) {
        RiderCancellationRejection.staleVersion => (
            'Cancellation not sent',
            'The booking changed before the cancellation was accepted. Check '
                'the same booking, then try again if it is still cancellable.',
          ),
        RiderCancellationRejection.notCancellable => (
            'Cancellation no longer available',
            'The booking has already moved on. Check its current status.',
          ),
        RiderCancellationRejection.notFound => (
            'Booking not found for this Rider',
            'No cancellation was confirmed. Check the same booking.',
          ),
        RiderCancellationRejection.reasonInvalid => (
            'Cancellation reason rejected',
            'Choose a reason between 1 and 100 characters.',
          ),
        RiderCancellationRejection.blockedOrDenied => (
            'Cancellation not allowed',
            'This account or booking cannot be cancelled right now.',
          ),
        RiderCancellationRejection.backend || null => (
            'Cancellation failed',
            'The booking service did not confirm the cancellation. Check the '
                'same booking.',
          ),
      },
  };
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

(String, String) _copyFor(
  RiderSearchPhase phase, {
  required bool assignmentVerified,
}) =>
    switch (phase) {
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
      RiderSearchPhase.noCandidates => (
          'No Driver candidates yet',
          'The matching attempt found no eligible candidate. Your original confirmed booking remains in place.',
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
      RiderSearchPhase.assignmentPending => assignmentVerified
          ? (
              'Match reported',
              'An assigned Trip was verified for this original booking. '
                  'Driver details are not displayed in this slice.',
            )
          : (
              'Match reported',
              'An assigned Trip has not been verified. Driver details are unavailable.',
            ),
    };
