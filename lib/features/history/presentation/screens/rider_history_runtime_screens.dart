import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ridex/core/models/driver_trip_completion.dart';
import 'package:ridex/core/models/payment_method.dart';
import 'package:ridex/core/models/ride_role.dart';
import 'package:ridex/core/providers/session_providers.dart';
import 'package:ridex/features/history/data/supabase_rider_history_summary_repository.dart';
import 'package:ridex/features/history/presentation/providers/rider_history_summary_provider.dart';
import 'package:ridex/features/history/presentation/screens/trip_details_screen.dart';
import 'package:ridex/features/history/presentation/screens/trip_history_screen.dart';
import 'package:ridex/features/rider_payments/presentation/providers/rider_checkout_controller_provider.dart';
import 'package:ridex/features/rider_payments/presentation/widgets/rider_checkout_panel.dart';

enum _CanonicalHistoryFilter { all, completed, cancelled }

/// Selects the canonical Rider history surface without changing Driver
/// History's existing route or repository behavior.
class RoleAwareHistoryRoute extends ConsumerWidget {
  const RoleAwareHistoryRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionControllerProvider).role;
    if (role == RideRole.rider) return const RiderCanonicalHistoryScreen();
    if (role == RideRole.driver) return const TripHistoryScreen();
    return const Scaffold(
      body: Center(
        child: Text('Trip history is unavailable for this account.'),
      ),
    );
  }
}

class RoleAwareTripDetailsRoute extends ConsumerWidget {
  const RoleAwareTripDetailsRoute({required this.tripId, super.key});
  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionControllerProvider).role;
    if (role == RideRole.rider) {
      return RiderCanonicalHistoryDetailScreen(tripId: tripId);
    }
    if (role == RideRole.driver) return TripDetailsScreen(tripId: tripId);
    return const Scaffold(
      body: Center(child: Text('Trip access could not be verified.')),
    );
  }
}

class RiderCanonicalHistoryScreen extends ConsumerStatefulWidget {
  const RiderCanonicalHistoryScreen({super.key});

  @override
  ConsumerState<RiderCanonicalHistoryScreen> createState() =>
      _RiderCanonicalHistoryScreenState();
}

