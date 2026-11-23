import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/card_payment.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/models/driver_approval_status.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/models/session_status.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/driver_flow/application/driver_completion_handoff_controller.dart';
import 'package:ridex/features/driver_flow/domain/driver_completion_handoff.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_completion_handoff_provider.dart';

/// Fail-closed replacement for the legacy shared Driver success route.
/// A route ID is only a locator: Trip completion, Payment and Receipt each
/// require their own current, authorized handoff evidence.
class DriverCompletionStatusScreen extends ConsumerStatefulWidget {
  const DriverCompletionStatusScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<DriverCompletionStatusScreen> createState() =>
      _DriverCompletionStatusScreenState();
}

class _DriverCompletionStatusScreenState
    extends ConsumerState<DriverCompletionStatusScreen> {
  bool _scheduled = false;

  void _scheduleRead(DriverCompletionHandoffController? controller) {
    if (_scheduled || controller == null || controller.tripId != widget.tripId) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && controller.tripId == widget.tripId) {
        controller.refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.watch(driverCompletionStatusProvider(widget.tripId));
    _scheduleRead(controller);
    final user = session.user;
    final eligibleSession = session.status == SessionStatus.authenticated &&
        session.role == RideRole.driver &&
        user != null &&
        !user.isBlocked &&
        user.driverApprovalStatus == DriverApprovalStatus.approved;
    final event = controller?.event;
    final trip = event?.trip;
    final verifiedCompletion =
        eligibleSession &&
        controller != null &&
        controller.tripId == widget.tripId &&
        event?.scope?.isApprovedDriver == true &&
        event?.scope?.owner.driverId?.toLowerCase() == user?.id.toLowerCase() &&
        event?.tripState == DriverHandoffReadState.verified &&
        event?.tripCompleted == true &&
        trip?.tripId.toLowerCase() == widget.tripId.toLowerCase() &&
        trip?.driverId.toLowerCase() == user?.id.toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Trip completion status')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: verifiedCompletion
              ? _verifiedCompletionBody(context, controller!, event!)
              : _unverifiedBody(context, controller),
        ),
      ),
    );
  }

  Widget _unverifiedBody(
    BuildContext context,
    DriverCompletionHandoffController? controller,
  ) =>
      Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.info_outline, size: 40),
          const SizedBox(height: 16),
          Text(
            'Trip completion details are unavailable or unverified.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (controller?.canRefresh == true) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: controller!.refresh,
              child: const Text('Recheck canonical status'),
            ),
          ],
        ],
      );

  Widget _verifiedCompletionBody(
    BuildContext context,
    DriverCompletionHandoffController controller,
    DriverCompletionHandoffEvent event,
  ) {
    final paymentMessage = switch (event.paymentState) {
      DriverHandoffReadState.verified => switch (event.payment) {
          DriverHandoffCashPayment(:final status) =>
            'Cash payment status: ${status.name}.',
          DriverHandoffCardPayment(:final status) =>
            'Card payment status: ${status.name}.',
          null => 'Payment status is unverified.',
        },
      DriverHandoffReadState.loading => 'Checking payment status.',
      DriverHandoffReadState.missing ||
      DriverHandoffReadState.unknown ||
      DriverHandoffReadState.error ||
      DriverHandoffReadState.unauthorized =>
        'Payment status is unavailable or unverified.',
      DriverHandoffReadState.notChecked => 'Payment status was not checked.',
    };
    final receipt = event.receiptState == DriverHandoffReadState.verified
        ? event.receipt
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, size: 44),
        const SizedBox(height: 12),
        Text(
          'Trip completion verified.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 24),
        Text(paymentMessage, key: const ValueKey('driver-payment-evidence')),
        const SizedBox(height: 12),
        Text(
          receipt == null
              ? 'Receipt status is unavailable or unverified.'
              : 'Verified receipt: ${receipt.number}',
          key: const ValueKey('driver-receipt-evidence'),
        ),
        const Spacer(),
        OutlinedButton(
          onPressed: controller.canRefresh ? controller.refresh : null,
          child: const Text('Recheck canonical status'),
        ),
      ],
    );
  }
}
