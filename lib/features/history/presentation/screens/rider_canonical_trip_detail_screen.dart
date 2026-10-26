import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/models/cash_payment.dart';
import 'package:ridex/core/repositories/rider_canonical_trip_detail_repository.dart';
import 'package:ridex/features/history/presentation/providers/rider_canonical_trip_detail_providers.dart';

class RiderCanonicalTripDetailScreen extends ConsumerWidget {
  const RiderCanonicalTripDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(riderCanonicalTripDetailProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Latest completed Cash Trip')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        result.when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const Column(children: [
            CircularProgressIndicator(),
            Text('Loading canonical Trip and payment')
          ]),
          error: (error, _) => Text(error is RiderTripDetailException &&
                  error.failure == RiderTripDetailFailure.unauthorized
              ? 'Payment access could not be verified. Sign in as the owning Rider.'
              : 'Canonical details could not be read. No payment outcome is inferred.'),
          data: (detail) => detail == null
              ? const Text(
                  'Canonical Trip and payment information unavailable.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Trip: completed'),
                  const SizedBox(height: 16),
                  Text(detail.amountDisplay,
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(switch (detail.payment.status) {
                    CashPaymentStatus.cashSelected => 'Cash selected (unpaid)',
                    CashPaymentStatus.paid => 'Canonical Cash status: paid',
                    CashPaymentStatus.cancelled =>
                      'Canonical Cash status: cancelled',
                  }),
                  const SizedBox(height: 16),
                  Text(detail.receipt == RiderReceiptEvidence.issued
                      ? 'Receipt issuance verified.'
                      : 'Receipt unverified. This does not mean payment failed.'),
                ]),
        ),
        const SizedBox(height: 24),
        TextButton(
            onPressed: result.isLoading
                ? null
                : () => ref.invalidate(riderCanonicalTripDetailProvider),
            child: const Text('Refresh canonical details')),
      ])),
    );
  }
}
