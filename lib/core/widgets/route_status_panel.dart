import 'package:flutter/material.dart';
import 'package:ridex/core/errors/route_exception.dart';
import 'package:ridex/core/models/route_models.dart';

class RouteStatusPanel extends StatelessWidget {
  const RouteStatusPanel({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final RouteState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      RouteStatus.idle => const SizedBox.shrink(),
      RouteStatus.loading => const Card(
          key: ValueKey('route-loading'),
          child: ListTile(
            leading: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            title: Text('Calculating route...'),
            subtitle:
                Text('Distance and duration come from the route service.'),
          ),
        ),
      RouteStatus.failure => Card(
          key: ValueKey(
            state.failure == RouteFailure.networkFailure
                ? 'route-network-failure'
                : 'route-unavailable',
          ),
          child: ListTile(
            leading: Icon(
              Icons.route_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              state.failure == RouteFailure.networkFailure
                  ? 'Network failure'
                  : 'Route unavailable',
            ),
            subtitle: Text(_failureMessage(state.failure)),
            trailing:
                TextButton(onPressed: onRetry, child: const Text('Retry')),
          ),
        ),
      RouteStatus.ready => Card(
          key: const ValueKey('route-ready'),
          child: ListTile(
            leading: const Icon(Icons.route_rounded),
            title: Text(_metrics(state.result!)),
            subtitle: const Text('Traffic-aware driving route'),
          ),
        ),
    };
  }

  static String _metrics(RouteResult result) {
    final distance = result.distanceMeters < 1000
        ? '${result.distanceMeters} m'
        : '${(result.distanceMeters / 1000).toStringAsFixed(1)} km';
    final minutes = (result.durationSeconds / 60).ceil();
    return '$distance | $minutes min';
  }

  static String _failureMessage(RouteFailure? failure) => switch (failure) {
        RouteFailure.networkFailure =>
          'Check your connection and try calculating the route again.',
        RouteFailure.notFound =>
          'No driving route was found for these locations.',
        RouteFailure.timedOut =>
          'Route calculation timed out. Please try again.',
        RouteFailure.unsupportedStops =>
          'Intermediate stops are not available yet.',
        _ => 'Route calculation is unavailable. Please try again.',
      };
}
