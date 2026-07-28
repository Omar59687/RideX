import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum RideXBrandVariant { wordmark, routeMark, appIcon }

class RideXBrand extends StatelessWidget {
  const RideXBrand({
    super.key,
    this.variant = RideXBrandVariant.wordmark,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.semanticLabel = 'RideX',
  });

  final RideXBrandVariant variant;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String semanticLabel;

  String get _asset => switch (variant) {
        RideXBrandVariant.wordmark => 'assets/branding/ridex-wordmark.svg',
        RideXBrandVariant.routeMark => 'assets/branding/ridex-route-mark.svg',
        RideXBrandVariant.appIcon => 'assets/branding/ridex-app-icon.svg',
      };

  @override
  Widget build(BuildContext context) {
    final useMonochromeWordmark = variant == RideXBrandVariant.wordmark &&
        Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      _asset,
      width: width,
      height: height,
      fit: fit,
      semanticsLabel: semanticLabel,
      colorFilter: useMonochromeWordmark
          ? ColorFilter.mode(
              Theme.of(context).colorScheme.onSurface,
              BlendMode.srcIn,
            )
          : null,
    );
  }
}
