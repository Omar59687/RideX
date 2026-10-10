import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/booking_handoff.dart';
import 'package:ridex/core/models/fare_quote.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/providers/diagnostics_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

/// Real booking confirmation stops here; it never enters Mock trip matching.
class BookingConfirmationScreen extends ConsumerStatefulWidget {
  const BookingConfirmationScreen({super.key, this.bookingRequestId});
  final String? bookingRequestId;
  @override
  ConsumerState<BookingConfirmationScreen> createState() =>
      _BookingConfirmationScreenState();
}

class _BookingConfirmationScreenState
    extends ConsumerState<BookingConfirmationScreen> {
  BookingHandoff? _handoff;
  SessionState? _ownerSession;
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (mounted) unawaited(_resolve());
    });
  }

  Future<void> _resolve({bool confirm = false, bool retire = false}) async {
    if (!mounted || _busy) return;
    final session = ref.read(sessionControllerProvider);
    final reporter = ref.read(appErrorReporterProvider);
    if (confirm &&
        (_handoff == null ||
            _handoff!.isConfirmed ||
            !identical(session, _ownerSession))) {
      return;
    }
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final controller = ref.read(pendingFareLockControllerProvider.notifier);
      final result = retire && _handoff != null
          ? await controller.resolveConfirmedEvidence(_handoff!.command)
          : await controller.bookingHandoff(
              confirm: confirm, bookingRequestId: widget.bookingRequestId);
      if (!mounted) return;
      if (!identical(ref.read(sessionControllerProvider), session)) {
        setState(() {
          _handoff = null;
          _failed = true;
          _busy = false;
        });
        return;
      }
      setState(() {
        _handoff = result;
        _ownerSession = session;
        _busy = false;
      });
    } on Object catch (error, stackTrace) {
      if (error is! FareException) {
        try {
          reporter.report(
              operation: 'handing off the original booking',
              error: error,
              stackTrace: stackTrace);
        } on Object {
          // Diagnostics cannot prevent recovery UI from settling.
        }
      }
      if (mounted) {
        setState(() {
          _handoff = null;
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final pending = ref.watch(pendingFareLockControllerProvider);
    final references = ref.watch(confirmedBookingReferencesProvider);
    final retired = _handoff != null &&
        references.any((r) => r.command.hasSameLockIdentity(_handoff!.command));
    final handoff = _handoff != null &&
            identical(session, _ownerSession) &&
            (pending?.hasSameLockIdentity(_handoff!.command) == true ||
                retired) &&
            _handoff!.command.riderId == session.user?.id
        ? _handoff
        : null;
    return AppScaffold(
        title: 'Original booking',
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else if (handoff != null) ...[
              Text(handoff.isConfirmed
                  ? 'Booking confirmed'
                  : 'Fare locked — booking not yet confirmed'),
              const SizedBox(height: 16),
              Text(
                  'Locked fare: ${formatFareFils(handoff.quote.fixedFareFils)}'),
              const Text(
                  'This is your original booking. Current route selections do not change this fare.'),
              if (!handoff.isConfirmed)
                AppButton(
                    label: 'Confirm original booking',
                    onPressed: () => unawaited(_resolve(confirm: true))),
              if (handoff.isConfirmed && !retired)
                AppButton(
                    label: 'Resolve evidence for another booking',
                    onPressed: () => unawaited(_resolve(retire: true))),
              if (handoff.isConfirmed && retired)
                AppButton(
                    label: 'Start another booking',
                    onPressed: () => context.go('/rider/home')),
              if (handoff.isConfirmed)
                const Text(
                    'Your booking is confirmed. Live driver matching is not available yet.'),
            ] else ...[
              const Text(
                  'Booking status is unresolved. Confirmation and changes are paused.'),
              if (_failed)
                const Text(
                    'We could not verify your original booking. Sign in as the original Rider and check again.'),
              AppButton(
                  label: 'Check booking status',
                  onPressed: () => unawaited(_resolve())),
            ],
            const SizedBox(height: 16),
            Text(retired
                ? 'Your confirmed booking reference is saved separately.'
                : 'Your original fare-lock recovery evidence remains protected.'),
          ],
        ));
  }
}
