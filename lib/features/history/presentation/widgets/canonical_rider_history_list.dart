import 'package:flutter/material.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/features/history/data/rider_trip_history_contract.dart';

/// Feature-local canonical history surface. The caller must supply an
/// authorized, participant-scoped repository; no global/router wiring here.
/// No demo fallback: read failures are explicit and recoverable.
class CanonicalRiderHistoryList extends StatefulWidget {
  const CanonicalRiderHistoryList({
    required this.repository,
    required this.riderId,
    required this.currentRiderId,
    required this.onOpenTrip,
    super.key,
  });

  final RiderTripHistoryRepository repository;
  final String riderId;
  final String? Function() currentRiderId;
  final ValueChanged<String> onOpenTrip;

  @override
  State<CanonicalRiderHistoryList> createState() =>
      _CanonicalRiderHistoryListState();
}

class _CanonicalRiderHistoryListState extends State<CanonicalRiderHistoryList> {
  final List<RiderHistoryTrip> _trips = [];
  RiderHistoryCursor? _cursor;
  RiderHistoryFilter _filter = RiderHistoryFilter.all;
  bool _loading = false;
  bool _hasLoaded = false;
  bool _hasMore = false;
  bool _failed = false;
  int _generation = 0;

  bool get _isAuthorized =>
      isCanonicalTripId(widget.riderId) &&
      widget.currentRiderId() == widget.riderId;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant CanonicalRiderHistoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.riderId != widget.riderId ||
        !identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.currentRiderId, widget.currentRiderId)) {
      _generation++;
      _trips.clear();
      _cursor = null;
      _hasMore = false;
      _hasLoaded = false;
      _failed = false;
      _loading = false;
      _filter = RiderHistoryFilter.all;
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _generation && _isAuthorized;

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || (!_hasMore && !_failed))) return;
    final generation = ++_generation;
    if (!_isAuthorized) {
      setState(() {
        _trips.clear();
        _cursor = null;
        _loading = false;
        _failed = true;
        _hasLoaded = true;
        _hasMore = false;
      });
      return;
    }
    final cursor = reset ? null : _cursor;
    final filter = _filter;
    final expectedRiderId = widget.riderId;
    final expectedRepository = widget.repository;
    setState(() {
      if (reset) {
        _trips.clear();
        _cursor = null;
        _hasMore = false;
        _hasLoaded = false;
      }
      _loading = true;
      _failed = false;
    });
    try {
      final page = await expectedRepository.readPage(
        RiderHistoryRequest(
          riderId: expectedRiderId,
          filter: filter,
          cursor: cursor,
        ),
      );
      if (!_isCurrent(generation)) {
        if (mounted && !_isAuthorized) {
          setState(() {
            _trips.clear();
            _cursor = null;
            _loading = false;
            _failed = true;
            _hasMore = false;
          });
        }
        return;
      }
      // Do not trust an adapter to have enforced ownership, filter or order.
      final seen = _trips.map((trip) => trip.tripId).toSet();
      final next = <RiderHistoryTrip>[];
      RiderHistoryTrip? previous = _trips.isEmpty ? null : _trips.last;
      for (final trip in page.trips) {
        final allowed = switch (_filter) {
          RiderHistoryFilter.all => true,
          RiderHistoryFilter.completed =>
            trip.status == DriverTripLifecycleStatus.completed,
          RiderHistoryFilter.cancelled =>
            trip.status == DriverTripLifecycleStatus.cancelledByRider ||
                trip.status == DriverTripLifecycleStatus.cancelledByDriver ||
                trip.status == DriverTripLifecycleStatus.cancelledByAdmin,
        };
        if (trip.riderId != expectedRiderId || !allowed) {
          throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
        }
        if (!seen.add(trip.tripId)) continue;
        final ordered = previous == null ||
            trip.createdAt.isBefore(previous.createdAt) ||
            (trip.createdAt.isAtSameMomentAs(previous.createdAt) &&
                trip.tripId.compareTo(previous.tripId) < 0);
        if (!ordered) {
          throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
        }
        next.add(trip);
        previous = trip;
      }
      if (page.nextCursor != null &&
          (next.isEmpty ||
              page.nextCursor!.tripId != next.last.tripId ||
              !page.nextCursor!.createdAt.isAtSameMomentAs(
                next.last.createdAt,
              ))) {
        throw const RiderHistoryException(RiderHistoryFailure.invalidResponse);
      }
      setState(() {
        _trips.addAll(next);
        _cursor = page.nextCursor;
        _hasMore = page.nextCursor != null;
        _hasLoaded = true;
        _loading = false;
      });
    } on Object {
      if (!_isCurrent(generation)) return;
      setState(() {
        _loading = false;
        _failed = true;
        _hasLoaded = true;
      });
    }
  }

  void _setFilter(RiderHistoryFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      // Discard prior account's loaded records on the next state update.
      if (_trips.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isAuthorized) {
            setState(() {
              _generation++;
              _trips.clear();
              _cursor = null;
              _hasMore = false;
              _loading = false;
            });
          }
        });
      }
      return const Center(
        child: Text('Sign in as the owning Rider to view trip history.'),
      );
    }
    return Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final option in RiderHistoryFilter.values)
              ChoiceChip(
                key: Key('canonical-filter-${option.name}'),
                label: Text(switch (option) {
                  RiderHistoryFilter.all => 'All',
                  RiderHistoryFilter.completed => 'Completed',
                  RiderHistoryFilter.cancelled => 'Cancelled',
                }),
                selected: _filter == option,
                onSelected: (_) => _setFilter(option),
              ),
          ],
        ),
        Expanded(
          child: _failed && _trips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Trip history could not be loaded.'),
                      TextButton(
                        key: const Key('canonical-history-retry'),
                        onPressed: () => _load(reset: _trips.isEmpty),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : !_hasLoaded && _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        key: Key('canonical-history-loading'),
                      ),
                    )
                  : _trips.isEmpty
                      ? const Center(
                          child: Text(
                            'No rides found.',
                            key: Key('canonical-history-empty'),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _trips.length + (_hasMore || _failed ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _trips.length) {
                              return Center(
                                child: TextButton(
                                  key: Key(_failed
                                      ? 'canonical-history-retry'
                                      : 'canonical-history-more'),
                                  onPressed: _loading
                                      ? null
                                      : () => _load(reset: false),
                                  child: Text(_loading
                                      ? 'Loading...'
                                      : _failed
                                          ? 'Retry'
                                          : 'Load more'),
                                ),
                              );
                            }
                            final trip = _trips[index];
                            return ListTile(
                              key: Key('canonical-history-${trip.tripId}'),
                              title: Text(
                                '${trip.pickupLabel} → ${trip.destinationLabel}',
                              ),
                              subtitle: Text(
                                '${trip.status.backendValue} · ${trip.createdAt.toUtc().toIso8601String()}',
                              ),
                              trailing: Text(
                                '${trip.currency} ${(trip.lockedFareFils / 1000).toStringAsFixed(3)}',
                              ),
                              onTap: () {
                                if (_isAuthorized) {
                                  widget.onOpenTrip(trip.tripId);
                                }
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
