import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/canonical_driver_presentation_controller.dart';
import '../providers/driver_active_trip_restoration_provider.dart';
import '../widgets/canonical_driver_reference_panel.dart';

/// Read-only Driver entry. Never mounts completion, generates a command, or
/// restores from a route ID. Host supplies the existing canonical read owner.
class DriverActiveTripRestorationScreen extends ConsumerStatefulWidget {
  const DriverActiveTripRestorationScreen({super.key});
  @override
  ConsumerState<DriverActiveTripRestorationScreen> createState() =>
      _RestorationState();
}

class _RestorationState extends ConsumerState<DriverActiveTripRestorationScreen>
    with WidgetsBindingObserver {
  CanonicalDriverPresentationController? _owner;
  bool _backgrounded = false;
  bool _covered = false;
  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _backgrounded = lifecycle != null && lifecycle != AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _backgrounded = true;
      _owner?.retire();
    } else if (_backgrounded && mounted) {
      _backgrounded = false;
      if (ModalRoute.of(context)?.isCurrent == true) {
        ref.invalidate(driverActiveTripRestorationProvider);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _owner?.retire(deferNotification: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _covered = ModalRoute.of(context)?.isCurrent == false;
    // Dependency/auth/config changes may replace the provider while paused.
    // Retire that replacement before queued delivery can publish into it.
    ref.listen(driverActiveTripRestorationProvider, (_, next) {
      _owner = next;
      if (_backgrounded || _covered) {
        next?.retire(deferNotification: true);
      }
    });
    _owner = ref.watch(driverActiveTripRestorationProvider);
    if (_backgrounded || _covered) {
      _owner?.retire(deferNotification: true);
    }
    final owner = _owner;
    final configured =
        owner != null && owner.restorationEnabled && !owner.offerActionsEnabled;
    return Scaffold(
        appBar: AppBar(title: const Text('Driver active Trip')),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: configured
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            CanonicalDriverReferencePanel(controller: owner),
                            TextButton(
                                onPressed: _backgrounded
                                    ? null
                                    : () => ref.invalidate(
                                        driverActiveTripRestorationProvider),
                                child:
                                    const Text('Reload canonical Trip owner')),
                          ])
                    : const Text(
                        'Canonical Driver restoration is not configured.'))));
  }
}
