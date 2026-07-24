import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/app/theme/app_radii.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';
import 'package:ridex/core/widgets/ride_x_brand.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = true,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final aurora = context.rideXTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 700
                ? AppSpacing.xxl
                : constraints.maxWidth < 360
                    ? AppSpacing.md
                    : AppSpacing.lg;
            return Stack(
              children: [
                Positioned(
                  top: -100,
                  right: -90,
                  child: IgnorePointer(
                    child: Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            aurora.routeLive.withValues(alpha: .22),
                            colors.surface.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    AppSpacing.sm,
                    horizontal,
                    AppSpacing.xl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 48,
                            child: Row(
                              children: [
                                if (showBack)
                                  IconButton(
                                    tooltip: 'Back',
                                    onPressed: () => context.canPop()
                                        ? context.pop()
                                        : context.go('/sign-in'),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  )
                                else
                                  const SizedBox(width: 8),
                                const Spacer(),
                                const RideXBrand(
                                  width: 92,
                                  height: 30,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          _RouteSignal(
                            color: aurora.routeLive,
                            destinationColor: colors.tertiary,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            title,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.sheet),
                              border: Border.all(color: colors.outline),
                              boxShadow: aurora.cardShadows,
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(
                                constraints.maxWidth < 360
                                    ? AppSpacing.md
                                    : AppSpacing.xl,
                              ),
                              child: child,
                            ),
                          ),
                          if (footer != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Center(child: footer!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RouteSignal extends StatelessWidget {
  const _RouteSignal({
    required this.color,
    required this.destinationColor,
  });

  final Color color;
  final Color destinationColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'RideX route',
      image: true,
      child: SizedBox(
        width: 116,
        height: 32,
        child: CustomPaint(
          painter: _RouteSignalPainter(color, destinationColor),
        ),
      ),
    );
  }
}

class _RouteSignalPainter extends CustomPainter {
  const _RouteSignalPainter(this.color, this.destinationColor);

  final Color color;
  final Color destinationColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(8, size.height - 6)
      ..cubicTo(34, size.height - 6, 34, 6, 58, 6)
      ..cubicTo(78, 6, 80, size.height - 8, size.width - 8, size.height - 8);
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(8, size.height - 6), 5, Paint()..color = color);
    canvas.drawCircle(
      Offset(size.width - 8, size.height - 8),
      5,
      Paint()..color = destinationColor,
    );
  }

  @override
  bool shouldRepaint(covariant _RouteSignalPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.destinationColor != destinationColor;
}
