import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/models/fare_lock_recovery.dart';
import 'package:ridex/core/models/pending_fare_lock.dart';
import 'package:ridex/core/models/route_models.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/route_providers.dart';
import 'package:ridex/core/repositories/fare_repository.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/fare_summary_card.dart';
import 'package:ridex/core/widgets/route_timeline.dart';
import 'package:ridex/core/widgets/route_status_panel.dart';
import 'package:ridex/core/widgets/vehicle_silhouette.dart';
import 'package:ridex/core/widgets/google_maps_attribution.dart';

/// Provisional backend vehicle-type codes (`public.vehicle_type_code`).
///
/// The local demo catalogue uses `economy`/`standard`/`premium`; the backend
/// contract uses `economy`/`comfort`/`xl`. Unknown ids pass through and the
/// backend rejects them honestly.
String _backendVehicleTypeCode(String id) {
  return switch (id) {
    'economy' => 'economy',
    'standard' => 'comfort',
    'premium' => 'xl',
    _ => id,
  };
}

/// The draft carries no payment selection yet; the screen displays `Cash`,
/// so draft persistence sends `cash` to match what is shown.
const _displayedPaymentMethod = 'cash';

String _fareFailureMessage(FareFailure failure) {
  return switch (failure) {
    FareFailure.mutationBlocked =>
      'Booking changes are paused. Check fare status before continuing.',
    FareFailure.versionConflict =>
      'The booking changed. Fare recovery is paused.',
    FareFailure.notFound => 'The booking draft was not found.',
    FareFailure.pricingUnavailable => 'Fares are unavailable right now.',
    FareFailure.unauthorized ||
    FareFailure.forbidden =>
      'Sign in again to see fares.',
    FareFailure.timedOut => 'The fare request timed out.',
    FareFailure.networkFailure => 'Could not reach the fare service.',
    FareFailure.expired => 'This fare quote expired. Request a new fare.',
    FareFailure.unavailable ||
    FareFailure.invalidResponse =>
      'Fares are unavailable right now.',
  };
}

String _expiryLabel(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  final hours = local.hour.toString().padLeft(2, '0');
  final minutes = local.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}

class FareEstimateScreen extends ConsumerStatefulWidget {
  const FareEstimateScreen({super.key});

  @override
  ConsumerState<FareEstimateScreen> createState() => _FareEstimateScreenState();
}

class _FareEstimateScreenState extends ConsumerState<FareEstimateScreen> {
  FareBookingRef? _booking;
  FareQuote? _quote;
  FareFailure? _failure;
  bool _loading = false;
  // True from the moment a lock request is sent until a definitive outcome
  // arrives: the commit outcome is unknown while the response is missing,
  // garbled, or otherwise unusable. The lock stays replayable with the
  // original identifiers and versions; draft updates and replacement quotes
  // are suppressed until it resolves, because they would abandon the
  // committed lock lineage.
  bool _lockUnresolved = false;
  // A conflict cannot establish whether an earlier lock committed. Without
  // a canonical read contract, retain this lineage and block all mutations.
  bool _bookingConflict = false;
  bool _lockSuspended = false;
  bool _canonicalRecovered = false;
  bool _handoffNavigation = false;
  String? _bookingOwnerId;
  String _requestKey = '';
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    // Same-user restoration: re-hydrate a persisted pending command when
    // the session is already authenticated (the controller also attempts
    // this on build for the session-still-loading case).
    Future<void>.microtask(() {
      if (mounted) {
        unawaited(
          ref
              .read(pendingFareLockControllerProvider.notifier)
              .restorePendingLock(),
        );
      }
    });
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  String _quoteKey(BookingDraft draft, RouteResult? result) {
    final stops = [
      for (final stop in draft.stops)
        '${stop.point.latitude},${stop.point.longitude},${stop.label}',
    ].join(';');
    return [
      draft.pickup?.point.latitude,
      draft.pickup?.point.longitude,
      draft.pickup?.label,
      draft.destination?.point.latitude,
      draft.destination?.point.longitude,
      draft.destination?.label,
      stops,
      draft.vehicleType?.id,
      _displayedPaymentMethod,
      result?.distanceMeters,
      result?.durationSeconds,
    ].join('|');
  }

