import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ridex/app/theme/app_spacing.dart';
import 'package:ridex/core/errors/place_exception.dart';
import 'package:ridex/core/models/booking_draft.dart';
import 'package:ridex/core/models/place_prediction.dart';
import 'package:ridex/core/providers/repositories_providers.dart';
import 'package:ridex/core/providers/session_providers.dart';

/// Provisional Phase 5 multi-stop management surface.
///
/// Reads the ordered stop list from [bookingControllerProvider] and forwards
/// every mutation to the frozen [BookingController] API ([BookingController.addStop],
/// [BookingController.removeStopAt], [BookingController.moveStop],
/// [BookingController.clearStops]). This widget keeps no duplicated
/// booking/stop state: only transient search predictions and feedback copy
/// live here.
///
/// Stop candidates reuse the existing place-selection patterns: debounced
/// search predictions and typed-address lookup through the configured place
/// repository, each producing a [RideLocation]. Rejected adds (a fourth stop
/// or a duplicate of the pickup, destination, or an existing stop) surface
/// honest inline messaging instead of silent no-ops.
///
/// Route geometry, distance, duration, and fares for stop routes are never
/// fabricated here: this surface only lists draft labels/addresses and lets
/// the existing route panels render whatever the configured route repository
/// returns for the draft (routing with stops is parallel P5-2 work).
class StopsSection extends ConsumerStatefulWidget {
  const StopsSection({super.key});

  @override
  ConsumerState<StopsSection> createState() => _StopsSectionState();
}

