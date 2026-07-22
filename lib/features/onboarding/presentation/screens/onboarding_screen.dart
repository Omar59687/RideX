import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_motion.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/widgets/app_button.dart';
import 'package:ridex/core/widgets/ride_x_brand.dart';

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
      Icons.local_taxi_rounded,
    ),
    _OnboardingSlide(
      'Track every moment',
      'Follow your driver, ETA, and live ride status through one polished trip flow.',
      Icons.route_rounded,
    ),
    _OnboardingSlide(
      'Built for reliable demos',
      'Role-based rider and driver journeys stay deterministic, smooth, and easy to present.',
      Icons.verified_user_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final slide = slides[index];
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final colors = Theme.of(context).colorScheme;
    final aurora = context.rideXTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  minHeight: constraints.maxHeight - AppSpacing.xxxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: RideXBrand(width: 92, height: 32),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedSwitcher(
                      duration:
                          reduceMotion ? AppMotion.reduced : AppMotion.standard,
                      child: Container(
                        key: ValueKey(index),
                        height: constraints.maxHeight < 700 ? 150 : 260,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: aurora.routeGradient,
                          borderRadius: BorderRadius.circular(AppRadii.sheet),
                          boxShadow: aurora.floatingShadows,
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: 30,
                              left: -25,
                              right: 55,
                              child: Divider(
                                color: Colors.white.withValues(alpha: .42),
                                thickness: 3,
                              ),
                            ),
                            Center(
                              child: Icon(
                                slide.icon,
                                size: 76,
                                color: Colors.white,
                                semanticLabel: slide.title,
                              ),
                            ),
                            PositionedDirectional(
                              end: 24,
                              bottom: 22,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: colors.tertiary,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(slide.title,
                        style: Theme.of(context).textTheme.displaySmall),
                    const SizedBox(height: AppSpacing.md),
                    Text(slide.body,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: List.generate(
                        slides.length,
                        (dotIndex) => AnimatedContainer(
                          duration:
                              reduceMotion ? AppMotion.reduced : AppMotion.fast,
                          width: dotIndex == index ? 28 : 8,
                          height: 8,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          decoration: BoxDecoration(
                            color: dotIndex == index
                                ? colors.primary
                                : colors.outline,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
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
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Skip',
                      variant: AppButtonVariant.text,
                      onPressed: () => context.go('/roles'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