  FareRouteLocation _fareLocation(RideLocation location) {
    return FareRouteLocation(
      latitude: location.point.latitude,
      longitude: location.point.longitude,
      label: location.label.trim().isEmpty ? null : location.label.trim(),
    );
  }

  Future<void> _refresh() async {
    if (!mounted ||
        _loading ||
        _lockUnresolved ||
        _bookingConflict ||
        _lockSuspended ||
        _canonicalRecovered ||
        ref.read(pendingFareLockControllerProvider) != null ||
        ref.read(pendingFareLockStorageBlockedProvider) ||
        (_bookingOwnerId != null && !_hasBookingOwner)) {
      return;
    }
    final session = ref.read(sessionControllerProvider);
    if (session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider) {
      return;
    }
    final draft = ref.read(bookingControllerProvider);
    final route = ref.read(routeControllerProvider);
    final result = route.resultFor(draft);
    final vehicle = draft.vehicleType;
    if (result == null || vehicle == null) return;
    setState(() {
      _bookingOwnerId = session.user!.id;
      _loading = true;
      _failure = null;
    });
    try {
      final repository = ref.read(fareRepositoryProvider);
      final pickup = _fareLocation(draft.pickup!);
      final destination = _fareLocation(draft.destination!);
      final stops = [
        for (final stop in draft.stops)
          FareStopInput(location: _fareLocation(stop), label: stop.label),
      ];
      final vehicleTypeCode = _backendVehicleTypeCode(vehicle.id);
      final FareBookingRef booking;
      final current = _booking;
      if (current == null) {
        booking = await repository.createBookingDraft(
          pickup: pickup,
          destination: destination,
          vehicleTypeCode: vehicleTypeCode,
          paymentMethod: _displayedPaymentMethod,
          stops: stops,
        );
      } else {
        // Updating the draft supersedes its `calculated` quotes
        // server-side, so every draft/route change re-quotes below.
        booking = await repository.updateBookingDraft(
          bookingRequestId: current.bookingRequestId,
          expectedBookingVersion: current.version,
          pickup: pickup,
          destination: destination,
          vehicleTypeCode: vehicleTypeCode,
          paymentMethod: _displayedPaymentMethod,
          stops: stops,
        );
      }
      if (!mounted || !_hasBookingOwner) return;
      // Draft persistence succeeds independently of quote retrieval. Retain
      // its new version even when Google/fare lookup fails, so Retry works.
      _booking = booking;
      final quote = await repository.fetchQuote(
        bookingRequestId: booking.bookingRequestId,
        expectedBookingVersion: booking.version,
        routeDistanceMeters: result.distanceMeters,
        routeDurationSeconds: result.durationSeconds,
      );
      if (!mounted || !_hasBookingOwner) return;
      _expiryTimer?.cancel();
      final remaining = quote.expiresAt.difference(DateTime.now());
      if (remaining > Duration.zero) {
        _expiryTimer = Timer(remaining, () {
          if (mounted) setState(() {});
        });
      }
      setState(() {
        _booking = booking;
        _quote = quote;
        _failure = null;
        _loading = false;
      });
    } on FareException catch (error) {
      if (!mounted || !_hasBookingOwner) return;
      setState(() {
        // Retain the identity; no safe canonical reconciliation is available.
        _bookingConflict = error.failure == FareFailure.versionConflict;
        _failure = error.failure;
        _loading = false;
      });
    }
  }