class _StopsSectionState extends ConsumerState<StopsSection> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<PlacePrediction> _predictions = const [];
  bool _searching = false;
  String? _feedback;
  bool _feedbackIsError = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _debounce?.cancel();
    final generation = ++_generation;
    if (query.length < 3) {
      setState(() {
        _predictions = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searching = true);
      unawaited(_loadPredictions(query, generation));
    });
  }

  Future<void> _loadPredictions(String query, int generation) async {
    try {
      final predictions = await ref
          .read(placeRepositoryProvider)
          .autocomplete(query: query, sessionToken: 'stop-search');
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _predictions = predictions;
        if (predictions.isEmpty) {
          _feedback = 'No matching places found.';
          _feedbackIsError = false;
        }
      });
    } on PlaceException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _predictions = const [];
        _feedback = _messageFor(error.failure);
        _feedbackIsError = true;
      });
    } on Object catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _predictions = const [];
        _feedback = _unavailableMessage;
        _feedbackIsError = true;
      });
    }
  }

  Future<void> _onSubmitted() async {
    final query = _search.text.trim();
    if (query.length < 3) {
      setState(() {
        _feedback = 'Type at least 3 characters to search for a stop.';
        _feedbackIsError = false;
      });
      return;
    }
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _predictions = const [];
    });
    try {
      final results = await ref
          .read(placeRepositoryProvider)
          .forwardGeocode(address: query);
      if (!mounted || generation != _generation) return;
      setState(() => _searching = false);
      if (results.isEmpty) {
        setState(() {
          _feedback = 'No matching location was found.';
          _feedbackIsError = false;
        });
        return;
      }
      _addStop(results.first);
    } on PlaceException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _feedback = _messageFor(error.failure);
        _feedbackIsError = true;
      });
    } on Object catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _feedback = _unavailableMessage;
        _feedbackIsError = true;
      });
    }
  }

  Future<void> _onPredictionSelected(PlacePrediction prediction) async {
    _debounce?.cancel();
    final generation = ++_generation;
    setState(() => _searching = true);
    try {
      final location =
          await ref.read(placeRepositoryProvider).resolvePrediction(
                prediction: prediction,
                sessionToken: 'stop-search',
              );
      if (!mounted || generation != _generation) return;
      setState(() => _searching = false);
      _addStop(location);
    } on PlaceException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _feedback = _messageFor(error.failure);
        _feedbackIsError = true;
      });
    } on Object catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _searching = false;
        _feedback = _unavailableMessage;
        _feedbackIsError = true;
      });
    }
  }

  void _addStop(RideLocation location) {
    final draft = ref.read(bookingControllerProvider);
    if (draft.stops.length >= BookingController.maxStops) {
      setState(() {
        _feedback = 'You can add up to ${BookingController.maxStops} stops. '
            'Remove one to add another.';
        _feedbackIsError = true;
      });
      return;
    }
    final added =
        ref.read(bookingControllerProvider.notifier).addStop(location);
    if (!mounted) return;
    if (!added) {
      setState(() {
        _feedback =
            'This stop is already in your route. Choose a different location.';
        _feedbackIsError = true;
      });
      return;
    }
    _search.clear();
    setState(() {
      _predictions = const [];
      _searching = false;
      _feedback = null;
      _feedbackIsError = false;
    });
  }

  void _removeStop(int index) {
    ref.read(bookingControllerProvider.notifier).removeStopAt(index);
    if (mounted) {
      setState(() {
        _feedback = null;
        _feedbackIsError = false;
      });
    }
  }

  void _moveStop(int from, int to) {
    ref.read(bookingControllerProvider.notifier).moveStop(from, to);
  }

  void _clearStops() {
    ref.read(bookingControllerProvider.notifier).clearStops();
    if (mounted) {
      setState(() {
        _feedback = null;
        _feedbackIsError = false;
      });
    }
  }

  static String _messageFor(PlaceFailure failure) => switch (failure) {
        PlaceFailure.notFound => 'No matching location was found.',
        PlaceFailure.unauthorized =>
          'Place search is unavailable for this account.',
        PlaceFailure.timedOut => 'Place search timed out. Please try again.',
        PlaceFailure.unavailable ||
        PlaceFailure.invalidResponse =>
          _unavailableMessage,
      };

  static const _unavailableMessage =
      'Place search is unavailable right now. Please try again.';

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(bookingControllerProvider);
    final stops = draft.stops;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Intermediate stops',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(
              '${stops.length}/${BookingController.maxStops}',
              key: const ValueKey('stops-count'),
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (stops.isEmpty)
          Text(
            'No stops yet. Add up to 3 places along your route.',
            key: const ValueKey('stops-empty'),
            style: theme.textTheme.bodySmall,
          )
        else ...[
          for (var index = 0; index < stops.length; index++)
            _StopCard(
              key: ValueKey('stop-card-$index'),
              index: index,
              total: stops.length,
              stop: stops[index],
              onRemove: () => _removeStop(index),
              onMoveUp: index > 0 ? () => _moveStop(index, index - 1) : null,
              onMoveDown: index < stops.length - 1
                  ? () => _moveStop(index, index + 1)
                  : null,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('stops-clear'),
              onPressed: _clearStops,
              child: const Text('Clear stops'),
            ),
          ),
          Text(
            'Stops are saved in order and apply to the next route calculation.',
            key: const ValueKey('stops-route-note'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('stop-search-field'),
          controller: _search,
          onChanged: _onSearchChanged,
          onSubmitted: (_) => _onSubmitted(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search for a stop',
            hintText: 'Place or street address',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    key: const ValueKey('stop-search-submit'),
                    tooltip: 'Search address',
                    onPressed: _onSubmitted,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
          ),
        ),
        if (_predictions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _predictions.length; index++)
                  ListTile(
                    key: ValueKey('stop-prediction-$index'),
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(_predictions[index].primaryText),
                    subtitle: _predictions[index].secondaryText.isEmpty
                        ? null
                        : Text(_predictions[index].secondaryText),
                    onTap: () => _onPredictionSelected(_predictions[index]),
                  ),
              ],
            ),
          ),
        ],
        if (_feedback != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _feedback!,
            key: const ValueKey('stops-feedback'),
            style: _feedbackIsError
                ? TextStyle(color: theme.colorScheme.error)
                : theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    super.key,
    required this.index,
    required this.total,
    required this.stop,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final int total;
  final RideLocation stop;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(stop.label, style: theme.textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(stop.address, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('stop-remove-$index'),
                  tooltip: 'Remove stop ${stop.label}',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            if (total > 1)
              Row(
                children: [
                  Text(
                    'Stop ${index + 1} of $total',
                    style: theme.textTheme.labelSmall,
                  ),
                  const Spacer(),
                  if (onMoveUp != null)
                    TextButton.icon(
                      key: ValueKey('stop-move-up-$index'),
                      onPressed: onMoveUp,
                      icon: const Icon(
                        Icons.arrow_upward_rounded,
                        size: 18,
                      ),
                      label: const Text('Move up'),
                    ),
                  if (onMoveDown != null)
                    TextButton.icon(
                      key: ValueKey('stop-move-down-$index'),
                      onPressed: onMoveDown,
                      icon: const Icon(
                        Icons.arrow_downward_rounded,
                        size: 18,
                      ),
                      label: const Text('Move down'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
