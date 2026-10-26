import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/features/trips/presentation/widgets/driver_cash_completion_panel.dart';

/// No route parameter, mock Trip, version or financial authority enters here.
/// The existing session-scoped composition discovers canonical backend context.
class DriverCanonicalTripScreen extends ConsumerWidget {
  const DriverCanonicalTripScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(driverCashRuntimeEnabledProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Canonical Cash Trip')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: enabled
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Isolated test backend'),
                    SizedBox(height: 12),
                    Text(
                      'Check your active Cash Trip using backend evidence. '
                      'Reconciliation only reads existing completion records. '
                      'Trip completion does not by itself prove payment or receipt issuance.',
                    ),
                    SizedBox(height: 24),
                    DriverCashCompletionPanel(),
                  ],
                )
              : const Text(
                  'Canonical Cash Trip access is disabled in this build.',
                ),
        ),
      ),
    );
  }
}
