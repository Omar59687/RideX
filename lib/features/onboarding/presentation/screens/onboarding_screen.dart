import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/app_scaffold.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int index = 0;

  static const slides = [
    _OnboardingSlide(
        'Book rides in seconds',
        'Plan your trip with confident pricing, clear steps, and a calm map-first experience.',
        Icons.local_taxi_rounded),
    _OnboardingSlide(
        'Track every moment',
        'Follow your driver, ETA, and live ride status through one polished trip flow.',
        Icons.route_rounded),
    _OnboardingSlide(
        'Built for reliable demos',
        'Role-based rider and driver journeys stay deterministic, smooth, and easy to present.',
        Icons.verified_user_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final slide = slides[index];
    return AppScaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Center(
            child: CircleAvatar(
              radius: 72,
              backgroundColor: Theme.of(context).colorScheme.surface,
              child: Icon(slide.icon, size: 56),
            ),
          ).animate().fadeIn(duration: 280.ms).slideY(begin: 0.06, end: 0),
          const SizedBox(height: AppSpacing.xxl),
          Text(slide.title, style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: AppSpacing.md),
          Text(slide.body, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: List.generate(
              slides.length,
              (dotIndex) => Container(
                width: dotIndex == index ? 28 : 8,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: dotIndex == index
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          const Spacer(),
          AppButton(
            label: index == slides.length - 1 ? 'Continue' : 'Next',
            onPressed: () {
              if (index == slides.length - 1) {
                context.go('/roles');
              } else {
                setState(() => index += 1);
              }
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: AppButton(
              label: 'Skip',
              variant: AppButtonVariant.text,
              onPressed: () => context.go('/roles'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide(this.title, this.body, this.icon);

  final String title;
  final String body;
  final IconData icon;
}