class _RiderCanonicalHistoryScreenState
    extends ConsumerState<RiderCanonicalHistoryScreen> {
  final _rows = <RiderHistorySummary>[];
  RiderHistorySummaryCursor? _cursor;
  SessionState? _owner;
  int _generation = 0;
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false;
  _CanonicalHistoryFilter _filter = _CanonicalHistoryFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(reset: true);
    });
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final owner = ref.read(sessionControllerProvider);
    final repository = ref.read(riderHistorySummaryRepositoryProvider);
    if (owner.role != RideRole.rider ||
        owner.user?.isBlocked != false ||
        repository == null) {
      setState(() {
        _rows.clear();
        _cursor = null;
        _owner = null;
        _loading = false;
        _failed = true;
        _loaded = true;
      });
      return;
    }
    final generation = ++_generation;
    final cursor = reset ? null : _cursor;
    setState(() {
      if (reset) {
        _rows.clear();
        _cursor = null;
        _loaded = false;
      }
      _owner = owner;
      _loading = true;
      _failed = false;
    });
    try {
      final page = await repository.readPage(cursor: cursor);
      if (!mounted ||
          generation != _generation ||
          !identical(ref.read(sessionControllerProvider), owner)) {
        return;
      }
      setState(() {
        _rows.addAll(page.rows);
        _cursor = page.nextCursor;
        _loaded = true;
        _loading = false;
      });
    } on Object {
      if (!mounted ||
          generation != _generation ||
          !identical(ref.read(sessionControllerProvider), owner)) {
        return;
      }
      setState(() {
        _failed = true;
        _loaded = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(sessionControllerProvider);
    final repository = ref.watch(riderHistorySummaryRepositoryProvider);
    ref.listen(sessionControllerProvider, (previous, next) {
      if (!identical(previous, next)) {
        _generation++;
        setState(() {
          _rows.clear();
          _cursor = null;
          _owner = null;
          _loaded = false;
          _loading = false;
          _filter = _CanonicalHistoryFilter.all;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(reset: true);
        });
      }
    });
    ref.listen(riderHistorySummaryRepositoryProvider, (previous, next) {
      if (!identical(previous, next)) {
        _generation++;
        setState(() {
          _rows.clear();
          _cursor = null;
          _owner = null;
          _loaded = false;
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(reset: true);
        });
      }
    });
    if (current.role != RideRole.rider || current.user?.isBlocked != false) {
      return const Scaffold(
        body: Center(child: Text('Sign in as a Rider to view your trips.')),
      );
    }
    if (repository == null) {
      return const Scaffold(
        body: Center(child: Text('Trip history could not be verified.')),
      );
    }
    if (_owner != null && !identical(_owner, current)) {
      return const Scaffold(
        body: Center(child: Text('Refreshing Rider history.')),
      );
    }
    final visibleRows = _rows
        .where((row) => switch (_filter) {
              _CanonicalHistoryFilter.all => true,
              _CanonicalHistoryFilter.completed =>
                row.status == DriverTripLifecycleStatus.completed,
              _CanonicalHistoryFilter.cancelled =>
                row.status == DriverTripLifecycleStatus.cancelledByRider ||
                    row.status == DriverTripLifecycleStatus.cancelledByDriver ||
                    row.status == DriverTripLifecycleStatus.cancelledByAdmin,
            })
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Your rides')),
      body: Column(children: [
        Wrap(
          spacing: 8,
          children: [
            for (final filter in _CanonicalHistoryFilter.values)
              ChoiceChip(
                key: Key('canonical-history-filter-${filter.name}'),
                label: Text(switch (filter) {
                  _CanonicalHistoryFilter.all => 'All',
                  _CanonicalHistoryFilter.completed => 'Completed',
                  _CanonicalHistoryFilter.cancelled => 'Cancelled',
                }),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
          ],
        ),
        Expanded(
          child: !_loaded && _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed && _rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Trip history could not be verified.'),
                          TextButton(
                            onPressed: () => _load(reset: true),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _rows.isEmpty
                      ? const Center(child: Text('No rides found.'))
                      : visibleRows.isEmpty && _cursor == null
                          ? const Center(
                              child: Text('No trips match this filter.'),
                            )
                          : ListView.builder(
                              itemCount: visibleRows.length +
                                  (_cursor != null || _failed ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == visibleRows.length) {
                                  return Center(
                                    child: TextButton(
                                      onPressed: _loading
                                          ? null
                                          : () => _load(reset: false),
                                      child: Text(
                                        _failed ? 'Retry' : 'Load more',
                                      ),
                                    ),
                                  );
                                }
                                final row = visibleRows[index];
                                return ListTile(
                                  key: ValueKey(
                                    'canonical-history-${row.tripId}',
                                  ),
                                  title: Text(_statusLabel(row.status)),
                                  subtitle: Text(_dateLabel(row.createdAt)),
                                  trailing: Text(
                                    row.paymentMethod?.name.toUpperCase() ??
                                        'Payment unverified',
                                  ),
                                  onTap: () =>
                                      context.push('/history/${row.tripId}'),
                                );
                              },
                            ),
        ),
      ]),
    );
  }
}

class RiderCanonicalHistoryDetailScreen extends ConsumerStatefulWidget {
  const RiderCanonicalHistoryDetailScreen({required this.tripId, super.key});
  final String tripId;

  @override
  ConsumerState<RiderCanonicalHistoryDetailScreen> createState() =>
      _RiderCanonicalHistoryDetailScreenState();
}

class _RiderCanonicalHistoryDetailScreenState
    extends ConsumerState<RiderCanonicalHistoryDetailScreen> {
  RiderHistorySummary? _trip;
  SessionState? _owner;
  int _generation = 0;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load() async {
    final owner = ref.read(sessionControllerProvider);
    final repository = ref.read(riderHistorySummaryRepositoryProvider);
    final generation = ++_generation;
    setState(() {
      _owner = owner;
      _trip = null;
      _loading = true;
      _failed = false;
    });
    try {
      final trip = repository == null
          ? null
          : await repository.readExactTrip(widget.tripId);
      if (!mounted ||
          generation != _generation ||
          !identical(ref.read(sessionControllerProvider), owner)) {
        return;
      }
      setState(() {
        _trip = trip;
        _loading = false;
      });
      if (trip?.paymentMethod == PaymentMethod.card) {
        await ref
            .read(riderCheckoutControllerProvider)
            .refresh(tripId: widget.tripId);
      }
    } on Object {
      if (!mounted ||
          generation != _generation ||
          !identical(ref.read(sessionControllerProvider), owner)) {
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final repository = ref.watch(riderHistorySummaryRepositoryProvider);
    ref.listen(sessionControllerProvider, (previous, next) {
      if (!identical(previous, next)) {
        _generation++;
        setState(() {
          _trip = null;
          _owner = null;
          _loading = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    });
    ref.listen(riderHistorySummaryRepositoryProvider, (previous, next) {
      if (!identical(previous, next)) {
        _generation++;
        setState(() {
          _trip = null;
          _owner = null;
          _loading = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    });
    if (session.role != RideRole.rider || session.user?.isBlocked != false) {
      return const Scaffold(
        body: Center(child: Text('Trip access could not be verified.')),
      );
    }
    if (repository == null) {
      return const Scaffold(
        body: Center(child: Text('Trip access could not be verified.')),
      );
    }
    if (_owner != null && !identical(_owner, session)) {
      return const Scaffold(
        body: Center(child: Text('Refreshing Trip details.')),
      );
    }
    final trip = _trip;
    final paymentMethod =
        trip?.paymentMethod?.name.toUpperCase() ?? 'Unavailable';
    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Trip details could not be verified.'),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : trip == null
                  ? const Center(
                      child: Text(
                        'Trip is unavailable or could not be authorized.',
                      ),
                    )
                  : ListView(padding: const EdgeInsets.all(16), children: [
                      Text('Trip status: ${_statusLabel(trip.status)}'),
                      Text('Trip date: ${_dateLabel(trip.createdAt)}'),
                      Text('Trip version: ${trip.version}'),
                      Text('Payment method: $paymentMethod'),
                      if (trip.paymentMethod == PaymentMethod.card) ...[
                        const SizedBox(height: 16),
                        RiderCheckoutPanel(
                          state:
                              ref.watch(riderCheckoutControllerProvider).state,
                          onRetry: () => ref
                              .read(riderCheckoutControllerProvider)
                              .refresh(tripId: widget.tripId),
                          onReceiptRecheck: () => ref
                              .read(riderCheckoutControllerProvider)
                              .refresh(tripId: widget.tripId),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'This history contract does not provide Cash '
                            'payment or receipt details.',
                          ),
                        ),
                    ]),
    );
  }
}

String _statusLabel(DriverTripLifecycleStatus status) => switch (status) {
      DriverTripLifecycleStatus.accepted => 'Accepted',
      DriverTripLifecycleStatus.driverArriving => 'Driver arriving',
      DriverTripLifecycleStatus.driverArrived => 'Driver arrived',
      DriverTripLifecycleStatus.inProgress => 'In progress',
      DriverTripLifecycleStatus.completed => 'Completed',
      DriverTripLifecycleStatus.cancelledByRider => 'Cancelled by Rider',
      DriverTripLifecycleStatus.cancelledByDriver => 'Cancelled by Driver',
      DriverTripLifecycleStatus.cancelledByAdmin => 'Cancelled',
      DriverTripLifecycleStatus.failed => 'Failed',
    };

String _dateLabel(DateTime date) => date.toLocal().toString();
