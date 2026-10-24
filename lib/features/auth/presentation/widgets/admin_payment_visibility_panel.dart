import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/auth/presentation/providers/admin_payment_providers.dart';
import 'package:ridex/features/auth/presentation/widgets/admin_sanitized_payment_card.dart';

class AdminPaymentVisibilityPanel extends ConsumerWidget {
  const AdminPaymentVisibilityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!canReadAdminPayments(ref.watch(sessionControllerProvider))) {
      return const Text('Administrator access is required to view payments.');
    }
    return ref.watch(adminPaymentsProvider).when(
          skipLoadingOnRefresh: false,
          skipLoadingOnReload: false,
          loading: () => const Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading payment summaries'),
            ],
          ),
          data: (payments) => Column(
            children: [
              const Text(
                  'Up to 50 recent payment records. Statuses are read-only.'),
              if (payments.isEmpty)
                const Text('No payment records are available.'),
              for (final payment in payments)
                AdminSanitizedPaymentCard(payment: payment),
              TextButton(
                onPressed: () => ref.invalidate(adminPaymentsProvider),
                child: const Text('Refresh payment summaries'),
              ),
            ],
          ),
          error: (error, _) => Column(
            children: [
              Text(switch (error) {
                AdminPaymentReadException(
                  failure: AdminPaymentReadFailure.unauthorized,
                ) =>
                  'Administrator access could not be verified.',
                AdminPaymentReadException(
                  failure: AdminPaymentReadFailure.unavailable,
                ) =>
                  'Payment visibility is unavailable in this configuration.',
                _ => 'Payment summaries could not be loaded.',
              }),
              TextButton(
                onPressed: () => ref.invalidate(adminPaymentsProvider),
                child: const Text('Retry payment summaries'),
              ),
            ],
          ),
        );
  }
}
