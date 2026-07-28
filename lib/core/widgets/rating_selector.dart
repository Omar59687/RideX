import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

class RatingSelector extends StatelessWidget {
  const RatingSelector({
    super.key,
    required this.rating,
    this.onChanged,
    this.maxRating = 5,
    this.label = 'Rating',
  }) : assert(maxRating > 0);

  final int rating;
  final ValueChanged<int>? onChanged;
  final int maxRating;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = context.rideXTheme.warning;
    final unselectedColor = theme.colorScheme.outline;
    return Semantics(
      container: true,
      label: '$label, $rating of $maxRating',
      child: Wrap(
        spacing: AppSpacing.xxs,
        alignment: WrapAlignment.center,
        children: [
          for (var value = 1; value <= maxRating; value++)
            Semantics(
              button: true,
              selected: value <= rating,
              label: '$value ${value == 1 ? 'star' : 'stars'}',
              child: IconButton(
                tooltip: 'Rate $value of $maxRating',
                onPressed: onChanged == null ? null : () => onChanged!(value),
                constraints:
                    const BoxConstraints.tightFor(width: 44, height: 44),
                icon: Icon(
                  value <= rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: value <= rating ? selectedColor : unselectedColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
