import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/core/providers/driver_cash_completion_providers.dart';
import 'package:ridex/features/driver_flow/presentation/providers/driver_completion_interaction_provider.dart';
import 'package:ridex/features/trips/presentation/widgets/driver_cash_completion_panel.dart';

/// No route parameter, mock Trip, version or financial authority enters here.
/// The existing session-scoped composition discovers canonical backend context.
class DriverCanonicalTripScreen extends ConsumerStatefulWidget {
  const DriverCanonicalTripScreen({super.key});

  @override
  ConsumerState<DriverCanonicalTripScreen> createState() =>
      _DriverCanonicalTripState();
}

class _DriverCanonicalTripState extends ConsumerState<DriverCanonicalTripScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ref
          .read(driverCompletionInteractionControllerProvider)
          ?.invalidateInteraction();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(driverCashRuntimeEnabledProvider);
    final interaction = enabled
        ? ref.watch(driverCompletionInteractionControllerProvider)
        : null;
    if (ModalRoute.of(context)?.isCurrent == false) {
      interaction?.invalidateInteraction(deferNotification: true);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Canonical Cash Trip')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: enabled && interaction != null
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
                  'Canonical Cash Trip interaction requires reviewed nonproduction configuration.',
                ),
        ),
      ),
    );
  }
}
