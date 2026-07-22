import 'package:flutter/material.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/app/theme/ridex_theme.dart';

@immutable
class RouteTimelineStop {
  const RouteTimelineStop({
    required this.title,
    this.subtitle,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final String? semanticLabel;
}

class RouteTimeline extends StatelessWidget {
  const RouteTimeline({
    super.key,
    required this.pickup,
    required this.destination,
    this.stops = const [],
    this.compact = false,
  });

  final RouteTimelineStop pickup;
  final RouteTimelineStop destination;
  final List<RouteTimelineStop> stops;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final rideXTheme = context.rideXTheme;
    final entries = [pickup, ...stops, destination];
    return Semantics(
      container: true,
      label: 'Route with ${entries.length} locations',
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++)
            _TimelineEntry(
              stop: entries[index],
              color: index == 0
                  ? rideXTheme.pickup
                  : index == entries.length - 1
                      ? rideXTheme.destination
                      : rideXTheme.routeLive,
              first: index == 0,
              last: index == entries.length - 1,
              compact: compact,
            ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.stop,
    required this.color,
    required this.first,
    required this.last,
    required this.compact,
  });

  final RouteTimelineStop stop;
  final Color color;
  final bool first;
  final bool last;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = context.rideXTheme.routeLive.withValues(alpha: 0.4);
    final verticalPadding = compact ? AppSpacing.xs : AppSpacing.sm;
    return Semantics(
      label: stop.semanticLabel ?? stop.title,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: first ? Colors.transparent : lineColor,
                      child: const SizedBox(width: 2),
                    ),
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: color, width: 4),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: last ? Colors.transparent : lineColor,
                      child: const SizedBox(width: 2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: verticalPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.title, style: theme.textTheme.titleMedium),
                    if (stop.subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        stop.subtitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
