import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/features/rider_payments/presentation/providers/rider_checkout_controller_provider.dart';
import 'package:ridex/features/rider_payments/presentation/widgets/rider_checkout_panel.dart';

/// Read-only payment/receipt presentation for an untrusted Trip locator.
/// The authenticated feature reader must verify ownership before any detail is
/// displayed. This screen has no financial action or callback surface.
class RiderPaymentStatusScreen extends ConsumerStatefulWidget {
  const RiderPaymentStatusScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<RiderPaymentStatusScreen> createState() =>
      _RiderPaymentStatusScreenState();
}

class _RiderPaymentStatusScreenState
    extends ConsumerState<RiderPaymentStatusScreen> {
  bool _initialReadScheduled = false;

  void _scheduleRead() {
    if (_initialReadScheduled) return;
    _initialReadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(riderCheckoutControllerProvider)
            .refresh(tripId: widget.tripId);
      }
    });
  }

  @override
  void didUpdateWidget(covariant RiderPaymentStatusScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId) {
      _initialReadScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleRead();
    final controller = ref.watch(riderCheckoutControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Payment status')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: RiderCheckoutPanel(
            state: controller.state,
            receiptState: controller.state.receipt,
            onRetry: controller.retry,
          ),
        ),
      ),
    );
  }
}
