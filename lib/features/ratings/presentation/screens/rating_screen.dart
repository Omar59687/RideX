import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';
import 'package:ridex/core/widgets/driver_info_card.dart';
import 'package:ridex/core/widgets/rating_selector.dart';

class RatingScreen extends ConsumerStatefulWidget {
  const RatingScreen({super.key});

  @override
  ConsumerState<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends ConsumerState<RatingScreen> {
  int rating = 4;

  @override
  Widget build(BuildContext context) {
    final trip = ref.watch(activeTripControllerProvider);
    if (trip == null) {
      return AppScaffold(
        title: 'Rate your trip',
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Driver details are unavailable for this session.'),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Return home',
              onPressed: () => context.go('/rider/home'),
            ),
          ],
        ),
      );
    }
    return AppScaffold(
      title: 'Rate your trip',
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xl),
            const CircleAvatar(radius: 40, child: Icon(Icons.person)),
            const SizedBox(height: AppSpacing.lg),
            Text('How was ${trip.driver.name}?',
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: AppSpacing.md),
            RatingSelector(
              rating: rating,
              label: 'Session rating for ${trip.driver.name}',
              onChanged: (value) => setState(() => rating = value),
            ),
            const SizedBox(height: AppSpacing.md),
            DriverInfoCard(driver: trip.driver),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Demo only: this rating stays in this session and is not saved.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Submit demo rating',
              onPressed: () => context.go('/history'),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Skip and return home',
              variant: AppButtonVariant.text,
              onPressed: () => context.go('/rider/home'),
            ),
          ],
        ),
      ),
    );
  }
}
