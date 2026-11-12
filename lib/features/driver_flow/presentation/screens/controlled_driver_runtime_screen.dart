import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/controlled_driver_runtime.dart';
import '../widgets/canonical_driver_reference_panel.dart';

/// Isolated read-only entry. It never starts tracking or any backend command.
class ControlledDriverRuntimeScreen extends ConsumerStatefulWidget {
  const ControlledDriverRuntimeScreen({super.key});
  @override
  ConsumerState<ControlledDriverRuntimeScreen> createState() =>
      _RuntimeScreenState();
}

class _RuntimeScreenState extends ConsumerState<ControlledDriverRuntimeScreen>
    with WidgetsBindingObserver {
  ControlledDriverRuntime? _runtime;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _runtime?.invalidate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runtime?.invalidate();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _runtime = ref.watch(controlledDriverRuntimeProvider);
    if (ModalRoute.of(context)?.isCurrent == false) _runtime?.invalidate();
    return Scaffold(
      appBar: AppBar(title: const Text('Controlled Driver discovery')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Read-only test entry. Offer and financial commands disabled.',
              ),
              const Text(
                'Background, auth changes or navigation stop this owner. Reenter to verify again.',
              ),
              const SizedBox(height: 16),
              if (_runtime == null)
                const Text(
                  'BLOCKED: enable the nonrelease test flag, approved nonproduction target and authenticated approved Driver.',
                )
              else
                CanonicalDriverReferencePanel(controller: _runtime!.controller),
            ],
          ),
        ),
      ),
    );
  }
}