  bool get _hasBookingOwner {
    final session = ref.read(sessionControllerProvider);
    return _bookingOwnerId != null &&
        session.user?.id == _bookingOwnerId &&
        session.status == SessionStatus.authenticated &&
        session.role == RideRole.rider;
  }

  /// Stages the pending lock command and completes its persistence BEFORE
  /// the lock RPC is dispatched. Returns null without dispatching when the
  /// command cannot be attributed to the booking owner or persistence
  /// fails (a known non-commit). Re-saving an identical staged command
  /// preserves its original `createdAt` instead of minting a new identity.
  ///
  /// F3: ownership is rechecked after persistence completes. If the session
  /// changed, signed out, or lost rider ownership while persistence was
  /// pending, this returns null so callers never dispatch the Lock RPC.
  Future<PendingFareLock?> _tryStagePendingLock(
    FareBookingRef bookingRef,
    FareQuote quoteRef,
  ) async {
    final ownerId = _bookingOwnerId;
    if (ownerId == null) return null;
    if (!_hasBookingOwner) return null;
    final errorReporter = ref.read(appErrorReporterProvider);
    final existing = ref.read(pendingFareLockControllerProvider);
    final command = existing != null &&
            existing.bookingRequestId == bookingRef.bookingRequestId &&
            existing.expectedBookingVersion == bookingRef.version &&
            existing.fareQuoteId == quoteRef.id &&
            existing.expectedQuoteVersion == quoteRef.quoteVersion &&
            existing.riderId == ownerId
        ? existing
        : PendingFareLock(
            bookingRequestId: bookingRef.bookingRequestId,
            expectedBookingVersion: bookingRef.version,
            fareQuoteId: quoteRef.id,
            expectedQuoteVersion: quoteRef.quoteVersion,
            riderId: ownerId,
            status: PendingLockRecoveryStatus.uncertain,
            createdAt: DateTime.now().toUtc(),
          );
    try {
      await ref
          .read(pendingFareLockControllerProvider.notifier)
          .stageForDispatch(command);
    } on Object catch (error, stackTrace) {
      errorReporter.report(
        operation: 'staging the pending fare lock',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    // Ownership may have changed while persistence was pending. Never hand
    // a stale command back for RPC dispatch into another session.
    if (!mounted || !_hasBookingOwner) return null;
    final session = ref.read(sessionControllerProvider);
    if (session.user?.id != command.riderId) return null;
    return command;
  }

  void _recordLockFailure(FareFailure failure, {required bool replay}) {
    // A rejected replay says nothing about the original request's outcome.
    final uncertain = replay ||
        failure == FareFailure.networkFailure ||
        failure == FareFailure.timedOut ||
        failure == FareFailure.invalidResponse ||
        failure == FareFailure.unavailable;
    _lockUnresolved = uncertain;
    _bookingConflict = failure == FareFailure.versionConflict;
    _lockSuspended = uncertain &&
        failure != FareFailure.networkFailure &&
        failure != FareFailure.timedOut &&
        failure != FareFailure.invalidResponse &&
        failure != FareFailure.unavailable;
    _failure = failure;
    _loading = false;
  }

  /// Replays an unresolved lock with its original booking and quote
  /// identifiers and versions, without replacing the quote.
  ///
  /// Migration 026 returns the linked locked row for exactly this replay.
  /// A rejected replay remains unresolved and may require canonical recovery.
  Future<void> _retryLock() async {
    final booking = _booking;
    final quote = _quote;
    if (!mounted ||
        _loading ||
        !_lockUnresolved ||
        _bookingConflict ||
        _lockSuspended ||
        !_hasBookingOwner ||
        booking == null ||
        quote == null) {
      return;
    }
    // A stale retry tap after the replay already locked must not re-issue
    // the request.
    if (quote.status == FareQuoteStatus.locked) return;
    setState(() {
      _loading = true;
      _failure = null;
      // The commit outcome is unknown from the moment the request is sent.
      _lockUnresolved = true;
    });
    // Durability first: a persistence failure is a known non-commit, so
    // the request is never dispatched and uncertainty is left untouched.
    // F3: _tryStagePendingLock already rechecks ownership after persistence;
    // recheck again here immediately before the potentially committing RPC
    // so a session change during staging can never dispatch.
    final staged = await _tryStagePendingLock(booking, quote);
    if (!mounted || !_hasBookingOwner) return;
    if (staged == null) {
      setState(() {
        _failure = FareFailure.unavailable;
        _loading = false;
      });
      return;
    }
    if (!_hasBookingOwner) return;
    try {
      final repository = ref.read(fareRepositoryProvider);
      final locked = await repository.lockQuote(
        bookingRequestId: booking.bookingRequestId,
        fareQuoteId: quote.id,
        expectedBookingVersion: booking.version,
        expectedQuoteVersion: quote.quoteVersion,
      );
      if (!mounted || !_hasBookingOwner) return;
      setState(() {
        _quote = locked;
        // The committed lock bumps the booking version server-side
        // (see 026); retain it so later draft updates use the fresh
        // version instead of conflicting.
        _booking = FareBookingRef(
          bookingRequestId: booking.bookingRequestId,
          version: booking.version + 1,
        );
        _lockUnresolved = false;
        _loading = false;
      });
      // Keep the command: neither lock success nor booking confirmation
      // authorizes replacement before approved lifecycle cleanup.
    } on FareException catch (error) {
      if (!mounted || !_hasBookingOwner) return;
      setState(() {
        _recordLockFailure(error.failure, replay: true);
      });
    }
  }

  /// Read-only reconciliation also works after the original widget is gone.
  /// A recovered fare belongs to the original booking, not the current draft.
  Future<void> _checkCanonicalLock() async {
    if (!mounted || _loading) return;
    final session = ref.read(sessionControllerProvider);
    if (session.status != SessionStatus.authenticated ||
        session.role != RideRole.rider) {
      return;
    }
    setState(() {
      _loading = true;
    });
    final result = await ref
        .read(pendingFareLockControllerProvider.notifier)
        .recoverCanonically();
    if (!mounted) return;
    final current = ref.read(sessionControllerProvider);
    if (result == null ||
        current.user?.id != result.command.riderId ||
        current.status != SessionStatus.authenticated ||
        current.role != RideRole.rider) {
      setState(() {
        _loading = false;
      });
      // A retry may have repaired storage readiness without finding a command.
      // The repository gate rechecks storage before any dispatch.
      if (result == null &&
          current.status == SessionStatus.authenticated &&
          current.role == RideRole.rider &&
          ref.read(pendingFareLockControllerProvider) == null &&
          !ref.read(pendingFareLockStorageBlockedProvider)) {
        setState(() {
          _bookingConflict = false;
          _failure = null;
        });
        unawaited(_refresh());
      }
      return;
    }
    // An original RPC may have completed while a read was in flight. An
    // uncertain snapshot must not replace its definitive locked response.
    if (_quote?.status == FareQuoteStatus.locked &&
        result.status != FareLockRecoveryStatus.confirmed) {
      setState(() {
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = false;
      if (result.status == FareLockRecoveryStatus.confirmed) {
        _bookingOwnerId = result.command.riderId;
        _booking = FareBookingRef(
            bookingRequestId: result.booking!.id,
            version: result.booking!.version);
        _quote = result.quote;
        _canonicalRecovered = true;
        _lockUnresolved = false;
        _bookingConflict = false;
        _lockSuspended = false;
        _failure = null;
      } else {
        _lockUnresolved = true;
        _bookingConflict = true;
        _lockSuspended = result.status == FareLockRecoveryStatus.suspended;
        _failure = result.failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingControllerProvider);
    final route = ref.watch(routeControllerProvider);
    final vehicle = draft.vehicleType;
    final session = ref.watch(sessionControllerProvider);
    final rider = session.user;
    final repository = ref.watch(fareRepositoryProvider);
    // Demo mode keeps the current deterministic demo fare path; the
    // authoritative backend-quote path below only runs when a real fare
    // repository is configured.
    final isDemo = repository is UnavailableFareRepository;
    final ownerAvailable = _bookingOwnerId == null ||
        (session.user?.id == _bookingOwnerId &&
            session.status == SessionStatus.authenticated &&
            session.role == RideRole.rider);
    // F4: unresolved storage corruption blocks recovery without exposing raw
    // records. The flag is per-rider and re-derived on session changes.
    final storageBlocked = ref.watch(pendingFareLockStorageBlockedProvider);
    final pending = ref.watch(pendingFareLockControllerProvider);
    final recoveryBlocked =
        _bookingConflict || _lockSuspended || !ownerAvailable || storageBlocked;

    final result = route.resultFor(draft);
    final routeReady =
        draft.isRoutingReady && route.isReadyFor(draft) && result != null;

    if (!isDemo && routeReady && vehicle != null) {
      final key = _quoteKey(draft, result);
      // While a lock is unresolved, never issue draft updates or
      // replacement quotes behind the rider's back; the pending lock must
      // replay first so the committed lineage is preserved. While blocked
      // on a conflict, canonical reconciliation is required before proceeding.
      if (key != _requestKey &&
          !_loading &&
          !_lockUnresolved &&
          pending == null &&
          !_canonicalRecovered &&
          !recoveryBlocked) {
        _requestKey = key;
        // A changed draft/route invalidates the displayed quote: never show
        // a stale total while the re-quote is in flight.
        _quote = null;
        _failure = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
      }
    }

    final demoFare =
        draft.estimatedFare > 0 ? draft.estimatedFare : vehicle?.baseFare ?? 0;
    final now = DateTime.now();
    // Only the quote fetched for the currently displayed draft/route may
    // back the total; anything else is stale and never shown.
    final quote = (!isDemo &&
            ownerAvailable &&
            (_canonicalRecovered ||
                _quote?.status == FareQuoteStatus.locked ||
                _requestKey == _quoteKey(draft, result)))
        ? _quote
        : null;
    final lockedQuote = quote?.status == FareQuoteStatus.locked;
    final usableQuote =
        quote != null && (lockedQuote || quote.isUsableAt(now)) ? quote : null;
    final staleQuote =
        quote != null && usableQuote == null && _failure == null && !_loading;
    final ready = isDemo
        ? draft.isRoutingReady &&
            route.isReadyFor(draft) &&
            vehicle != null &&
            demoFare > 0
        : routeReady &&
            vehicle != null &&
            usableQuote != null &&
            !lockedQuote &&
            !_loading &&
            !_lockUnresolved &&
            pending == null &&
            !recoveryBlocked &&
            _failure == null;

    return PopScope(
      // Leaving mid-lock would orphan a possibly-committed lock lineage
      // that this screen can no longer replay. Ordinary navigation stays
      // available at every other time.
      canPop: !_lockUnresolved,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted && _lockUnresolved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Waiting for the fare lock to resolve…'),
            ),
          );
        }
      },
      child: AppScaffold(
        title: 'Review booking',
        body: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inverseSurface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR ROUTE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onInverseSurface,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Theme(
                    data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.apply(
                            bodyColor:
                                Theme.of(context).colorScheme.onInverseSurface,
                            displayColor:
                                Theme.of(context).colorScheme.onInverseSurface,
                          ),
                    ),
                    child: RouteTimeline(
                      pickup: RouteTimelineStop(
                        title: draft.pickup?.address ?? 'Pickup not selected',
                        subtitle: draft.pickup?.label,
                      ),
                      destination: RouteTimelineStop(
                        title: draft.destination?.address ??
                            'Destination not selected',
                        subtitle: draft.destination?.label,
                      ),
                      stops: [
                        for (final stop in draft.stops)
                          RouteTimelineStop(
                            title: stop.address,
                            subtitle: stop.label,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (draft.pickup?.providerName == 'google' ||
                draft.destination?.providerName == 'google')
              const Align(
                alignment: Alignment.centerRight,
                child: GoogleMapsAttribution(),
              ),
            const SizedBox(height: AppSpacing.xl),
            RouteStatusPanel(
              state: route,
              onRetry: () => ref.read(routeControllerProvider.notifier).retry(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Ride details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const VehicleSilhouette(width: 72, height: 42),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vehicle?.name ?? 'No ride selected',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                vehicle == null
                                    ? 'Return to choose a ride'
                                    : 'Arrives in ${vehicle.arrivalMinutes} min · ${vehicle.capacity} passengers',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.xl),
                    _SummaryRow(
                      label: 'Passenger',
                      value: rider?.name ?? 'Demo rider',
                    ),
                    const _SummaryRow(label: 'Payment', value: 'Cash'),
                    const _SummaryRow(
                      label: 'Location status',
                      value: 'Pickup and destination selected',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (isDemo)
              FareSummaryCard(
                title: 'Demo fare',
                total: demoFare,
                note:
                    'Demo fare — a deterministic placeholder, not a backend quote. It stays fixed for the route shown.',
              )
            else if (_lockUnresolved ||
                recoveryBlocked ||
                (pending != null && !lockedQuote))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recoveryBlocked
                          ? 'Fare recovery blocked'
                          : 'Fare lock pending'),
                      const SizedBox(height: AppSpacing.sm),
                      Text(recoveryBlocked
                          ? 'We cannot confirm this booking. Changes are paused; '
                              'no replacement booking has been created.'
                          : 'The fare lock is not confirmed yet. Retry to check '
                              'the same booking before making changes.'),
                      if (ownerAvailable && _failure != null)
                        Text(_fareFailureMessage(_failure!)),
                      if (!_loading &&
                          (pending != null || storageBlocked) &&
                          session.status == SessionStatus.authenticated &&
                          session.role == RideRole.rider &&
                          repository is FareLockRecoveryRepository) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                            label: 'Check fare status',
                            onPressed: () => unawaited(_checkCanonicalLock())),
                      ],
                      if (!recoveryBlocked && !_loading) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppButton(
                          label: 'Retry fare lock',
                          onPressed: () => unawaited(_retryLock()),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (!_canonicalRecovered && (!routeReady || vehicle == null))
              Text(
                'Select a route and ride to request the authoritative fare.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else if (usableQuote != null && _failure == null)
              Column(children: [
                if (_canonicalRecovered)
                  const Text('Recovered the fare for your original booking. '
                      'Current route selections may differ.'),
                if (lockedQuote)
                  const Text('Your locked fare is protected. Review your '
                      'original booking to continue. Replacement remains paused.'),
                if (lockedQuote &&
                    !_canonicalRecovered &&
                    _requestKey != _quoteKey(draft, result))
                  const Text('This fare belongs to your original booking. '
                      'Current route selections may differ.'),
                _AuthoritativeFareCard(quote: usableQuote),
              ])
            else if (staleQuote)
              _ExpiredFareCard(
                onRequote: () {
                  if (!mounted ||
                      _loading ||
                      _lockUnresolved ||
                      _bookingConflict ||
                      _lockSuspended ||
                      ref.read(pendingFareLockStorageBlockedProvider) ||
                      !_hasBookingOwner ||
                      _quote?.id != quote.id ||
                      _quote?.quoteVersion != quote.quoteVersion ||
                      _quote?.status == FareQuoteStatus.locked) {
                    return;
                  }
                  final currentDraft = ref.read(bookingControllerProvider);
                  final currentRoute = ref.read(routeControllerProvider);
                  _requestKey = _quoteKey(
                      currentDraft, currentRoute.resultFor(currentDraft));
                  _quote = null;
                  _failure = null;
                  unawaited(_refresh());
                },
              )
            else if (_failure != null)
              _FareErrorCard(
                failure: _failure!,
                onRetry: () {
                  // Idempotent at the UI-state level: a retained stale callback
                  // never issues work while another attempt is in flight and
                  // never discards a confirmed locked quote.
                  if (!mounted ||
                      _loading ||
                      _lockUnresolved ||
                      _bookingConflict ||
                      _lockSuspended ||
                      ref.read(pendingFareLockStorageBlockedProvider) ||
                      !_hasBookingOwner ||
                      _failure == null) {
                    return;
                  }
                  if (_quote?.status == FareQuoteStatus.locked) return;
                  // Re-read live state: a retained callback must not reuse a
                  // stale draft or route snapshot.
                  final currentDraft = ref.read(bookingControllerProvider);
                  final currentRoute = ref.read(routeControllerProvider);
                  _requestKey = _quoteKey(
                    currentDraft,
                    currentRoute.resultFor(currentDraft),
                  );
                  _quote = null;
                  _failure = null;
                  unawaited(_refresh());
                },
              )
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text('Requesting the authoritative fare…'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Unsupported route changes must be confirmed before requesting a driver.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: isDemo
                  ? 'Confirm & find a driver'
                  : lockedQuote
                      ? 'Fare locked'
                      : _loading
                          ? 'Please wait...'
                          : 'Lock fare',
              onPressed: ready
                  ? () async {
                      if (isDemo) {
                        await ref
                            .read(bookingControllerProvider.notifier)
                            .estimateFare();
                        if (context.mounted) context.push('/rider/searching');
                        return;
                      }

                      final booking = _booking;
                      final currentQuote = usableQuote;
                      if (!mounted ||
                          _loading ||
                          _lockUnresolved ||
                          _bookingConflict ||
                          _lockSuspended ||
                          !_hasBookingOwner ||
                          _failure != null ||
                          booking == null ||
                          currentQuote == null) {
                        return;
                      }
                      // Rapid taps can reuse a stale closure before the rebuild
                      // lands: re-check live state so a second lock is never
                      // issued for an already-locked or already-replaced quote.
                      final liveQuote = _quote;
                      if (liveQuote == null ||
                          liveQuote.id != currentQuote.id ||
                          liveQuote.status == FareQuoteStatus.locked) {
                        return;
                      }
                      if (!currentQuote.isUsableAt(DateTime.now())) {
                        setState(() => _failure = FareFailure.expired);
                        return;
                      }
                      setState(() {
                        _loading = true;
                        _failure = null;
                        // The commit outcome is unknown from the moment the
                        // request is sent.
                        _lockUnresolved = true;
                      });
                      // Durability first: persistence completes before the
                      // potentially committing RPC. A persistence failure is
                      // a known non-commit, so nothing is dispatched and
                      // uncertainty is NOT recorded. F3: recheck ownership
                      // immediately before the committing RPC.
                      final staged = await _tryStagePendingLock(
                        booking,
                        currentQuote,
                      );
                      if (!mounted || !_hasBookingOwner) return;
                      if (staged == null) {
                        setState(() {
                          _failure = FareFailure.unavailable;
                          _loading = false;
                          _lockUnresolved = false;
                        });
                        return;
                      }
                      if (!_hasBookingOwner) return;
                      try {
                        final locked = await repository.lockQuote(
                          bookingRequestId: booking.bookingRequestId,
                          fareQuoteId: currentQuote.id,
                          expectedBookingVersion: booking.version,
                          expectedQuoteVersion: currentQuote.quoteVersion,
                        );
                        if (!mounted || !_hasBookingOwner) return;
                        setState(() {
                          _quote = locked;
                          // The committed lock bumps the booking version
                          // server-side (see 026); retain it so later draft
                          // updates use the fresh version instead of
                          // conflicting.
                          _booking = FareBookingRef(
                            bookingRequestId: booking.bookingRequestId,
                            version: booking.version + 1,
                          );
                          _lockUnresolved = false;
                          _loading = false;
                        });
                        // Retain protection through booking confirmation.
                        // Real matching is Phase 7. Do not pass a backend quote
                        // into the deterministic MockTrips search flow.
                      } on FareException catch (error) {
                        if (!mounted || !_hasBookingOwner) return;
                        setState(() {
                          _recordLockFailure(error.failure, replay: false);
                        });
                      }
                    }
                  : null,
            ),
            if (!isDemo) ...[
              for (final reference
                  in ref.watch(confirmedBookingReferencesProvider))
                if (reference.command.riderId == session.user?.id)
                  AppButton(
                      label:
                          'View confirmed booking ${reference.command.bookingRequestId}',
                      onPressed: () => context.push<void>(Uri(
                              path: '/rider/confirmation',
                              queryParameters: {
                                'booking': reference.command.bookingRequestId
                              }).toString())),
              if (pending != null &&
                  pending.riderId == session.user?.id &&
                  session.status == SessionStatus.authenticated &&
                  session.role == RideRole.rider &&
                  repository is BookingConfirmationRepository)
                AppButton(
                    label: 'Review original booking',
                    onPressed: () async {
                      if (!mounted ||
                          _handoffNavigation ||
                          !identical(
                              ref.read(sessionControllerProvider), session) ||
                          ref
                                  .read(pendingFareLockControllerProvider)
                                  ?.hasSameLockIdentity(pending) !=
                              true) {
                        return;
                      }
                      _handoffNavigation = true;
                      try {
                        await context.push<void>('/rider/confirmation');
                      } finally {
                        if (mounted) _handoffNavigation = false;
                      }
                    }),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'You can review and confirm your original locked booking. Live driver matching is not '
                'available yet; no driver request or payment is made here.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthoritativeFareCard extends StatelessWidget {
  const _AuthoritativeFareCard({required this.quote});

  final FareQuote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = quote.breakdown;
    return Semantics(
      container: true,
      label: 'Upfront fare, total ${formatFareFils(quote.fixedFareFils)}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Upfront fare', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              _FareFilsRow(
                  label: 'Base fare',
                  value: formatFareFils(breakdown.baseFareFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Distance',
                  value: formatFareFils(breakdown.distanceFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Duration',
                  value: formatFareFils(breakdown.durationFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Stops', value: formatFareFils(breakdown.stopsFils)),
              const SizedBox(height: AppSpacing.xs),
              _FareFilsRow(
                  label: 'Subtotal',
                  value: formatFareFils(breakdown.subtotalFils)),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: Text('Total', style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    formatFareFils(quote.fixedFareFils),
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Fixed fare · Quote v${quote.quoteVersion} · '
                'Pricing v${quote.pricingVersion} · '
                '${quote.status == FareQuoteStatus.locked ? 'Locked' : 'Expires ${_expiryLabel(quote.expiresAt)}'}'
                '${breakdown.minimumApplied ? ' · Minimum fare applied' : ''} · '
                'Rounded to the nearest ${breakdown.roundingIncrementFils} fils.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpiredFareCard extends StatelessWidget {
  const _ExpiredFareCard({required this.onRequote});

  final VoidCallback onRequote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fare quote expired', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'This quote is no longer valid, so no total is shown. '
              'Request a new fare to continue.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Request a new fare', onPressed: onRequote),
          ],
        ),
      ),
    );
  }
}

class _FareErrorCard extends StatelessWidget {
  const _FareErrorCard({
    required this.failure,
    required this.onRetry,
  });

  final FareFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fare unavailable', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(_fareFailureMessage(failure)),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Retry fare request', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _FareFilsRow extends StatelessWidget {
  const _FareFilsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}
