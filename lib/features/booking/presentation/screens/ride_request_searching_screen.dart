import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_motion.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/models/mock_trip.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_dialog.dart';
import 'package:ridex/core/widgets/app_error_view.dart';
import 'package:ridex/core/widgets/app_loading.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/map_placeholder.dart';
import 'package:ridex/core/widgets/trip_status_card.dart';

class RideRequestSearchingScreen extends ConsumerStatefulWidget {
  const RideRequestSearchingScreen({super.key});

  @override
  ConsumerState<RideRequestSearchingScreen> createState() =>
      _RideRequestSearchingScreenState();
}

class _RideRequestSearchingScreenState
    extends ConsumerState<RideRequestSearchingScreen> {
  Object? _creationError;
  bool _isCreating = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_createTrip);
  }

  Future<void> _createTrip() async {
    if (mounted) {
      setState(() {
        _isCreating = true;
        _creationError = null;
      });
    }
    try {
      await ref.read(activeTripControllerProvider.notifier).createTrip();
    } catch (error) {
      if (mounted) _creationError = error;
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _driverFound() {
    final controller = ref.read(activeTripControllerProvider.notifier);
    controller.setStatus(TripStatus.accepted);
    if (!mounted ||
        ref.read(activeTripControllerProvider)?.status != TripStatus.accepted) {
      return;
    }
    context.go('/rider/trip');
  }

  Future<void> _cancelSearch() async {
    final confirmed = await showAppDialog(
      context: context,
      title: 'Cancel this request?',
      message: 'You will not be charged while RideX is still searching.',
      icon: Icons.close_rounded,
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    ref
        .read(activeTripControllerProvider.notifier)
        .setStatus(TripStatus.cancelledByRider);
    if (ref.read(activeTripControllerProvider)?.status ==
            TripStatus.cancelledByRider &&
        mounted) {
      context.go('/rider/home');
    }
  }

  void _noDriverFound() {
    ref
        .read(activeTripControllerProvider.notifier)
        .setStatus(TripStatus.noDriverFound);
  }

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(activeTripControllerProvider);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final status = trip?.status;

    return AppScaffold(
      title: 'Finding a driver',
      maxContentWidth: 700,
      body: AnimatedSwitcher(
        duration: reduceMotion ? AppMotion.reduced : AppMotion.standard,
        child: _creationError != null
            ? AppErrorView(
                key: const ValueKey('creation-error'),
                title: 'Request not created',
                message: 'We could not start the search. Please try again.',
                onRetry: _createTrip,
              )
            : status == TripStatus.noDriverFound
                ? _NoDriverFound(onReturnHome: () => context.go('/rider/home'))
                : Column(
                    key: const ValueKey('searching'),
                    children: [
                      Expanded(
                        child: MapPlaceholder(
                          liveState: MapLiveState.searching,
                          showRoute: false,
                          semanticLabel:
                              'Searching for deterministic demo drivers nearby',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TripStatusCard(
                        status: TripStatus.searching,
                        title: 'Finding your best match',
                        message: _isCreating
                            ? 'Creating your ride request safely.'
                            : 'Nearby deterministic demo drivers are being checked.',
                        trailing: _isCreating
                            ? const SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const AppLoading(
                          label: 'Matching you with a nearby driver'),
                      if (!_isCreating && trip != null) ...[
                        Text(
                          '${trip.booking.vehicleType?.name ?? 'Ride'} | '
                          '${trip.booking.estimatedFare.toStringAsFixed(2)} JOD',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              key: const ValueKey('cancel-search-button'),
                              label: 'Cancel',
                              variant: AppButtonVariant.secondary,
                              onPressed:
                                  !_isCreating && status == TripStatus.searching
                                      ? _cancelSearch
                                      : null,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: AppButton(
                              key: const ValueKey('driver-found-button'),
                              label: 'Demo: Driver found',
                              onPressed:
                                  !_isCreating && status == TripStatus.searching
                                      ? _driverFound
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        key: const ValueKey('no-driver-button'),
                        label: 'Demo: No driver found',
                        variant: AppButtonVariant.text,
                        onPressed:
                            !_isCreating && status == TripStatus.searching
                                ? _noDriverFound
                                : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
      ),
    );
  }
}

class _NoDriverFound extends StatelessWidget {
  const _NoDriverFound({required this.onReturnHome});

  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('no-driver-found'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const TripStatusCard(
          status: TripStatus.noDriverFound,
          title: 'No driver available',
          message:
              'No nearby demo driver could take this request. Try again soon.',
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(label: 'Return home', onPressed: onReturnHome),
      ],
    );
  }
}
